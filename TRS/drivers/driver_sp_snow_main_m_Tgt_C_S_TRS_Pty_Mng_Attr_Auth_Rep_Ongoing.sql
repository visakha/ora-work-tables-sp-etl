-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- IDQ mapping: m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Driver name and signature are EXACTLY as the current main procedure,
-- so every existing CALL still works. Install schema is TRS_ETL_WRK in
-- database MDM_ETL_TRS; all table names below are unqualified, except
-- the config table, which is COMMON-qualified (COMMON.ETL_RUN_CONFIG_TBL).
--
-- BUSINESS FLOW (read this top to bottom -- it IS the business flow)
    Step  5  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
                                  previous run (drops only, no
                                  checkpoint), then rebuild from step 10
    Step  10  PAYEE_CASE_ROWS        WRK_TRS_MNGAR_S10_PAYEE
    Step  20  VALID_SRC              WRK_TRS_MNGAR_S20_SRC
    Step  30  KEYED                  WRK_TRS_MNGAR_S30_KEYED
    Step  40  AGG_DEDUP              WRK_TRS_MNGAR_S40_AGG
    Step  50  PUBLISH_C_S_TRS_PTY_MNG_ATTR C_S_TRS_PTY_MNG_ATTR (Authorised representative flags)
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
--   WRK_TRS_MNGAR_S10_PAYEE, WRK_TRS_MNGAR_S20_SRC, WRK_TRS_MNGAR_S30_KEYED, WRK_TRS_MNGAR_S40_AGG. They live in the same schema as the targets (unqualified
--   names, as in the original code) and are prefixed WRK_TRS_. They
--   survive a session crash (TRANSIENT, not TEMP), which is what makes
--   inspection after a run possible. No cursor was used: every step
--   here is set-based by design.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently; condensed
-- from the current main header -- see the manifest for the full text)
----   (kept deliberately, do not "fix" silently)
--     * IDQ deletes ONLY its own attribute type from C_S_TRS_PTY_MNG_ATTR
--       before loading (pre-SQL: DELETE ... WHERE MNG_ATTR_TP =
--       '$ATTR_TP_AUTH_REP').  THE SNOWFLAKE ORIGINAL DOES NOT DO THIS:
--       it contains no DELETE at all, and this rewrite preserves that --
--       it only skips keys already present in the target (VERSION_SEQ = 1)
--       and keeps one row per key in this run.  Consequence, stated
--       plainly: a re-run inserts nothing twice, but a stale
--       Auth_Rep_Flag row that IDQ would have deleted and reloaded is
--       left in place by this version.  If IDQ parity is required, the
--       delete must be added as an explicit publish sub-step inside the
--       step-50 transaction (see the User Guide, "Parity gaps") -- it has
--       NOT been invented here.
--     * Insert-only otherwise, as in the original Snowflake code: no
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
CREATE OR REPLACE FUNCTION sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing (P_ATTR_TP_AUTH_REP IN VARCHAR2 DEFAULT 'Auth_Rep_Flag', P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TRS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing';
    l_run_ts TIMESTAMP DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP);
    l_job_run_id VARCHAR2(4000);
    l_rows NUMBER DEFAULT 0;
    l_summary VARCHAR2(4000) DEFAULT '';
-- Config flags (STEP_NO 0 = driver row, then steps, then branches)
    l_flag_TRS_AUTHREP_DRIVER     VARCHAR DEFAULT 'Y'
    l_flag_TRS_AUTHREP_S10_PAYEE VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_AUTHREP_S20_SRC VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_AUTHREP_S30_KEYED VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_AUTHREP_S40_AGG VARCHAR2(4000) DEFAULT 'Y';
    l_flag_TRS_AUTHREP_C_S_TRS_PTY_MNG_ATTR VARCHAR2(4000) DEFAULT 'Y';
