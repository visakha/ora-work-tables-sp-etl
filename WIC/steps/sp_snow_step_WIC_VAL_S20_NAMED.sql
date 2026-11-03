-- ============================================================================
-- sp_snow_step_WIC_VAL_S20_NAMED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (WIC)
--
-- Mapping: m_Tgt_C_S_WIC_Pty_Validation, workflow wf_WIC_Stage_Load, step 20.
-- Step name (checkpoint): NAMED_BLANK_TEST.
--
-- WHAT THIS STEP PRODUCES
--   WRK_WIC_VAL_S20_NAMED: Standardised first, middle and last names pulled out; the blank-name test applied (name_missing).
--
-- DOES IT FEED THE SPINE?
--   Indirectly: it is a staged step; every later step reads (transitively) from it, and the publish branches read the final step, which derives from it. It writes no target itself.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only. Default: 'WRK_WIC_VAL_S10_ENRICHED'. Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT dynamic SQL: the CTAS below still names its sources literally, as in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-20 SELECT verbatim. Only substitution: :l_run_ts -> :P_RUN_TS (not used by this step), :c_mapping -> the local constant below (used by the checkpoint). Original-parameter refs: none. No business expression, filter, guard or column list was changed.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no transactions, no target writes. This proc writes its own checkpoint in the v2 10-argument form (STEP_NAME, STEP_STATUS, TARGET_TABLE, MESSAGE, ERROR_MESSAGE; STEP_NO, row count and work-table arguments dropped per the new signature). P_JOB_RUN_ID is present in every new proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_WIC_VAL_S20_NAMED (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_WIC_VAL_S10_ENRICHED') RETURN NUMBER AUTHID CURRENT_USER AS
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

    -- ---- Step 20: NAMED_BLANK_TEST (verbatim from current main)
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_WIC_VAL_S20_NAMED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_WIC_VAL_S20_NAMED AS SELECT n.*,
           CAST(n.nm.first_name AS VARCHAR2(4000))  AS std_first_name,
           CAST(n.nm.middle_name AS VARCHAR2(4000)) AS std_mdl_name,
           CAST(n.nm.last_name AS VARCHAR2(4000))   AS std_lst_name,
           /* VALIDATION */ (fn_snow_helper03_common(CAST(n.nm.first_name AS VARCHAR2(4000)))
                             OR fn_snow_helper03_common(CAST(n.nm.last_name AS VARCHAR2(4000))) = 1) AS name_missing
      FROM WRK_WIC_VAL_S10_ENRICHED n]';
    SELECT COUNT(*) INTO l_rows FROM WRK_WIC_VAL_S20_NAMED;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'NAMED_BLANK_TEST', 'COMPLETED', NULL, 'Step 20 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_WIC_VAL_S20_NAMED;
/

