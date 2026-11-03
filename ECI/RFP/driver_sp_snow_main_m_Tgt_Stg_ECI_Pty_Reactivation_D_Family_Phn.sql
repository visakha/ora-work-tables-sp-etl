-- ============================================================================
-- sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn
--   --  MODULAR REWRITE, CONFIG-DRIVEN STEP DRIVER (ECI example)
--   Driver name and signature are EXACTLY as the current main procedure.
--
-- IDQ mapping: m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn, workflow
-- wf_ECI_Stage_Load. Install schema is ECI_ETL_WRK in database
-- MDM_ETL_ECI; all table names below are unqualified, as in the
-- original code. Config table is COMMON.ETL_RUN_CONFIG_TBL (COMMON
-- schema, qualified).
--
-- WHAT THIS MAPPING DOES, IN PLAIN WORDS — READ TOP TO BOTTOM, IT IS
-- THE BUSINESS FLOW. This mapping's outcome IS the dimension/status
-- write: it moves the latest history row of each phone record of a
-- reactivated family into the delta table. Phone records already in
-- the delta table are skipped. There is no second branch: no EXC
-- branch, no non-spine branch, no other target. The single publish
-- branch below is the whole outcome.
--   Step 10  WRK_ECI_RFP_S10_LATEST   latest history row per phone
--                                     record of reactivated families
--                                     (step proc sp_snow_step_ECI_RFP_S10_LATEST)
--   Step 20  WRK_ECI_RFP_S20_KEEPNEW  latest rows not already in the
--                                     delta table
--                                     (step proc sp_snow_step_ECI_RFP_S20_KEEPNEW)
--   Step 30  PUBLISH                STG_ECI_D_FAMILY_PHONE, in one
--                                     transaction, one INSERT
--                                     (publish proc sp_snow_pub_ECI_RFP_
--                                      STG_ECI_D_FAMILY_PHONE)
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- WHAT CHANGED FROM THE CURRENT MAIN (re-housing only)
--   The current main's two staged steps and its publish INSERT are
--   unchanged business SQL, moved into their own procedures (see those
--   files: each CTAS / INSERT is verbatim). This driver keeps only
--   orchestration: job-run-id generation, config gather, step 5
--   cleanup, conditional step calls, the publish transaction, the
--   publish checkpoint after COMMIT, TERMINATING, and the exception
--   handler. No business expression, filter, guard, or column list
--   was changed anywhere in this refactor. FLAG (carried over): the
--   original has no CTE chain, so the split (latest rows, then
--   keep-new filter, then publish) is the closest sensible split,
--   not a CTE-boundary split.
--
-- CONFIG-DRIVEN NOTES (COMMON.ETL_RUN_CONFIG_TBL)
--   Before step 5, the driver GATHERs one row-set for this workflow +
--   mapping: IS_RUN_ENABLED per STEP_NO (0 = driver row, 10, 20, 30)
--   and WORK_TABLES_CONSUMED per STEP_NO (10, 20, 30). Every flag is
--   pre-initialised to 'Y' and every consumed string to its default
--   literal, so if the config table is missing or unreadable the
--   nested GATHER block's exception handler leaves the defaults
--   standing and the run proceeds exactly as the current main did.
--   A config row with no match for a STEP_NO likewise falls back to
--   its COALESCE default. The gathered consumed strings are passed as
--   P_INPUT_TABLES to the step/publish procedures, where they act as
--   a dependency declaration plus a runtime existence check — the
--   step/publish SQL itself still reads its fixed table names
--   (Snowflake cannot parameterise table names in static SQL).
--   * STEP_NO 0 = 'N' disables the whole mapping: a SKIPPED
--     checkpoint row (STEP_NAME MAPPING_SKIPPED) is written, the job
--     is finished with a skipped message, and the driver RETURNs
--     early — BEFORE step 5 cleanup, so the previous run's work
--     tables are left standing, not dropped.
--   * A step/branch flag = 'N' skips that step/branch only: a SKIPPED
--     checkpoint row (same STEP_NAME as the step) is written
--     and a plain-text summary line is appended; helper36 is NOT used
--     for skips, because it renders NULL as '0 row(s)'.
--   * SKIPPED-STEP DEPENDENCY WARNING: flags are honoured
--     independently; there is no dependency enforcement from
--     IS_DEPENDENT / DEPENDENT_ON in this driver. Skipping step 10
--     while step 20 is enabled fails at step 20 (step 5 dropped
--     WRK_ECI_RFP_S10_LATEST and nothing recreated it), and skipping
--     step 20 while publish is enabled fails at publish (step 5
--     dropped WRK_ECI_RFP_S20_KEEPNEW). To skip downstream work,
--     disable the downstream steps too. This is flagged for the user
--     to confirm as intended config behaviour.
--
-- TRANSACTION EDGES (framework rule — never a checkpoint between
-- BEGIN TRANSACTION and COMMIT)
--   Steps run outside any transaction; each step procedure writes its
--   own checkpoint, which autocommits. The publish branch procedure
--   contains NO checkpoint and NO transaction control: the driver
--   calls it inside BEGIN TRANSACTION ... COMMIT, and only AFTER
--   COMMIT writes the step 30 checkpoint. Job begin happens before
--   everything; job finish happens after the publish COMMIT; the
--   exception handler ROLLBACKs first, then writes its checkpoints.
--
-- SKIPPED VOCABULARY NOTE (user choice to confirm)
--   JOB_CONTROL_ETL.STEP_STATUS has NO CHECK constraint (only a DDL
--   comment listing STARTED | COMPLETED | FAILED), so 'SKIPPED' rows
--   are used here for config-skipped steps, the skipped mapping, and
--   the skipped publish branch. Flagged to the user as a choice to
--   confirm: either accept 'SKIPPED' as a STEP_STATUS value, or add
--   it to the DDL comment / a constraint.
--
-- WORK TABLES (all TRANSIENT, same names as now)
--   WRK_ECI_RFP_S10_LATEST, WRK_ECI_RFP_S20_KEEPNEW. They live in the
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
--   * The original procedure took no parameters and had no :l_run_ts
--     reference anywhere in its SQL, so there is no original
--     parameter or run-ts substitution in this refactor. P_RUN_TS is
--     a driver-added run timestamp (CURRENT_TIMESTAMP() at driver
--     start), passed to every step/publish procedure for signature
--     uniformity; it is unused by this mapping's SQL because no
--     column in it carries a run timestamp.
--
-- SIGNATURE (identical to the current main)
--   The original procedure took no parameters, so there are no original
--   parameters to preserve. One parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run
--                                             (a run id is generated and
--                                             returned in the summary).
--   A restart is simply a new run: the mapping cleans up the
--   previous run's work tables at its start (step 5) and runs
--   every step from scratch. There is no step-level restart.
--
-- COMPILE-TIME VERIFICATION ITEMS (no live Snowflake here)
--   * Procedure-call return capture uses the Snowflake Scripting
--     scalar-call form `l_rows := (CALL proc(...));` — verify this
--     compiles and returns the procedure's NUMBER result in this
--     install; if it does not, the fallback is CALL ... INTO
--     :l_rows (or an equivalent result-capture form) with no other
--     change to this driver.
--   * The step/publish existence checks use EXECUTE IMMEDIATE with a
--     concatenated identifier for the missing-table error — verify
--     on first live compile (see the step procedure headers).
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn';
    l_job_run_id VARCHAR2(4000);
    l_run_ts TIMESTAMP DEFAULT SYSTIMESTAMP;
    l_rows NUMBER DEFAULT 0;
    l_summary VARCHAR2(4000) DEFAULT '';
    l_flag_ECI_RFP_DRIVER VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_RFP_S10_LATEST VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_RFP_S20_KEEPNEW VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_RFP_STG_ECI_D_FAMILY_PHONE VARCHAR2(4000) DEFAULT 'Y';
    l_in_ECI_RFP_S10_LATEST VARCHAR2(4000) DEFAULT '';
    l_in_ECI_RFP_S20_KEEPNEW VARCHAR2(4000) DEFAULT 'WRK_ECI_RFP_S10_LATEST';
    l_in_ECI_RFP_STG_ECI_D_FAMILY_PHONE VARCHAR2(4000) DEFAULT 'WRK_ECI_RFP_S20_KEEPNEW';
    l_config_fallback VARCHAR2(4000) DEFAULT 'N';
    l_pub_ECI_RFP_STG_ECI_D_FAMILY_PHONE_skipped VARCHAR2(4000) DEFAULT 'N';
