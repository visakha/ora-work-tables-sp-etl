-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_OnGoing  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- IDQ mapping: m_Tgt_C_S_TRS_Pty_OnGoing, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Driver name and signature are EXACTLY as the current main procedure,
-- so every existing CALL still works. Install schema is TRS_ETL_WRK in
-- database MDM_ETL_TRS; all table names below are unqualified, except
-- the config table, which is COMMON-qualified (COMMON.ETL_RUN_CONFIG_TBL).
--
-- BUSINESS FLOW (read this top to bottom -- it IS the business flow)
    Step  5  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
                                  previous run (drops only, no
                                  checkpoint), then rebuild from step 10
    Step  10  SRC_VALID_LIST         WRK_TRS_PTY_S1_SRC
    Step  20  DQ_STANDARDISE_VALIDATE WRK_TRS_PTY_S2_DQ
    Step  30  ROUTER_EXCEPTIONS      WRK_TRS_PTY_S3_ROUTER
    Step  40  DEDUP_VALID            WRK_TRS_PTY_S4_DEDUP
    Step  50  PUBLISH_EXC_NAME       EXC_STG_BAD_REC_MEMB (Invalid party name)
    Step  60  PUBLISH_EXC_GENDER     EXC_STG_BAD_REC_MEMB (Invalid gender code)
    Step  70  PUBLISH_EXC_DEATH      EXC_STG_BAD_REC_MEMB (Invalid death date)
    Step  80  PUBLISH_EXC_BIRTH      EXC_STG_BAD_REC_MEMB (Invalid birth date)
    Step  90  PUBLISH_C_S_TRS_PTY    C_S_TRS_PTY (Valid parties)
    Step 100  PUBLISH_C_S_TRS_PTY_RLE C_S_TRS_PTY_RLE (Valid roles)
    Step 110  PUBLISH_STG_TRS_VALID_MEMBERS STG_TRS_VALID_MEMBERS (New valid members)
    Step 120  PUBLISH_EXC_RACE       EXC_STG_BAD_REC_MEMB (Race exceptions)
    Step 130  PUBLISH_EXC_ETHNICITY  EXC_STG_BAD_REC_MEMB (Ethnicity exceptions)
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
--   WRK_TRS_PTY_S1_SRC, WRK_TRS_PTY_S2_DQ, WRK_TRS_PTY_S3_ROUTER, WRK_TRS_PTY_S4_DEDUP. They live in the same schema as the targets (unqualified
--   names, as in the original code) and are prefixed WRK_TRS_. They
--   survive a session crash (TRANSIENT, not TEMP), which is what makes
--   inspection after a run possible. No cursor was used: every step
--   here is set-based by design.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently; condensed
-- from the current main header -- see the manifest for the full text)
----   (kept deliberately, do not "fix" silently)
--     * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--       DELETE of targets.  IDQ truncates C_S_TRS_PTY / C_S_TRS_PTY_RLE;
--       the Snowflake version instead skips keys already present
--       (uq_pty / uq_rle / uq_exc_* guards).  A re-run therefore inserts
--       nothing twice, but it also does not remove rows that IDQ would
--       have truncated away -- see the User Guide, "Parity gaps".
--     * The stored source filter INDV_ID = 504937068 is NOT applied here,
--       exactly as in the original Snowflake code (it was not part of the
--       custom query).  Confirm in the live IDQ mapping whether it should
--       be (BR notes, Verify item 1).
--     * VERSION_SEQ is hard-coded to 1 (TIMELINE: the MD5 / version
--       comparison is commented out in IDQ); PERIOD_END_DATE,
--       PERIOD_REFERENCE_TIME and TIMELINE_ACTION are NULL (unfed ports).
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
CREATE OR REPLACE FUNCTION sp_snow_main_m_Tgt_C_S_TRS_Pty_OnGoing (P_PTY_BO_CLASS_CD_MEMBER IN VARCHAR2 DEFAULT 'Indv', P_RLE_BO_CLASS_CD_MEMBER IN VARCHAR2 DEFAULT 'Member', P_DC_INDV_TBL_SRC IN VARCHAR2 DEFAULT 'DC_INDV', P_MCI_TBL_SRC IN VARCHAR2 DEFAULT 'MCI', P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TRS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_OnGoing';
    l_run_ts TIMESTAMP DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP);
    l_job_run_id VARCHAR2(4000);
    l_rows NUMBER DEFAULT 0;
    l_summary VARCHAR2(4000) DEFAULT '';
