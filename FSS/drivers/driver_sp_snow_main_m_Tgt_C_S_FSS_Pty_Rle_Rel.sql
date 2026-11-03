-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Rel  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (FSS)
--
-- IDQ mapping: m_Tgt_C_S_FSS_Pty_Rle_Rel, workflow wf_FSS_Stage_Load.
-- Install schema is FSS_ETL_WRK in database MDM_ETL_FSS; all table
-- names below are unqualified, except the config table, which is
-- COMMON-qualified (COMMON.ETL_RUN_CONFIG_TBL).
-- Driver name and signature are EXACTLY as the current main procedure,
-- so every existing CALL still works.
--
-- WHAT THIS MAPPING DOES, IN PLAIN WORDS
--   Loads translated FSS relationships into the spine and logs untranslated relationships as exceptions.
--
-- BUSINESS FLOW (read this top to bottom -- it IS the business flow)
--   Step  5  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                  previous run (drops only, no
--                                  checkpoint), then rebuild from step 10
--   Step 10  SRC_ACTIVE             Source relationships, both parties off the deactivation list
--   Step 20  CODED                  Relationship code built (missing code defaults to CAREGIVER), direction code type, output gender, both role keys
--   Step 30  TYPED                  Relationship code translated through the code-value lookup
--   Step 40  FINAL                  Relationship key, constants, exception details, insert-only guards
--   ---- PUBLISH (one transaction; branches below, in order) --------
--   Step 50  PUBLISH_C_S_FSS_PTY_RLE_REL Valid relationships -> C_S_FSS_PTY_RLE_REL (SPINE)
--   Step 60  PUBLISH_EXC            Untranslated relationships -> EXC_STG_BAD_REC_MEMB (EXCEPTION)
--   End    TERMINATING             work tables are NOT dropped: they
--                                  stay in the database until the next
--                                  run of this mapping cleans them up
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
--     summary line is appended (helper36 is NOT used for skips -- it
--     renders NULL as '0 row(s)'). No other step is auto-skipped: if a
--     downstream step stays enabled while its input step was skipped,
--     that step's input-existence check raises the missing table
--     loudly instead of running on stale data. Disable downstream
--     steps explicitly if you disable an upstream one.
--   * Config columns IS_DEPENDENT, DEPENDENT_ON and
--     WORK_TABLES_PRODUCED are present in the table but are NOT read
--     by this driver; gating is by IS_RUN_ENABLED only.
--   * SKIPPED vocabulary: JOB_CONTROL_ETL.STEP_STATUS has NO CHECK
--     constraint (a DDL comment that in v2 lists STARTED | COMPLETED | FAILED | SKIPPED), so 'SKIPPED' rows are used here and are flagged to the
--     user as a choice to confirm.
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
--   WRK_FSS_REL_S1_SRC, WRK_FSS_REL_S2_CODED, WRK_FSS_REL_S3_TYPED, WRK_FSS_REL_S4_FINAL.
--   They live in the same schema as the targets (unqualified names, as
--   in the original code) and are prefixed WRK_FSS_. They survive a
--   session crash (TRANSIENT, not TEMP), which is what makes inspection
--   after a run possible. No CURSOR was used: every step here is
--   set-based by design.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only: no TRUNCATE, no DELETE of targets. The IDQ truncate of the relationship table is NOT performed; keys already present are skipped instead (uq_rel guard).
--   * PRESERVED: an untranslated relationship is logged with the looked-up exception code, which is NULL when the 'Invalid_Relationship' code is not configured in the exception catalogue.
--   * PRESERVED: the direction rule -- 'To Child' rows use the related party's gender and code type REL_TP, other rows use the party's own gender and code type INVERSE_REL -- exactly as in the original.
--   * Version sequence is 1 and the period start date is the relationship create date, exactly as in the original.
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
CREATE OR REPLACE FUNCTION sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Rel (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'FSS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_FSS_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_FSS_Pty_Rle_Rel';
    l_run_ts TIMESTAMP DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP);
    l_job_run_id VARCHAR2(4000);
    l_rows NUMBER DEFAULT 0;
    l_summary VARCHAR2(4000) DEFAULT '';
-- Config flags (STEP_NO 0 = driver row, then steps, then branches)
    l_flag_FSS_REL_DRIVER                                VARCHAR DEFAULT 'Y'
    l_flag_FSS_REL_S10_SRC VARCHAR2(4000) DEFAULT 'Y';
    l_flag_FSS_REL_S20_CODED VARCHAR2(4000) DEFAULT 'Y';
    l_flag_FSS_REL_S30_TYPED VARCHAR2(4000) DEFAULT 'Y';
    l_flag_FSS_REL_S40_FINAL VARCHAR2(4000) DEFAULT 'Y';
    l_flag_FSS_REL_C_S_FSS_PTY_RLE_REL VARCHAR2(4000) DEFAULT 'Y';
    l_flag_FSS_REL_EXC_STG_BAD_REC_MEMB VARCHAR2(4000) DEFAULT 'Y';
