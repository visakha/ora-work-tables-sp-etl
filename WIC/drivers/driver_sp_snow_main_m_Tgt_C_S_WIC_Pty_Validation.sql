-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (WIC)
--
-- IDQ mapping: m_Tgt_C_S_WIC_Pty_Validation, workflow wf_WIC_Stage_Load.
-- Install schema is WIC_ETL_WRK in database MDM_ETL_WIC; all table
-- names below are unqualified, except the config table, which is
-- COMMON-qualified (COMMON.ETL_RUN_CONFIG_TBL).
-- Driver name and signature are EXACTLY as the current main procedure,
-- so every existing CALL still works.
--
-- WHAT THIS MAPPING DOES, IN PLAIN WORDS
--   Checks the WIC parties and maintains the deactivation list every later WIC mapping reads. A party whose standardised first or last name is blank is logged as an exception, written to the deactivation log, and given a new deactivation-status row if it has none yet. A party that already has a status and now has both names present is written to the deactivation log as a reactivation.
--
-- BUSINESS FLOW (read this top to bottom -- it IS the business flow)
--     Step  5  CLEANUP_PREVIOUS_RUN  drop any work tables left by the previous run (drops only, no checkpoint), then rebuild from step 10
--     Step 10  ENRICHED                 WRK_WIC_VAL_S10_ENRICHED
--     Step 20  NAMED_BLANK_TEST         WRK_WIC_VAL_S20_NAMED
--     Step 30  ROUTED                   WRK_WIC_VAL_S30_ROUTED
--     Step 40  PUBLISH_EXC_STG_BAD_REC_MEMB invalid-name exceptions -> EXC_STG_BAD_REC_MEMB (EXCEPTION)
--     Step 50  PUBLISH_STG_WIC_PTY_INACTIVE_LOG_DEACTIVATION deactivation log rows -> STG_WIC_PTY_INACTIVE_LOG (STATUS)
--     Step 60  PUBLISH_STG_WIC_PTY_INACTIVE_STS new deactivation-status rows -> STG_WIC_PTY_INACTIVE_STS (STATUS)
--     Step 70  PUBLISH_STG_WIC_PTY_INACTIVE_LOG_REACTIVATION reactivation log rows -> STG_WIC_PTY_INACTIVE_LOG (STATUS)
--     End    TERMINATING             work tables are NOT dropped: they stay in the database until the next run of this mapping cleans them up
--
-- CONFIG-DRIVEN NOTES (COMMON.ETL_RUN_CONFIG_TBL)
--   * The driver reads IS_RUN_ENABLED (per STEP_NO) and WORK_TABLES_CONSUMED (per STEP_NO) in ONE SELECT at the start. Flags and consumed strings are pre-initialised to their defaults ('Y' / the step's normal input), so a missing or unreadable config table leaves every step enabled with its normal inputs: the config can only disable steps, never break a run by absence.
--   * A driver row with STEP_NO = 0 and IS_RUN_ENABLED = 'N' skips the WHOLE mapping before step 5 cleanup (no work tables are dropped).
--   * A step/branch row with IS_RUN_ENABLED = 'N' skips just that step/branch: a SKIPPED checkpoint row is written and a plain-text summary line is appended (helper36 is NOT used for skips -- it renders NULL as '0 row(s)'). No other step is auto-skipped: if a downstream step stays enabled while its input step was skipped, that step's input-existence check raises the missing table loudly instead of running on stale data. Disable downstream steps explicitly if you disable an upstream one.
--   * Config columns IS_DEPENDENT, DEPENDENT_ON and WORK_TABLES_PRODUCED are present in the table but are NOT read by this driver; gating is by IS_RUN_ENABLED only.
--   * SKIPPED vocabulary: JOB_CONTROL_ETL.STEP_STATUS has NO CHECK constraint (a DDL comment that in v2 lists STARTED | COMPLETED | FAILED | SKIPPED), so 'SKIPPED' rows are used here and are flagged to the user as a choice to confirm.
--
-- TRANSACTION EDGES (framework rule)
--   Never call a checkpoint between BEGIN TRANSACTION and COMMIT. Steps run (autocommitted) with their own checkpoints first; then ONE publish transaction calls the branch procs (which contain NO checkpoint calls and NO transaction control); then COMMIT; then, and only then, the driver checkpoints each executed branch and writes SKIPPED rows for skipped branches. The exception handler ROLLBACKs first, then checkpoints, so its rows are not rolled back.
--
-- WORK TABLES (all TRANSIENT)
--   WRK_WIC_VAL_S10_ENRICHED, WRK_WIC_VAL_S20_NAMED, WRK_WIC_VAL_S30_ROUTED. They live in the same schema as the targets (unqualified names, as in the original code) and are prefixed WRK_WIC_. They survive a session crash (TRANSIENT, not TEMP), which is what makes inspection after a run possible. No CURSOR was used: every step here is set-based by design.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only: the IDQ delete of STG_WIC_PTY_INACTIVE_STS is NOT performed. A reactivation therefore only writes a log row; the status row stays, so the party stays excluded by the downstream NOT EXISTS filters until something else removes the status row. This is the Snowflake Yes/No reactivation verdict for WIC (IDQ re-admits via Upd_Delete_Inactive, which the Snowflake code does not perform).
--   * Deactivation detection is pure ETL interpretation: no source deactivation flag is read. Only the blank-standardised-name test (name_missing) drives deactivation and reactivation.
--   * The cross-reference lookup filters on TRIM(ROWID_SYSTEM) = WIC.
--   * No timeline handling in this mapping (no VERSION_SEQ).
--   * Step 30 (and therefore the publish) is computed before any publish INSERT runs, so all routing sees the pre-run deactivation status, as in the original single INSERT ALL.
--
-- SIGNATURE
--   The original parameters are unchanged and in the same order, so every existing CALL still works. One parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run (a run id is generated and returned in the summary).
--   A restart is simply a new run: the mapping cleans up the previous run's work tables at its start (step 5) and runs every step from scratch. There is no step-level restart.
--   Procedure-call return capture uses `l_rows := (CALL proc(...));` (Snowflake Scripting scalar-call form) -- a compile-time verification item, since there is no live Snowflake here.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'WIC';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_WIC_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_WIC_Pty_Validation';
    l_run_ts TIMESTAMP DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP);
    l_job_run_id VARCHAR2(4000);
    l_rows NUMBER DEFAULT 0;
    l_summary VARCHAR2(4000) DEFAULT '';