-- Config flags (STEP_NO 0 = driver row, then steps, then branches)
    l_flag_TRS_PTY_DRIVER     VARCHAR DEFAULT 'Y'
    l_flag_TRS_PTY_S10_SRC VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_PTY_S20_DQ VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_PTY_S30_ROUTER VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_PTY_S40_DEDUP VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_NAME VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_GENDER VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_DEATH VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_PTY_C_S_TRS_PTY VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_PTY_C_S_TRS_PTY_RLE VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_PTY_STG_TRS_VALID_MEMBERS VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_RACE VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY VARCHAR2(4000) DEFAULT 'Y';
-- Config consumed strings (work-table inputs, per STEP_NO)
    l_in_TRS_PTY_S10_SRC VARCHAR DEFAULT ''
    l_in_TRS_PTY_S20_DQ VARCHAR2(4000) DEFAULT 'WRK_TRS_PTY_S1_SRC';
    l_in_TRS_PTY_S30_ROUTER VARCHAR2(4000) DEFAULT 'WRK_TRS_PTY_S2_DQ';
    l_in_TRS_PTY_S40_DEDUP VARCHAR2(4000) DEFAULT 'WRK_TRS_PTY_S2_DQ';
    l_in_TRS_PTY_EXC_STG_BAD_REC_MEMB_NAME VARCHAR2(4000) DEFAULT 'WRK_TRS_PTY_S3_ROUTER';
    l_in_TRS_PTY_EXC_STG_BAD_REC_MEMB_GENDER VARCHAR2(4000) DEFAULT 'WRK_TRS_PTY_S3_ROUTER';
    l_in_TRS_PTY_EXC_STG_BAD_REC_MEMB_DEATH VARCHAR2(4000) DEFAULT 'WRK_TRS_PTY_S3_ROUTER';
    l_in_TRS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH VARCHAR2(4000) DEFAULT 'WRK_TRS_PTY_S3_ROUTER';
    l_in_TRS_PTY_C_S_TRS_PTY VARCHAR2(4000) DEFAULT 'WRK_TRS_PTY_S4_DEDUP';
    l_in_TRS_PTY_C_S_TRS_PTY_RLE VARCHAR2(4000) DEFAULT 'WRK_TRS_PTY_S4_DEDUP';
    l_in_TRS_PTY_STG_TRS_VALID_MEMBERS VARCHAR2(4000) DEFAULT 'WRK_TRS_PTY_S4_DEDUP';
    l_in_TRS_PTY_EXC_STG_BAD_REC_MEMB_RACE VARCHAR2(4000) DEFAULT 'WRK_TRS_PTY_S4_DEDUP';
    l_in_TRS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY VARCHAR2(4000) DEFAULT 'WRK_TRS_PTY_S4_DEDUP';
