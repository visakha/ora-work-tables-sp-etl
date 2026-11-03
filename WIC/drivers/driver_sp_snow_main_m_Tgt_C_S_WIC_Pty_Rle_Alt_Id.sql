-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (WIC)
--
-- IDQ mapping: m_Tgt_C_S_WIC_Pty_Rle_Alt_Id, workflow wf_WIC_Stage_Load.
-- Install schema is WIC_ETL_WRK in database MDM_ETL_WIC; all table
-- names below are unqualified, except the config table, which is
-- COMMON-qualified (COMMON.ETL_RUN_CONFIG_TBL).
-- Driver name and signature are EXACTLY as the current main procedure,
-- so every existing CALL still works.
--
-- WHAT THIS MAPPING DOES, IN PLAIN WORDS
--   Writes one alternate id per active WIC party: the WIC id padded to 12, type 020 for SOURCE_TABLE CLIENT and 021 otherwise. Parties with a deactivation status are excluded; keys already in the target are skipped.
--
-- BUSINESS FLOW (read this top to bottom -- it IS the business flow)
--     Step  5  CLEANUP_PREVIOUS_RUN  drop any work tables left by the previous run (drops only, no checkpoint), then rebuild from step 10
--     Step 10  KEYS                     WRK_WIC_ALT_S10_KEYS
--     Step 20  READY                    WRK_WIC_ALT_S20_READY
--     Step 30  PUBLISH_C_S_WIC_PTY_RLE_ALT_ID one alternate id per active party -> C_S_WIC_PTY_RLE_ALT_ID (SPINE)
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
--   WRK_WIC_ALT_S10_KEYS, WRK_WIC_ALT_S20_READY. They live in the same schema as the targets (unqualified names, as in the original code) and are prefixed WRK_WIC_. They survive a session crash (TRANSIENT, not TEMP), which is what makes inspection after a run possible. No CURSOR was used: every step here is set-based by design.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Thin split, flagged in the multisource step map: this original has no CTE chain, it is a single query (an inner derived table plus an outer SELECT). Step 10 builds the keys (the original inner derived table) and step 20 applies the deactivation filter, the already-loaded guard and the one-row-per-key rank (the original outer SELECT). No business expression was changed.
--   * Insert-only: IDQ truncate of C_S_WIC_PTY_RLE_ALT_ID is not performed.
--   * HUB_STATE_IND is not linked (left to the column default).
--   * VERSION_SEQ = 1; PERIOD_START_DATE = DATEKEY; no validation rule runs in this mapping.
--   * The publish INSERT uses the run timestamp directly (not a materialised run_ts column), so this publish proc is the one WIC publish proc in which P_RUN_TS is actually used in the body.
--
-- SIGNATURE
--   The original parameters are unchanged and in the same order, so every existing CALL still works. One parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run (a run id is generated and returned in the summary).
--   A restart is simply a new run: the mapping cleans up the previous run's work tables at its start (step 5) and runs every step from scratch. There is no step-level restart.
--   Procedure-call return capture uses `l_rows := (CALL proc(...));` (Snowflake Scripting scalar-call form) -- a compile-time verification item, since there is no live Snowflake here.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'WIC';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_WIC_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_WIC_Pty_Rle_Alt_Id';
    l_run_ts TIMESTAMP DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP);
    l_job_run_id VARCHAR2(4000);
    l_rows NUMBER DEFAULT 0;
    l_summary VARCHAR2(4000) DEFAULT '';
-- Config flags (STEP_NO 0 = driver row, then steps, then branches)
    l_flag_WIC_ALT_DRIVER VARCHAR DEFAULT 'Y'
    l_flag_WIC_ALT_S10_KEYS VARCHAR2(4000) DEFAULT 'Y';
    l_flag_WIC_ALT_S20_READY VARCHAR2(4000) DEFAULT 'Y';
    l_flag_WIC_ALT_C_S_WIC_PTY_RLE_ALT_ID VARCHAR2(4000) DEFAULT 'Y';
-- Config consumed strings (work-table inputs, per STEP_NO)
    l_in_WIC_ALT_S10_KEYS VARCHAR DEFAULT ''
    l_in_WIC_ALT_S20_READY VARCHAR2(4000) DEFAULT 'WRK_WIC_ALT_S10_KEYS';
    l_in_WIC_ALT_C_S_WIC_PTY_RLE_ALT_ID VARCHAR2(4000) DEFAULT 'WRK_WIC_ALT_S20_READY';
