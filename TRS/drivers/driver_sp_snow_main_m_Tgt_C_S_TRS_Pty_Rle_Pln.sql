-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Pln  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- IDQ mapping: m_Tgt_C_S_TRS_Pty_Rle_Pln, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Driver name and signature are EXACTLY as the current main procedure,
-- so every existing CALL still works. Install schema is TRS_ETL_WRK in
-- database MDM_ETL_TRS; all table names below are unqualified, except
-- the config table, which is COMMON-qualified (COMMON.ETL_RUN_CONFIG_TBL).
--
-- BUSINESS FLOW (read this top to bottom -- it IS the business flow)
    Step  5  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
                                  previous run (drops only, no
                                  checkpoint), then rebuild from step 10
    Step  10  MANAGED_CARE_SRC       WRK_TRS_PLN_S10_SRC
    Step  20  PLAN_TRANSLATED        WRK_TRS_PLN_S20_PLANNED
    Step  30  RANKED                 WRK_TRS_PLN_S30_RANKED
    Step  40  PUBLISH_C_S_TRS_PTY_RLE_PLN C_S_TRS_PTY_RLE_PLN (Valid plans)
    Step  50  PUBLISH_EXC_STG_BAD_REC_MEMB EXC_STG_BAD_REC_MEMB (Invalid plans)
    End    TERMINATING             work tables are NOT dropped: they
                                  stay in the database until the next
                                  run of this mapping cleans them up
--
-- CONFIG-DRIVEN NOTES (COMMON.ETL_RUN_CONFIG_TBL)
--   * The driver reads IS_RUN_ENABLED (per STEP_NO) and
--     WORK_TABLES_CONSUMED (per STEP_NO) in ONE SELECT at the start.
--     Flags and consumed strings are pre-initialised to their defaults
--     ('Y' / the step's normal input), so a missing or unreadable
--     config table leaves every step enabled with its normal inputs:
--     the config can only disable steps, never break a run by absence.
--   * A driver row with STEP_NO = 0 and IS_RUN_ENABLED = 'N' skips the
--     WHOLE mapping before step 5 cleanup (no work tables are dropped).
--   * A step/branch row with IS_RUN_ENABLED = 'N' skips just that
--     step/branch: a SKIPPED checkpoint row is written and a plain-text
--     summary line is appended. No other step is auto-skipped: if a
--     downstream step stays enabled while its input step was skipped,
--     that step's input-existence check raises the missing table
--     loudly instead of running on stale data. Disable downstream
--     steps explicitly if you disable an upstream one.
--   * Config columns IS_DEPENDENT, DEPENDENT_ON and
--     WORK_TABLES_PRODUCED are present in the table but are NOT read
--     by this driver; gating is by IS_RUN_ENABLED only.
--   * SKIPPED vocabulary: JOB_CONTROL_ETL.STEP_STATUS has NO CHECK
--     constraint, so 'SKIPPED' rows are used here as in the ECI v2.1
--     template.
--
-- TRANSACTION EDGES (framework rule)
--   Never call a checkpoint between BEGIN TRANSACTION and COMMIT.
--   Steps run (autocommitted) with their own checkpoints first; then
--   ONE publish transaction calls the branch procs (which contain NO
--   checkpoint calls and NO transaction control); then COMMIT; then,
--   and only then, the driver checkpoints each executed branch and
--   writes SKIPPED rows for skipped branches. The exception handler
--   ROLLBACKs first, then checkpoints, so its rows are not rolled back.
--
-- WORK TABLES (all TRANSIENT)
--   WRK_TRS_PLN_S10_SRC, WRK_TRS_PLN_S20_PLANNED, WRK_TRS_PLN_S30_RANKED. They live in the same schema as the targets (unqualified
--   names, as in the original code) and are prefixed WRK_TRS_. They
--   survive a session crash (TRANSIENT, not TEMP), which is what makes
--   inspection after a run possible. No cursor was used: every step
--   here is set-based by design.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently; condensed
-- from the current main header -- see the manifest for the full text)
----   (kept deliberately, do not "fix" silently)
--     * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--       DELETE of the targets.  IDQ truncates C_S_TRS_PTY_RLE_PLN; the
--       Snowflake version instead skips keys already present (the
--       existing-key guard in step 30) and keeps the last row per key in
--       this run.  A re-run therefore inserts nothing twice, but it also
--       does not remove rows that IDQ would have truncated away -- see
--       the User Guide, "Parity gaps".
--     * Rows whose begin date is NOT before the end date (including
--       begin = end) are dropped by the step-10 source filter, silently:
--       they are neither loaded nor exceptioned, exactly as in the
--       original.  Open-ended rows (END_DT IS NULL) do load.
--     * The plan lookup is under source system 'MAX', not 'TRS', as in the
--       original -- preserved, not "corrected".
--
-- SIGNATURE
--   The original parameters are unchanged and in the same order, so
--   every existing CALL still works. One parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run
--                                             (a run id is generated and
--                                             returned in the summary).
--   A restart is simply a new run: the mapping cleans up the
--   previous run's work tables at its start (step 5) and runs
--   every step from scratch. There is no step-level restart.
--   Procedure-call return capture uses `l_rows := (CALL proc(...));`
--   (Snowflake Scripting scalar-call form) -- a compile-time
--   verification item, since there is no live Snowflake here.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Pln (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TRS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_Pln';
    l_run_ts TIMESTAMP DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP);
    l_job_run_id VARCHAR2(4000);
    l_rows NUMBER DEFAULT 0;
    l_summary VARCHAR2(4000) DEFAULT '';