-- Config flags (STEP_NO 0 = driver row, then steps, then branches)
    l_flag_WIC_VAL_DRIVER VARCHAR DEFAULT 'Y'
    l_flag_WIC_VAL_S10_ENRICHED VARCHAR2(4000) DEFAULT 'Y';
    l_flag_WIC_VAL_S20_NAMED VARCHAR2(4000) DEFAULT 'Y';
    l_flag_WIC_VAL_S30_ROUTED VARCHAR2(4000) DEFAULT 'Y';
    l_flag_WIC_VAL_EXC_STG_BAD_REC_MEMB VARCHAR2(4000) DEFAULT 'Y';
    l_flag_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_DEACTIVATION VARCHAR2(4000) DEFAULT 'Y';
    l_flag_WIC_VAL_STG_WIC_PTY_INACTIVE_STS VARCHAR2(4000) DEFAULT 'Y';
    l_flag_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_REACTIVATION VARCHAR2(4000) DEFAULT 'Y';
-- Config consumed strings (work-table inputs, per STEP_NO)
    l_in_WIC_VAL_S10_ENRICHED VARCHAR DEFAULT ''
    l_in_WIC_VAL_S20_NAMED VARCHAR2(4000) DEFAULT 'WRK_WIC_VAL_S10_ENRICHED';
    l_in_WIC_VAL_S30_ROUTED VARCHAR2(4000) DEFAULT 'WRK_WIC_VAL_S20_NAMED';
    l_in_WIC_VAL_EXC_STG_BAD_REC_MEMB VARCHAR2(4000) DEFAULT 'WRK_WIC_VAL_S30_ROUTED';
    l_in_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_DEACTIVATION VARCHAR2(4000) DEFAULT 'WRK_WIC_VAL_S30_ROUTED';
    l_in_WIC_VAL_STG_WIC_PTY_INACTIVE_STS VARCHAR2(4000) DEFAULT 'WRK_WIC_VAL_S30_ROUTED';
    l_in_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_REACTIVATION VARCHAR2(4000) DEFAULT 'WRK_WIC_VAL_S30_ROUTED';