-- Per-branch publish counts (one variable per branch)
    l_pub_WIC_ALT_C_S_WIC_PTY_RLE_ALT_ID NUMBER DEFAULT 0
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
               COALESCE(MAX(CASE WHEN STEP_NO = 10 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), ''),
               COALESCE(MAX(CASE WHEN STEP_NO = 20 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_WIC_ALT_S10_KEYS'),
               COALESCE(MAX(CASE WHEN STEP_NO = 30 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_WIC_ALT_S20_READY')
          INTO l_flag_WIC_ALT_DRIVER, l_flag_WIC_ALT_S10_KEYS, l_flag_WIC_ALT_S20_READY, l_flag_WIC_ALT_C_S_WIC_PTY_RLE_ALT_ID,
               l_in_WIC_ALT_S10_KEYS, l_in_WIC_ALT_S20_READY, l_in_WIC_ALT_C_S_WIC_PTY_RLE_ALT_ID
          FROM COMMON.ETL_RUN_CONFIG_TBL
         WHERE WORKFLOW_NAME = c_workflow
           AND MAPPING_NAME = c_mapping;
    WHEN OTHERS THEN
            -- Defaults stand: re-assert them explicitly.
            l_flag_WIC_ALT_DRIVER := 'Y'; l_flag_WIC_ALT_S10_KEYS := 'Y'; l_flag_WIC_ALT_S20_READY := 'Y'; l_flag_WIC_ALT_C_S_WIC_PTY_RLE_ALT_ID := 'Y';
            l_in_WIC_ALT_S10_KEYS := ''; l_in_WIC_ALT_S20_READY := 'WRK_WIC_ALT_S10_KEYS'; l_in_WIC_ALT_C_S_WIC_PTY_RLE_ALT_ID := 'WRK_WIC_ALT_S20_READY';
    END;

    -- ---- Driver-row disable: skip the whole mapping BEFORE step 5 cleanup
    IF (l_flag_WIC_ALT_DRIVER = 'N') THEN
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'MAPPING_SKIPPED', 'SKIPPED', NULL, 'Mapping skipped by ETL_RUN_CONFIG_TBL (STEP_NO = 0, IS_RUN_ENABLED = N).', NULL);
        l_summary := 'm_Tgt_C_S_WIC_Pty_Rle_Alt_Id SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
        sp_etl_job_finish('WIC', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_WIC_Pty_Rle_Alt_Id skipped by config. JOB_RUN_ID = ' || l_job_run_id);
        RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
    END IF;

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Drops only, no checkpoint call for drops. UNCHANGED from current main.
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_WIC_ALT_S10_KEYS';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_WIC_ALT_S20_READY';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;

    -- ---- Step 10: KEYS
    IF (l_flag_WIC_ALT_S10_KEYS = 'Y') THEN
        l_rows := sp_snow_step_WIC_ALT_S10_KEYS(l_job_run_id, l_run_ts, l_in_WIC_ALT_S10_KEYS);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 10 KEYS', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'KEYS', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 10 KEYS: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 20: READY
    IF (l_flag_WIC_ALT_S20_READY = 'Y') THEN
        l_rows := sp_snow_step_WIC_ALT_S20_READY(l_job_run_id, l_run_ts, l_in_WIC_ALT_S20_READY);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 20 READY', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'READY', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 20 READY: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- PUBLISH: ONE transaction, all enabled branches, in order ----
    -- Branch procs contain no checkpoint calls and no transaction control; the
    -- driver checkpoints each branch AFTER COMMIT below.
    -- (Snowflake BEGIN TRANSACTION removed: Oracle transactions are implicit)
    IF (l_flag_WIC_ALT_C_S_WIC_PTY_RLE_ALT_ID = 'Y') THEN
        l_pub_WIC_ALT_C_S_WIC_PTY_RLE_ALT_ID := sp_snow_pub_WIC_ALT_C_S_WIC_PTY_RLE_ALT_ID(l_job_run_id, l_run_ts, l_in_WIC_ALT_C_S_WIC_PTY_RLE_ALT_ID);
    END IF;
    COMMIT;

    IF (l_flag_WIC_ALT_C_S_WIC_PTY_RLE_ALT_ID = 'Y') THEN
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_WIC_PTY_RLE_ALT_ID', 'COMPLETED', 'C_S_WIC_PTY_RLE_ALT_ID', 'Published one alternate id per active party to C_S_WIC_PTY_RLE_ALT_ID.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 30 PUBLISH_C_S_WIC_PTY_RLE_ALT_ID', l_pub_WIC_ALT_C_S_WIC_PTY_RLE_ALT_ID) || CHR(10);
    ELSE
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_WIC_PTY_RLE_ALT_ID', 'SKIPPED', 'C_S_WIC_PTY_RLE_ALT_ID', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 30 PUBLISH_C_S_WIC_PTY_RLE_ALT_ID: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- TERMINATING ------------------------------------------------------
    sp_etl_job_finish('WIC', l_job_run_id, c_workflow, c_mapping,
        'm_Tgt_C_S_WIC_Pty_Rle_Alt_Id completed. JOB_RUN_ID = ' || l_job_run_id);
    RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
WHEN OTHERS THEN
        ROLLBACK;
        sp_etl_checkpoint('WIC', l_job_run_id, c_workflow, c_mapping, 'TERMINATING',
            'JOB_END', 'FAILED', NULL, 'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. See ALL_TABLES for WRK_% tables in this schema and VW_ETL_JOB_STORY for the last completed step.', 'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        sp_etl_job_fail('WIC', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_WIC_Pty_Rle_Alt_Id failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id;
/