BEGIN
    -- ---- STARTING -------------------------------------------------------
    -- Job-run-id generation exactly as in the current main. (l_job_run_id
    -- starts NULL, so this branch always runs; COALESCE then takes the
    -- supplied id when non-empty, else generates one — as now.)
    IF (l_job_run_id IS NULL OR l_job_run_id = '') THEN
        l_job_run_id := COALESCE(NULLIF(P_JOB_RUN_ID, ''),
            'ECI_' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDD_HH24MISS')
            || '_' || RAWTOHEX(SYS_GUID()));
    END IF;
    sp_etl_job_begin('ECI', c_workflow, c_mapping, l_job_run_id);

    -- ---- GATHER config (COMMON.ETL_RUN_CONFIG_TBL) ----------------------
    -- Flags pre-initialised to 'Y', consumed strings to their defaults
    -- (see DECLARE). One SELECT gathers all of them; on any exception
    -- (e.g. a missing/unreadable config table) the handler leaves the
    -- defaults standing and the run proceeds as the current main did.
    BEGIN
        SELECT COALESCE(MAX(CASE WHEN STEP_NO = 0 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 10 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 20 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 30 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 10 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), ''),
               COALESCE(MAX(CASE WHEN STEP_NO = 20 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_RFP_S10_LATEST'),
               COALESCE(MAX(CASE WHEN STEP_NO = 30 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_RFP_S20_KEEPNEW')
          INTO l_flag_ECI_RFP_DRIVER, l_flag_ECI_RFP_S10_LATEST, l_flag_ECI_RFP_S20_KEEPNEW, l_flag_ECI_RFP_STG_ECI_D_FAMILY_PHONE,
               l_in_ECI_RFP_S10_LATEST, l_in_ECI_RFP_S20_KEEPNEW, l_in_ECI_RFP_STG_ECI_D_FAMILY_PHONE
          FROM COMMON.ETL_RUN_CONFIG_TBL
         WHERE WORKFLOW_NAME = c_workflow
           AND MAPPING_NAME = c_mapping;
    WHEN OTHERS THEN
            l_config_fallback := 'Y';
    END;

    -- ---- Driver-row disable: skip the whole mapping, BEFORE step 5 -----
    IF (l_flag_ECI_RFP_DRIVER = 'N') THEN
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'MAPPING_SKIPPED', 'SKIPPED', NULL,
            'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N for STEP_NO 0).', NULL);
        l_summary := l_summary || 'MAPPING_SKIPPED: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
        sp_etl_job_finish('ECI', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn skipped by ETL_RUN_CONFIG_TBL. JOB_RUN_ID = ' || l_job_run_id);
        RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
    END IF;

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Drops only, no checkpoint call for drops. UNCHANGED from the current main.
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_RFP_S10_LATEST';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_RFP_S20_KEEPNEW';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;

    -- ---- Step 10: LATEST_HISTORY_ROWS ------------------------------------
    IF (l_flag_ECI_RFP_S10_LATEST = 'Y') THEN
        l_rows := sp_snow_step_ECI_RFP_S10_LATEST(l_job_run_id, l_run_ts, l_in_ECI_RFP_S10_LATEST);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 10 LATEST_HISTORY_ROWS', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'LATEST_HISTORY_ROWS', 'SKIPPED', NULL,
            'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N).', NULL);
        l_summary := l_summary || 'step 10 LATEST_HISTORY_ROWS: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 20: KEEP_NEW_ONLY ------------------------------------------
    IF (l_flag_ECI_RFP_S20_KEEPNEW = 'Y') THEN
        l_rows := sp_snow_step_ECI_RFP_S20_KEEPNEW(l_job_run_id, l_run_ts, l_in_ECI_RFP_S20_KEEPNEW);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 20 KEEP_NEW_ONLY', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'KEEP_NEW_ONLY', 'SKIPPED', 'STG_ECI_D_FAMILY_PHONE',
            'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N).', NULL);
        l_summary := l_summary || 'step 20 KEEP_NEW_ONLY: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 30: PUBLISH -- one transaction, one target ----------------
    -- This is the ONLY step that writes to a final target, and the only
    -- step inside an explicit transaction. The publish procedure holds
    -- the original INSERT, with its source changed from the history
    -- join to step 20 (as in the current main's staging split). No
    -- TRUNCATE, no DELETE. No checkpoint is written inside this
    -- transaction: the branch checkpoint follows, AFTER COMMIT.
    l_pub_ECI_RFP_STG_ECI_D_FAMILY_PHONE_skipped := 'N';
    -- (Snowflake BEGIN TRANSACTION removed: Oracle transactions are implicit)
    IF (l_flag_ECI_RFP_STG_ECI_D_FAMILY_PHONE = 'Y') THEN
        l_rows := sp_snow_pub_ECI_RFP_STG_ECI_D_FAMILY_PHONE(l_job_run_id, l_run_ts, l_in_ECI_RFP_STG_ECI_D_FAMILY_PHONE);
    ELSE
        l_pub_ECI_RFP_STG_ECI_D_FAMILY_PHONE_skipped := 'Y';
        l_rows := 0;
    END IF;
    COMMIT;
    IF (l_pub_ECI_RFP_STG_ECI_D_FAMILY_PHONE_skipped = 'Y') THEN
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_STG_ECI_D_FAMILY_PHONE', 'SKIPPED', 'STG_ECI_D_FAMILY_PHONE',
            'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N).', NULL);
        l_summary := l_summary || 'step 30 PUBLISH_STG_ECI_D_FAMILY_PHONE: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_STG_ECI_D_FAMILY_PHONE', 'COMPLETED', 'STG_ECI_D_FAMILY_PHONE',
            'Published in one transaction: latest history phone rows of reactivated families '
            || 'into the delta table. Count shown is rows inserted.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 30 PUBLISH_STG_ECI_D_FAMILY_PHONE', l_rows) || CHR(10);
    END IF;

    -- ---- TERMINATING ------------------------------------------------------
    sp_etl_job_finish('ECI', l_job_run_id, c_workflow, c_mapping,
        'm_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn completed. JOB_RUN_ID = ' || l_job_run_id);
    RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
WHEN OTHERS THEN
        ROLLBACK;
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'TERMINATING',
            'JOB_END', 'FAILED', NULL,
            'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. '
            || 'See ALL_TABLES for WRK_% tables in this schema and VW_ETL_JOB_STORY for the last completed step.',
            'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        sp_etl_job_fail('ECI', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn;
/

