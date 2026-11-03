-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- IDQ mapping: m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Driver name and signature are EXACTLY as the current main procedure,
-- so every existing CALL still works. Install schema is TRS_ETL_WRK in
-- database MDM_ETL_TRS; all table names below are unqualified, except
-- the config table, which is COMMON-qualified (COMMON.ETL_RUN_CONFIG_TBL).
--
-- BUSINESS FLOW (read this top to bottom -- it IS the business flow)
    Step  5  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
                                  previous run (drops only, no
                                  checkpoint), then rebuild from step 10
    Step  10  SRC_RELATIONSHIPS      WRK_TRS_REL1_S1_SRC
    Step  20  KEYED                  WRK_TRS_REL1_S2_KEYED
    Step  30  ROUTER_EXCEPTIONS      WRK_TRS_REL1_S3_ROUTER
    Step  40  CONSOLIDATED           WRK_TRS_REL1_S4_CONSOL
    Step  50  PREPARED               WRK_TRS_REL1_S5_PREP
    Step  60  TIMELINE               WRK_TRS_REL1_S6_TIMELINE
    Step  70  PUBLISH_EXC_MAIN_ALT_ID EXC_STG_BAD_REC_MEMB (Invalid main alt id)
    Step  80  PUBLISH_EXC_REF_ALT_ID EXC_STG_BAD_REC_MEMB (Invalid ref alt id)
    Step  90  PUBLISH_EXC_LOOKUP     EXC_STG_BAD_REC_MEMB (Invalid lookup)
    Step 100  PUBLISH_EXC_DATES      EXC_STG_BAD_REC_MEMB (Period dates reversed)
    Step 110  PUBLISH_C_S_TRS_PTY_RLE_REL C_S_TRS_PTY_RLE_REL (Valid relationships)
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
--   WRK_TRS_REL1_S1_SRC, WRK_TRS_REL1_S2_KEYED, WRK_TRS_REL1_S3_ROUTER, WRK_TRS_REL1_S4_CONSOL, WRK_TRS_REL1_S5_PREP, WRK_TRS_REL1_S6_TIMELINE. They live in the same schema as the targets (unqualified
--   names, as in the original code) and are prefixed WRK_TRS_. They
--   survive a session crash (TRANSIENT, not TEMP), which is what makes
--   inspection after a run possible. No cursor was used: every step
--   here is set-based by design.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently; condensed
-- from the current main header -- see the manifest for the full text)
----   (kept deliberately, do not "fix" silently)
--     * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--       DELETE of targets.  IDQ truncates C_S_TRS_PTY_RLE_REL; the
--       Snowflake version instead skips keys already present (uq_rel).
--       A re-run therefore inserts nothing twice, but it also does not
--       remove rows that IDQ would have truncated away.
--     * Relationship foreign keys are based on source keys, not MDM
--       rowids, as in IDQ (keys are '<pty_pk>|Member').
--     * 'Invalid_Rel_Type' writes the looked-up code: the exception code
--       column in that INSERT is the code row looked up from
--       EXC_LOOKUP_CODE_VALUE, so it is NULL when that code is not
--       configured in the lookup table -- preserved.
--     * Unfed ports written as NULL: ROWID_OBJECT, DELETED_*, UPDATED_BY,
--       CREATOR.  HUB_STATE_IND is 1 only on the open row with
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
CREATE OR REPLACE FUNCTION sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem (P_INDV_ID_ALT_ID_TP IN VARCHAR2 DEFAULT '007', -- $INDV_ID_ALT_ID_TP (substituted into the source SQL)
    P_JOB_RUN_ID             VARCHAR DEFAULT NULL IN ) RETURN VARCHAR2 AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TRS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem';
    l_run_ts TIMESTAMP DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP);
    l_job_run_id VARCHAR2(4000);
    l_rows NUMBER DEFAULT 0;
    l_summary VARCHAR2(4000) DEFAULT '';
