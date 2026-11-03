-- ============================================================================
-- sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr
--   --  MODULAR REWRITE, CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI ONLY)
--
-- IDQ mapping: m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr, workflow
-- wf_ECI_Stage_Load. Install schema is ECI_ETL_WRK in database
-- MDM_ETL_ECI; all table names below are unqualified.
--
-- WHAT THIS MAPPING DOES, IN PLAIN WORDS
--   Moves the latest history row of each address of a reactivated
--   family into the delta table, so the address mapping re-sends it to
--   the MDM. Addresses already in the delta table are skipped.
--
-- BUSINESS FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_ECI_RFA_S10_LATEST   latest history row per address of
--                                     reactivated families
--   Step 20  WRK_ECI_RFA_S20_KEEPNEW  latest rows not already in the
--                                     delta table
--   Step 30  PUBLISH                STG_ECI_D_FAMILY_ADDRESS, in one
--                                     transaction
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--   NOTE ON THE OUTCOME: this mapping's outcome IS the STATUS /
--   dimension write. The publish writes STG_ECI_D_FAMILY_ADDRESS --
--   the reactivation delta/status table -- and there is NO other
--   branch: no EXC branch, no non-spine branch, no second target.
--   The single publish branch below is the whole publish.
--
-- CONFIG-DRIVEN EXECUTION (COMMON.ETL_RUN_CONFIG_TBL)
--   Before step 5, the driver reads one row set from
--   COMMON.ETL_RUN_CONFIG_TBL for this workflow + mapping:
--     * STEP_NO 0  (driver row): IS_RUN_ENABLED = 'N' skips the whole
--       mapping -- SKIPPED checkpoint (STEP_NAME MAPPING_SKIPPED),
--       sp_etl_job_finish, RETURN -- BEFORE any step-5 cleanup, so a
--       skipped run never destroys the previous run's work tables.
--     * STEP_NO 10 / 20 / 30: IS_RUN_ENABLED = 'N' skips that step or
--       branch only. A skipped step writes a SKIPPED checkpoint row
--       (same STEP_NAME as the step, STATE 'WORKING') and a
--       plain-text summary line; helper36 is NOT used for skips,
--       because it renders NULL as '0 row(s)'. A skipped publish
--       branch is not called at all.
--     * WORK_TABLES_CONSUMED per step overrides the P_INPUT_TABLES
--       passed to the step / publish proc (the dependency declaration
--       + runtime existence check); defaults are the literals below.
--   Flags default to 'Y' and consumed strings to their default
--   literals BEFORE the SELECT, so if the config table is missing or
--   unreadable the GATHER exception handler leaves the defaults
--   standing and the mapping runs exactly as before (all steps on).
--   SKIPPED vocabulary note: JOB_CONTROL_ETL.STEP_STATUS has NO CHECK
--   constraint (a DDL comment that in v2 lists STARTED | COMPLETED | FAILED | SKIPPED), so 'SKIPPED' rows are used here and are flagged to the
--   user as a choice to confirm.
--
-- TRANSACTION EDGES (framework rule -- read before changing anything)
--   Step checkpoints are written by the step procs themselves, outside
--   any transaction, so they autocommit and survive a later rollback.
--   The ONLY explicit transaction is the publish: BEGIN TRANSACTION,
--   conditionally CALL the publish-branch proc, COMMIT -- and only
--   AFTER COMMIT does the driver checkpoint the publish branch, so a
--   publish checkpoint can never roll back with the publish itself.
--   Never call a checkpoint between BEGIN TRANSACTION and COMMIT.
--   The publish-branch proc itself has NO transaction control and NO
--   checkpoint calls. The driver exception handler ROLLBACKs first,
--   then checkpoints, so its rows are not rolled back either.
--
-- WORK TABLES (all TRANSIENT)
--   WRK_ECI_RFA_S10_LATEST, WRK_ECI_RFA_S20_KEEPNEW. They live in the
--   same schema as the targets (unqualified names, as in the original
--   code) and are prefixed WRK_ECI_. They survive a session crash
--   (TRANSIENT, not TEMP). No CURSOR was used: every step here is
--   set-based by design.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets. Rows already in the delta table are skipped
--     (the keep-new filter); the filter reads the delta table as it
--     was before the publish, because it is evaluated in step 20,
--     before any insert happens.
--   * No validation rule runs here; preserved.
--   * FLAG (from the current main): this original has no CTE chain, so
--     the split below is the closest sensible split (latest rows, then
--     keep-new filter, then publish), not a CTE-boundary split.
--   * Publish checkpoint STEP_NAME is 'PUBLISH_STG_ECI_D_FAMILY_ADDRESS'
--     (PUBLISH_<TARGET>) in this refactor, where the current main used
--     plain 'PUBLISH'; see RFA_MANIFEST.md. Everything else about the
--     publish checkpoint (TARGET_TABLE, message) is the same.
--
-- SIGNATURE (identical to the current main -- name and parameters)
--   The original procedure took no parameters, so there are no original
--   parameters to preserve. One parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run
--                                             (a run id is generated and
--                                             returned in the summary).
--   A restart is simply a new run: the mapping cleans up the
--   previous run's work tables at its start (step 5) and runs
--   every step from scratch. There is no step-level restart.
--   COMPILE-TIME VERIFICATION ITEM (no live Snowflake here):
--   procedure-call return capture uses the Snowflake Scripting
--   scalar-call form `l_rows := (CALL proc(...));` -- confirm at first
--   compile, as must the RAISE EXCEPTION form used by the step /
--   publish procs (see RFA_MANIFEST.md).
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr';
    l_job_run_id VARCHAR2(4000);
    l_run_ts TIMESTAMP DEFAULT SYSTIMESTAMP;
    l_rows NUMBER DEFAULT 0;
    l_pub_ECI_RFA_STG_ECI_D_FAMILY_ADDRESS NUMBER DEFAULT 0;
    l_summary VARCHAR2(4000) DEFAULT '';
    l_config_ok NUMBER(1) DEFAULT 1;
    l_flag_ECI_RFA_DRIVER VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_RFA_S10_LATEST VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_RFA_S20_KEEPNEW VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_RFA_STG_ECI_D_FAMILY_ADDRESS VARCHAR2(4000) DEFAULT 'Y';
    l_in_ECI_RFA_S10_LATEST VARCHAR2(4000) DEFAULT '';
    l_in_ECI_RFA_S20_KEEPNEW VARCHAR2(4000) DEFAULT 'WRK_ECI_RFA_S10_LATEST';
    l_in_ECI_RFA_STG_ECI_D_FAMILY_ADDRESS VARCHAR2(4000) DEFAULT 'WRK_ECI_RFA_S20_KEEPNEW';
