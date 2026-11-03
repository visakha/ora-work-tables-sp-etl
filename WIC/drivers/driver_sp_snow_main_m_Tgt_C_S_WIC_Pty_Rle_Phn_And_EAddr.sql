-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (WIC)
--
-- IDQ mapping: m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr, workflow wf_WIC_Stage_Load.
-- Install schema is WIC_ETL_WRK in database MDM_ETL_WIC; all table
-- names below are unqualified, except the config table, which is
-- COMMON-qualified (COMMON.ETL_RUN_CONFIG_TBL).
-- Driver name and signature are EXACTLY as the current main procedure,
-- so every existing CALL still works.
--
-- WHAT THIS MAPPING DOES, IN PLAIN WORDS
--   Each active WIC row gives one phone and possibly one e-mail. Good phones load, bad phones are logged. Non-null e-mails are validated the same way: valid e-mails load, bad e-mails are logged.
--
-- BUSINESS FLOW (read this top to bottom -- it IS the business flow)
--     Step  5  CLEANUP_PREVIOUS_RUN  drop any work tables left by the previous run (drops only, no checkpoint), then rebuild from step 10
--     Step 10  SRC                      WRK_WIC_PHN_S10_SRC
--     Step 20  CHECKED                  WRK_WIC_PHN_S20_CHECKED
--     Step 30  ROUTED                   WRK_WIC_PHN_S30_ROUTED
--     Step 40  READY                    WRK_WIC_PHN_S40_READY
--     Step 50  PUBLISH_C_S_WIC_PTY_RLE_PHN good phones -> C_S_WIC_PTY_RLE_PHN (SPINE)
--     Step 60  PUBLISH_EXC_STG_BAD_REC_MEMB_PHONE bad-phone exceptions -> EXC_STG_BAD_REC_MEMB (EXCEPTION)
--     Step 70  PUBLISH_C_S_WIC_PTY_RLE_EADDR valid e-mails -> C_S_WIC_PTY_RLE_EADDR (SPINE)
--     Step 80  PUBLISH_EXC_STG_BAD_REC_MEMB_EMAIL bad-e-mail exceptions -> EXC_STG_BAD_REC_MEMB (EXCEPTION)
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
--   WRK_WIC_PHN_S10_SRC, WRK_WIC_PHN_S20_CHECKED, WRK_WIC_PHN_S30_ROUTED, WRK_WIC_PHN_S40_READY. They live in the same schema as the targets (unqualified names, as in the original code) and are prefixed WRK_WIC_. They survive a session crash (TRANSIENT, not TEMP), which is what makes inspection after a run possible. No CURSOR was used: every step here is set-based by design.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only: IDQ truncates of the phone and e-mail targets are not performed.
--   * No null-phone filter: a party without a phone is validated and logged as an invalid phone.
--   * The e-mail key uses the e-mail as read (no trim).
--   * The phone routing groups overlap by construction: a Missing_AreaCode code counts as both good and bad, so the original INSERT ALL would write such a row to both the phone table and the exception table, and the publish INSERTs keep the same WHEN conditions (the original header notes Missing_AreaCode only exists for ECI, so WIC never gets it in practice).
--   * VERSION_SEQ is 1 on both targets; PERIOD_START_DATE = DATEKEY.
--
-- SIGNATURE
--   The original parameters are unchanged and in the same order, so every existing CALL still works. One parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run (a run id is generated and returned in the summary).
--   A restart is simply a new run: the mapping cleans up the previous run's work tables at its start (step 5) and runs every step from scratch. There is no step-level restart.
--   Procedure-call return capture uses `l_rows := (CALL proc(...));` (Snowflake Scripting scalar-call form) -- a compile-time verification item, since there is no live Snowflake here.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'WIC';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_WIC_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr';
    l_run_ts TIMESTAMP DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP);
    l_job_run_id VARCHAR2(4000);
    l_rows NUMBER DEFAULT 0;
    l_summary VARCHAR2(4000) DEFAULT '';
-- Config flags (STEP_NO 0 = driver row, then steps, then branches)
    l_flag_WIC_PHN_DRIVER VARCHAR DEFAULT 'Y'
    l_flag_WIC_PHN_S10_SRC VARCHAR2(4000) DEFAULT 'Y';
    l_flag_WIC_PHN_S20_CHECKED VARCHAR2(4000) DEFAULT 'Y';
    l_flag_WIC_PHN_S30_ROUTED VARCHAR2(4000) DEFAULT 'Y';
    l_flag_WIC_PHN_S40_READY VARCHAR2(4000) DEFAULT 'Y';
    l_flag_WIC_PHN_C_S_WIC_PTY_RLE_PHN VARCHAR2(4000) DEFAULT 'Y';
    l_flag_WIC_PHN_EXC_STG_BAD_REC_MEMB_PHONE VARCHAR2(4000) DEFAULT 'Y';
    l_flag_WIC_PHN_C_S_WIC_PTY_RLE_EADDR VARCHAR2(4000) DEFAULT 'Y';
    l_flag_WIC_PHN_EXC_STG_BAD_REC_MEMB_EMAIL VARCHAR2(4000) DEFAULT 'Y';
