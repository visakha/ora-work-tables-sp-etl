-- ============================================================================
-- sp_snow_step_TTF_PHN_S30_ROUTED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TTF)
--
-- Mapping: m_Tgt_C_S_TTF_Pty_Rle_Phn, workflow wf_TTF_Stage_Load, step 30.
-- Step name (checkpoint): ROUTED.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TTF_PHN_S3_ROUTED. Reads ONLY WRK_TTF_PHN_S2_CHECKED (plus reference lookups / target guard tables where the original reads them; those are not work-table dependencies).
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
CREATE OR REPLACE FUNCTION sp_snow_step_TTF_PHN_S30_ROUTED (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TTF_PHN_S2_CHECKED') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TTF';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TTF_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TTF_Pty_Rle_Phn';
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
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TTF_PHN_S3_ROUTED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TTF_PHN_S3_ROUTED AS WITH
    lkp_exc  AS (SELECT * FROM TABLE(fn_snow_helper40_common()))
    SELECT c.*,
           xp.EXCEPTION_DESC                                    AS phone_exception_desc,
           '1' /* TIMELINE: VERSION_SEQ */                     AS version_seq,
           1                                                    AS hub_state_ind,
           NVL(CASE WHEN c.PTY_SRC_KEY = 1 THEN 1 ELSE 0 END, '') || '|Member'                  AS pty_rle_fk,
           'Telephone'                                          AS phn_tp,
           '001'                                                AS usg_tp,
           'Primary'                                            AS pref_lvl,
           'TTF'                                                AS src_sys,
           :1                                            AS run_ts,
           :2                                           AS mapping_name,
           'Rejected Record'                                    AS exc_type_rejected,
           'Main Phone'                                         AS attr_phone,
           /* BAD DATA: unique keys Snowflake does not enforce */
           (ROW_NUMBER() OVER (PARTITION BY c.phone_exception_code IS NULL, c.phn_pkey
                                   ORDER BY c.SUBMITDATE DESC) = 1
            AND xph.PKEY_SRC_OBJECT IS NULL)                    AS uq_phn,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY c.phone_exception_code IS NULL, c.PTY_SRC_KEY, c.phone_exception_code
                                  ORDER BY c.SUBMITDATE DESC) = 1 THEN 1 ELSE 0 END AS uq_phone_exc
      FROM WRK_TTF_PHN_S2_CHECKED c
      LEFT JOIN lkp_exc xp ON xp.EXCEPTION_CODE = c.phone_exception_code
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TTF_PTY_RLE_PHN WHERE VERSION_SEQ = 1) xph
             ON xph.PKEY_SRC_OBJECT = c.phn_pkey]' USING P_RUN_TS, c_mapping;
    SELECT COUNT(*) INTO l_rows FROM WRK_TTF_PHN_S3_ROUTED;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'ROUTED', 'COMPLETED', NULL, 'Step 30 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TTF_PHN_S30_ROUTED;
/

