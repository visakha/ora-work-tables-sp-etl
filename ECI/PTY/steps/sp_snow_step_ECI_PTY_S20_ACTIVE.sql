-- ============================================================================
-- sp_snow_step_ECI_PTY_S20_ACTIVE  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI)
--
-- Mapping: m_Tgt_C_S_ECI_Pty, workflow wf_ECI_Stage_Load, step 20.
-- Step name (checkpoint): ACTIVE_PARTIES.
--
-- WHAT THIS STEP PRODUCES
--   WRK_ECI_PTY_S20_ACTIVE: active parties only (no deactivation
--   status). This is the original active CTE (lookup on
--   STG_ECI_PTY_INACTIVE_STS plus the inactive filter). Note the
--   stored inactive filter condition is written as a comment in IDQ
--   ("--not IsNull(...)"), so ACTIVE parties are kept; preserved as
--   the NOT EXISTS filter below.
--
-- DOES IT FEED THE SPINE?
--   Indirectly: the publish spine branches read step 50, which derives
--   from this step. It writes no target itself.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (base source tables and
--   target guard tables are not work-table dependencies). Default:
--   'WRK_ECI_PTY_S10_SRC'. Snowflake cannot parameterise table names
--   in static SQL, so P_INPUT_TABLES is a dependency declaration +
--   runtime check, NOT dynamic SQL: the CTAS below still names its
--   source literally, as in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-20 SELECT verbatim. Only
--   substitutions: :c_mapping -> the local constant below (used by the
--   checkpoint). No business expression, filter, guard or column list
--   was changed. This step uses neither original parameter.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   with the same STEP_NAME and message as the current step-20 checkpoint (v2 10-argument form; STEP_NO, row count, and work-table arguments dropped).
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_ECI_PTY_S20_ACTIVE (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_PTY_S10_SRC') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_ECI_Pty';
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

    -- ---- Step 20: ACTIVE PARTIES ONLY (verbatim from current main)
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_PTY_S20_ACTIVE';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_ECI_PTY_S20_ACTIVE AS SELECT e.*
      FROM WRK_ECI_PTY_S10_SRC e
     WHERE NOT EXISTS (SELECT 1 FROM STG_ECI_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = e.pkey_src_object = 1 AND i.ROWID_SYSTEM = e.src_system = 1 AND i.DEACTIVATION_STS IS NOT NULL)]';
    SELECT COUNT(*) INTO l_rows FROM WRK_ECI_PTY_S20_ACTIVE;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'ACTIVE_PARTIES', 'COMPLETED', NULL, 'Step 20 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_ECI_PTY_S20_ACTIVE;
/