-- Config flags (STEP_NO 0 = driver row, then steps, then branches)
    l_flag_TRS_PLN_DRIVER     VARCHAR DEFAULT 'Y'
    l_flag_TRS_PLN_S10_SRC VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_PLN_S20_PLANNED VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_PLN_S30_RANKED VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_PLN_C_S_TRS_PTY_RLE_PLN VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_PLN_EXC_STG_BAD_REC_MEMB VARCHAR2(4000) DEFAULT 'Y';
-- Config consumed strings (work-table inputs, per STEP_NO)
    l_in_TRS_PLN_S10_SRC VARCHAR DEFAULT ''
    l_in_TRS_PLN_S20_PLANNED VARCHAR2(4000) DEFAULT 'WRK_TRS_PLN_S10_SRC';
    l_in_TRS_PLN_S30_RANKED VARCHAR2(4000) DEFAULT 'WRK_TRS_PLN_S20_PLANNED';
    l_in_TRS_PLN_C_S_TRS_PTY_RLE_PLN VARCHAR2(4000) DEFAULT 'WRK_TRS_PLN_S30_RANKED';
    l_in_TRS_PLN_EXC_STG_BAD_REC_MEMB VARCHAR2(4000) DEFAULT 'WRK_TRS_PLN_S30_RANKED';
-- Per-branch publish counts (one variable per branch)
    l_pub_TRS_PLN_C_S_TRS_PTY_RLE_PLN NUMBER DEFAULT 0
    l_pub_TRS_PLN_EXC_STG_BAD_REC_MEMB NUMBER DEFAULT 0;