-- Config flags (STEP_NO 0 = driver row, then steps, then branches)
    l_flag_TRS_REL1_DRIVER     VARCHAR DEFAULT 'Y'
    l_flag_TRS_REL1_S10_SRC VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_REL1_S20_KEYED VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_REL1_S30_ROUTER VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_REL1_S40_CONSOL VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_REL1_S50_PREP VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_REL1_S60_TIMELINE VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_REL1_EXC_STG_BAD_REC_MEMB_MAIN_ALT_ID VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_REL1_EXC_STG_BAD_REC_MEMB_REF_ALT_ID VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_REL1_EXC_STG_BAD_REC_MEMB_LOOKUP VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_REL1_EXC_STG_BAD_REC_MEMB_DATES VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_REL1_C_S_TRS_PTY_RLE_REL VARCHAR2(4000) DEFAULT 'Y';
-- Config consumed strings (work-table inputs, per STEP_NO)
    l_in_TRS_REL1_S10_SRC VARCHAR DEFAULT ''
    l_in_TRS_REL1_S20_KEYED VARCHAR2(4000) DEFAULT 'WRK_TRS_REL1_S1_SRC';
    l_in_TRS_REL1_S30_ROUTER VARCHAR2(4000) DEFAULT 'WRK_TRS_REL1_S2_KEYED';
    l_in_TRS_REL1_S40_CONSOL VARCHAR2(4000) DEFAULT 'WRK_TRS_REL1_S2_KEYED';
    l_in_TRS_REL1_S50_PREP VARCHAR2(4000) DEFAULT 'WRK_TRS_REL1_S4_CONSOL';
    l_in_TRS_REL1_S60_TIMELINE VARCHAR2(4000) DEFAULT 'WRK_TRS_REL1_S5_PREP';
    l_in_TRS_REL1_EXC_STG_BAD_REC_MEMB_MAIN_ALT_ID VARCHAR2(4000) DEFAULT 'WRK_TRS_REL1_S3_ROUTER';
    l_in_TRS_REL1_EXC_STG_BAD_REC_MEMB_REF_ALT_ID VARCHAR2(4000) DEFAULT 'WRK_TRS_REL1_S3_ROUTER';
    l_in_TRS_REL1_EXC_STG_BAD_REC_MEMB_LOOKUP VARCHAR2(4000) DEFAULT 'WRK_TRS_REL1_S3_ROUTER';
    l_in_TRS_REL1_EXC_STG_BAD_REC_MEMB_DATES VARCHAR2(4000) DEFAULT 'WRK_TRS_REL1_S3_ROUTER';
    l_in_TRS_REL1_C_S_TRS_PTY_RLE_REL VARCHAR2(4000) DEFAULT 'WRK_TRS_REL1_S6_TIMELINE';