-- Config consumed strings (work-table inputs, per STEP_NO)
    l_in_TRS_AUTHREP_S10_PAYEE VARCHAR DEFAULT ''
    l_in_TRS_AUTHREP_S20_SRC VARCHAR2(4000) DEFAULT 'WRK_TRS_MNGAR_S10_PAYEE';
    l_in_TRS_AUTHREP_S30_KEYED VARCHAR2(4000) DEFAULT 'WRK_TRS_MNGAR_S20_SRC';
    l_in_TRS_AUTHREP_S40_AGG VARCHAR2(4000) DEFAULT 'WRK_TRS_MNGAR_S30_KEYED';
    l_in_TRS_AUTHREP_C_S_TRS_PTY_MNG_ATTR VARCHAR2(4000) DEFAULT 'WRK_TRS_MNGAR_S40_AGG';
-- Per-branch publish counts (one variable per branch)
    l_pub_TRS_AUTHREP_C_S_TRS_PTY_MNG_ATTR NUMBER DEFAULT 0
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
               COALESCE(MAX(CASE WHEN STEP_NO = 20 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_MNGAR_S10_PAYEE'),
               COALESCE(MAX(CASE WHEN STEP_NO = 30 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_MNGAR_S20_SRC'),
               COALESCE(MAX(CASE WHEN STEP_NO = 40 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_MNGAR_S30_KEYED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 50 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_TRS_MNGAR_S40_AGG')
          INTO l_flag_TRS_AUTHREP_DRIVER, l_flag_TRS_AUTHREP_S10_PAYEE, l_flag_TRS_AUTHREP_S20_SRC, l_flag_TRS_AUTHREP_S30_KEYED, l_flag_TRS_AUTHREP_S40_AGG, l_flag_TRS_AUTHREP_C_S_TRS_PTY_MNG_ATTR,
               l_in_TRS_AUTHREP_S10_PAYEE, l_in_TRS_AUTHREP_S20_SRC, l_in_TRS_AUTHREP_S30_KEYED, l_in_TRS_AUTHREP_S40_AGG, l_in_TRS_AUTHREP_C_S_TRS_PTY_MNG_ATTR
          FROM COMMON.ETL_RUN_CONFIG_TBL
         WHERE WORKFLOW_NAME = c_workflow
           AND MAPPING_NAME = c_mapping;
    WHEN OTHERS THEN
            -- Defaults stand: re-assert them explicitly.
            l_flag_TRS_AUTHREP_DRIVER := 'Y'; l_flag_TRS_AUTHREP_S10_PAYEE := 'Y'; l_flag_TRS_AUTHREP_S20_SRC := 'Y'; l_flag_TRS_AUTHREP_S30_KEYED := 'Y'; l_flag_TRS_AUTHREP_S40_AGG := 'Y'; l_flag_TRS_AUTHREP_C_S_TRS_PTY_MNG_ATTR := 'Y';
            l_in_TRS_AUTHREP_S10_PAYEE := ''; l_in_TRS_AUTHREP_S20_SRC := 'WRK_TRS_MNGAR_S10_PAYEE'; l_in_TRS_AUTHREP_S30_KEYED := 'WRK_TRS_MNGAR_S20_SRC'; l_in_TRS_AUTHREP_S40_AGG := 'WRK_TRS_MNGAR_S30_KEYED'; l_in_TRS_AUTHREP_C_S_TRS_PTY_MNG_ATTR := 'WRK_TRS_MNGAR_S40_AGG';
    END;

    -- ---- Driver-row disable: skip the whole mapping BEFORE step 5 cleanup
    IF (l_flag_TRS_AUTHREP_DRIVER = 'N') THEN
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'MAPPING_SKIPPED', 'SKIPPED', NULL, 'Mapping skipped by ETL_RUN_CONFIG_TBL (STEP_NO = 0, IS_RUN_ENABLED = N).', NULL);
        l_summary := 'm_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
        sp_etl_job_finish('TRS', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing skipped by config. JOB_RUN_ID = ' || l_job_run_id);
        RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
    END IF;

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Drops only, no checkpoint call for drops. UNCHANGED from current main.
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_MNGAR_S10_PAYEE';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_MNGAR_S20_SRC';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_MNGAR_S30_KEYED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_MNGAR_S40_AGG';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;

    -- ---- Step 10: PAYEE_CASE_ROWS
    IF (l_flag_TRS_AUTHREP_S10_PAYEE = 'Y') THEN
        l_rows := sp_snow_step_TRS_AUTHREP_S10_PAYEE(l_job_run_id, l_run_ts, l_in_TRS_AUTHREP_S10_PAYEE);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 10 PAYEE_CASE_ROWS', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PAYEE_CASE_ROWS', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 10 PAYEE_CASE_ROWS: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 20: VALID_SRC
    IF (l_flag_TRS_AUTHREP_S20_SRC = 'Y') THEN
        l_rows := sp_snow_step_TRS_AUTHREP_S20_SRC(l_job_run_id, l_run_ts, l_in_TRS_AUTHREP_S20_SRC);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 20 VALID_SRC', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'VALID_SRC', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 20 VALID_SRC: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 30: KEYED
    IF (l_flag_TRS_AUTHREP_S30_KEYED = 'Y') THEN
        l_rows := sp_snow_step_TRS_AUTHREP_S30_KEYED(P_ATTR_TP_AUTH_REP, l_job_run_id, l_run_ts, l_in_TRS_AUTHREP_S30_KEYED);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 30 KEYED', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'KEYED', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 30 KEYED: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 40: AGG_DEDUP
    IF (l_flag_TRS_AUTHREP_S40_AGG = 'Y') THEN
        l_rows := sp_snow_step_TRS_AUTHREP_S40_AGG(l_job_run_id, l_run_ts, l_in_TRS_AUTHREP_S40_AGG);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 40 AGG_DEDUP', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'AGG_DEDUP', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 40 AGG_DEDUP: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- PUBLISH: ONE transaction, all enabled branches, in order ----
    -- This is the ONLY step that writes to final targets. Branch procs
    -- contain no checkpoint calls and no transaction control; the
    -- driver checkpoints each branch AFTER COMMIT below.
    -- (Snowflake BEGIN TRANSACTION removed: Oracle transactions are implicit)
    IF (l_flag_TRS_AUTHREP_C_S_TRS_PTY_MNG_ATTR = 'Y') THEN
        l_pub_TRS_AUTHREP_C_S_TRS_PTY_MNG_ATTR := sp_snow_pub_TRS_AUTHREP_C_S_TRS_PTY_MNG_ATTR(P_ATTR_TP_AUTH_REP, l_job_run_id, l_run_ts, l_in_TRS_AUTHREP_C_S_TRS_PTY_MNG_ATTR);
    END IF;
    COMMIT;

    -- ---- Publish checkpoints AFTER COMMIT (one per branch) ----
    IF (l_flag_TRS_AUTHREP_C_S_TRS_PTY_MNG_ATTR = 'Y') THEN
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_TRS_PTY_MNG_ATTR', 'COMPLETED', 'C_S_TRS_PTY_MNG_ATTR', 'Published Authorised representative flags to C_S_TRS_PTY_MNG_ATTR.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 50 PUBLISH_C_S_TRS_PTY_MNG_ATTR', l_pub_TRS_AUTHREP_C_S_TRS_PTY_MNG_ATTR) || CHR(10);
    ELSE
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_TRS_PTY_MNG_ATTR', 'SKIPPED', 'C_S_TRS_PTY_MNG_ATTR', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 50 PUBLISH_C_S_TRS_PTY_MNG_ATTR: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- TERMINATING ------------------------------------------------------
    sp_etl_job_finish('TRS', l_job_run_id, c_workflow, c_mapping,
        'm_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing completed. JOB_RUN_ID = ' || l_job_run_id);
    RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
WHEN OTHERS THEN
        ROLLBACK;
        sp_etl_checkpoint('TRS', l_job_run_id, c_workflow, c_mapping, 'TERMINATING',
            'JOB_END', 'FAILED', NULL, 'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. ' || 'See ALL_TABLES for WRK_% tables in this schema and VW_ETL_JOB_STORY for the last completed step.', 'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        sp_etl_job_fail('TRS', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing;
/