-- Config consumed strings (work-table inputs, per STEP_NO)
    l_in_FSS_REL_S10_SRC                                 VARCHAR DEFAULT ''
    l_in_FSS_REL_S20_CODED VARCHAR2(4000) DEFAULT 'WRK_FSS_REL_S1_SRC';
    l_in_FSS_REL_S30_TYPED VARCHAR2(4000) DEFAULT 'WRK_FSS_REL_S2_CODED';
    l_in_FSS_REL_S40_FINAL VARCHAR2(4000) DEFAULT 'WRK_FSS_REL_S3_TYPED';
    l_in_FSS_REL_C_S_FSS_PTY_RLE_REL VARCHAR2(4000) DEFAULT 'WRK_FSS_REL_S4_FINAL';
    l_in_FSS_REL_EXC_STG_BAD_REC_MEMB VARCHAR2(4000) DEFAULT 'WRK_FSS_REL_S4_FINAL';
-- Per-branch publish counts (one variable per branch)
    l_pub_FSS_REL_C_S_FSS_PTY_RLE_REL                    NUMBER DEFAULT 0
    l_pub_FSS_REL_EXC_STG_BAD_REC_MEMB NUMBER DEFAULT 0;
BEGIN
    -- ---- STARTING: job-run-id generation exactly as in the current main
    IF (l_job_run_id IS NULL OR l_job_run_id = '') THEN
        l_job_run_id := COALESCE(NULLIF(P_JOB_RUN_ID, ''),
            'FSS_' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDD_HH24MISS')
            || '_' || RAWTOHEX(SYS_GUID()));
    END IF;
    sp_etl_job_begin('FSS', c_workflow, c_mapping, l_job_run_id);

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
               COALESCE(MAX(CASE WHEN STEP_NO = 10 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), ''),
               COALESCE(MAX(CASE WHEN STEP_NO = 20 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_FSS_REL_S1_SRC'),
               COALESCE(MAX(CASE WHEN STEP_NO = 30 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_FSS_REL_S2_CODED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 40 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_FSS_REL_S3_TYPED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 50 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_FSS_REL_S4_FINAL'),
               COALESCE(MAX(CASE WHEN STEP_NO = 60 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_FSS_REL_S4_FINAL')
          INTO l_flag_FSS_REL_DRIVER, l_flag_FSS_REL_S10_SRC, l_flag_FSS_REL_S20_CODED, l_flag_FSS_REL_S30_TYPED, l_flag_FSS_REL_S40_FINAL, l_flag_FSS_REL_C_S_FSS_PTY_RLE_REL, l_flag_FSS_REL_EXC_STG_BAD_REC_MEMB, l_in_FSS_REL_S10_SRC, l_in_FSS_REL_S20_CODED, l_in_FSS_REL_S30_TYPED, l_in_FSS_REL_S40_FINAL, l_in_FSS_REL_C_S_FSS_PTY_RLE_REL, l_in_FSS_REL_EXC_STG_BAD_REC_MEMB
          FROM COMMON.ETL_RUN_CONFIG_TBL
         WHERE WORKFLOW_NAME = c_workflow
           AND MAPPING_NAME = c_mapping;
    WHEN OTHERS THEN
            -- Defaults stand: re-assert them explicitly.
            l_flag_FSS_REL_DRIVER := 'Y'; l_flag_FSS_REL_S10_SRC := 'Y'; l_flag_FSS_REL_S20_CODED := 'Y'; l_flag_FSS_REL_S30_TYPED := 'Y'; l_flag_FSS_REL_S40_FINAL := 'Y'; l_flag_FSS_REL_C_S_FSS_PTY_RLE_REL := 'Y'; l_flag_FSS_REL_EXC_STG_BAD_REC_MEMB := 'Y';
            l_in_FSS_REL_S10_SRC := ''; l_in_FSS_REL_S20_CODED := 'WRK_FSS_REL_S1_SRC'; l_in_FSS_REL_S30_TYPED := 'WRK_FSS_REL_S2_CODED'; l_in_FSS_REL_S40_FINAL := 'WRK_FSS_REL_S3_TYPED'; l_in_FSS_REL_C_S_FSS_PTY_RLE_REL := 'WRK_FSS_REL_S4_FINAL'; l_in_FSS_REL_EXC_STG_BAD_REC_MEMB := 'WRK_FSS_REL_S4_FINAL';
    END;

    -- ---- Driver-row disable: skip the whole mapping BEFORE step 5 cleanup
    IF (l_flag_FSS_REL_DRIVER = 'N') THEN
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'MAPPING_SKIPPED', 'SKIPPED', NULL, 'Mapping skipped by ETL_RUN_CONFIG_TBL (STEP_NO = 0, IS_RUN_ENABLED = N).', NULL);
        l_summary := 'm_Tgt_C_S_FSS_Pty_Rle_Rel SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
        sp_etl_job_finish('FSS', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_FSS_Pty_Rle_Rel skipped by config. JOB_RUN_ID = ' || l_job_run_id);
        RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
    END IF;

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Drops only, no checkpoint call for drops. UNCHANGED from current main.
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_FSS_REL_S1_SRC';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_FSS_REL_S2_CODED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_FSS_REL_S3_TYPED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_FSS_REL_S4_FINAL';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;

    -- ---- Step 10: SRC_ACTIVE
    IF (l_flag_FSS_REL_S10_SRC = 'Y') THEN
        l_rows := sp_snow_step_FSS_REL_S10_SRC(l_job_run_id, l_run_ts, l_in_FSS_REL_S10_SRC);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 10 SRC_ACTIVE', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'SRC_ACTIVE', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 10 SRC_ACTIVE: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 20: CODED
    IF (l_flag_FSS_REL_S20_CODED = 'Y') THEN
        l_rows := sp_snow_step_FSS_REL_S20_CODED(l_job_run_id, l_run_ts, l_in_FSS_REL_S20_CODED);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 20 CODED', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'CODED', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 20 CODED: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 30: TYPED
    IF (l_flag_FSS_REL_S30_TYPED = 'Y') THEN
        l_rows := sp_snow_step_FSS_REL_S30_TYPED(l_job_run_id, l_run_ts, l_in_FSS_REL_S30_TYPED);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 30 TYPED', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'TYPED', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 30 TYPED: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 40: FINAL
    IF (l_flag_FSS_REL_S40_FINAL = 'Y') THEN
        l_rows := sp_snow_step_FSS_REL_S40_FINAL(l_job_run_id, l_run_ts, l_in_FSS_REL_S40_FINAL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 40 FINAL', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'FINAL', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 40 FINAL: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- PUBLISH: ONE transaction, all enabled branches, in order ----
    -- This is the ONLY step that writes to final targets. Branch procs
    -- contain no checkpoint calls and no transaction control; the
    -- driver checkpoints each branch AFTER COMMIT below.
    -- (Snowflake BEGIN TRANSACTION removed: Oracle transactions are implicit)
    IF (l_flag_FSS_REL_C_S_FSS_PTY_RLE_REL = 'Y') THEN
        l_pub_FSS_REL_C_S_FSS_PTY_RLE_REL := sp_snow_pub_FSS_REL_C_S_FSS_PTY_RLE_REL(l_job_run_id, l_run_ts, l_in_FSS_REL_C_S_FSS_PTY_RLE_REL);
    END IF;
    IF (l_flag_FSS_REL_EXC_STG_BAD_REC_MEMB = 'Y') THEN
        l_pub_FSS_REL_EXC_STG_BAD_REC_MEMB := sp_snow_pub_FSS_REL_EXC_STG_BAD_REC_MEMB(l_job_run_id, l_run_ts, l_in_FSS_REL_EXC_STG_BAD_REC_MEMB);
    END IF;
    COMMIT;

    -- ---- Publish checkpoints AFTER COMMIT (one per branch) ----
    IF (l_flag_FSS_REL_C_S_FSS_PTY_RLE_REL = 'Y') THEN
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_FSS_PTY_RLE_REL', 'COMPLETED', 'C_S_FSS_PTY_RLE_REL', 'Published valid relationships to C_S_FSS_PTY_RLE_REL.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 50 PUBLISH_C_S_FSS_PTY_RLE_REL', l_pub_FSS_REL_C_S_FSS_PTY_RLE_REL) || CHR(10);
    ELSE
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_FSS_PTY_RLE_REL', 'SKIPPED', 'C_S_FSS_PTY_RLE_REL', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 50 PUBLISH_C_S_FSS_PTY_RLE_REL: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_FSS_REL_EXC_STG_BAD_REC_MEMB = 'Y') THEN
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published untranslated relationships to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 60 PUBLISH_EXC', l_pub_FSS_REL_EXC_STG_BAD_REC_MEMB) || CHR(10);
    ELSE
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 60 PUBLISH_EXC: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- TERMINATING ------------------------------------------------------
    sp_etl_job_finish('FSS', l_job_run_id, c_workflow, c_mapping,
        'm_Tgt_C_S_FSS_Pty_Rle_Rel completed. JOB_RUN_ID = ' || l_job_run_id);
    RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
WHEN OTHERS THEN
        ROLLBACK;
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'TERMINATING',
            'JOB_END', 'FAILED', NULL, 'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. ' || 'See ALL_TABLES for WRK_% tables in this schema and VW_ETL_JOB_STORY for the last completed step.', 'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        sp_etl_job_fail('FSS', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_FSS_Pty_Rle_Rel failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Rel;
/

