-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_TOA  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- IDQ mapping: m_Tgt_C_S_TRS_Pty_Rle_TOA, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Driver name and signature are EXACTLY as the current main procedure,
-- so every existing CALL still works. Install schema is TRS_ETL_WRK in
-- database MDM_ETL_TRS; all table names below are unqualified, except
-- the config table, which is COMMON-qualified (COMMON.ETL_RUN_CONFIG_TBL).
--
-- BUSINESS FLOW (read this top to bottom -- it IS the business flow)
    Step  5  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
                                  previous run (drops only, no
                                  checkpoint), then rebuild from step 10
    Step  10  TOA_SRC_RANKED         WRK_TRS_TOA_S10_RAW
    Step  20  TOA_LATEST             WRK_TRS_TOA_S20_SRC
    Step  30  TOA_KEYED              WRK_TRS_TOA_S30_KEYED
    Step  40  TOA_RANKED             WRK_TRS_TOA_S40_RANKED
    Step  50  PUBLISH_EXC_BAD_VALUE  EXC_STG_BAD_REC_MEMB (Bad value)
    Step  60  PUBLISH_EXC_DATES      EXC_STG_BAD_REC_MEMB (Inverted dates)
    Step  70  PUBLISH_C_S_TRS_PTY_RLE_TOA C_S_TRS_PTY_RLE_TOA (Valid TOA rows)
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
--   WRK_TRS_TOA_S10_RAW, WRK_TRS_TOA_S20_SRC, WRK_TRS_TOA_S30_KEYED, WRK_TRS_TOA_S40_RANKED. They live in the same schema as the targets (unqualified
--   names, as in the original code) and are prefixed WRK_TRS_. They
--   survive a session crash (TRANSIENT, not TEMP), which is what makes
--   inspection after a run possible. No cursor was used: every step
--   here is set-based by design.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently; condensed
-- from the current main header -- see the manifest for the full text)
----   (kept deliberately, do not "fix" silently)
--     * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--       DELETE of the targets.  IDQ truncates C_S_TRS_PTY_RLE_TOA; the
--       Snowflake version instead skips keys already present (the uq_*
--       flags in step 40).  A re-run therefore inserts nothing twice,
--       but it also does not remove rows that IDQ would have truncated
--       away -- see the User Guide, "Parity gaps".
--     * The Bad_Value exception row writes the looked-up EXCEPTION_CODE
--       for 'Invalid_TOA', which is NULL when that code is not configured
--       in EXC_LOOKUP_CODE_VALUE -- preserved, not defaulted.  The date
--       exception row writes the computed code
--       'Period_Start_Date_>_Period_End_Date'.
--     * The original source carries only the MCI_EDG_INDV branch
--       (SRC_TBL = 'MCI_EDG_INDV', decoded to source 'TIERS'); the
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
CREATE OR REPLACE FUNCTION sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_TOA (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TRS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_TOA';
    l_run_ts TIMESTAMP DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP);
    l_job_run_id VARCHAR2(4000);
    l_rows NUMBER DEFAULT 0;
    l_summary VARCHAR2(4000) DEFAULT '';
-- Config flags (STEP_NO 0 = driver row, then steps, then branches)
    l_flag_TRS_TOA_DRIVER     VARCHAR DEFAULT 'Y'
    l_flag_TRS_TOA_S10_RAW VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_TOA_S20_LATEST VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_TOA_S30_KEYED VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_TOA_S40_RANKED VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_TOA_EXC_STG_BAD_REC_MEMB_BAD_VALUE VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_TOA_EXC_STG_BAD_REC_MEMB_DATES VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_TOA_C_S_TRS_PTY_RLE_TOA VARCHAR2(4000) DEFAULT 'Y';
-- Config consumed strings (work-table inputs, per STEP_NO)
    l_in_TRS_TOA_S10_RAW VARCHAR DEFAULT ''
    l_in_TRS_TOA_S20_LATEST VARCHAR2(4000) DEFAULT 'WRK_TRS_TOA_S10_RAW';
    l_in_TRS_TOA_S30_KEYED VARCHAR2(4000) DEFAULT 'WRK_TRS_TOA_S20_SRC';
    l_in_TRS_TOA_S40_RANKED VARCHAR2(4000) DEFAULT 'WRK_TRS_TOA_S30_KEYED';
    l_in_TRS_TOA_EXC_STG_BAD_REC_MEMB_BAD_VALUE VARCHAR2(4000) DEFAULT 'WRK_TRS_TOA_S40_RANKED';
    l_in_TRS_TOA_EXC_STG_BAD_REC_MEMB_DATES VARCHAR2(4000) DEFAULT 'WRK_TRS_TOA_S40_RANKED';
    l_in_TRS_TOA_C_S_TRS_PTY_RLE_TOA VARCHAR2(4000) DEFAULT 'WRK_TRS_TOA_S40_RANKED';