BEGIN
    -- ---- STARTING: job-run-id generation, exactly as in the current main
    IF (l_job_run_id IS NULL OR l_job_run_id = '') THEN
        l_job_run_id := COALESCE(NULLIF(P_JOB_RUN_ID, ''),
            'ECI_' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDD_HH24MISS')
            || '_' || RAWTOHEX(SYS_GUID()));
    END IF;
    sp_etl_job_begin('ECI', c_workflow, c_mapping, l_job_run_id);

    -- ---- GATHER config: flags + consumed strings, defaults stand on error
    BEGIN
        SELECT COALESCE(MAX(CASE WHEN STEP_NO = 0 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 10 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 20 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 30 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 10 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), ''),
               COALESCE(MAX(CASE WHEN STEP_NO = 20 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_RFA_S10_LATEST'),
               COALESCE(MAX(CASE WHEN STEP_NO = 30 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_RFA_S20_KEEPNEW')
          INTO l_flag_ECI_RFA_DRIVER, l_flag_ECI_RFA_S10_LATEST, l_flag_ECI_RFA_S20_KEEPNEW, l_flag_ECI_RFA_STG_ECI_D_FAMILY_ADDRESS,
               l_in_ECI_RFA_S10_LATEST, l_in_ECI_RFA_S20_KEEPNEW, l_in_ECI_RFA_STG_ECI_D_FAMILY_ADDRESS
          FROM COMMON.ETL_RUN_CONFIG_TBL
         WHERE WORKFLOW_NAME = c_workflow
           AND MAPPING_NAME = c_mapping;
    WHEN OTHERS THEN
            l_config_ok := 0;
    END;

    -- ---- Driver-row disable: skip the whole mapping BEFORE step 5 cleanup
    IF (l_flag_ECI_RFA_DRIVER = 'N') THEN
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'MAPPING_SKIPPED', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N for STEP_NO 0).', NULL);
        l_summary := l_summary || 'MAPPING_SKIPPED: SKIPPED by config (IS_RUN_ENABLED = N for STEP_NO 0)' || CHR(10);
        sp_etl_job_finish('ECI', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N for STEP_NO 0). JOB_RUN_ID = ' || l_job_run_id);
        RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
    END IF;

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Drops only, no checkpoint call for drops.
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_RFA_S10_LATEST';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_RFA_S20_KEEPNEW';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;

    -- ---- Step 10: LATEST_HISTORY_ROWS ------------------------------------
    IF (l_flag_ECI_RFA_S10_LATEST = 'Y') THEN
        l_rows := sp_snow_step_ECI_RFA_S10_LATEST(l_job_run_id, l_run_ts, l_in_ECI_RFA_S10_LATEST);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 10 LATEST_HISTORY_ROWS', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'LATEST_HISTORY_ROWS', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 10 LATEST_HISTORY_ROWS: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 20: KEEP_NEW_ONLY -----------------------------------------
    IF (l_flag_ECI_RFA_S20_KEEPNEW = 'Y') THEN
        l_rows := sp_snow_step_ECI_RFA_S20_KEEPNEW(l_job_run_id, l_run_ts, l_in_ECI_RFA_S20_KEEPNEW);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 20 KEEP_NEW_ONLY', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'KEEP_NEW_ONLY', 'SKIPPED', 'STG_ECI_D_FAMILY_ADDRESS', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 20 KEEP_NEW_ONLY: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 30: PUBLISH -- one transaction, one target, one branch ----
    -- This is the ONLY step that writes to a final target, and the only
    -- step inside an explicit transaction. No checkpoint is called
    -- between BEGIN TRANSACTION and COMMIT: the branch checkpoint
    -- below runs only AFTER COMMIT.
    -- (Snowflake BEGIN TRANSACTION removed: Oracle transactions are implicit)
    IF (l_flag_ECI_RFA_STG_ECI_D_FAMILY_ADDRESS = 'Y') THEN
        l_pub_ECI_RFA_STG_ECI_D_FAMILY_ADDRESS := sp_snow_pub_ECI_RFA_STG_ECI_D_FAMILY_ADDRESS(l_job_run_id, l_run_ts, l_in_ECI_RFA_STG_ECI_D_FAMILY_ADDRESS);
    END IF;
    COMMIT;
    IF (l_flag_ECI_RFA_STG_ECI_D_FAMILY_ADDRESS = 'Y') THEN
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_STG_ECI_D_FAMILY_ADDRESS', 'COMPLETED', 'STG_ECI_D_FAMILY_ADDRESS', 'Published in one transaction: latest history address rows of reactivated families '
            || 'into the delta table. Count shown is rows inserted.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 30 PUBLISH_STG_ECI_D_FAMILY_ADDRESS', l_pub_ECI_RFA_STG_ECI_D_FAMILY_ADDRESS) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_STG_ECI_D_FAMILY_ADDRESS', 'SKIPPED', 'STG_ECI_D_FAMILY_ADDRESS', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 30 PUBLISH_STG_ECI_D_FAMILY_ADDRESS: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- TERMINATING ------------------------------------------------------
    sp_etl_job_finish('ECI', l_job_run_id, c_workflow, c_mapping,
        'm_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr completed. JOB_RUN_ID = ' || l_job_run_id);
    RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
WHEN OTHERS THEN
        ROLLBACK;
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'TERMINATING',
            'JOB_END', 'FAILED', NULL, 'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. '
            || 'See ALL_TABLES for WRK_% tables in this schema and VW_ETL_JOB_STORY for the last completed step.', 'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        sp_etl_job_fail('ECI', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr;
/

