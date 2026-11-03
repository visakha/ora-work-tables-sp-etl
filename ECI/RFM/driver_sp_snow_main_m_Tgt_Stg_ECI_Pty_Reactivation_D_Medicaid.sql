-- ============================================================================
-- sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid
--   --  MODULAR REWRITE, CONFIG-DRIVEN STEP DRIVER (ECI example)
--
-- IDQ mapping: m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid, workflow
-- wf_ECI_Stage_Load. Install schema is ECI_ETL_WRK in database
-- MDM_ETL_ECI; all table names below are unqualified, except the config
-- table, which is COMMON-qualified (COMMON.ETL_RUN_CONFIG_TBL).
--
-- BUSINESS FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_ECI_RFM_S10_LATEST   latest history row per Medicaid
--                                     record of reactivated children,
--                                     plus the delta-table lookup key
--   Step 20  WRK_ECI_RFM_S20_KEEPNEW  rows passing the keep-new filter,
--                                     one row per Medicaid id
--   Step 30  PUBLISH                STG_ECI_D_MEDICAID, in one
--                                     transaction
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- THIS MAPPING'S OUTCOME IS THE STATUS / DIMENSION WRITE
--   The step-30 publish into STG_ECI_D_MEDICAID is the mapping's
--   outcome: the latest history Medicaid rows of reactivated children
--   landing in the delta table. There is no second publish branch and
--   no non-spine branch for this mapping -- the single INSERT in the
--   publish proc is the whole publish. A run that skips step 30 by
--   config therefore writes nothing to any target.
--
-- CONFIG-DRIVEN NOTES
--   Before step 5, the driver reads COMMON.ETL_RUN_CONFIG_TBL (columns
--   WORKFLOW_NAME, MAPPING_NAME, STEP_NO, STEP_PROC_NAME,
--   IS_DRIVER, IS_RUN_ENABLED, IS_DEPENDENT, DEPENDENT_ON,
--   WORK_TABLES_PRODUCED, WORK_TABLES_CONSUMED) for this workflow +
--   mapping. One SELECT gathers, per step, IS_RUN_ENABLED (the run
--   flag) and WORK_TABLES_CONSUMED (the work-table inputs the step
--   proc must check). Flags are pre-initialised to 'Y' and consumed
--   strings to their defaults, and the gather runs in a nested
--   BEGIN/EXCEPTION block: if the config table is missing or
--   unreadable, the exception handler leaves the defaults standing and
--   the mapping runs every step, exactly as before config.
--   The driver row is STEP_NO = 0: if its flag is 'N', the driver
--   writes a MAPPING_SKIPPED checkpoint row, finishes the job, and
--   RETURNS early -- BEFORE step 5 cleanup, so a disabled mapping
--   never drops a previous run's work tables.
--   A step whose flag is 'N' is not called: the driver writes a
--   SKIPPED checkpoint row for that step and a plain-text summary
--   line (helper36 is NOT used for skips -- it renders NULL as
--   '0 row(s)'). The driver consumes only IS_RUN_ENABLED and
--   WORK_TABLES_CONSUMED; STEP_PROC_NAME, IS_DRIVER, IS_DEPENDENT,
--   DEPENDENT_ON and WORK_TABLES_PRODUCED are not read here (they are
--   for runner / orchestration use).
--   NOTE ON DEPENDENCY CHAIN: skipping an upstream step while a
--   downstream step stays enabled is a config error, not a silent
--   no-op -- the downstream step's existence check raises on the
--   missing work table and the driver fails the run. Enable the chain
--   together (10, 20, 30) or disable the mapping at STEP_NO = 0.
--
-- TRANSACTION EDGES (framework rule)
--   Never call a checkpoint between BEGIN TRANSACTION and COMMIT.
--   Step checkpoints autocommit (they run outside any transaction).
--   The publish transaction contains ONLY the branch-proc call; the
--   step-30 checkpoint is written AFTER COMMIT. The exception handler
--   rolls back first, then checkpoints, so the failure rows survive.
--
-- WORK TABLES (all TRANSIENT)
--   WRK_ECI_RFM_S10_LATEST, WRK_ECI_RFM_S20_KEEPNEW. They live in the
--   same schema as the targets (unqualified names, as in the original
--   code) and are prefixed WRK_ECI_. They survive a session crash
--   (TRANSIENT, not TEMP). No CURSOR was used: every step here is
--   set-based by design.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * PRESERVED DEFECT: the keep-new filter tests the SOURCE port
--     ID_MEDICAID, not the lookup result, when P_TEST_LOOKUP_RESULT
--     is 'N' (the default). ID_MEDICAID is the history key and never
--     NULL, so with the default the mapping writes no rows, exactly as
--     IDQ does. Passing 'Y' tests the lookup result instead and keeps
--     records not yet in STG_ECI_D_MEDICAID (the intended behaviour,
--     as the family address / phone reactivation mappings do).
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets. STG_ECI_D_MEDICAID has primary key
--     ID_MEDICAID, which Snowflake does not enforce: with 'Y', one row
--     per ID_MEDICAID is written and ids already in the table are
--     skipped (the step-20 rank plus the lookup filter).
--   * No validation rule runs here; preserved.
--   * FLAG: this original has no CTE chain, so the split below is the
--     closest sensible split (latest rows plus lookup, then keep-new
--     filter plus rank, then publish), not a CTE-boundary split.
--
-- SKIPPED VOCABULARY NOTE (choice to confirm with the user)
--   JOB_CONTROL_ETL.STEP_STATUS has NO CHECK constraint (only a DDL
--   comment listing STARTED|COMPLETED|FAILED), so 'SKIPPED' rows are
--   written for config-skipped steps and for a config-skipped mapping.
--   This is used here and will be flagged to the user as a choice to
--   confirm, not silently assumed to be sanctioned.
--
-- SIGNATURE (identical to the current main -- every existing CALL
-- still works)
--   The original parameter is unchanged and in the same order, so
--   every existing CALL still works. One parameter was APPENDED:
--     P_TEST_LOOKUP_RESULT VARCHAR  DEFAULT 'N'
--     P_JOB_RUN_ID         VARCHAR  DEFAULT NULL  -- NULL = start a new
--                                             run (a run id is generated
--                                             and returned in the summary).
--   A restart is simply a new run: the mapping cleans up the
--   previous run's work tables at its start (step 5) and runs
--   every step from scratch. There is no step-level restart.
--
-- COMPILE-TIME VERIFICATION ITEMS (no live Snowflake here)
--   * Procedure-call return capture uses the Snowflake Scripting
--     scalar-call form `l_rows := (CALL proc(...));` -- verify it
--     compiles in the target Snowflake account before use.
--   * The RAISE EXCEPTION form with a concatenated message in the step
--     and publish procs -- verify it compiles; if it does not, the
--     fallback is EXECUTE IMMEDIATE 'SELECT 1 FROM <missing table>'
--     to surface the native object-not-exists error.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid (P_TEST_LOOKUP_RESULT IN VARCHAR2 DEFAULT 'N', P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid';
    l_job_run_id VARCHAR2(4000);
    l_run_ts TIMESTAMP;
    l_rows NUMBER DEFAULT 0;
    l_pub_ECI_RFM_STG_ECI_D_MEDICAID NUMBER DEFAULT 0;
    l_summary VARCHAR2(4000) DEFAULT '';
    l_flag_ECI_RFM_DRIVER VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_RFM_S10_LATEST VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_RFM_S20_KEEPNEW VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_RFM_STG_ECI_D_MEDICAID VARCHAR2(4000) DEFAULT 'Y';
    l_in_ECI_RFM_S10_LATEST VARCHAR2(4000) DEFAULT '';
    l_in_ECI_RFM_S20_KEEPNEW VARCHAR2(4000) DEFAULT 'WRK_ECI_RFM_S10_LATEST';
    l_in_ECI_RFM_STG_ECI_D_MEDICAID VARCHAR2(4000) DEFAULT 'WRK_ECI_RFM_S20_KEEPNEW';
BEGIN
    -- ---- STARTING -------------------------------------------------------
    -- Job-run-id generation, exactly as now (l_job_run_id starts NULL,
    -- so this branch always runs; the net effect is: a supplied run id
    -- is used, otherwise one is generated).
    IF (l_job_run_id IS NULL OR l_job_run_id = '') THEN
        l_job_run_id := COALESCE(NULLIF(P_JOB_RUN_ID, ''),
            'ECI_' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDD_HH24MISS')
            || '_' || RAWTOHEX(SYS_GUID()));
    END IF;
    l_run_ts := SYSTIMESTAMP;
    sp_etl_job_begin('ECI', c_workflow, c_mapping, l_job_run_id);

    -- ---- CONFIG GATHER ---------------------------------------------------
    -- Flags pre-initialised to 'Y', consumed strings to their defaults
    -- (see DECLARE). On any exception the defaults stand, so a missing
    -- or unreadable config table means "run everything", as before.
    BEGIN
        SELECT
            COALESCE(MAX(CASE WHEN STEP_NO = 0 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
            COALESCE(MAX(CASE WHEN STEP_NO = 10 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
            COALESCE(MAX(CASE WHEN STEP_NO = 20 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
            COALESCE(MAX(CASE WHEN STEP_NO = 30 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
            COALESCE(MAX(CASE WHEN STEP_NO = 10 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), ''),
            COALESCE(MAX(CASE WHEN STEP_NO = 20 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_RFM_S10_LATEST'),
            COALESCE(MAX(CASE WHEN STEP_NO = 30 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_RFM_S20_KEEPNEW')
          INTO l_flag_ECI_RFM_DRIVER, l_flag_ECI_RFM_S10_LATEST, l_flag_ECI_RFM_S20_KEEPNEW, l_flag_ECI_RFM_STG_ECI_D_MEDICAID,
               l_in_ECI_RFM_S10_LATEST, l_in_ECI_RFM_S20_KEEPNEW, l_in_ECI_RFM_STG_ECI_D_MEDICAID
          FROM COMMON.ETL_RUN_CONFIG_TBL
         WHERE WORKFLOW_NAME = c_workflow
           AND MAPPING_NAME = c_mapping;
    WHEN OTHERS THEN
            l_flag_ECI_RFM_DRIVER := COALESCE(l_flag_ECI_RFM_DRIVER, 'Y');
            l_flag_ECI_RFM_S10_LATEST := COALESCE(l_flag_ECI_RFM_S10_LATEST, 'Y');
            l_flag_ECI_RFM_S20_KEEPNEW := COALESCE(l_flag_ECI_RFM_S20_KEEPNEW, 'Y');
            l_flag_ECI_RFM_STG_ECI_D_MEDICAID := COALESCE(l_flag_ECI_RFM_STG_ECI_D_MEDICAID, 'Y');
            l_in_ECI_RFM_S10_LATEST := COALESCE(l_in_ECI_RFM_S10_LATEST, '');
            l_in_ECI_RFM_S20_KEEPNEW := COALESCE(l_in_ECI_RFM_S20_KEEPNEW, 'WRK_ECI_RFM_S10_LATEST');
            l_in_ECI_RFM_STG_ECI_D_MEDICAID := COALESCE(l_in_ECI_RFM_STG_ECI_D_MEDICAID, 'WRK_ECI_RFM_S20_KEEPNEW');
    END;

    -- ---- DRIVER-ROW DISABLE: skip the whole mapping, BEFORE cleanup -----
    IF (l_flag_ECI_RFM_DRIVER <> 'Y') THEN
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'MAPPING_SKIPPED', 'SKIPPED', NULL, 'Mapping skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N for STEP_NO 0).', NULL);
        sp_etl_job_finish('ECI', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid skipped by config. JOB_RUN_ID = ' || l_job_run_id);
        RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10)
            || 'MAPPING_SKIPPED by config (IS_RUN_ENABLED = N for STEP_NO 0)' || CHR(10);
    END IF;

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Drops only, no checkpoint call for drops.
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_RFM_S10_LATEST';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_RFM_S20_KEEPNEW';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;

    -- ---- Step 10: LATEST HISTORY ROWS + LOOKUP ----------------------------
    IF (l_flag_ECI_RFM_S10_LATEST = 'Y') THEN
        l_rows := sp_snow_step_ECI_RFM_S10_LATEST(l_job_run_id, l_run_ts, l_in_ECI_RFM_S10_LATEST);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 10 LATEST_HISTORY_ROWS', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'LATEST_HISTORY_ROWS', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 10 LATEST_HISTORY_ROWS: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 20: KEEP-NEW FILTER + ONE ROW PER ID ------------------------
    IF (l_flag_ECI_RFM_S20_KEEPNEW = 'Y') THEN
        l_rows := sp_snow_step_ECI_RFM_S20_KEEPNEW(P_TEST_LOOKUP_RESULT, l_job_run_id, l_run_ts, l_in_ECI_RFM_S20_KEEPNEW);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 20 KEEP_NEW_ONLY', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'KEEP_NEW_ONLY', 'SKIPPED', 'STG_ECI_D_MEDICAID', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 20 KEEP_NEW_ONLY: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 30: PUBLISH -- one transaction, one target ----------------
    -- This is the ONLY step that writes to a final target, and the only
    -- step inside an explicit transaction. No checkpoint is written
    -- inside the transaction; the branch checkpoint follows COMMIT.
    -- (Snowflake BEGIN TRANSACTION removed: Oracle transactions are implicit)
    IF (l_flag_ECI_RFM_STG_ECI_D_MEDICAID = 'Y') THEN
        l_pub_ECI_RFM_STG_ECI_D_MEDICAID := sp_snow_pub_ECI_RFM_STG_ECI_D_MEDICAID(l_job_run_id, l_run_ts, l_in_ECI_RFM_STG_ECI_D_MEDICAID);
    END IF;
    COMMIT;
    IF (l_flag_ECI_RFM_STG_ECI_D_MEDICAID = 'Y') THEN
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_STG_ECI_D_MEDICAID', 'COMPLETED', 'STG_ECI_D_MEDICAID', 'Published in one transaction: latest history Medicaid rows of reactivated children '
            || 'into the delta table. Count shown is rows inserted (0 with the default parameter).', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 30 PUBLISH_STG_ECI_D_MEDICAID', l_pub_ECI_RFM_STG_ECI_D_MEDICAID) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_STG_ECI_D_MEDICAID', 'SKIPPED', 'STG_ECI_D_MEDICAID', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 30 PUBLISH_STG_ECI_D_MEDICAID: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- TERMINATING ------------------------------------------------------
    sp_etl_job_finish('ECI', l_job_run_id, c_workflow, c_mapping,
        'm_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid completed. JOB_RUN_ID = ' || l_job_run_id);
    RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
WHEN OTHERS THEN
        ROLLBACK;
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'TERMINATING',
            'JOB_END', 'FAILED', NULL, 'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. '
            || 'See ALL_TABLES for WRK_% tables in this schema and VW_ETL_JOB_STORY for the last completed step.', 'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        sp_etl_job_fail('ECI', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid;
/