-- Per-branch publish counts (one variable per branch)
    l_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_NAME NUMBER DEFAULT 0
    l_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_GENDER NUMBER DEFAULT 0;
    l_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_DEATH NUMBER DEFAULT 0;
    l_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH NUMBER DEFAULT 0;
    l_pub_TRS_PTY_C_S_TRS_PTY NUMBER DEFAULT 0;
    l_pub_TRS_PTY_C_S_TRS_PTY_RLE NUMBER DEFAULT 0;
    l_pub_TRS_PTY_STG_TRS_VALID_MEMBERS NUMBER DEFAULT 0;
    l_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_RACE NUMBER DEFAULT 0;
    l_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY NUMBER DEFAULT 0;
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
               COALESCE(MAX(CASE WHEN STEP_NO = 80 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 90 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 100 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 110 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 120 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 130 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 10 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), ''),
               COALESCE(MAX(CASE WHEN STEP_NO = 20 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_PTY_S1_SRC'),
               COALESCE(MAX(CASE WHEN STEP_NO = 30 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_PTY_S2_DQ'),
               COALESCE(MAX(CASE WHEN STEP_NO = 40 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_PTY_S2_DQ'),
               COALESCE(MAX(CASE WHEN STEP_NO = 50 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_PTY_S3_ROUTER'),
               COALESCE(MAX(CASE WHEN STEP_NO = 60 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_PTY_S3_ROUTER'),
               COALESCE(MAX(CASE WHEN STEP_NO = 70 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_PTY_S3_ROUTER'),
               COALESCE(MAX(CASE WHEN STEP_NO = 80 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_PTY_S3_ROUTER'),
               COALESCE(MAX(CASE WHEN STEP_NO = 90 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_PTY_S4_DEDUP'),
               COALESCE(MAX(CASE WHEN STEP_NO = 100 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_PTY_S4_DEDUP'),
               COALESCE(MAX(CASE WHEN STEP_NO = 110 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_PTY_S4_DEDUP'),
               COALESCE(MAX(CASE WHEN STEP_NO = 120 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_PTY_S4_DEDUP'),
               COALESCE(MAX(CASE WHEN STEP_NO = 130 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_PTY_S4_DEDUP')
          INTO l_flag_TRS_PTY_DRIVER, l_flag_TRS_PTY_S10_SRC, l_flag_TRS_PTY_S20_DQ, l_flag_TRS_PTY_S30_ROUTER, l_flag_TRS_PTY_S40_DEDUP, l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_NAME, l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_GENDER, l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_DEATH, l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH, l_flag_TRS_PTY_C_S_TRS_PTY, l_flag_TRS_PTY_C_S_TRS_PTY_RLE, l_flag_TRS_PTY_STG_TRS_VALID_MEMBERS, l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_RACE, l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY,
               l_in_TRS_PTY_S10_SRC, l_in_TRS_PTY_S20_DQ, l_in_TRS_PTY_S30_ROUTER, l_in_TRS_PTY_S40_DEDUP, l_in_TRS_PTY_EXC_STG_BAD_REC_MEMB_NAME, l_in_TRS_PTY_EXC_STG_BAD_REC_MEMB_GENDER, l_in_TRS_PTY_EXC_STG_BAD_REC_MEMB_DEATH, l_in_TRS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH, l_in_TRS_PTY_C_S_TRS_PTY, l_in_TRS_PTY_C_S_TRS_PTY_RLE, l_in_TRS_PTY_STG_TRS_VALID_MEMBERS, l_in_TRS_PTY_EXC_STG_BAD_REC_MEMB_RACE, l_in_TRS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY
          FROM COMMON.ETL_RUN_CONFIG_TBL
         WHERE WORKFLOW_NAME = c_workflow
           AND MAPPING_NAME = c_mapping;
    WHEN OTHERS THEN
            -- Defaults stand: re-assert them explicitly.
            l_flag_TRS_PTY_DRIVER := 'Y'; l_flag_TRS_PTY_S10_SRC := 'Y'; l_flag_TRS_PTY_S20_DQ := 'Y'; l_flag_TRS_PTY_S30_ROUTER := 'Y'; l_flag_TRS_PTY_S40_DEDUP := 'Y'; l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_NAME := 'Y'; l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_GENDER := 'Y'; l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_DEATH := 'Y'; l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH := 'Y'; l_flag_TRS_PTY_C_S_TRS_PTY := 'Y'; l_flag_TRS_PTY_C_S_TRS_PTY_RLE := 'Y'; l_flag_TRS_PTY_STG_TRS_VALID_MEMBERS := 'Y'; l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_RACE := 'Y'; l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY := 'Y';
            l_in_TRS_PTY_S10_SRC := ''; l_in_TRS_PTY_S20_DQ := 'WRK_TRS_PTY_S1_SRC'; l_in_TRS_PTY_S30_ROUTER := 'WRK_TRS_PTY_S2_DQ'; l_in_TRS_PTY_S40_DEDUP := 'WRK_TRS_PTY_S2_DQ'; l_in_TRS_PTY_EXC_STG_BAD_REC_MEMB_NAME := 'WRK_TRS_PTY_S3_ROUTER'; l_in_TRS_PTY_EXC_STG_BAD_REC_MEMB_GENDER := 'WRK_TRS_PTY_S3_ROUTER'; l_in_TRS_PTY_EXC_STG_BAD_REC_MEMB_DEATH := 'WRK_TRS_PTY_S3_ROUTER'; l_in_TRS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH := 'WRK_TRS_PTY_S3_ROUTER'; l_in_TRS_PTY_C_S_TRS_PTY := 'WRK_TRS_PTY_S4_DEDUP'; l_in_TRS_PTY_C_S_TRS_PTY_RLE := 'WRK_TRS_PTY_S4_DEDUP'; l_in_TRS_PTY_STG_TRS_VALID_MEMBERS := 'WRK_TRS_PTY_S4_DEDUP'; l_in_TRS_PTY_EXC_STG_BAD_REC_MEMB_RACE := 'WRK_TRS_PTY_S4_DEDUP'; l_in_TRS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY := 'WRK_TRS_PTY_S4_DEDUP';
    END;

    -- ---- Driver-row disable: skip the whole mapping BEFORE step 5 cleanup
    IF (l_flag_TRS_PTY_DRIVER = 'N') THEN
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'MAPPING_SKIPPED', 'SKIPPED', NULL, 'Mapping skipped by ETL_RUN_CONFIG_TBL (STEP_NO = 0, IS_RUN_ENABLED = N).', NULL);
        l_summary := 'm_Tgt_C_S_TRS_Pty_OnGoing SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
        sp_etl_job_finish('TRS', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_TRS_Pty_OnGoing skipped by config. JOB_RUN_ID = ' || l_job_run_id);
        RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
    END IF;

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Drops only, no checkpoint call for drops. UNCHANGED from current main.
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_PTY_S1_SRC';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_PTY_S2_DQ';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_PTY_S3_ROUTER';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_PTY_S4_DEDUP';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;

    -- ---- Step 10: SRC_VALID_LIST
    IF (l_flag_TRS_PTY_S10_SRC = 'Y') THEN
        l_rows := sp_snow_step_TRS_PTY_S10_SRC(P_DC_INDV_TBL_SRC, P_MCI_TBL_SRC, l_job_run_id, l_run_ts, l_in_TRS_PTY_S10_SRC);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 10 SRC_VALID_LIST', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'SRC_VALID_LIST', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 10 SRC_VALID_LIST: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 20: DQ_STANDARDISE_VALIDATE
    IF (l_flag_TRS_PTY_S20_DQ = 'Y') THEN
        l_rows := sp_snow_step_TRS_PTY_S20_DQ(P_DC_INDV_TBL_SRC, l_job_run_id, l_run_ts, l_in_TRS_PTY_S20_DQ);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 20 DQ_STANDARDISE_VALIDATE', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'DQ_STANDARDISE_VALIDATE', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 20 DQ_STANDARDISE_VALIDATE: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 30: ROUTER_EXCEPTIONS
    IF (l_flag_TRS_PTY_S30_ROUTER = 'Y') THEN
        l_rows := sp_snow_step_TRS_PTY_S30_ROUTER(l_job_run_id, l_run_ts, l_in_TRS_PTY_S30_ROUTER);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 30 ROUTER_EXCEPTIONS', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'ROUTER_EXCEPTIONS', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 30 ROUTER_EXCEPTIONS: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 40: DEDUP_VALID
    IF (l_flag_TRS_PTY_S40_DEDUP = 'Y') THEN
        l_rows := sp_snow_step_TRS_PTY_S40_DEDUP(P_RLE_BO_CLASS_CD_MEMBER, l_job_run_id, l_run_ts, l_in_TRS_PTY_S40_DEDUP);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 40 DEDUP_VALID', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'DEDUP_VALID', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 40 DEDUP_VALID: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- PUBLISH: ONE transaction, all enabled branches, in order ----
    -- This is the ONLY step that writes to final targets. Branch procs
    -- contain no checkpoint calls and no transaction control; the
    -- driver checkpoints each branch AFTER COMMIT below.
    -- (Snowflake BEGIN TRANSACTION removed: Oracle transactions are implicit)
    IF (l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_NAME = 'Y') THEN
        l_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_NAME := sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_NAME(l_job_run_id, l_run_ts, l_in_TRS_PTY_EXC_STG_BAD_REC_MEMB_NAME);
    END IF;
    IF (l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_GENDER = 'Y') THEN
        l_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_GENDER := sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_GENDER(l_job_run_id, l_run_ts, l_in_TRS_PTY_EXC_STG_BAD_REC_MEMB_GENDER);
    END IF;
    IF (l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_DEATH = 'Y') THEN
        l_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_DEATH := sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_DEATH(l_job_run_id, l_run_ts, l_in_TRS_PTY_EXC_STG_BAD_REC_MEMB_DEATH);
    END IF;
    IF (l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH = 'Y') THEN
        l_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH := sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH(l_job_run_id, l_run_ts, l_in_TRS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH);
    END IF;
    IF (l_flag_TRS_PTY_C_S_TRS_PTY = 'Y') THEN
        l_pub_TRS_PTY_C_S_TRS_PTY := sp_snow_pub_TRS_PTY_C_S_TRS_PTY(P_PTY_BO_CLASS_CD_MEMBER, l_job_run_id, l_run_ts, l_in_TRS_PTY_C_S_TRS_PTY);
    END IF;
    IF (l_flag_TRS_PTY_C_S_TRS_PTY_RLE = 'Y') THEN
        l_pub_TRS_PTY_C_S_TRS_PTY_RLE := sp_snow_pub_TRS_PTY_C_S_TRS_PTY_RLE(P_RLE_BO_CLASS_CD_MEMBER, l_job_run_id, l_run_ts, l_in_TRS_PTY_C_S_TRS_PTY_RLE);
    END IF;
    IF (l_flag_TRS_PTY_STG_TRS_VALID_MEMBERS = 'Y') THEN
        l_pub_TRS_PTY_STG_TRS_VALID_MEMBERS := sp_snow_pub_TRS_PTY_STG_TRS_VALID_MEMBERS(l_job_run_id, l_run_ts, l_in_TRS_PTY_STG_TRS_VALID_MEMBERS);
    END IF;
    IF (l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_RACE = 'Y') THEN
        l_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_RACE := sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_RACE(l_job_run_id, l_run_ts, l_in_TRS_PTY_EXC_STG_BAD_REC_MEMB_RACE);
    END IF;
    IF (l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY = 'Y') THEN
        l_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY := sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY(l_job_run_id, l_run_ts, l_in_TRS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY);
    END IF;
    COMMIT;

    -- ---- Publish checkpoints AFTER COMMIT (one per branch) ----
    IF (l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_NAME = 'Y') THEN
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_NAME', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published Invalid party name to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 50 PUBLISH_EXC_NAME', l_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_NAME) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_NAME', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 50 PUBLISH_EXC_NAME: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_GENDER = 'Y') THEN
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_GENDER', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published Invalid gender code to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 60 PUBLISH_EXC_GENDER', l_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_GENDER) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_GENDER', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 60 PUBLISH_EXC_GENDER: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_DEATH = 'Y') THEN
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_DEATH', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published Invalid death date to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 70 PUBLISH_EXC_DEATH', l_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_DEATH) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_DEATH', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 70 PUBLISH_EXC_DEATH: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH = 'Y') THEN
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_BIRTH', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published Invalid birth date to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 80 PUBLISH_EXC_BIRTH', l_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_BIRTH', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 80 PUBLISH_EXC_BIRTH: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_TRS_PTY_C_S_TRS_PTY = 'Y') THEN
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_TRS_PTY', 'COMPLETED', 'C_S_TRS_PTY', 'Published Valid parties to C_S_TRS_PTY.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 90 PUBLISH_C_S_TRS_PTY', l_pub_TRS_PTY_C_S_TRS_PTY) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_TRS_PTY', 'SKIPPED', 'C_S_TRS_PTY', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 90 PUBLISH_C_S_TRS_PTY: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_TRS_PTY_C_S_TRS_PTY_RLE = 'Y') THEN
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_TRS_PTY_RLE', 'COMPLETED', 'C_S_TRS_PTY_RLE', 'Published Valid roles to C_S_TRS_PTY_RLE.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 100 PUBLISH_C_S_TRS_PTY_RLE', l_pub_TRS_PTY_C_S_TRS_PTY_RLE) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_TRS_PTY_RLE', 'SKIPPED', 'C_S_TRS_PTY_RLE', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 100 PUBLISH_C_S_TRS_PTY_RLE: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_TRS_PTY_STG_TRS_VALID_MEMBERS = 'Y') THEN
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_STG_TRS_VALID_MEMBERS', 'COMPLETED', 'STG_TRS_VALID_MEMBERS', 'Published New valid members to STG_TRS_VALID_MEMBERS.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 110 PUBLISH_STG_TRS_VALID_MEMBERS', l_pub_TRS_PTY_STG_TRS_VALID_MEMBERS) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_STG_TRS_VALID_MEMBERS', 'SKIPPED', 'STG_TRS_VALID_MEMBERS', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 110 PUBLISH_STG_TRS_VALID_MEMBERS: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_RACE = 'Y') THEN
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_RACE', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published Race exceptions to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 120 PUBLISH_EXC_RACE', l_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_RACE) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_RACE', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 120 PUBLISH_EXC_RACE: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_TRS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY = 'Y') THEN
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_ETHNICITY', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published Ethnicity exceptions to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 130 PUBLISH_EXC_ETHNICITY', l_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_ETHNICITY', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 130 PUBLISH_EXC_ETHNICITY: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- TERMINATING ------------------------------------------------------
    sp_etl_job_finish('TRS', l_job_run_id, c_workflow, c_mapping,
        'm_Tgt_C_S_TRS_Pty_OnGoing completed. JOB_RUN_ID = ' || l_job_run_id);
    RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
WHEN OTHERS THEN
        ROLLBACK;
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'TERMINATING',
            'JOB_END', 'FAILED', NULL, 'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. ' || 'See ALL_TABLES for WRK_% tables in this schema and VW_ETL_JOB_STORY for the last completed step.', 'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        sp_etl_job_fail('TRS', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_TRS_Pty_OnGoing failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END sp_snow_main_m_Tgt_C_S_TRS_Pty_OnGoing;
/