-- Per-branch publish counts (one variable per branch)
    l_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_MAIN_ALT_ID NUMBER DEFAULT 0
    l_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_REF_ALT_ID NUMBER DEFAULT 0;
    l_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_LOOKUP NUMBER DEFAULT 0;
    l_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_DATES NUMBER DEFAULT 0;
    l_pub_TRS_REL1_C_S_TRS_PTY_RLE_REL NUMBER DEFAULT 0;
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
               COALESCE(MAX(CASE WHEN STEP_NO = 10 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), ''),
               COALESCE(MAX(CASE WHEN STEP_NO = 20 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_REL1_S1_SRC'),
               COALESCE(MAX(CASE WHEN STEP_NO = 30 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_REL1_S2_KEYED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 40 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_REL1_S2_KEYED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 50 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_REL1_S4_CONSOL'),
               COALESCE(MAX(CASE WHEN STEP_NO = 60 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_REL1_S5_PREP'),
               COALESCE(MAX(CASE WHEN STEP_NO = 70 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_REL1_S3_ROUTER'),
               COALESCE(MAX(CASE WHEN STEP_NO = 80 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_REL1_S3_ROUTER'),
               COALESCE(MAX(CASE WHEN STEP_NO = 90 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_REL1_S3_ROUTER'),
               COALESCE(MAX(CASE WHEN STEP_NO = 100 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_REL1_S3_ROUTER'),
               COALESCE(MAX(CASE WHEN STEP_NO = 110 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_REL1_S6_TIMELINE')
          INTO l_flag_TRS_REL1_DRIVER, l_flag_TRS_REL1_S10_SRC, l_flag_TRS_REL1_S20_KEYED, l_flag_TRS_REL1_S30_ROUTER, l_flag_TRS_REL1_S40_CONSOL, l_flag_TRS_REL1_S50_PREP, l_flag_TRS_REL1_S60_TIMELINE, l_flag_TRS_REL1_EXC_STG_BAD_REC_MEMB_MAIN_ALT_ID, l_flag_TRS_REL1_EXC_STG_BAD_REC_MEMB_REF_ALT_ID, l_flag_TRS_REL1_EXC_STG_BAD_REC_MEMB_LOOKUP, l_flag_TRS_REL1_EXC_STG_BAD_REC_MEMB_DATES, l_flag_TRS_REL1_C_S_TRS_PTY_RLE_REL,
               l_in_TRS_REL1_S10_SRC, l_in_TRS_REL1_S20_KEYED, l_in_TRS_REL1_S30_ROUTER, l_in_TRS_REL1_S40_CONSOL, l_in_TRS_REL1_S50_PREP, l_in_TRS_REL1_S60_TIMELINE, l_in_TRS_REL1_EXC_STG_BAD_REC_MEMB_MAIN_ALT_ID, l_in_TRS_REL1_EXC_STG_BAD_REC_MEMB_REF_ALT_ID, l_in_TRS_REL1_EXC_STG_BAD_REC_MEMB_LOOKUP, l_in_TRS_REL1_EXC_STG_BAD_REC_MEMB_DATES, l_in_TRS_REL1_C_S_TRS_PTY_RLE_REL
          FROM COMMON.ETL_RUN_CONFIG_TBL
         WHERE WORKFLOW_NAME = c_workflow
           AND MAPPING_NAME = c_mapping;
    WHEN OTHERS THEN
            -- Defaults stand: re-assert them explicitly.
            l_flag_TRS_REL1_DRIVER := 'Y'; l_flag_TRS_REL1_S10_SRC := 'Y'; l_flag_TRS_REL1_S20_KEYED := 'Y'; l_flag_TRS_REL1_S30_ROUTER := 'Y'; l_flag_TRS_REL1_S40_CONSOL := 'Y'; l_flag_TRS_REL1_S50_PREP := 'Y'; l_flag_TRS_REL1_S60_TIMELINE := 'Y'; l_flag_TRS_REL1_EXC_STG_BAD_REC_MEMB_MAIN_ALT_ID := 'Y'; l_flag_TRS_REL1_EXC_STG_BAD_REC_MEMB_REF_ALT_ID := 'Y'; l_flag_TRS_REL1_EXC_STG_BAD_REC_MEMB_LOOKUP := 'Y'; l_flag_TRS_REL1_EXC_STG_BAD_REC_MEMB_DATES := 'Y'; l_flag_TRS_REL1_C_S_TRS_PTY_RLE_REL := 'Y';
            l_in_TRS_REL1_S10_SRC := ''; l_in_TRS_REL1_S20_KEYED := 'WRK_TRS_REL1_S1_SRC'; l_in_TRS_REL1_S30_ROUTER := 'WRK_TRS_REL1_S2_KEYED'; l_in_TRS_REL1_S40_CONSOL := 'WRK_TRS_REL1_S2_KEYED'; l_in_TRS_REL1_S50_PREP := 'WRK_TRS_REL1_S4_CONSOL'; l_in_TRS_REL1_S60_TIMELINE := 'WRK_TRS_REL1_S5_PREP'; l_in_TRS_REL1_EXC_STG_BAD_REC_MEMB_MAIN_ALT_ID := 'WRK_TRS_REL1_S3_ROUTER'; l_in_TRS_REL1_EXC_STG_BAD_REC_MEMB_REF_ALT_ID := 'WRK_TRS_REL1_S3_ROUTER'; l_in_TRS_REL1_EXC_STG_BAD_REC_MEMB_LOOKUP := 'WRK_TRS_REL1_S3_ROUTER'; l_in_TRS_REL1_EXC_STG_BAD_REC_MEMB_DATES := 'WRK_TRS_REL1_S3_ROUTER'; l_in_TRS_REL1_C_S_TRS_PTY_RLE_REL := 'WRK_TRS_REL1_S6_TIMELINE';
    END;

    -- ---- Driver-row disable: skip the whole mapping BEFORE step 5 cleanup
    IF (l_flag_TRS_REL1_DRIVER = 'N') THEN
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'MAPPING_SKIPPED', 'SKIPPED', NULL, 'Mapping skipped by ETL_RUN_CONFIG_TBL (STEP_NO = 0, IS_RUN_ENABLED = N).', NULL);
        l_summary := 'm_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
        sp_etl_job_finish('TRS', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem skipped by config. JOB_RUN_ID = ' || l_job_run_id);
        RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
    END IF;

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Drops only, no checkpoint call for drops. UNCHANGED from current main.
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_REL1_S1_SRC';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_REL1_S2_KEYED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_REL1_S3_ROUTER';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_REL1_S4_CONSOL';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_REL1_S5_PREP';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_REL1_S6_TIMELINE';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;

    -- ---- Step 10: SRC_RELATIONSHIPS
    IF (l_flag_TRS_REL1_S10_SRC = 'Y') THEN
        l_rows := sp_snow_step_TRS_REL1_S10_SRC(P_INDV_ID_ALT_ID_TP, l_job_run_id, l_run_ts, l_in_TRS_REL1_S10_SRC);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 10 SRC_RELATIONSHIPS', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'SRC_RELATIONSHIPS', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 10 SRC_RELATIONSHIPS: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 20: KEYED
    IF (l_flag_TRS_REL1_S20_KEYED = 'Y') THEN
        l_rows := sp_snow_step_TRS_REL1_S20_KEYED(l_job_run_id, l_run_ts, l_in_TRS_REL1_S20_KEYED);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 20 KEYED', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'KEYED', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 20 KEYED: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 30: ROUTER_EXCEPTIONS
    IF (l_flag_TRS_REL1_S30_ROUTER = 'Y') THEN
        l_rows := sp_snow_step_TRS_REL1_S30_ROUTER(l_job_run_id, l_run_ts, l_in_TRS_REL1_S30_ROUTER);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 30 ROUTER_EXCEPTIONS', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'ROUTER_EXCEPTIONS', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 30 ROUTER_EXCEPTIONS: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 40: CONSOLIDATED
    IF (l_flag_TRS_REL1_S40_CONSOL = 'Y') THEN
        l_rows := sp_snow_step_TRS_REL1_S40_CONSOL(l_job_run_id, l_run_ts, l_in_TRS_REL1_S40_CONSOL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 40 CONSOLIDATED', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'CONSOLIDATED', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 40 CONSOLIDATED: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 50: PREPARED
    IF (l_flag_TRS_REL1_S50_PREP = 'Y') THEN
        l_rows := sp_snow_step_TRS_REL1_S50_PREP(l_job_run_id, l_run_ts, l_in_TRS_REL1_S50_PREP);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 50 PREPARED', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PREPARED', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 50 PREPARED: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 60: TIMELINE
    IF (l_flag_TRS_REL1_S60_TIMELINE = 'Y') THEN
        l_rows := sp_snow_step_TRS_REL1_S60_TIMELINE(l_job_run_id, l_run_ts, l_in_TRS_REL1_S60_TIMELINE);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 60 TIMELINE', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'TIMELINE', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 60 TIMELINE: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- PUBLISH: ONE transaction, all enabled branches, in order ----
    -- This is the ONLY step that writes to final targets. Branch procs
    -- contain no checkpoint calls and no transaction control; the
    -- driver checkpoints each branch AFTER COMMIT below.
    -- (Snowflake BEGIN TRANSACTION removed: Oracle transactions are implicit)
    IF (l_flag_TRS_REL1_EXC_STG_BAD_REC_MEMB_MAIN_ALT_ID = 'Y') THEN
        l_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_MAIN_ALT_ID := sp_snow_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_MAIN_ALT_ID(l_job_run_id, l_run_ts, l_in_TRS_REL1_EXC_STG_BAD_REC_MEMB_MAIN_ALT_ID);
    END IF;
    IF (l_flag_TRS_REL1_EXC_STG_BAD_REC_MEMB_REF_ALT_ID = 'Y') THEN
        l_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_REF_ALT_ID := sp_snow_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_REF_ALT_ID(l_job_run_id, l_run_ts, l_in_TRS_REL1_EXC_STG_BAD_REC_MEMB_REF_ALT_ID);
    END IF;
    IF (l_flag_TRS_REL1_EXC_STG_BAD_REC_MEMB_LOOKUP = 'Y') THEN
        l_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_LOOKUP := sp_snow_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_LOOKUP(l_job_run_id, l_run_ts, l_in_TRS_REL1_EXC_STG_BAD_REC_MEMB_LOOKUP);
    END IF;
    IF (l_flag_TRS_REL1_EXC_STG_BAD_REC_MEMB_DATES = 'Y') THEN
        l_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_DATES := sp_snow_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_DATES(l_job_run_id, l_run_ts, l_in_TRS_REL1_EXC_STG_BAD_REC_MEMB_DATES);
    END IF;
    IF (l_flag_TRS_REL1_C_S_TRS_PTY_RLE_REL = 'Y') THEN
        l_pub_TRS_REL1_C_S_TRS_PTY_RLE_REL := sp_snow_pub_TRS_REL1_C_S_TRS_PTY_RLE_REL(l_job_run_id, l_run_ts, l_in_TRS_REL1_C_S_TRS_PTY_RLE_REL);
    END IF;
    COMMIT;

    -- ---- Publish checkpoints AFTER COMMIT (one per branch) ----
    IF (l_flag_TRS_REL1_EXC_STG_BAD_REC_MEMB_MAIN_ALT_ID = 'Y') THEN
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_MAIN_ALT_ID', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published Invalid main alt id to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 70 PUBLISH_EXC_MAIN_ALT_ID', l_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_MAIN_ALT_ID) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_MAIN_ALT_ID', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 70 PUBLISH_EXC_MAIN_ALT_ID: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_TRS_REL1_EXC_STG_BAD_REC_MEMB_REF_ALT_ID = 'Y') THEN
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_REF_ALT_ID', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published Invalid ref alt id to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 80 PUBLISH_EXC_REF_ALT_ID', l_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_REF_ALT_ID) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_REF_ALT_ID', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 80 PUBLISH_EXC_REF_ALT_ID: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_TRS_REL1_EXC_STG_BAD_REC_MEMB_LOOKUP = 'Y') THEN
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_LOOKUP', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published Invalid lookup to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 90 PUBLISH_EXC_LOOKUP', l_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_LOOKUP) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_LOOKUP', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 90 PUBLISH_EXC_LOOKUP: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_TRS_REL1_EXC_STG_BAD_REC_MEMB_DATES = 'Y') THEN
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_DATES', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published Period dates reversed to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 100 PUBLISH_EXC_DATES', l_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_DATES) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_DATES', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 100 PUBLISH_EXC_DATES: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_TRS_REL1_C_S_TRS_PTY_RLE_REL = 'Y') THEN
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_TRS_PTY_RLE_REL', 'COMPLETED', 'C_S_TRS_PTY_RLE_REL', 'Published Valid relationships to C_S_TRS_PTY_RLE_REL.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 110 PUBLISH_C_S_TRS_PTY_RLE_REL', l_pub_TRS_REL1_C_S_TRS_PTY_RLE_REL) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_TRS_PTY_RLE_REL', 'SKIPPED', 'C_S_TRS_PTY_RLE_REL', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 110 PUBLISH_C_S_TRS_PTY_RLE_REL: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- TERMINATING ------------------------------------------------------
    sp_etl_job_finish('TRS', l_job_run_id, c_workflow, c_mapping,
        'm_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem completed. JOB_RUN_ID = ' || l_job_run_id);
    RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
WHEN OTHERS THEN
        ROLLBACK;
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'TERMINATING',
            'JOB_END', 'FAILED', NULL, 'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. ' || 'See ALL_TABLES for WRK_% tables in this schema and VW_ETL_JOB_STORY for the last completed step.', 'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        sp_etl_job_fail('TRS', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem;
/