-- Per-branch publish counts (one variable per branch)
    l_pub_TRS_TOA_EXC_STG_BAD_REC_MEMB_BAD_VALUE NUMBER DEFAULT 0
    l_pub_TRS_TOA_EXC_STG_BAD_REC_MEMB_DATES NUMBER DEFAULT 0;
    l_pub_TRS_TOA_C_S_TRS_PTY_RLE_TOA NUMBER DEFAULT 0;
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
               COALESCE(MAX(CASE WHEN STEP_NO = 60 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 70 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 10 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), ''),
               COALESCE(MAX(CASE WHEN STEP_NO = 20 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_TOA_S10_RAW'),
               COALESCE(MAX(CASE WHEN STEP_NO = 30 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_TOA_S20_SRC'),
               COALESCE(MAX(CASE WHEN STEP_NO = 40 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_TOA_S30_KEYED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 50 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_TOA_S40_RANKED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 60 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_TOA_S40_RANKED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 70 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_TOA_S40_RANKED')
          INTO l_flag_TRS_TOA_DRIVER, l_flag_TRS_TOA_S10_RAW, l_flag_TRS_TOA_S20_LATEST, l_flag_TRS_TOA_S30_KEYED, l_flag_TRS_TOA_S40_RANKED, l_flag_TRS_TOA_EXC_STG_BAD_REC_MEMB_BAD_VALUE, l_flag_TRS_TOA_EXC_STG_BAD_REC_MEMB_DATES, l_flag_TRS_TOA_C_S_TRS_PTY_RLE_TOA,
               l_in_TRS_TOA_S10_RAW, l_in_TRS_TOA_S20_LATEST, l_in_TRS_TOA_S30_KEYED, l_in_TRS_TOA_S40_RANKED, l_in_TRS_TOA_EXC_STG_BAD_REC_MEMB_BAD_VALUE, l_in_TRS_TOA_EXC_STG_BAD_REC_MEMB_DATES, l_in_TRS_TOA_C_S_TRS_PTY_RLE_TOA
          FROM COMMON.ETL_RUN_CONFIG_TBL
         WHERE WORKFLOW_NAME = c_workflow
           AND MAPPING_NAME = c_mapping;
    WHEN OTHERS THEN
            -- Defaults stand: re-assert them explicitly.
            l_flag_TRS_TOA_DRIVER := 'Y'; l_flag_TRS_TOA_S10_RAW := 'Y'; l_flag_TRS_TOA_S20_LATEST := 'Y'; l_flag_TRS_TOA_S30_KEYED := 'Y'; l_flag_TRS_TOA_S40_RANKED := 'Y'; l_flag_TRS_TOA_EXC_STG_BAD_REC_MEMB_BAD_VALUE := 'Y'; l_flag_TRS_TOA_EXC_STG_BAD_REC_MEMB_DATES := 'Y'; l_flag_TRS_TOA_C_S_TRS_PTY_RLE_TOA := 'Y';
            l_in_TRS_TOA_S10_RAW := ''; l_in_TRS_TOA_S20_LATEST := 'WRK_TRS_TOA_S10_RAW'; l_in_TRS_TOA_S30_KEYED := 'WRK_TRS_TOA_S20_SRC'; l_in_TRS_TOA_S40_RANKED := 'WRK_TRS_TOA_S30_KEYED'; l_in_TRS_TOA_EXC_STG_BAD_REC_MEMB_BAD_VALUE := 'WRK_TRS_TOA_S40_RANKED'; l_in_TRS_TOA_EXC_STG_BAD_REC_MEMB_DATES := 'WRK_TRS_TOA_S40_RANKED'; l_in_TRS_TOA_C_S_TRS_PTY_RLE_TOA := 'WRK_TRS_TOA_S40_RANKED';
    END;

    -- ---- Driver-row disable: skip the whole mapping BEFORE step 5 cleanup
    IF (l_flag_TRS_TOA_DRIVER = 'N') THEN
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'MAPPING_SKIPPED', 'SKIPPED', NULL, 'Mapping skipped by ETL_RUN_CONFIG_TBL (STEP_NO = 0, IS_RUN_ENABLED = N).', NULL);
        l_summary := 'm_Tgt_C_S_TRS_Pty_Rle_TOA SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
        sp_etl_job_finish('TRS', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_TRS_Pty_Rle_TOA skipped by config. JOB_RUN_ID = ' || l_job_run_id);
        RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
    END IF;

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Drops only, no checkpoint call for drops. UNCHANGED from current main.
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_TOA_S10_RAW';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_TOA_S20_SRC';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_TOA_S30_KEYED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_TOA_S40_RANKED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;

    -- ---- Step 10: TOA_SRC_RANKED
    IF (l_flag_TRS_TOA_S10_RAW = 'Y') THEN
        l_rows := sp_snow_step_TRS_TOA_S10_RAW(l_job_run_id, l_run_ts, l_in_TRS_TOA_S10_RAW);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 10 TOA_SRC_RANKED', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'TOA_SRC_RANKED', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 10 TOA_SRC_RANKED: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 20: TOA_LATEST
    IF (l_flag_TRS_TOA_S20_LATEST = 'Y') THEN
        l_rows := sp_snow_step_TRS_TOA_S20_LATEST(l_job_run_id, l_run_ts, l_in_TRS_TOA_S20_LATEST);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 20 TOA_LATEST', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'TOA_LATEST', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 20 TOA_LATEST: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 30: TOA_KEYED
    IF (l_flag_TRS_TOA_S30_KEYED = 'Y') THEN
        l_rows := sp_snow_step_TRS_TOA_S30_KEYED(l_job_run_id, l_run_ts, l_in_TRS_TOA_S30_KEYED);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 30 TOA_KEYED', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'TOA_KEYED', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 30 TOA_KEYED: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 40: TOA_RANKED
    IF (l_flag_TRS_TOA_S40_RANKED = 'Y') THEN
        l_rows := sp_snow_step_TRS_TOA_S40_RANKED(l_job_run_id, l_run_ts, l_in_TRS_TOA_S40_RANKED);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 40 TOA_RANKED', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'TOA_RANKED', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 40 TOA_RANKED: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- PUBLISH: ONE transaction, all enabled branches, in order ----
    -- This is the ONLY step that writes to final targets. Branch procs
    -- contain no checkpoint calls and no transaction control; the
    -- driver checkpoints each branch AFTER COMMIT below.
    -- (Snowflake BEGIN TRANSACTION removed: Oracle transactions are implicit)
    IF (l_flag_TRS_TOA_EXC_STG_BAD_REC_MEMB_BAD_VALUE = 'Y') THEN
        l_pub_TRS_TOA_EXC_STG_BAD_REC_MEMB_BAD_VALUE := sp_snow_pub_TRS_TOA_EXC_STG_BAD_REC_MEMB_BAD_VALUE(l_job_run_id, l_run_ts, l_in_TRS_TOA_EXC_STG_BAD_REC_MEMB_BAD_VALUE);
    END IF;
    IF (l_flag_TRS_TOA_EXC_STG_BAD_REC_MEMB_DATES = 'Y') THEN
        l_pub_TRS_TOA_EXC_STG_BAD_REC_MEMB_DATES := sp_snow_pub_TRS_TOA_EXC_STG_BAD_REC_MEMB_DATES(l_job_run_id, l_run_ts, l_in_TRS_TOA_EXC_STG_BAD_REC_MEMB_DATES);
    END IF;
    IF (l_flag_TRS_TOA_C_S_TRS_PTY_RLE_TOA = 'Y') THEN
        l_pub_TRS_TOA_C_S_TRS_PTY_RLE_TOA := sp_snow_pub_TRS_TOA_C_S_TRS_PTY_RLE_TOA(l_job_run_id, l_run_ts, l_in_TRS_TOA_C_S_TRS_PTY_RLE_TOA);
    END IF;
    COMMIT;

    -- ---- Publish checkpoints AFTER COMMIT (one per branch) ----
    IF (l_flag_TRS_TOA_EXC_STG_BAD_REC_MEMB_BAD_VALUE = 'Y') THEN
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_BAD_VALUE', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published Bad value to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 50 PUBLISH_EXC_BAD_VALUE', l_pub_TRS_TOA_EXC_STG_BAD_REC_MEMB_BAD_VALUE) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_BAD_VALUE', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 50 PUBLISH_EXC_BAD_VALUE: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_TRS_TOA_EXC_STG_BAD_REC_MEMB_DATES = 'Y') THEN
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_DATES', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published Inverted dates to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 60 PUBLISH_EXC_DATES', l_pub_TRS_TOA_EXC_STG_BAD_REC_MEMB_DATES) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_DATES', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 60 PUBLISH_EXC_DATES: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_TRS_TOA_C_S_TRS_PTY_RLE_TOA = 'Y') THEN
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_TRS_PTY_RLE_TOA', 'COMPLETED', 'C_S_TRS_PTY_RLE_TOA', 'Published Valid TOA rows to C_S_TRS_PTY_RLE_TOA.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 70 PUBLISH_C_S_TRS_PTY_RLE_TOA', l_pub_TRS_TOA_C_S_TRS_PTY_RLE_TOA) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_TRS_PTY_RLE_TOA', 'SKIPPED', 'C_S_TRS_PTY_RLE_TOA', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 70 PUBLISH_C_S_TRS_PTY_RLE_TOA: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- TERMINATING ------------------------------------------------------
    sp_etl_job_finish('TRS', l_job_run_id, c_workflow, c_mapping,
        'm_Tgt_C_S_TRS_Pty_Rle_TOA completed. JOB_RUN_ID = ' || l_job_run_id);
    RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
WHEN OTHERS THEN
        ROLLBACK;
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'TERMINATING',
            'JOB_END', 'FAILED', NULL, 'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. ' || 'See ALL_TABLES for WRK_% tables in this schema and VW_ETL_JOB_STORY for the last completed step.', 'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        sp_etl_job_fail('TRS', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_TRS_Pty_Rle_TOA failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_TOA;
/

