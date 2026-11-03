-- ============================================================================
-- sp_snow_step_WIC_VAL_S30_ROUTED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (WIC)
--
-- Mapping: m_Tgt_C_S_WIC_Pty_Validation, workflow wf_WIC_Stage_Load, step 30.
-- Step name (checkpoint): ROUTED.
--
-- WHAT THIS STEP PRODUCES
--   WRK_WIC_VAL_S30_ROUTED: Exception code, attribute name and value, new deactivation status from hub state, looked-up exception description and type, run constants, and the first-row-per-exception-key flag (uq_exc_name). Computed before publish, so routing sees the pre-run status.
--
-- DOES IT FEED THE SPINE?
--   Directly: the publish branches read ONLY this table. It writes no target itself.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only. Default: 'WRK_WIC_VAL_S20_NAMED'. Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT dynamic SQL: the CTAS below still names its sources literally, as in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-30 SELECT verbatim. Only substitution: :l_run_ts -> :P_RUN_TS (used by this step), :c_mapping -> the local constant below (used by the checkpoint). Original-parameter refs: none. No business expression, filter, guard or column list was changed.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no transactions, no target writes. This proc writes its own checkpoint in the v2 10-argument form (STEP_NAME, STEP_STATUS, TARGET_TABLE, MESSAGE, ERROR_MESSAGE; STEP_NO, row count and work-table arguments dropped per the new signature). P_JOB_RUN_ID is present in every new proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_WIC_VAL_S30_ROUTED (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_WIC_VAL_S20_NAMED') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'WIC';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_WIC_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_WIC_Pty_Validation';
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
        EXECUTE IMMEDIATE 'DROP TABLE WRK_WIC_VAL_S30_ROUTED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_WIC_VAL_S30_ROUTED AS WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    routed AS (
        SELECT r.*,
               CASE WHEN fn_snow_helper03_common(r.std_first_name) = 1 THEN 'Missing_First_Name'
                    WHEN fn_snow_helper03_common(r.std_lst_name) = 1 THEN 'Missing_Last_Name' END  AS exc_code_name,
               CASE WHEN fn_snow_helper03_common(r.std_first_name) = 1 THEN 'First Name'
                    WHEN fn_snow_helper03_common(r.std_lst_name) = 1 THEN 'Last Name' END          AS exc_attribute_name,
               CASE WHEN fn_snow_helper03_common(r.std_first_name) = 1 THEN r.std_first_name
                    WHEN fn_snow_helper03_common(r.std_lst_name) = 1 THEN r.std_lst_name END       AS exc_attribute_value,
               fn_snow_helper02_common(r.hub_state_ind)                                        AS new_deactivation_sts
          FROM WRK_WIC_VAL_S20_NAMED r
    )
    SELECT r.*,
           ex.EXCEPTION_DESC     AS exc_desc_name,
           ex.EXCEPTION_TYPE     AS exc_type_name,
           'WIC'                 AS src_sys,
           :1             AS run_ts,
           :2            AS mapping_name,
           'Deactivation'        AS action_deactivation,
           'Reactivation'        AS action_reactivation,
           CASE WHEN /* BAD DATA: unique key of EXC_STG_BAD_REC_MEMB, first row per key in this run */
           ROW_NUMBER() OVER (PARTITION BY r.name_missing, r.PTY_SRC_KEY, ex.EXCEPTION_TYPE, r.exc_code_name
                                  ORDER BY r.DATEKEY DESC, r.ID) = 1 THEN 1 ELSE 0 END AS uq_exc_name
      FROM routed r
      LEFT JOIN lkp_exc ex ON ex.EXCEPTION_CODE = r.exc_code_name]' USING P_RUN_TS, c_mapping;
    SELECT COUNT(*) INTO l_rows FROM WRK_WIC_VAL_S30_ROUTED;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'ROUTED', 'COMPLETED', NULL, 'Step 30 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_WIC_VAL_S30_ROUTED;
/

