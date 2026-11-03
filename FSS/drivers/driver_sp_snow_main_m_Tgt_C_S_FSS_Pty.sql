-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_FSS_Pty  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (FSS)
--
-- IDQ mapping: m_Tgt_C_S_FSS_Pty, workflow wf_FSS_Stage_Load.
-- Install schema is FSS_ETL_WRK in database MDM_ETL_FSS; all table
-- names below are unqualified, except the config table, which is
-- COMMON-qualified (COMMON.ETL_RUN_CONFIG_TBL).
-- Driver name and signature are EXACTLY as the current main procedure,
-- so every existing CALL still works.
--
-- WHAT THIS MAPPING DOES, IN PLAIN WORDS
--   Loads active FSS parties and party roles into the spine and logs demographic exceptions. An exception never rejects the party: the party is loaded AND logged.
--
-- BUSINESS FLOW (read this top to bottom -- it IS the business flow)
--   Step  5  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                  previous run (drops only, no
--                                  checkpoint), then rebuild from step 10
--   Step 10  SRC_ACTIVE             Source clients, deactivated parties removed
--   Step 20  DQ_CHECKS              Name standardisation, gender, birth date, ethnicity, race, language, suffix checks
--   Step 30  DQ2_EXCEPTIONS         Standardised values with exception codes / descriptions / types resolved
--   Step 40  ROUTED                 Party / role keys, exception groups, insert-only guards
--   ---- PUBLISH (one transaction; branches below, in order) --------
--   Step 50  PUBLISH_C_S_FSS_PTY    Valid parties -> C_S_FSS_PTY (SPINE)
--   Step 60  PUBLISH_C_S_FSS_PTY_RLE Valid roles -> C_S_FSS_PTY_RLE (SPINE)
--   Step 70  PUBLISH_EXC_GENDER     Invalid gender -> EXC_STG_BAD_REC_MEMB (EXCEPTION)
--   Step 80  PUBLISH_EXC_BIRTH      Invalid birth date -> EXC_STG_BAD_REC_MEMB (EXCEPTION)
--   Step 90  PUBLISH_EXC_ETHNICITY  Invalid ethnicity -> EXC_STG_BAD_REC_MEMB (EXCEPTION)
--   Step 100  PUBLISH_EXC_RACE       Invalid race -> EXC_STG_BAD_REC_MEMB (EXCEPTION)
--   Step 110  PUBLISH_EXC_LANGUAGE   Invalid language -> EXC_STG_BAD_REC_MEMB (EXCEPTION)
--   Step 120  PUBLISH_EXC_SUFFIX     Invalid suffix -> EXC_STG_BAD_REC_MEMB (EXCEPTION)
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
--   WRK_FSS_PTY_S1_SRC, WRK_FSS_PTY_S2_DQ, WRK_FSS_PTY_S3_DQ2, WRK_FSS_PTY_S4_ROUTED.
--   They live in the same schema as the targets (unqualified names, as
--   in the original code) and are prefixed WRK_FSS_. They survive a
--   session crash (TRANSIENT, not TEMP), which is what makes inspection
--   after a run possible. No CURSOR was used: every step here is
--   set-based by design.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only: no TRUNCATE, no DELETE of targets. The IDQ truncate of the party and role tables is NOT performed; keys already present are skipped instead (uq_pty / uq_rle guards). A re-run inserts nothing twice but does not remove rows IDQ would have truncated away.
--   * PRESERVED: the party table's birth date is the source date of birth, so a future birth date is still loaded; the language exception row writes the checked birth date instead (blank for a future one).
--   * PRESERVED: ethnicity, race and language exceptions are routed on the looked-up code, so an unconfigured code produces no row; gender is routed on the looked-up description.
--   * PRESERVED: the suffix check uses the code-value lookup WITHOUT a code-type filter, exactly as in the original.
--   * PRESERVED: the commented-out testing source filter is not applied, exactly as in the original.
--   * Version sequence is hard-coded to 1 and the period start date is the last-update date on both targets, exactly as in the original.
--   * An exception never rejects the party: the party is loaded AND logged.
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
CREATE OR REPLACE FUNCTION sp_snow_main_m_Tgt_C_S_FSS_Pty (P_PTY_BO_CLASS_CD_MEMBER IN VARCHAR2 DEFAULT 'Indv', P_RLE_BO_CLASS_CD_MEMBER IN VARCHAR2 DEFAULT 'Member', P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'FSS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_FSS_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_FSS_Pty';
    l_run_ts TIMESTAMP DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP);
    l_job_run_id VARCHAR2(4000);
    l_rows NUMBER DEFAULT 0;
    l_summary VARCHAR2(4000) DEFAULT '';
