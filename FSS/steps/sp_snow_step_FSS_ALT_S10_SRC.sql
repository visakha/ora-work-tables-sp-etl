-- ============================================================================
-- sp_snow_step_FSS_ALT_S10_SRC  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (FSS)
--
-- Mapping: m_Tgt_C_S_FSS_Pty_Rle_Alt_Id, workflow wf_FSS_Stage_Load, step 10.
-- Step name (checkpoint): SRC_KEYED.
--
-- WHAT THIS STEP PRODUCES
--   WRK_FSS_ALT_S1_SRC: Keyed source rows: role key, alternate-ID type (022 / 023) and key, last active registrations.
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
CREATE OR REPLACE FUNCTION sp_snow_step_FSS_ALT_S10_SRC (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT '') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'FSS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_FSS_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_FSS_Pty_Rle_Alt_Id';
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

    -- ---- Step 10: SRC_KEYED (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_FSS_ALT_S1_SRC';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_FSS_ALT_S1_SRC AS SELECT v.SOURCE_TYPE, v.DT_CREATED, v.DT_LAST_UPDATE, v.PTY_SRC_KEY, v.ID_CLIENT,
           NVL(CASE WHEN v.PTY_SRC_KEY = 1 THEN 1 ELSE 0 END, '') || '|Member'                                      AS pty_rle_fk,
           CASE WHEN v.SOURCE_TYPE = 'CLIENT' THEN '022' ELSE '023' END                              AS alt_id_tp,
           NVL(CASE WHEN v.PTY_SRC_KEY = 1 THEN 1 ELSE 0 END, '') || '|Member|' || CASE WHEN v.SOURCE_TYPE = 'CLIENT' THEN '022' ELSE '023' END || '|'
           || NVL(LPAD(TO_CHAR(v.ID_CLIENT), 10, '0'), '')                        AS pkey_src_object
      FROM V_FSS_ETL_SRC v
     -- source filter (the commented-out testing filter is not applied)
     WHERE v.LAST_ACTIVE_CLIENT_REGISTRATION_YN = 'Y']';
    SELECT COUNT(*) INTO l_rows FROM WRK_FSS_ALT_S1_SRC;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'SRC_KEYED', 'COMPLETED', NULL, 'Step 10 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_FSS_ALT_S10_SRC;
/

