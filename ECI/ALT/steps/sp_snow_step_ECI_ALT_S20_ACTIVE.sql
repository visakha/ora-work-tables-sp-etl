-- ============================================================================
-- sp_snow_step_ECI_ALT_S20_ACTIVE  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI)
--
-- Mapping: m_Tgt_C_S_ECI_Pty_Rle_Alt_Id, workflow wf_ECI_Stage_Load,
-- step 20. Step name (checkpoint): ACTIVE_ALT_IDS.
--
-- WHAT THIS STEP PRODUCES
--   WRK_ECI_ALT_S20_ACTIVE: ids whose party (first 11 characters of
--   the role key, '|' trimmed) has no deactivation status. This is the
--   original active CTE.
--
-- DOES IT FEED THE SPINE?
--   Indirectly: it is the second staged step; the validation, ready
--   and publish spine branch all read (transitively) from it. It
--   writes no target itself.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only: WRK_ECI_ALT_S10_SRC
--   by default. Base source tables (STG_ECI_PTY_INACTIVE_STS, the
--   deactivation-status guard table) and target guard tables are NOT
--   work-table dependencies and are not listed. Snowflake cannot
--   parameterise table names in static SQL, so P_INPUT_TABLES is a
--   dependency declaration + runtime check, NOT dynamic SQL: the CTAS
--   below still names its sources literally, as in the current main
--   procedure.
--
-- INPUT EXISTENCE CHECK
--   Skipped when P_INPUT_TABLES is NULL/empty. Otherwise the value is
--   split on '|', each name is trimmed and upper-cased (Snowflake
--   stores unquoted identifiers uppercase), and checked against
--   INFORMATION_SCHEMA.TABLES in the current schema. The first missing
--   table (alphabetically) surfaces via EXECUTE IMMEDIATE
--   'SELECT 1 FROM <missing table>', which raises the native
--   object-not-exists error naming that table; the step is identified
--   by this procedure's name. RAISE is NOT used for this: Snowflake's
--   RAISE takes only a declared exception name, whose message is fixed
--   at declaration and so cannot name a runtime-discovered table.
--   No CURSOR is used: the check is a single set-based query.
--
-- BUSINESS SQL
--   The CTAS below is the current step-20 SELECT verbatim. Only
--   substitutions: :l_run_ts -> :P_RUN_TS (not used by this step),
--   :c_mapping -> the local constant below (used by the checkpoint).
--   No business expression, filter, guard or column list was changed.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   with the same STEP_NAME and message as the current step-20 checkpoint (v2 10-argument form; STEP_NO, row count, and work-table arguments dropped).
--   P_JOB_RUN_ID is present in every new proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_ECI_ALT_S20_ACTIVE (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_ALT_S10_SRC') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_ECI_Pty_Rle_Alt_Id';
    l_rows NUMBER DEFAULT 0;
    l_missing VARCHAR2(4000) DEFAULT NULL;
    l_sql VARCHAR2(4000) DEFAULT NULL;
    l_probe_dummy NUMBER;
SELECT MIN(s.tbl) INTO l_missing FROM (SELECT REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL) AS raw, UPPER(TRIM(REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL))) AS tbl FROM DUAL CONNECT BY REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL) IS NOT NULL) s WHERE s.tbl <> '' AND NOT EXISTS (SELECT 1 FROM ALL_TABLES t WHERE t.OWNER = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AND t.TABLE_NAME = s.tbl);
        IF (l_missing IS NOT NULL) THEN
            l_sql := 'SELECT COUNT(*) FROM ' || l_missing;
            EXECUTE IMMEDIATE l_sql INTO l_probe_dummy;
        END IF;
    END IF;

    -- ---- Step 20: ACTIVE PARTIES ONLY (verbatim from current main)
    -- Purpose: drop ids whose party (first 11 characters of the role
    -- key, '|' trimmed) has a deactivation status. This is the
    -- original active CTE.
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_ALT_S20_ACTIVE';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_ECI_ALT_S20_ACTIVE AS SELECT s.*
      FROM WRK_ECI_ALT_S10_SRC s
     WHERE NOT EXISTS (SELECT 1 FROM STG_ECI_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = RTRIM(SUBSTR(s.PTY_REL_FK, 1, 11), '|') AND i.ROWID_SYSTEM = 'ECI'
                          AND i.DEACTIVATION_STS IS NOT NULL)]';
    SELECT COUNT(*) INTO l_rows FROM WRK_ECI_ALT_S20_ACTIVE;
    sp_etl_checkpoint(c_source,
        P_JOB_RUN_ID,
        c_workflow,
        c_mapping,
        'WORKING',
        'ACTIVE_ALT_IDS',
        'COMPLETED',
        NULL,
        'Step 20 complete.',
        NULL);
    RETURN l_rows;
END sp_snow_step_ECI_ALT_S20_ACTIVE;
/