-- Config flags (STEP_NO 0 = driver row, then steps, then branches)
    l_flag_FSS_PTY_DRIVER                                VARCHAR DEFAULT 'Y'
    l_flag_FSS_PTY_S10_SRC VARCHAR2(4000) DEFAULT 'Y';
    l_flag_FSS_PTY_S20_DQ VARCHAR2(4000) DEFAULT 'Y';
    l_flag_FSS_PTY_S30_DQ2 VARCHAR2(4000) DEFAULT 'Y';
    l_flag_FSS_PTY_S40_ROUTED VARCHAR2(4000) DEFAULT 'Y';
    l_flag_FSS_PTY_C_S_FSS_PTY VARCHAR2(4000) DEFAULT 'Y';
    l_flag_FSS_PTY_C_S_FSS_PTY_RLE VARCHAR2(4000) DEFAULT 'Y';
    l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_GENDER VARCHAR2(4000) DEFAULT 'Y';
    l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH VARCHAR2(4000) DEFAULT 'Y';
    l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY VARCHAR2(4000) DEFAULT 'Y';
    l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_RACE VARCHAR2(4000) DEFAULT 'Y';
    l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE VARCHAR2(4000) DEFAULT 'Y';
    l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_SUFFIX VARCHAR2(4000) DEFAULT 'Y';
-- Config consumed strings (work-table inputs, per STEP_NO)
    l_in_FSS_PTY_S10_SRC                                 VARCHAR DEFAULT ''
    l_in_FSS_PTY_S20_DQ VARCHAR2(4000) DEFAULT 'WRK_FSS_PTY_S1_SRC';
    l_in_FSS_PTY_S30_DQ2 VARCHAR2(4000) DEFAULT 'WRK_FSS_PTY_S2_DQ';
    l_in_FSS_PTY_S40_ROUTED VARCHAR2(4000) DEFAULT 'WRK_FSS_PTY_S3_DQ2';
    l_in_FSS_PTY_C_S_FSS_PTY VARCHAR2(4000) DEFAULT 'WRK_FSS_PTY_S4_ROUTED';
    l_in_FSS_PTY_C_S_FSS_PTY_RLE VARCHAR2(4000) DEFAULT 'WRK_FSS_PTY_S4_ROUTED';
    l_in_FSS_PTY_EXC_STG_BAD_REC_MEMB_GENDER VARCHAR2(4000) DEFAULT 'WRK_FSS_PTY_S4_ROUTED';
    l_in_FSS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH VARCHAR2(4000) DEFAULT 'WRK_FSS_PTY_S4_ROUTED';
    l_in_FSS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY VARCHAR2(4000) DEFAULT 'WRK_FSS_PTY_S4_ROUTED';
    l_in_FSS_PTY_EXC_STG_BAD_REC_MEMB_RACE VARCHAR2(4000) DEFAULT 'WRK_FSS_PTY_S4_ROUTED';
    l_in_FSS_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE VARCHAR2(4000) DEFAULT 'WRK_FSS_PTY_S4_ROUTED';
    l_in_FSS_PTY_EXC_STG_BAD_REC_MEMB_SUFFIX VARCHAR2(4000) DEFAULT 'WRK_FSS_PTY_S4_ROUTED';