-- Config consumed strings (work-table inputs, per STEP_NO)
    l_in_WIC_PHN_S10_SRC VARCHAR DEFAULT ''
    l_in_WIC_PHN_S20_CHECKED VARCHAR2(4000) DEFAULT 'WRK_WIC_PHN_S10_SRC';
    l_in_WIC_PHN_S30_ROUTED VARCHAR2(4000) DEFAULT 'WRK_WIC_PHN_S20_CHECKED';
    l_in_WIC_PHN_S40_READY VARCHAR2(4000) DEFAULT 'WRK_WIC_PHN_S30_ROUTED';
    l_in_WIC_PHN_C_S_WIC_PTY_RLE_PHN VARCHAR2(4000) DEFAULT 'WRK_WIC_PHN_S40_READY';
    l_in_WIC_PHN_EXC_STG_BAD_REC_MEMB_PHONE VARCHAR2(4000) DEFAULT 'WRK_WIC_PHN_S40_READY';
    l_in_WIC_PHN_C_S_WIC_PTY_RLE_EADDR VARCHAR2(4000) DEFAULT 'WRK_WIC_PHN_S40_READY';
    l_in_WIC_PHN_EXC_STG_BAD_REC_MEMB_EMAIL VARCHAR2(4000) DEFAULT 'WRK_WIC_PHN_S40_READY';
