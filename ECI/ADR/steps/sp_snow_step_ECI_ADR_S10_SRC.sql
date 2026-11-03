-- ============================================================================
-- sp_snow_step_ECI_ADR_S10_SRC  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI)
--
-- Mapping: m_Tgt_C_S_ECI_Pty_Addr, workflow wf_ECI_Stage_Load, step 10.
-- Step name (checkpoint): SRC_ADDRESSES.
--
-- WHAT THIS STEP PRODUCES
--   WRK_ECI_ADR_S10_SRC: Address source rows with party / role keys and translated address types (original src CTE: source view + address-type lookup).
--
-- DOES IT FEED THE SPINE?
--   Indirectly: first staged step; every later step reads (transitively) from it, and the publish spine branch reads step 50, which derives from it. It writes no target itself.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (default '').
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
--   The CTAS below is the current step-10 SELECT verbatim. Only
--   substitutions: :l_run_ts -> :P_RUN_TS, :c_mapping -> the local
--   constant below (same value), original-param refs -> this proc's
--   params. No business expression, filter, guard or column list was
--   changed. Original params used by this step's SQL: none (grep of this step's SQL finds neither P_MEMBER_HIERARCHY_CODE nor P_MEMBER_HM_REL_TP_CD), so neither is in this signature.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   with the same STEP_NAME and message as the current step-10 checkpoint (v2 10-argument form; STEP_NO, row count, and work-table arguments dropped).
--   P_JOB_RUN_ID is present in every new proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_ECI_ADR_S10_SRC (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT '') RETURN NUMBER AUTHID CURRENT_USER AS
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

    -- ---- Step 10: SRC_ADDRESSES (verbatim from current main)
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_ADR_S10_SRC';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_ECI_ADR_S10_SRC AS WITH
    lkp_cv AS (SELECT * FROM TABLE(fn_snow_helper41_common()))
    SELECT s.SOURCE_TABLE, s.ID, s.ID_FAMILY_ADDRESS, s.ADDRESS1, s.ADDRESS2, s.ADDRESS_CD, s.CITY_NAME,
           s.COUNTY_NAME, s.STATE_ABBREV, s.ZIP_CODE, s.ZIP_SFX, s.LAST_UPDATE_DATE,
           LPAD(TO_CHAR(s.ID), 10, '0') || CASE WHEN s.SOURCE_TABLE = 'ECI_FAMILY' THEN 'F' ELSE '' END   AS pty_src_key,
           LPAD(TO_CHAR(s.ID), 10, '0') || CASE WHEN s.SOURCE_TABLE = 'ECI_FAMILY' THEN 'F' ELSE '' END || '|Member'
                                                                                           AS pty_rle_fk,
           at.MSTR_CODE_VALUE                                                              AS mstr_addr_tp
      FROM V_ECI_ETL_SRC_FAMILY_ADDRESS s
      LEFT JOIN lkp_cv at ON at.CODE_TYPE = 'ADDR_TP' AND at.SRC_SYS = 'ECI'
                         AND at.SRC_CODE_VALUE = s.ADDRESS_CD]';
    SELECT COUNT(*) INTO l_rows FROM WRK_ECI_ADR_S10_SRC;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'SRC_ADDRESSES', 'COMPLETED', NULL, 'Step 10 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_ECI_ADR_S10_SRC;
/

