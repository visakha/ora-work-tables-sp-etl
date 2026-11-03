-- ============================================================================
-- sp_snow_step_FSS_ADR_S10_SRC  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (FSS)
--
-- Mapping: m_Tgt_C_S_FSS_Pty_Addr, workflow wf_FSS_Stage_Load, step 10.
-- Step name (checkpoint): SRC_ACTIVE.
--
-- WHAT THIS STEP PRODUCES
--   WRK_FSS_ADDR_S1_SRC: Source addresses with address key built, deactivated parties removed.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (default: '').
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-10 SELECT verbatim. Only
--   substitution: :l_run_ts -> :P_RUN_TS (not used by this step),
--   :c_mapping -> the local constant below (used by the checkpoint).
--   No business expression, filter, guard or column list was changed.
--   Original parameters used by this step: none.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   in the v2 10-argument form (TARGET_TABLE NULL, as in the current
--   main's step checkpoints; row count survives in the RETURN value
--   and the driver's helper36 summary line).
--   P_JOB_RUN_ID is present in every new proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_FSS_ADR_S10_SRC (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT '') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'FSS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_FSS_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_FSS_Pty_Addr';
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

    -- ---- Step 10: SRC_ACTIVE (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_FSS_ADDR_S1_SRC';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_FSS_ADDR_S1_SRC AS SELECT s.*
      FROM (SELECT v.SOURCE_TYPE, v.ID_CLIENT, v.ADDR_LINE1, v.ADDR_LINE2, v.ADDR_CITY, v.CD_CNTY, v.ADDR_ZIP,
                   v.ADDR_STATE, v.PTY_SRC_KEY, v.ID_REGISTRATION_CLIENT, v.DT_LAST_UPDATE, v.DT_CREATED,
                   NVL(CASE WHEN v.PTY_SRC_KEY = 1 THEN 1 ELSE 0 END, '') || '|Member|002|' || NVL(LPAD(TO_CHAR(v.ID_REGISTRATION_CLIENT), 10, '0'), '')
                   || '|' || NVL(TRIM(UPPER(v.ADDR_LINE1)), '') || '|' || NVL(TRIM(UPPER(v.ADDR_LINE2)), '') || '|'
                   || NVL(UPPER(v.ADDR_CITY), '') || '|' || NVL(UPPER(v.ADDR_STATE), '') || '|' || NVL(v.ADDR_ZIP, '')
                                                                                                   AS pkey_src_object,
                   -- exp_Score_and_Exception_details.PTY_SRC_KEY (DQM_ADDRESS only)
                   LPAD(TO_CHAR(v.ID_CLIENT), 10, '0') || CASE WHEN v.SOURCE_TYPE = 'FSS_FAMILY' THEN 'F' ELSE '' END AS dqm_pty_src_key
              FROM V_FSS_ETL_SRC v
             WHERE v.DTL__CAPXACTION <> 'D') s
     WHERE NOT EXISTS (SELECT 1 FROM STG_FSS_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = s.PTY_SRC_KEY = 1 AND i.ROWID_SYSTEM = 'FSS'
                          AND i.DEACTIVATION_STS IS NOT NULL)]';
    SELECT COUNT(*) INTO l_rows FROM WRK_FSS_ADDR_S1_SRC;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'SRC_ACTIVE', 'COMPLETED', NULL, 'Step 10 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_FSS_ADR_S10_SRC;
/