-- Per-branch publish counts (one variable per branch)
    l_pub_WIC_PHN_C_S_WIC_PTY_RLE_PHN NUMBER DEFAULT 0
    l_pub_WIC_PHN_EXC_STG_BAD_REC_MEMB_PHONE NUMBER DEFAULT 0;
    l_pub_WIC_PHN_C_S_WIC_PTY_RLE_EADDR NUMBER DEFAULT 0;
    l_pub_WIC_PHN_EXC_STG_BAD_REC_MEMB_EMAIL NUMBER DEFAULT 0;
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
               COALESCE(MAX(CASE WHEN STEP_NO = 80 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 10 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), ''),
               COALESCE(MAX(CASE WHEN STEP_NO = 20 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_WIC_PHN_S10_SRC'),
               COALESCE(MAX(CASE WHEN STEP_NO = 30 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_WIC_PHN_S20_CHECKED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 40 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_WIC_PHN_S30_ROUTED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 50 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_WIC_PHN_S40_READY'),
               COALESCE(MAX(CASE WHEN STEP_NO = 60 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_WIC_PHN_S40_READY'),
               COALESCE(MAX(CASE WHEN STEP_NO = 70 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_WIC_PHN_S40_READY'),
               COALESCE(MAX(CASE WHEN STEP_NO = 80 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_WIC_PHN_S40_READY')
          INTO l_flag_WIC_PHN_DRIVER, l_flag_WIC_PHN_S10_SRC, l_flag_WIC_PHN_S20_CHECKED, l_flag_WIC_PHN_S30_ROUTED, l_flag_WIC_PHN_S40_READY, l_flag_WIC_PHN_C_S_WIC_PTY_RLE_PHN, l_flag_WIC_PHN_EXC_STG_BAD_REC_MEMB_PHONE, l_flag_WIC_PHN_C_S_WIC_PTY_RLE_EADDR, l_flag_WIC_PHN_EXC_STG_BAD_REC_MEMB_EMAIL,
               l_in_WIC_PHN_S10_SRC, l_in_WIC_PHN_S20_CHECKED, l_in_WIC_PHN_S30_ROUTED, l_in_WIC_PHN_S40_READY, l_in_WIC_PHN_C_S_WIC_PTY_RLE_PHN, l_in_WIC_PHN_EXC_STG_BAD_REC_MEMB_PHONE, l_in_WIC_PHN_C_S_WIC_PTY_RLE_EADDR, l_in_WIC_PHN_EXC_STG_BAD_REC_MEMB_EMAIL
          FROM COMMON.ETL_RUN_CONFIG_TBL
         WHERE WORKFLOW_NAME = c_workflow
           AND MAPPING_NAME = c_mapping;
    WHEN OTHERS THEN
            -- Defaults stand: re-assert them explicitly.
            l_flag_WIC_PHN_DRIVER := 'Y'; l_flag_WIC_PHN_S10_SRC := 'Y'; l_flag_WIC_PHN_S20_CHECKED := 'Y'; l_flag_WIC_PHN_S30_ROUTED := 'Y';
            l_flag_WIC_PHN_S40_READY := 'Y'; l_flag_WIC_PHN_C_S_WIC_PTY_RLE_PHN := 'Y'; l_flag_WIC_PHN_EXC_STG_BAD_REC_MEMB_PHONE := 'Y'; l_flag_WIC_PHN_C_S_WIC_PTY_RLE_EADDR := 'Y';
            l_flag_WIC_PHN_EXC_STG_BAD_REC_MEMB_EMAIL := 'Y';
            l_in_WIC_PHN_S10_SRC := ''; l_in_WIC_PHN_S20_CHECKED := 'WRK_WIC_PHN_S10_SRC'; l_in_WIC_PHN_S30_ROUTED := 'WRK_WIC_PHN_S20_CHECKED';
            l_in_WIC_PHN_S40_READY := 'WRK_WIC_PHN_S30_ROUTED'; l_in_WIC_PHN_C_S_WIC_PTY_RLE_PHN := 'WRK_WIC_PHN_S40_READY'; l_in_WIC_PHN_EXC_STG_BAD_REC_MEMB_PHONE := 'WRK_WIC_PHN_S40_READY';
            l_in_WIC_PHN_C_S_WIC_PTY_RLE_EADDR := 'WRK_WIC_PHN_S40_READY'; l_in_WIC_PHN_EXC_STG_BAD_REC_MEMB_EMAIL := 'WRK_WIC_PHN_S40_READY';
    END;

    -- ---- Driver-row disable: skip the whole mapping BEFORE step 5 cleanup
    IF (l_flag_WIC_PHN_DRIVER = 'N') THEN
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'MAPPING_SKIPPED', 'SKIPPED', NULL, 'Mapping skipped by ETL_RUN_CONFIG_TBL (STEP_NO = 0, IS_RUN_ENABLED = N).', NULL);
        l_summary := 'm_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
        sp_etl_job_finish('WIC', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr skipped by config. JOB_RUN_ID = ' || l_job_run_id);
        RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
    END IF;

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Drops only, no checkpoint call for drops. UNCHANGED from current main.
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_WIC_PHN_S10_SRC';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_WIC_PHN_S20_CHECKED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_WIC_PHN_S30_ROUTED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_WIC_PHN_S40_READY';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;

    -- ---- Step 10: SRC
    IF (l_flag_WIC_PHN_S10_SRC = 'Y') THEN
        l_rows := sp_snow_step_WIC_PHN_S10_SRC(l_job_run_id, l_run_ts, l_in_WIC_PHN_S10_SRC);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 10 SRC', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'SRC', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 10 SRC: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 20: CHECKED
    IF (l_flag_WIC_PHN_S20_CHECKED = 'Y') THEN
        l_rows := sp_snow_step_WIC_PHN_S20_CHECKED(l_job_run_id, l_run_ts, l_in_WIC_PHN_S20_CHECKED);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 20 CHECKED', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'CHECKED', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 20 CHECKED: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 30: ROUTED
    IF (l_flag_WIC_PHN_S30_ROUTED = 'Y') THEN
        l_rows := sp_snow_step_WIC_PHN_S30_ROUTED(l_job_run_id, l_run_ts, l_in_WIC_PHN_S30_ROUTED);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 30 ROUTED', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'ROUTED', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 30 ROUTED: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 40: READY
    IF (l_flag_WIC_PHN_S40_READY = 'Y') THEN
        l_rows := sp_snow_step_WIC_PHN_S40_READY(l_job_run_id, l_run_ts, l_in_WIC_PHN_S40_READY);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 40 READY', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'READY', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 40 READY: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- PUBLISH: ONE transaction, all enabled branches, in order ----
    -- Branch procs contain no checkpoint calls and no transaction control; the
    -- driver checkpoints each branch AFTER COMMIT below.
    -- (Snowflake BEGIN TRANSACTION removed: Oracle transactions are implicit)
    IF (l_flag_WIC_PHN_C_S_WIC_PTY_RLE_PHN = 'Y') THEN
        l_pub_WIC_PHN_C_S_WIC_PTY_RLE_PHN := sp_snow_pub_WIC_PHN_C_S_WIC_PTY_RLE_PHN(l_job_run_id, l_run_ts, l_in_WIC_PHN_C_S_WIC_PTY_RLE_PHN);
    END IF;
    IF (l_flag_WIC_PHN_EXC_STG_BAD_REC_MEMB_PHONE = 'Y') THEN
        l_pub_WIC_PHN_EXC_STG_BAD_REC_MEMB_PHONE := sp_snow_pub_WIC_PHN_EXC_STG_BAD_REC_MEMB_PHONE(l_job_run_id, l_run_ts, l_in_WIC_PHN_EXC_STG_BAD_REC_MEMB_PHONE);
    END IF;
    IF (l_flag_WIC_PHN_C_S_WIC_PTY_RLE_EADDR = 'Y') THEN
        l_pub_WIC_PHN_C_S_WIC_PTY_RLE_EADDR := sp_snow_pub_WIC_PHN_C_S_WIC_PTY_RLE_EADDR(l_job_run_id, l_run_ts, l_in_WIC_PHN_C_S_WIC_PTY_RLE_EADDR);
    END IF;
    IF (l_flag_WIC_PHN_EXC_STG_BAD_REC_MEMB_EMAIL = 'Y') THEN
        l_pub_WIC_PHN_EXC_STG_BAD_REC_MEMB_EMAIL := sp_snow_pub_WIC_PHN_EXC_STG_BAD_REC_MEMB_EMAIL(l_job_run_id, l_run_ts, l_in_WIC_PHN_EXC_STG_BAD_REC_MEMB_EMAIL);
    END IF;
    COMMIT;

    IF (l_flag_WIC_PHN_C_S_WIC_PTY_RLE_PHN = 'Y') THEN
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_WIC_PTY_RLE_PHN', 'COMPLETED', 'C_S_WIC_PTY_RLE_PHN', 'Published good phones to C_S_WIC_PTY_RLE_PHN.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 50 PUBLISH_C_S_WIC_PTY_RLE_PHN', l_pub_WIC_PHN_C_S_WIC_PTY_RLE_PHN) || CHR(10);
    ELSE
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_WIC_PTY_RLE_PHN', 'SKIPPED', 'C_S_WIC_PTY_RLE_PHN', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 50 PUBLISH_C_S_WIC_PTY_RLE_PHN: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    IF (l_flag_WIC_PHN_EXC_STG_BAD_REC_MEMB_PHONE = 'Y') THEN
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_STG_BAD_REC_MEMB_PHONE', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published bad-phone exceptions to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 60 PUBLISH_EXC_STG_BAD_REC_MEMB_PHONE', l_pub_WIC_PHN_EXC_STG_BAD_REC_MEMB_PHONE) || CHR(10);
    ELSE
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_STG_BAD_REC_MEMB_PHONE', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 60 PUBLISH_EXC_STG_BAD_REC_MEMB_PHONE: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    IF (l_flag_WIC_PHN_C_S_WIC_PTY_RLE_EADDR = 'Y') THEN
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_WIC_PTY_RLE_EADDR', 'COMPLETED', 'C_S_WIC_PTY_RLE_EADDR', 'Published valid e-mails to C_S_WIC_PTY_RLE_EADDR.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 70 PUBLISH_C_S_WIC_PTY_RLE_EADDR', l_pub_WIC_PHN_C_S_WIC_PTY_RLE_EADDR) || CHR(10);
    ELSE
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_WIC_PTY_RLE_EADDR', 'SKIPPED', 'C_S_WIC_PTY_RLE_EADDR', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 70 PUBLISH_C_S_WIC_PTY_RLE_EADDR: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    IF (l_flag_WIC_PHN_EXC_STG_BAD_REC_MEMB_EMAIL = 'Y') THEN
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_STG_BAD_REC_MEMB_EMAIL', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published bad-e-mail exceptions to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 80 PUBLISH_EXC_STG_BAD_REC_MEMB_EMAIL', l_pub_WIC_PHN_EXC_STG_BAD_REC_MEMB_EMAIL) || CHR(10);
    ELSE
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_STG_BAD_REC_MEMB_EMAIL', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 80 PUBLISH_EXC_STG_BAD_REC_MEMB_EMAIL: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- TERMINATING ------------------------------------------------------
    sp_etl_job_finish('WIC', l_job_run_id, c_workflow, c_mapping,
        'm_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr completed. JOB_RUN_ID = ' || l_job_run_id);
    RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
WHEN OTHERS THEN
        ROLLBACK;
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'TERMINATING',
            'JOB_END', 'FAILED', NULL, 'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. See ALL_TABLES for WRK_% tables in this schema and VW_ETL_JOB_STORY for the last completed step.', 'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        sp_etl_job_fail('WIC', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr;
/