BEGIN
    -- ---- STARTING: job-run-id generation exactly as in the current main
    IF (l_job_run_id IS NULL OR l_job_run_id = '') THEN
        l_job_run_id := COALESCE(NULLIF(P_JOB_RUN_ID, ''),
            'TRS_' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDD_HH24MISS')
            || '_' || RAWTOHEX(SYS_GUID()));
    END IF;
    sp_etl_job_begin('TRS', c_workflow, c_mapping, l_job_run_id);

    -- ---- GATHER config: one SELECT; on exception the pre-initialised
    -- defaults stand (covers a missing/unreadable config table).
    BEGIN
        SELECT COALESCE(MAX(CASE WHEN STEP_NO = 0 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 10 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 20 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 30 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 40 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 50 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 10 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), ''),
               COALESCE(MAX(CASE WHEN STEP_NO = 20 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_PLN_S10_SRC'),
               COALESCE(MAX(CASE WHEN STEP_NO = 30 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_PLN_S20_PLANNED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 40 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_PLN_S30_RANKED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 50 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_PLN_S30_RANKED')
          INTO l_flag_TRS_PLN_DRIVER, l_flag_TRS_PLN_S10_SRC, l_flag_TRS_PLN_S20_PLANNED, l_flag_TRS_PLN_S30_RANKED, l_flag_TRS_PLN_C_S_TRS_PTY_RLE_PLN, l_flag_TRS_PLN_EXC_STG_BAD_REC_MEMB,
               l_in_TRS_PLN_S10_SRC, l_in_TRS_PLN_S20_PLANNED, l_in_TRS_PLN_S30_RANKED, l_in_TRS_PLN_C_S_TRS_PTY_RLE_PLN, l_in_TRS_PLN_EXC_STG_BAD_REC_MEMB
          FROM COMMON.ETL_RUN_CONFIG_TBL
         WHERE WORKFLOW_NAME = c_workflow
           AND MAPPING_NAME = c_mapping;
    WHEN OTHERS THEN
            -- Defaults stand: re-assert them explicitly.
            l_flag_TRS_PLN_DRIVER := 'Y'; l_flag_TRS_PLN_S10_SRC := 'Y'; l_flag_TRS_PLN_S20_PLANNED := 'Y'; l_flag_TRS_PLN_S30_RANKED := 'Y'; l_flag_TRS_PLN_C_S_TRS_PTY_RLE_PLN := 'Y'; l_flag_TRS_PLN_EXC_STG_BAD_REC_MEMB := 'Y';
            l_in_TRS_PLN_S10_SRC := ''; l_in_TRS_PLN_S20_PLANNED := 'WRK_TRS_PLN_S10_SRC'; l_in_TRS_PLN_S30_RANKED := 'WRK_TRS_PLN_S20_PLANNED'; l_in_TRS_PLN_C_S_TRS_PTY_RLE_PLN := 'WRK_TRS_PLN_S30_RANKED'; l_in_TRS_PLN_EXC_STG_BAD_REC_MEMB := 'WRK_TRS_PLN_S30_RANKED';
    END;

    -- ---- Driver-row disable: skip the whole mapping BEFORE step 5 cleanup
    IF (l_flag_TRS_PLN_DRIVER = 'N') THEN
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'MAPPING_SKIPPED', 'SKIPPED', NULL, 'Mapping skipped by ETL_RUN_CONFIG_TBL (STEP_NO = 0, IS_RUN_ENABLED = N).', NULL);
        l_summary := 'm_Tgt_C_S_TRS_Pty_Rle_Pln SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
        sp_etl_job_finish('TRS', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_TRS_Pty_Rle_Pln skipped by config. JOB_RUN_ID = ' || l_job_run_id);
        RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
    END IF;

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Drops only, no checkpoint call for drops. UNCHANGED from current main.
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_PLN_S10_SRC';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_PLN_S20_PLANNED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_PLN_S30_RANKED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;

    -- ---- Step 10: MANAGED_CARE_SRC
    IF (l_flag_TRS_PLN_S10_SRC = 'Y') THEN
        l_rows := sp_snow_step_TRS_PLN_S10_SRC(l_job_run_id, l_run_ts, l_in_TRS_PLN_S10_SRC);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 10 MANAGED_CARE_SRC', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'MANAGED_CARE_SRC', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 10 MANAGED_CARE_SRC: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 20: PLAN_TRANSLATED
    IF (l_flag_TRS_PLN_S20_PLANNED = 'Y') THEN
        l_rows := sp_snow_step_TRS_PLN_S20_PLANNED(l_job_run_id, l_run_ts, l_in_TRS_PLN_S20_PLANNED);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 20 PLAN_TRANSLATED', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PLAN_TRANSLATED', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 20 PLAN_TRANSLATED: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 30: RANKED
    IF (l_flag_TRS_PLN_S30_RANKED = 'Y') THEN
        l_rows := sp_snow_step_TRS_PLN_S30_RANKED(l_job_run_id, l_run_ts, l_in_TRS_PLN_S30_RANKED);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 30 RANKED', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'RANKED', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 30 RANKED: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- PUBLISH: ONE transaction, all enabled branches, in order ----
    -- This is the ONLY step that writes to final targets. Branch procs
    -- contain no checkpoint calls and no transaction control; the
    -- driver checkpoints each branch AFTER COMMIT below.
    -- (Snowflake BEGIN TRANSACTION removed: Oracle transactions are implicit)
    IF (l_flag_TRS_PLN_C_S_TRS_PTY_RLE_PLN = 'Y') THEN
        l_pub_TRS_PLN_C_S_TRS_PTY_RLE_PLN := sp_snow_pub_TRS_PLN_C_S_TRS_PTY_RLE_PLN(l_job_run_id, l_run_ts, l_in_TRS_PLN_C_S_TRS_PTY_RLE_PLN);
    END IF;
    IF (l_flag_TRS_PLN_EXC_STG_BAD_REC_MEMB = 'Y') THEN
        l_pub_TRS_PLN_EXC_STG_BAD_REC_MEMB := sp_snow_pub_TRS_PLN_EXC_STG_BAD_REC_MEMB(l_job_run_id, l_run_ts, l_in_TRS_PLN_EXC_STG_BAD_REC_MEMB);
    END IF;
    COMMIT;

    -- ---- Publish checkpoints AFTER COMMIT (one per branch) ----
    IF (l_flag_TRS_PLN_C_S_TRS_PTY_RLE_PLN = 'Y') THEN
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_TRS_PTY_RLE_PLN', 'COMPLETED', 'C_S_TRS_PTY_RLE_PLN', 'Published Valid plans to C_S_TRS_PTY_RLE_PLN.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 40 PUBLISH_C_S_TRS_PTY_RLE_PLN', l_pub_TRS_PLN_C_S_TRS_PTY_RLE_PLN) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_TRS_PTY_RLE_PLN', 'SKIPPED', 'C_S_TRS_PTY_RLE_PLN', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 40 PUBLISH_C_S_TRS_PTY_RLE_PLN: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_TRS_PLN_EXC_STG_BAD_REC_MEMB = 'Y') THEN
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_STG_BAD_REC_MEMB', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published Invalid plans to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 50 PUBLISH_EXC_STG_BAD_REC_MEMB', l_pub_TRS_PLN_EXC_STG_BAD_REC_MEMB) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_STG_BAD_REC_MEMB', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 50 PUBLISH_EXC_STG_BAD_REC_MEMB: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- TERMINATING ------------------------------------------------------
    sp_etl_job_finish('TRS', l_job_run_id, c_workflow, c_mapping,
        'm_Tgt_C_S_TRS_Pty_Rle_Pln completed. JOB_RUN_ID = ' || l_job_run_id);
    RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
WHEN OTHERS THEN
        ROLLBACK;
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'TERMINATING',
            'JOB_END', 'FAILED', NULL, 'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. ' || 'See ALL_TABLES for WRK_% tables in this schema and VW_ETL_JOB_STORY for the last completed step.', 'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        sp_etl_job_fail('TRS', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_TRS_Pty_Rle_Pln failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Pln;
/

