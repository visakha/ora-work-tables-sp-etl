-- ============================================================================
-- sp_snow_step_TTF_VAL_S30_ROUTED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TTF)
--
-- Mapping: m_Tgt_C_S_TTF_Pty_Validation, workflow wf_TTF_Stage_Load, step 30.
-- Step name (checkpoint): ROUTED.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TTF_VAL_S3_ROUTED. Reads ONLY WRK_TTF_VAL_S2_NAMED (plus reference lookups / target guard tables where the original reads them; those are not work-table dependencies).
--
-- DOES IT FEED THE SPINE?
--   YES, directly: all publish branches in this mapping read ONLY this table. It writes no target itself.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only. Snowflake cannot
--   parameterise table names in static SQL, so P_INPUT_TABLES is a
--   dependency declaration + runtime check, NOT dynamic SQL: the CTAS
--   below still names its source work table literally, as in the
--   current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-30 SELECT verbatim. Only
--   substitution: :l_run_ts -> :P_RUN_TS; :c_mapping resolves to the
--   local constant below (used by the checkpoint and, where the
--   original used it, materialised into the work table). No business
--   expression, filter, guard or column list was changed. This step uses no original parameter.
--   It references the run timestamp (:P_RUN_TS).
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   in the v2 10-argument form. P_JOB_RUN_ID is present in every new
--   proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_TTF_VAL_S30_ROUTED (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TTF_VAL_S2_NAMED') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TTF';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TTF_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TTF_Pty_Validation';
    l_rows NUMBER DEFAULT 0;
    l_missing VARCHAR2(4000) DEFAULT NULL;
    l_probe_sql VARCHAR2(4000);
    l_probe_dummy NUMBER;
BEGIN
    -- ---- Input existence check (skipped when P_INPUT_TABLES is empty)
    IF (P_INPUT_TABLES IS NOT NULL AND TRIM(P_INPUT_TABLES) <> '') THEN
        SELECT LISTAGG(tbl, ', ') WITHIN GROUP (ORDER BY tbl) INTO l_missing FROM (SELECT UPPER(TRIM(REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL))) AS tbl FROM DUAL CONNECT BY REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL) IS NOT NULL) f WHERE NOT EXISTS (SELECT 1 FROM ALL_TABLES t WHERE t.OWNER = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AND t.TABLE_NAME = f.tbl);
        IF (l_missing IS NOT NULL) THEN
            l_probe_sql := 'SELECT COUNT(*) FROM ' || TRIM(REGEXP_SUBSTR(l_missing, '[^,]+', 1, 1));
            EXECUTE IMMEDIATE l_probe_sql INTO l_probe_dummy;
        END IF;
    END IF;

    -- ---- Step 30: ROUTED (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TTF_VAL_S3_ROUTED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TTF_VAL_S3_ROUTED AS WITH
    lkp_exc  AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    -- Rtr_Valid_Party + Exp_Invalid_PTY_NM
    routed AS (
        SELECT r.*,
               CASE WHEN (r.name_missing = 1 OR r.name_declined = 1 OR r.name_undisclosed = 1) THEN 1 ELSE 0 END AS grp_invalid_party_name,
               CASE WHEN (r.name_missing = 1 OR r.name_declined = 1 OR NVL(CASE WHEN r.CLIENT_EXISTS_FLAG = 'N' THEN 1 ELSE 0 END, 0) = 1) THEN 1 ELSE 0 END AS grp_deactivation,
               NVL(CASE WHEN r.deactivation_sts IS NOT NULL AND r.name_missing = 0
                   AND NOT (UPPER(r.std_lst_name) = 'DECLINED') AND NOT (UPPER(r.std_first_name) = 'DECLINED')
                   AND r.CLIENT_EXISTS_FLAG = 'Y' THEN 1 ELSE 0 END, 0)                                      AS grp_reactivation,
               CASE WHEN fn_snow_helper03_common(r.std_first_name) = 1 THEN 'Missing_First_Name'
                    WHEN UPPER(TRIM(r.std_first_name)) IN ('DECLINED', 'DO_NOT_DISCLOSE') THEN 'Invalid_First_Name'
                    WHEN fn_snow_helper03_common(r.std_lst_name) = 1 THEN 'Missing_Last_Name'
                    WHEN UPPER(TRIM(r.std_lst_name)) IN ('DECLINED', 'DO_NOT_DISCLOSE') THEN 'Invalid_Last_Name'
                    ELSE 'Valid' END                                                           AS exc_code_name,
               fn_snow_helper02_common(r.hub_state_ind)                                        AS new_deactivation_sts
          FROM WRK_TTF_VAL_S2_NAMED r
    )
    SELECT r.*,
           ex.EXCEPTION_DESC     AS exc_desc_name,
           ex.EXCEPTION_TYPE     AS exc_type_name,
           'TTF'                 AS src_sys,
           :1             AS run_ts,
           :2            AS mapping_name,
           'Deactivation'        AS action_deactivation,
           'Reactivation'        AS action_reactivation,
           CASE WHEN /* BAD DATA: unique key of EXC_STG_BAD_REC_MEMB, first row per key in this run */
           ROW_NUMBER() OVER (PARTITION BY r.grp_invalid_party_name, r.pkey_src_object, ex.EXCEPTION_TYPE,
                                           r.exc_code_name ORDER BY r.SUBMITDATE DESC, r.CLIENTS_ID) = 1 THEN 1 ELSE 0 END AS uq_exc_name
      FROM routed r
      LEFT JOIN lkp_exc ex ON ex.EXCEPTION_CODE = r.exc_code_name]' USING P_RUN_TS, c_mapping;
    SELECT COUNT(*) INTO l_rows FROM WRK_TTF_VAL_S3_ROUTED;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'ROUTED', 'COMPLETED', NULL, 'Step 30 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TTF_VAL_S30_ROUTED;
/

