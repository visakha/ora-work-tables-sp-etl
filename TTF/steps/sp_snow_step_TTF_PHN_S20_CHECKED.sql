-- ============================================================================
-- sp_snow_step_TTF_PHN_S20_CHECKED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TTF)
--
-- Mapping: m_Tgt_C_S_TTF_Pty_Rle_Phn, workflow wf_TTF_Stage_Load, step 20.
-- Step name (checkpoint): CHECKED.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TTF_PHN_S2_CHECKED. Reads ONLY WRK_TTF_PHN_S1_SRC (plus reference lookups / target guard tables where the original reads them; those are not work-table dependencies).
--
-- DOES IT FEED THE SPINE?
--   Indirectly: it is an early staged step; every later step reads (transitively) from it, and the publish branches read the final routed table, which derives from it. It writes no target itself.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only. Snowflake cannot
--   parameterise table names in static SQL, so P_INPUT_TABLES is a
--   dependency declaration + runtime check, NOT dynamic SQL: the CTAS
--   below still names its source work table literally, as in the
--   current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-20 SELECT verbatim. Only
--   substitution: :l_run_ts -> :P_RUN_TS; :c_mapping resolves to the
--   local constant below (used by the checkpoint and, where the
--   original used it, materialised into the work table). No business
--   expression, filter, guard or column list was changed. This step uses no original parameter.
--   It does not reference the run timestamp directly; P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   in the v2 10-argument form. P_JOB_RUN_ID is present in every new
--   proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_TTF_PHN_S20_CHECKED (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TTF_PHN_S1_SRC') RETURN NUMBER AUTHID CURRENT_USER AS
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

    -- ---- Step 20: CHECKED (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TTF_PHN_S2_CHECKED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TTF_PHN_S2_CHECKED AS WITH
    lkp_area AS (SELECT * FROM TABLE(fn_snow_helper44_common()))
    SELECT s.*,
           /* VALIDATION */ fn_snow_helper24_common(s.std_phone, 'TTF', '001', ar.NPA_ID, ar.SERVICE) AS phone_exception_code
      FROM WRK_TTF_PHN_S1_SRC s
      LEFT JOIN lkp_area ar ON ar.NPA_ID = SUBSTR(s.std_phone, 1, 3)]';
    SELECT COUNT(*) INTO l_rows FROM WRK_TTF_PHN_S2_CHECKED;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'CHECKED', 'COMPLETED', NULL, 'Step 20 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TTF_PHN_S20_CHECKED;
/

