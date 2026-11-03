-- ============================================================================
-- sp_snow_step_FSS_PHN_S20_DQ  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (FSS)
--
-- Mapping: m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr, workflow wf_FSS_Stage_Load, step 20.
-- Step name (checkpoint): DQ_VALIDATE.
--
-- WHAT THIS STEP PRODUCES
--   WRK_FSS_PHN_S2_DQ: E-mail validation, phone standardisation, extension check.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (default: 'WRK_FSS_PHN_S1_SRC').
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-20 SELECT verbatim. Only
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
CREATE OR REPLACE FUNCTION sp_snow_step_FSS_PHN_S20_DQ (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_FSS_PHN_S1_SRC') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'FSS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_FSS_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr';
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

    -- ---- Step 20: DQ_VALIDATE (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_FSS_PHN_S2_DQ';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_FSS_PHN_S2_DQ AS SELECT s.*,
           CASE WHEN s.ADDR_EMAIL IS NOT NULL THEN fn_snow_helper22_common(s.ADDR_EMAIL) ELSE NULL END    AS em,
           CASE WHEN s.NBR_PHONE IS NOT NULL THEN fn_snow_helper23_common(s.NBR_PHONE) ELSE NULL END      AS std_phone,
           CASE WHEN s.NBR_PHONE IS NOT NULL THEN fn_snow_helper25_common(s.NBR_PHONE_EXT) ELSE NULL END  AS px
      FROM WRK_FSS_PHN_S1_SRC s]';
    SELECT COUNT(*) INTO l_rows FROM WRK_FSS_PHN_S2_DQ;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'DQ_VALIDATE', 'COMPLETED', NULL, 'Step 20 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_FSS_PHN_S20_DQ;
/