-- Per-branch publish counts (one variable per branch)
    l_pub_WIC_VAL_EXC_STG_BAD_REC_MEMB NUMBER DEFAULT 0
    l_pub_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_DEACTIVATION NUMBER DEFAULT 0;
    l_pub_WIC_VAL_STG_WIC_PTY_INACTIVE_STS NUMBER DEFAULT 0;
    l_pub_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_REACTIVATION NUMBER DEFAULT 0;
BEGIN
    -- ---- STARTING: job-run-id generation exactly as in the current main
    IF (l_job_run_id IS NULL OR l_job_run_id = '') THEN
        l_job_run_id := COALESCE(NULLIF(P_JOB_RUN_ID, ''),
            'WIC_' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDD_HH24MISS')
            || '_' || RAWTOHEX(SYS_GUID()));
    END IF;
    sp_etl_job_begin('WIC', c_workflow, c_mapping, l_job_run_id);

    -- ---- GATHER config: one SELECT; on exception the pre-initialised
    -- defaults stand (covers a missing/unreadable config table).
    BEGIN
        SELECT COALESCE(MAX(CASE WHEN STEP_NO = 0 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 10 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 20 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 30 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 40 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 50 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 60 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 70 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 10 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), ''),
               COALESCE(MAX(CASE WHEN STEP_NO = 20 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_WIC_VAL_S10_ENRICHED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 30 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_WIC_VAL_S20_NAMED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 40 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_WIC_VAL_S30_ROUTED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 50 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_WIC_VAL_S30_ROUTED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 60 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_WIC_VAL_S30_ROUTED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 70 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_WIC_VAL_S30_ROUTED')
          INTO l_flag_WIC_VAL_DRIVER, l_flag_WIC_VAL_S10_ENRICHED, l_flag_WIC_VAL_S20_NAMED, l_flag_WIC_VAL_S30_ROUTED, l_flag_WIC_VAL_EXC_STG_BAD_REC_MEMB, l_flag_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_DEACTIVATION, l_flag_WIC_VAL_STG_WIC_PTY_INACTIVE_STS, l_flag_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_REACTIVATION,
               l_in_WIC_VAL_S10_ENRICHED, l_in_WIC_VAL_S20_NAMED, l_in_WIC_VAL_S30_ROUTED, l_in_WIC_VAL_EXC_STG_BAD_REC_MEMB, l_in_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_DEACTIVATION, l_in_WIC_VAL_STG_WIC_PTY_INACTIVE_STS, l_in_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_REACTIVATION
          FROM COMMON.ETL_RUN_CONFIG_TBL
         WHERE WORKFLOW_NAME = c_workflow
           AND MAPPING_NAME = c_mapping;
    WHEN OTHERS THEN
            -- Defaults stand: re-assert them explicitly.
            l_flag_WIC_VAL_DRIVER := 'Y'; l_flag_WIC_VAL_S10_ENRICHED := 'Y'; l_flag_WIC_VAL_S20_NAMED := 'Y'; l_flag_WIC_VAL_S30_ROUTED := 'Y';
            l_flag_WIC_VAL_EXC_STG_BAD_REC_MEMB := 'Y'; l_flag_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_DEACTIVATION := 'Y'; l_flag_WIC_VAL_STG_WIC_PTY_INACTIVE_STS := 'Y'; l_flag_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_REACTIVATION := 'Y';
            l_in_WIC_VAL_S10_ENRICHED := ''; l_in_WIC_VAL_S20_NAMED := 'WRK_WIC_VAL_S10_ENRICHED'; l_in_WIC_VAL_S30_ROUTED := 'WRK_WIC_VAL_S20_NAMED';
            l_in_WIC_VAL_EXC_STG_BAD_REC_MEMB := 'WRK_WIC_VAL_S30_ROUTED'; l_in_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_DEACTIVATION := 'WRK_WIC_VAL_S30_ROUTED'; l_in_WIC_VAL_STG_WIC_PTY_INACTIVE_STS := 'WRK_WIC_VAL_S30_ROUTED';
            l_in_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_REACTIVATION := 'WRK_WIC_VAL_S30_ROUTED';
    END;

    -- ---- Driver-row disable: skip the whole mapping BEFORE step 5 cleanup
    IF (l_flag_WIC_VAL_DRIVER = 'N') THEN
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'MAPPING_SKIPPED', 'SKIPPED', NULL, 'Mapping skipped by ETL_RUN_CONFIG_TBL (STEP_NO = 0, IS_RUN_ENABLED = N).', NULL);
        l_summary := 'm_Tgt_C_S_WIC_Pty_Validation SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
        sp_etl_job_finish('WIC', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_WIC_Pty_Validation skipped by config. JOB_RUN_ID = ' || l_job_run_id);
        RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
    END IF;

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Drops only, no checkpoint call for drops. UNCHANGED from current main.
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_WIC_VAL_S10_ENRICHED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_WIC_VAL_S20_NAMED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_WIC_VAL_S30_ROUTED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;

    -- ---- Step 10: ENRICHED
    IF (l_flag_WIC_VAL_S10_ENRICHED = 'Y') THEN
        l_rows := sp_snow_step_WIC_VAL_S10_ENRICHED(l_job_run_id, l_run_ts, l_in_WIC_VAL_S10_ENRICHED);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 10 ENRICHED', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'ENRICHED', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 10 ENRICHED: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 20: NAMED_BLANK_TEST
    IF (l_flag_WIC_VAL_S20_NAMED = 'Y') THEN
        l_rows := sp_snow_step_WIC_VAL_S20_NAMED(l_job_run_id, l_run_ts, l_in_WIC_VAL_S20_NAMED);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 20 NAMED_BLANK_TEST', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'NAMED_BLANK_TEST', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 20 NAMED_BLANK_TEST: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 30: ROUTED
    IF (l_flag_WIC_VAL_S30_ROUTED = 'Y') THEN
        l_rows := sp_snow_step_WIC_VAL_S30_ROUTED(l_job_run_id, l_run_ts, l_in_WIC_VAL_S30_ROUTED);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 30 ROUTED', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'ROUTED', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 30 ROUTED: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- PUBLISH: ONE transaction, all enabled branches, in order ----
    -- Branch procs contain no checkpoint calls and no transaction control; the
    -- driver checkpoints each branch AFTER COMMIT below.
    -- (Snowflake BEGIN TRANSACTION removed: Oracle transactions are implicit)
    IF (l_flag_WIC_VAL_EXC_STG_BAD_REC_MEMB = 'Y') THEN
        l_pub_WIC_VAL_EXC_STG_BAD_REC_MEMB := sp_snow_pub_WIC_VAL_EXC_STG_BAD_REC_MEMB(l_job_run_id, l_run_ts, l_in_WIC_VAL_EXC_STG_BAD_REC_MEMB);
    END IF;
    IF (l_flag_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_DEACTIVATION = 'Y') THEN
        l_pub_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_DEACTIVATION := sp_snow_pub_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_DEACTIVATION(l_job_run_id, l_run_ts, l_in_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_DEACTIVATION);
    END IF;
    IF (l_flag_WIC_VAL_STG_WIC_PTY_INACTIVE_STS = 'Y') THEN
        l_pub_WIC_VAL_STG_WIC_PTY_INACTIVE_STS := sp_snow_pub_WIC_VAL_STG_WIC_PTY_INACTIVE_STS(l_job_run_id, l_run_ts, l_in_WIC_VAL_STG_WIC_PTY_INACTIVE_STS);
    END IF;
    IF (l_flag_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_REACTIVATION = 'Y') THEN
        l_pub_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_REACTIVATION := sp_snow_pub_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_REACTIVATION(l_job_run_id, l_run_ts, l_in_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_REACTIVATION);
    END IF;
    COMMIT;

    IF (l_flag_WIC_VAL_EXC_STG_BAD_REC_MEMB = 'Y') THEN
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_STG_BAD_REC_MEMB', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published invalid-name exceptions to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 40 PUBLISH_EXC_STG_BAD_REC_MEMB', l_pub_WIC_VAL_EXC_STG_BAD_REC_MEMB) || CHR(10);
    ELSE
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_STG_BAD_REC_MEMB', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 40 PUBLISH_EXC_STG_BAD_REC_MEMB: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    IF (l_flag_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_DEACTIVATION = 'Y') THEN
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_STG_WIC_PTY_INACTIVE_LOG_DEACTIVATION', 'COMPLETED', 'STG_WIC_PTY_INACTIVE_LOG', 'Published deactivation log rows to STG_WIC_PTY_INACTIVE_LOG.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 50 PUBLISH_STG_WIC_PTY_INACTIVE_LOG_DEACTIVATION', l_pub_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_DEACTIVATION) || CHR(10);
    ELSE
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_STG_WIC_PTY_INACTIVE_LOG_DEACTIVATION', 'SKIPPED', 'STG_WIC_PTY_INACTIVE_LOG', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 50 PUBLISH_STG_WIC_PTY_INACTIVE_LOG_DEACTIVATION: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    IF (l_flag_WIC_VAL_STG_WIC_PTY_INACTIVE_STS = 'Y') THEN
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_STG_WIC_PTY_INACTIVE_STS', 'COMPLETED', 'STG_WIC_PTY_INACTIVE_STS', 'Published new deactivation-status rows to STG_WIC_PTY_INACTIVE_STS.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 60 PUBLISH_STG_WIC_PTY_INACTIVE_STS', l_pub_WIC_VAL_STG_WIC_PTY_INACTIVE_STS) || CHR(10);
    ELSE
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_STG_WIC_PTY_INACTIVE_STS', 'SKIPPED', 'STG_WIC_PTY_INACTIVE_STS', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 60 PUBLISH_STG_WIC_PTY_INACTIVE_STS: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    IF (l_flag_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_REACTIVATION = 'Y') THEN
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_STG_WIC_PTY_INACTIVE_LOG_REACTIVATION', 'COMPLETED', 'STG_WIC_PTY_INACTIVE_LOG', 'Published reactivation log rows to STG_WIC_PTY_INACTIVE_LOG.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 70 PUBLISH_STG_WIC_PTY_INACTIVE_LOG_REACTIVATION', l_pub_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_REACTIVATION) || CHR(10);
    ELSE
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_STG_WIC_PTY_INACTIVE_LOG_REACTIVATION', 'SKIPPED', 'STG_WIC_PTY_INACTIVE_LOG', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 70 PUBLISH_STG_WIC_PTY_INACTIVE_LOG_REACTIVATION: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- TERMINATING ------------------------------------------------------
    sp_etl_job_finish('WIC', l_job_run_id, c_workflow, c_mapping,
        'm_Tgt_C_S_WIC_Pty_Validation completed. JOB_RUN_ID = ' || l_job_run_id);
    RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
WHEN OTHERS THEN
        ROLLBACK;
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'TERMINATING',
            'JOB_END', 'FAILED', NULL, 'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. See ALL_TABLES for WRK_% tables in this schema and VW_ETL_JOB_STORY for the last completed step.', 'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        sp_etl_job_fail('WIC', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_WIC_Pty_Validation failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation;
/