-- Per-branch publish counts (one variable per branch)
    l_pub_FSS_PTY_C_S_FSS_PTY                            NUMBER DEFAULT 0
    l_pub_FSS_PTY_C_S_FSS_PTY_RLE NUMBER DEFAULT 0;
    l_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_GENDER NUMBER DEFAULT 0;
    l_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH NUMBER DEFAULT 0;
    l_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY NUMBER DEFAULT 0;
    l_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_RACE NUMBER DEFAULT 0;
    l_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE NUMBER DEFAULT 0;
    l_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_SUFFIX NUMBER DEFAULT 0;
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
               COALESCE(MAX(CASE WHEN STEP_NO = 70 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 80 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 90 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 100 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 110 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 120 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 10 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), ''),
               COALESCE(MAX(CASE WHEN STEP_NO = 20 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_FSS_PTY_S1_SRC'),
               COALESCE(MAX(CASE WHEN STEP_NO = 30 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_FSS_PTY_S2_DQ'),
               COALESCE(MAX(CASE WHEN STEP_NO = 40 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_FSS_PTY_S3_DQ2'),
               COALESCE(MAX(CASE WHEN STEP_NO = 50 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_FSS_PTY_S4_ROUTED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 60 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_FSS_PTY_S4_ROUTED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 70 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_FSS_PTY_S4_ROUTED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 80 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_FSS_PTY_S4_ROUTED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 90 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_FSS_PTY_S4_ROUTED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 100 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_FSS_PTY_S4_ROUTED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 110 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_FSS_PTY_S4_ROUTED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 120 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_FSS_PTY_S4_ROUTED')
          INTO l_flag_FSS_PTY_DRIVER, l_flag_FSS_PTY_S10_SRC, l_flag_FSS_PTY_S20_DQ, l_flag_FSS_PTY_S30_DQ2, l_flag_FSS_PTY_S40_ROUTED, l_flag_FSS_PTY_C_S_FSS_PTY, l_flag_FSS_PTY_C_S_FSS_PTY_RLE, l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_GENDER, l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH, l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY, l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_RACE, l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE, l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_SUFFIX, l_in_FSS_PTY_S10_SRC, l_in_FSS_PTY_S20_DQ, l_in_FSS_PTY_S30_DQ2, l_in_FSS_PTY_S40_ROUTED, l_in_FSS_PTY_C_S_FSS_PTY, l_in_FSS_PTY_C_S_FSS_PTY_RLE, l_in_FSS_PTY_EXC_STG_BAD_REC_MEMB_GENDER, l_in_FSS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH, l_in_FSS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY, l_in_FSS_PTY_EXC_STG_BAD_REC_MEMB_RACE, l_in_FSS_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE, l_in_FSS_PTY_EXC_STG_BAD_REC_MEMB_SUFFIX
          FROM COMMON.ETL_RUN_CONFIG_TBL
         WHERE WORKFLOW_NAME = c_workflow
           AND MAPPING_NAME = c_mapping;
    WHEN OTHERS THEN
            -- Defaults stand: re-assert them explicitly.
            l_flag_FSS_PTY_DRIVER := 'Y'; l_flag_FSS_PTY_S10_SRC := 'Y'; l_flag_FSS_PTY_S20_DQ := 'Y'; l_flag_FSS_PTY_S30_DQ2 := 'Y'; l_flag_FSS_PTY_S40_ROUTED := 'Y'; l_flag_FSS_PTY_C_S_FSS_PTY := 'Y'; l_flag_FSS_PTY_C_S_FSS_PTY_RLE := 'Y'; l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_GENDER := 'Y'; l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH := 'Y'; l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY := 'Y'; l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_RACE := 'Y'; l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE := 'Y'; l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_SUFFIX := 'Y';
            l_in_FSS_PTY_S10_SRC := ''; l_in_FSS_PTY_S20_DQ := 'WRK_FSS_PTY_S1_SRC'; l_in_FSS_PTY_S30_DQ2 := 'WRK_FSS_PTY_S2_DQ'; l_in_FSS_PTY_S40_ROUTED := 'WRK_FSS_PTY_S3_DQ2'; l_in_FSS_PTY_C_S_FSS_PTY := 'WRK_FSS_PTY_S4_ROUTED'; l_in_FSS_PTY_C_S_FSS_PTY_RLE := 'WRK_FSS_PTY_S4_ROUTED'; l_in_FSS_PTY_EXC_STG_BAD_REC_MEMB_GENDER := 'WRK_FSS_PTY_S4_ROUTED'; l_in_FSS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH := 'WRK_FSS_PTY_S4_ROUTED'; l_in_FSS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY := 'WRK_FSS_PTY_S4_ROUTED'; l_in_FSS_PTY_EXC_STG_BAD_REC_MEMB_RACE := 'WRK_FSS_PTY_S4_ROUTED'; l_in_FSS_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE := 'WRK_FSS_PTY_S4_ROUTED'; l_in_FSS_PTY_EXC_STG_BAD_REC_MEMB_SUFFIX := 'WRK_FSS_PTY_S4_ROUTED';
    END;

    -- ---- Driver-row disable: skip the whole mapping BEFORE step 5 cleanup
    IF (l_flag_FSS_PTY_DRIVER = 'N') THEN
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'MAPPING_SKIPPED', 'SKIPPED', NULL, 'Mapping skipped by ETL_RUN_CONFIG_TBL (STEP_NO = 0, IS_RUN_ENABLED = N).', NULL);
        l_summary := 'm_Tgt_C_S_FSS_Pty SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
        sp_etl_job_finish('FSS', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_FSS_Pty skipped by config. JOB_RUN_ID = ' || l_job_run_id);
        RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
    END IF;

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Drops only, no checkpoint call for drops. UNCHANGED from current main.
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_FSS_PTY_S1_SRC';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_FSS_PTY_S2_DQ';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_FSS_PTY_S3_DQ2';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_FSS_PTY_S4_ROUTED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;

    -- ---- Step 10: SRC_ACTIVE
    IF (l_flag_FSS_PTY_S10_SRC = 'Y') THEN
        l_rows := sp_snow_step_FSS_PTY_S10_SRC(l_job_run_id, l_run_ts, l_in_FSS_PTY_S10_SRC);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 10 SRC_ACTIVE', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'SRC_ACTIVE', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 10 SRC_ACTIVE: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 20: DQ_CHECKS
    IF (l_flag_FSS_PTY_S20_DQ = 'Y') THEN
        l_rows := sp_snow_step_FSS_PTY_S20_DQ(l_job_run_id, l_run_ts, l_in_FSS_PTY_S20_DQ);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 20 DQ_CHECKS', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'DQ_CHECKS', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 20 DQ_CHECKS: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 30: DQ2_EXCEPTIONS
    IF (l_flag_FSS_PTY_S30_DQ2 = 'Y') THEN
        l_rows := sp_snow_step_FSS_PTY_S30_DQ2(l_job_run_id, l_run_ts, l_in_FSS_PTY_S30_DQ2);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 30 DQ2_EXCEPTIONS', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'DQ2_EXCEPTIONS', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 30 DQ2_EXCEPTIONS: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 40: ROUTED
    IF (l_flag_FSS_PTY_S40_ROUTED = 'Y') THEN
        l_rows := sp_snow_step_FSS_PTY_S40_ROUTED(P_PTY_BO_CLASS_CD_MEMBER, P_RLE_BO_CLASS_CD_MEMBER, l_job_run_id, l_run_ts, l_in_FSS_PTY_S40_ROUTED);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 40 ROUTED', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'ROUTED', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 40 ROUTED: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- PUBLISH: ONE transaction, all enabled branches, in order ----
    -- This is the ONLY step that writes to final targets. Branch procs
    -- contain no checkpoint calls and no transaction control; the
    -- driver checkpoints each branch AFTER COMMIT below.
    -- (Snowflake BEGIN TRANSACTION removed: Oracle transactions are implicit)
    IF (l_flag_FSS_PTY_C_S_FSS_PTY = 'Y') THEN
        l_pub_FSS_PTY_C_S_FSS_PTY := sp_snow_pub_FSS_PTY_C_S_FSS_PTY(l_job_run_id, l_run_ts, l_in_FSS_PTY_C_S_FSS_PTY);
    END IF;
    IF (l_flag_FSS_PTY_C_S_FSS_PTY_RLE = 'Y') THEN
        l_pub_FSS_PTY_C_S_FSS_PTY_RLE := sp_snow_pub_FSS_PTY_C_S_FSS_PTY_RLE(l_job_run_id, l_run_ts, l_in_FSS_PTY_C_S_FSS_PTY_RLE);
    END IF;
    IF (l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_GENDER = 'Y') THEN
        l_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_GENDER := sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_GENDER(l_job_run_id, l_run_ts, l_in_FSS_PTY_EXC_STG_BAD_REC_MEMB_GENDER);
    END IF;
    IF (l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH = 'Y') THEN
        l_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH := sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH(l_job_run_id, l_run_ts, l_in_FSS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH);
    END IF;
    IF (l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY = 'Y') THEN
        l_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY := sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY(l_job_run_id, l_run_ts, l_in_FSS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY);
    END IF;
    IF (l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_RACE = 'Y') THEN
        l_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_RACE := sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_RACE(l_job_run_id, l_run_ts, l_in_FSS_PTY_EXC_STG_BAD_REC_MEMB_RACE);
    END IF;
    IF (l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE = 'Y') THEN
        l_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE := sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE(l_job_run_id, l_run_ts, l_in_FSS_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE);
    END IF;
    IF (l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_SUFFIX = 'Y') THEN
        l_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_SUFFIX := sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_SUFFIX(l_job_run_id, l_run_ts, l_in_FSS_PTY_EXC_STG_BAD_REC_MEMB_SUFFIX);
    END IF;
    COMMIT;

    -- ---- Publish checkpoints AFTER COMMIT (one per branch) ----
    IF (l_flag_FSS_PTY_C_S_FSS_PTY = 'Y') THEN
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_FSS_PTY', 'COMPLETED', 'C_S_FSS_PTY', 'Published valid parties to C_S_FSS_PTY.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 50 PUBLISH_C_S_FSS_PTY', l_pub_FSS_PTY_C_S_FSS_PTY) || CHR(10);
    ELSE
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_FSS_PTY', 'SKIPPED', 'C_S_FSS_PTY', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 50 PUBLISH_C_S_FSS_PTY: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_FSS_PTY_C_S_FSS_PTY_RLE = 'Y') THEN
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_FSS_PTY_RLE', 'COMPLETED', 'C_S_FSS_PTY_RLE', 'Published valid roles to C_S_FSS_PTY_RLE.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 60 PUBLISH_C_S_FSS_PTY_RLE', l_pub_FSS_PTY_C_S_FSS_PTY_RLE) || CHR(10);
    ELSE
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_FSS_PTY_RLE', 'SKIPPED', 'C_S_FSS_PTY_RLE', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 60 PUBLISH_C_S_FSS_PTY_RLE: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_GENDER = 'Y') THEN
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_GENDER', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published invalid gender to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 70 PUBLISH_EXC_GENDER', l_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_GENDER) || CHR(10);
    ELSE
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_GENDER', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 70 PUBLISH_EXC_GENDER: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH = 'Y') THEN
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_BIRTH', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published invalid birth date to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 80 PUBLISH_EXC_BIRTH', l_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH) || CHR(10);
    ELSE
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_BIRTH', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 80 PUBLISH_EXC_BIRTH: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY = 'Y') THEN
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_ETHNICITY', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published invalid ethnicity to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 90 PUBLISH_EXC_ETHNICITY', l_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY) || CHR(10);
    ELSE
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_ETHNICITY', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 90 PUBLISH_EXC_ETHNICITY: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_RACE = 'Y') THEN
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_RACE', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published invalid race to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 100 PUBLISH_EXC_RACE', l_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_RACE) || CHR(10);
    ELSE
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_RACE', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 100 PUBLISH_EXC_RACE: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE = 'Y') THEN
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_LANGUAGE', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published invalid language to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 110 PUBLISH_EXC_LANGUAGE', l_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE) || CHR(10);
    ELSE
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_LANGUAGE', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 110 PUBLISH_EXC_LANGUAGE: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_FSS_PTY_EXC_STG_BAD_REC_MEMB_SUFFIX = 'Y') THEN
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_SUFFIX', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published invalid suffix to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 120 PUBLISH_EXC_SUFFIX', l_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_SUFFIX) || CHR(10);
    ELSE
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_SUFFIX', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 120 PUBLISH_EXC_SUFFIX: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- TERMINATING ------------------------------------------------------
    sp_etl_job_finish('FSS', l_job_run_id, c_workflow, c_mapping,
        'm_Tgt_C_S_FSS_Pty completed. JOB_RUN_ID = ' || l_job_run_id);
    RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
WHEN OTHERS THEN
        ROLLBACK;
        sp_etl_checkpoint('FSS', l_job_run_id, c_workflow, c_mapping, 'TERMINATING',
            'JOB_END', 'FAILED', NULL, 'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. ' || 'See ALL_TABLES for WRK_% tables in this schema and VW_ETL_JOB_STORY for the last completed step.', 'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        sp_etl_job_fail('FSS', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_FSS_Pty failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END sp_snow_main_m_Tgt_C_S_FSS_Pty;
/

