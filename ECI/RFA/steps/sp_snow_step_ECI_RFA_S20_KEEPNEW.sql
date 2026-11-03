-- ============================================================================
-- sp_snow_step_ECI_RFA_S20_KEEPNEW  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI)
--
-- Mapping: m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr, workflow
-- wf_ECI_Stage_Load, step 20.
-- Step name (checkpoint): KEEP_NEW_ONLY.
--
-- WHAT THIS STEP PRODUCES
--   WRK_ECI_RFA_S20_KEEPNEW: the step-10 latest rows that are not
--   already in the delta table STG_ECI_D_FAMILY_ADDRESS. This is the
--   original lookup plus keep-new filter. It reads ONLY step 10, so
--   the filter sees the delta table as it was before this run's
--   publish, exactly as in the original.
--
-- DOES IT FEED THE REACTIVATION STATUS WRITE?
--   Yes, directly: step 30 publishes exactly this table into
--   STG_ECI_D_FAMILY_ADDRESS -- the reactivation delta/status write
--   that causes the downstream address mapping to re-send these
--   addresses to the MDM. This step writes no target itself.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only: 'WRK_ECI_RFA_S10_LATEST'.
--   The delta table STG_ECI_D_FAMILY_ADDRESS is a guard table, not a
--   work-table dependency, so it is not listed (but it is still read
--   literally by the CTAS, as in the current main procedure).
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-20 SELECT verbatim. Only
--   substitutions: :l_run_ts -> :P_RUN_TS (not used by this step --
--   the original step has no run-timestamp column),
--   :c_mapping -> the local constant below (used by the checkpoint).
--   No business expression, filter, guard or column list was changed.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   with the same STEP_NAME, TARGET_TABLE, and message as the current step-20 checkpoint (note: the
--   step-20 checkpoint names STG_ECI_D_FAMILY_ADDRESS as TARGET_TABLE
--   even though this step does not write it -- preserved as-is).
--   P_JOB_RUN_ID is present in every new proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_ECI_RFA_S20_KEEPNEW (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_RFA_S10_LATEST') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr';
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

    -- ---- Step 20: KEEP-NEW FILTER (verbatim from current main)
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_RFA_S20_KEEPNEW';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_ECI_RFA_S20_KEEPNEW AS SELECT h.*
      FROM WRK_ECI_RFA_S10_LATEST h
     WHERE NOT EXISTS (SELECT 1 FROM STG_ECI_D_FAMILY_ADDRESS d
                        WHERE d.ID_FAMILY_ADDRESS = h.ID_FAMILY_ADDRESS)]';
    SELECT COUNT(*) INTO l_rows FROM WRK_ECI_RFA_S20_KEEPNEW;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'KEEP_NEW_ONLY', 'COMPLETED', 'STG_ECI_D_FAMILY_ADDRESS', 'Step 20 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_ECI_RFA_S20_KEEPNEW;
/

