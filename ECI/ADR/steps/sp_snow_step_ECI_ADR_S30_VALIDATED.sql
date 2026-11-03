-- ============================================================================
-- sp_snow_step_ECI_ADR_S30_VALIDATED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI)
--
-- Mapping: m_Tgt_C_S_ECI_Pty_Addr, workflow wf_ECI_Stage_Load, step 30.
-- Step name (checkpoint): ADDR_VALIDATION.
--
-- WHAT THIS STEP PRODUCES
--   WRK_ECI_ADR_S30_VALIDATED: Address validation result (pass-through stand-in for AddressDoctor) + state lookup (original validated CTE).
--
-- DOES IT FEED THE SPINE?
--   Indirectly: feeds the unpacking step, and through it the publish spine branch. It writes no target itself.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (default 'WRK_ECI_ADR_S20_KEYED').
--   Base source tables and target guard tables are NOT work-table
--   dependencies and are not listed. Snowflake cannot parameterise
--   table names in static SQL, so P_INPUT_TABLES is a dependency
--   declaration + runtime check, NOT dynamic SQL: the CTAS below still
--   names its sources literally, as in the current main procedure.
--   The existence check probes the first missing table with
--   EXECUTE IMMEDIATE 'SELECT 1 FROM <table>' (LISTAGG/FLATTEN form,
--   no row-by-row iteration), surfacing the native object-not-exists
--   error (coordinator normalisation: Snowflake RAISE accepts only a
--   declared exception name, so a dynamic message is not possible).
--
-- BUSINESS SQL
--   The CTAS below is the current step-30 SELECT verbatim. Only
--   substitutions: :l_run_ts -> :P_RUN_TS, :c_mapping -> the local
--   constant below (same value), original-param refs -> this proc's
--   params. No business expression, filter, guard or column list was
--   changed. Original params used by this step's SQL: none (grep of this step's SQL finds neither P_MEMBER_HIERARCHY_CODE nor P_MEMBER_HM_REL_TP_CD), so neither is in this signature.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   with the same STEP_NAME and message as the current step-30 checkpoint (v2 10-argument form; STEP_NO, row count, and work-table arguments dropped).
--   P_JOB_RUN_ID is present in every new proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_ECI_ADR_S30_VALIDATED (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_ADR_S20_KEYED') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_ECI_Pty_Addr';
    l_rows NUMBER DEFAULT 0;
    l_missing VARCHAR2(4000) DEFAULT NULL;
    l_probe_sql VARCHAR2(4000);
    l_probe_dummy NUMBER;
BEGIN
    -- ---- Input existence check (skipped when P_INPUT_TABLES is NULL/empty)
    -- P_INPUT_TABLES is a dependency declaration + runtime check, NOT
    -- dynamic SQL (Snowflake cannot parameterise table names in static
    -- SQL); the CTAS below still names its sources literally, as now.
    IF (P_INPUT_TABLES IS NOT NULL AND TRIM(P_INPUT_TABLES) <> '') THEN
        SELECT LISTAGG(tbl, ', ') WITHIN GROUP (ORDER BY tbl) INTO l_missing FROM (SELECT UPPER(TRIM(REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL))) AS tbl FROM DUAL CONNECT BY REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL) IS NOT NULL) f WHERE NOT EXISTS (SELECT 1 FROM ALL_TABLES t WHERE t.OWNER = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AND t.TABLE_NAME = f.tbl);
        IF (l_missing IS NOT NULL) THEN
            l_probe_sql := 'SELECT COUNT(*) FROM ' || TRIM(REGEXP_SUBSTR(l_missing, '[^,]+', 1, 1));
            EXECUTE IMMEDIATE l_probe_sql INTO l_probe_dummy;
        END IF;
    END IF;

    -- ---- Step 30: ADDR_VALIDATION (verbatim from current main)
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_ADR_S30_VALIDATED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_ECI_ADR_S30_VALIDATED AS WITH
    lkp_cv AS (SELECT * FROM TABLE(fn_snow_helper41_common()))
    SELECT k.*,
           fn_snow_helper34_common(k.ADDRESS1, k.ADDRESS2, k.CITY_NAME, k.STATE_ABBREV,
                                   NVL(k.ZIP_CODE, '') || CASE WHEN k.ZIP_SFX IS NOT NULL THEN '-' || k.ZIP_SFX ELSE '' END,
                                   'US', st.MSTR_CODE_VALUE) AS av
      FROM WRK_ECI_ADR_S20_KEYED k
      LEFT JOIN lkp_cv st ON st.CODE_TYPE = 'STATE' AND st.SRC_SYS = 'ECI'
                         AND st.SRC_CODE_VALUE = UPPER(TRIM(k.STATE_ABBREV))]';
    SELECT COUNT(*) INTO l_rows FROM WRK_ECI_ADR_S30_VALIDATED;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'ADDR_VALIDATION', 'COMPLETED', NULL, 'Step 30 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_ECI_ADR_S30_VALIDATED;
/

