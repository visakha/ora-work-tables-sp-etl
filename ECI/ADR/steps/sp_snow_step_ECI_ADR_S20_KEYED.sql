-- ============================================================================
-- sp_snow_step_ECI_ADR_S20_KEYED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI)
--
-- Mapping: m_Tgt_C_S_ECI_Pty_Addr, workflow wf_ECI_Stage_Load, step 20.
-- Step name (checkpoint): KEYED_ACTIVE.
--
-- WHAT THIS STEP PRODUCES
--   WRK_ECI_ADR_S20_KEYED: Active addresses only, each with its record key (original keyed CTE).
--
-- DOES IT FEED THE SPINE?
--   Indirectly: feeds the validation step, and through it the publish spine branch. It writes no target itself.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (default 'WRK_ECI_ADR_S10_SRC').
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
--   The CTAS below is the current step-20 SELECT verbatim. Only
--   substitutions: :l_run_ts -> :P_RUN_TS, :c_mapping -> the local
--   constant below (same value), original-param refs -> this proc's
--   params. No business expression, filter, guard or column list was
--   changed. Original params used by this step's SQL: none (grep of this step's SQL finds neither P_MEMBER_HIERARCHY_CODE nor P_MEMBER_HM_REL_TP_CD), so neither is in this signature.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   with the same STEP_NAME and message as the current step-20 checkpoint (v2 10-argument form; STEP_NO, row count, and work-table arguments dropped).
--   P_JOB_RUN_ID is present in every new proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_ECI_ADR_S20_KEYED (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_ADR_S10_SRC') RETURN NUMBER AUTHID CURRENT_USER AS
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

    -- ---- Step 20: KEYED_ACTIVE (verbatim from current main)
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_ADR_S20_KEYED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_ECI_ADR_S20_KEYED AS SELECT s.*,
           s.pty_rle_fk || '|' || NVL(s.mstr_addr_tp, '') || '|'
           || NVL(LPAD(TO_CHAR(s.ID_FAMILY_ADDRESS), 10, '0'), '') || '|'
           || NVL(TRIM(UPPER(s.ADDRESS1)), '') || '|' || NVL(TRIM(UPPER(s.ADDRESS2)), '') || '|'
           || NVL(UPPER(s.CITY_NAME), '') || '|' || NVL(UPPER(s.STATE_ABBREV), '') || '|'
           || NVL(s.ZIP_CODE, '') || '|' || NVL(s.ZIP_SFX, '')                             AS pkey_src_object
      FROM WRK_ECI_ADR_S10_SRC s
     WHERE NOT EXISTS (SELECT 1 FROM STG_ECI_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = s.pty_src_key = 1 AND i.ROWID_SYSTEM = 'ECI'
                          AND i.DEACTIVATION_STS IS NOT NULL)]';
    SELECT COUNT(*) INTO l_rows FROM WRK_ECI_ADR_S20_KEYED;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'KEYED_ACTIVE', 'COMPLETED', NULL, 'Step 20 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_ECI_ADR_S20_KEYED;
/

