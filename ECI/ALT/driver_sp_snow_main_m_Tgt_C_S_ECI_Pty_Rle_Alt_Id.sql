-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id  --  CONFIG-DRIVEN STEP DRIVER
-- (ECI ONLY, example for user feedback)
--
-- IDQ mapping: m_Tgt_C_S_ECI_Pty_Rle_Alt_Id, workflow wf_ECI_Stage_Load.
-- Install schema is ECI_ETL_WRK in database MDM_ETL_ECI; all table
-- names below are unqualified. This driver has EXACTLY the name and
-- signature of the current main procedure (one appended parameter,
-- P_JOB_RUN_ID; the original mapping took no parameters).
--
-- WHAT THIS MAPPING DOES, IN PLAIN WORDS
--   Loads alternate ids of the ECI parties into the role alternate-id
--   table: child ECI id (018), child SSN (004, only when valid),
--   Medicaid number (002, only when valid, via the case table) and
--   family ECI id (019). Invalid SSNs and Medicaid ids are not loaded,
--   only logged. The id written is the SOURCE value; the standardised
--   SSN / Medicaid id is only used for validation.
--
-- BUSINESS FLOW (read this top to bottom -- it IS the business flow)
--   Step  5  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                  previous run (drops only, no
--                                  checkpoint), then rebuild from step 10
--   Step 10  SRC_ALT_IDS           four alternate-id branches
--                                  (018, 004, 002, 019)
--   Step 20  ACTIVE_ALT_IDS        ids whose party is not
--                                  deactivated
--   Step 30  VALIDATED_ROUTED      SSN / Medicaid validation and
--                                  router groups (valid, SSN
--                                  exception, Medicaid exception)
--   Step 40  READY_TO_PUBLISH      publish-ready rows with
--                                  insert-only guards
--   Step 50  PUBLISH -- SPINE      valid alternate ids ->
--                                  C_S_ECI_PTY_RLE_ALT_ID
--   Step 60  PUBLISH -- NON-SPINE  invalid SSN ->
--                                  EXC_STG_BAD_REC_MEMB (RUN_DATE
--                                  unlinked, NULL)
--   Step 70  PUBLISH -- NON-SPINE  invalid Medicaid id ->
--                                  EXC_STG_BAD_REC_MEMB
--   End    TERMINATING             work tables are NOT dropped: they
--                                  stay in the database until the next
--                                  run of this mapping cleans them up
--   The SPINE branch (step 50) is the mapping's hub load. The two
--   NON-SPINE branches (steps 60, 70) only log exceptions; they never
--   write a hub table. The three publish branches run inside ONE
--   transaction, so a publish either lands completely or not at all.
--
-- WORK TABLES (all TRANSIENT, same names as the current main)
--   WRK_ECI_ALT_S10_SRC, WRK_ECI_ALT_S20_ACTIVE,
--   WRK_ECI_ALT_S30_ROUTED, WRK_ECI_ALT_S40_READY. They live in the
--   same schema as the targets (unqualified names, as in the original
--   code) and are prefixed WRK_ECI_. They survive a session crash
--   (TRANSIENT, not TEMP). No CURSOR was used: every step here is
--   set-based by design.
--
-- CONFIG-DRIVEN NOTES (ETL_RUN_CONFIG_TBL, schema COMMON, qualified)
--   Before step 5, the driver GATHERs one row-set from
--   COMMON.ETL_RUN_CONFIG_TBL for this workflow + mapping: one
--   IS_RUN_ENABLED flag per STEP_NO (0, 10, 20, 30, 40, 50, 60, 70)
--   and one WORK_TABLES_CONSUMED string per executable STEP_NO (10,
--   20, 30, 40, 50, 60, 70). Flags default to 'Y' and consumed strings
--   to this mapping's work-table chain when the config row is absent
--   or the table is unreadable (the GATHER runs in a nested
--   BEGIN/EXCEPTION block, so on exception the pre-initialised
--   defaults stand and the run proceeds; a note line is added to the
--   summary in that case).
--   * STEP_NO 0 = the driver row. If it is 'N', the driver writes a
--     SKIPPED checkpoint, finishes, and RETURNS before step 5: no
--     work table is cleaned and no step runs.
--   * Any other flag 'N' skips just that step / publish branch: a
--     SKIPPED checkpoint row is written (same STEP_NAME as
--     the step) and a plain-text 'SKIPPED by config' summary line is
--     appended. helper36 is NOT used for skips (it renders NULL as
--     '0 row(s)').
--   * Skipping is per-step, NOT cascading: if an upstream step is
--     skipped, a downstream step that still runs will fail on its
--     missing input (its existence check raises), which is
--     fail-closed. Do not skip step 10 while leaving step 20 enabled
--     unless that failure is what you want.
--   * P_INPUT_TABLES is a dependency declaration + runtime check,
--     NOT dynamic SQL: Snowflake cannot parameterise table names in
--     static SQL, so each step proc still names its sources
--     literally. A config override of WORK_TABLES_CONSUMED therefore
--     changes what is CHECKED, not what is READ.
--   * SKIPPED vocabulary: JOB_CONTROL_ETL.STEP_STATUS has NO CHECK
--     constraint (a DDL comment that in v2 lists STARTED | COMPLETED | FAILED | SKIPPED), so 'SKIPPED' rows are used here. This is a choice to
--     confirm with the user, not a constraint change.
--
-- TRANSACTION EDGES (framework rule, do not move these)
--   Steps run outside any explicit transaction and checkpoint
--   immediately (autocommit), so a step checkpoint survives a later
--   rollback. The publish block is the ONLY explicit transaction:
--   BEGIN TRANSACTION -> branch calls -> COMMIT -> THEN, only after
--   COMMIT, one checkpoint per executed branch plus SKIPPED rows for
--   skipped branches. NEVER call a checkpoint between BEGIN
--   TRANSACTION and COMMIT: it would roll back with the transaction.
--   Publish-branch procs contain no transaction control and no
--   checkpoint calls of their own.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently; adapted
-- from the current main procedure)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets. Keys already present are skipped (uq_alt_id
--     guard).
--   * The SSN exception row has no RUN_DATE linked (NULL) and writes
--     the exception code returned by the exception lookup (NULL when
--     Invalid_SSN is not configured); the Medicaid exception row
--     writes the computed code; preserved. Because the SSN row's
--     RUN_DATE is NULL, its key repeats from run to run: in Oracle the
--     unique constraint rejects the row of every later run, so an
--     invalid SSN is logged only once, ever. That is reproduced here
--     (key already in the table -> skipped, via the uq_ssn_exc guard).
--   * VERSION_SEQ is 1; PERIOD_START_DATE is source DATE_CREATED;
--     preserved.
--   * Business SQL is preserved, only re-housed: each step proc holds
--     the current step's CTAS verbatim and each publish-branch proc
--     holds one current publish INSERT verbatim. No business
--     expression, filter, guard or column list was changed.
--
-- COMPILE-TIME VERIFICATION ITEMS (no live Snowflake here)
--   * Procedure-call return capture uses the Snowflake Scripting
--     scalar-call form `l_rows := (CALL proc(...));` -- verify it
--     compiles against a live Snowflake before first use.
--   * The config GATHER uses a multi-column SELECT ... INTO and a
--     nested BEGIN/EXCEPTION block -- verify both compile.
--   * The step existence check uses the EXECUTE IMMEDIATE fallback
--     (see the step headers): Snowflake's RAISE takes only an
--     exception name, so a dynamic message naming the missing table
--     is not possible via RAISE.
--
-- SIGNATURE (identical to the current main procedure)
--   The original procedure took no parameters, so there are no original
--   parameters to preserve. One parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run
--                                             (a run id is generated and
--                                             returned in the summary).
--   A restart is simply a new run: the mapping cleans up the
--   previous run's work tables at its start (step 5) and runs
--   every step from scratch. There is no step-level restart.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_ECI_Pty_Rle_Alt_Id';
    l_run_ts TIMESTAMP DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP);
    l_job_run_id VARCHAR2(4000);
    l_rows NUMBER DEFAULT 0;
    l_pub_ECI_ALT_C_S_ECI_PTY_RLE_ALT_ID NUMBER DEFAULT 0;
    l_pub_ECI_ALT_EXC_STG_BAD_REC_MEMB_SSN NUMBER DEFAULT 0;
    l_pub_ECI_ALT_EXC_STG_BAD_REC_MEMB_MEDICAID NUMBER DEFAULT 0;
    l_summary VARCHAR2(4000) DEFAULT '';
    l_config_note VARCHAR2(4000) DEFAULT '';
-- Config flags, pre-initialised to 'Y' (run). Overwritten by GATHER.
    l_flag_ECI_ALT_DRIVER     VARCHAR DEFAULT 'Y'
    l_flag_ECI_ALT_S10_SRC VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_ALT_S20_ACTIVE VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_ALT_S30_ROUTED VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_ALT_S40_READY VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_ALT_C_S_ECI_PTY_RLE_ALT_ID VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_ALT_EXC_STG_BAD_REC_MEMB_SSN VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_ALT_EXC_STG_BAD_REC_MEMB_MEDICAID VARCHAR2(4000) DEFAULT 'Y';
-- Config consumed strings, pre-initialised to the defaults below.
    -- Overwritten by GATHER. Step 10 reads base source tables only,
    -- so its default is empty and its existence check is skipped.
    l_in_ECI_ALT_S10_SRC    VARCHAR DEFAULT ''
    l_in_ECI_ALT_S20_ACTIVE VARCHAR2(4000) DEFAULT 'WRK_ECI_ALT_S10_SRC';
    l_in_ECI_ALT_S30_ROUTED VARCHAR2(4000) DEFAULT 'WRK_ECI_ALT_S20_ACTIVE';
    l_in_ECI_ALT_S40_READY VARCHAR2(4000) DEFAULT 'WRK_ECI_ALT_S30_ROUTED';
    l_in_ECI_ALT_C_S_ECI_PTY_RLE_ALT_ID VARCHAR2(4000) DEFAULT 'WRK_ECI_ALT_S40_READY';
    l_in_ECI_ALT_EXC_STG_BAD_REC_MEMB_SSN VARCHAR2(4000) DEFAULT 'WRK_ECI_ALT_S40_READY';
    l_in_ECI_ALT_EXC_STG_BAD_REC_MEMB_MEDICAID VARCHAR2(4000) DEFAULT 'WRK_ECI_ALT_S40_READY';
BEGIN
    -- ---- STARTING -------------------------------------------------------
    -- Job-run-id generation EXACTLY as in the current main procedure.
    IF (l_job_run_id IS NULL OR l_job_run_id = '') THEN
        l_job_run_id := COALESCE(NULLIF(P_JOB_RUN_ID, ''),
            'ECI_' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDD_HH24MISS')
            || '_' || RAWTOHEX(SYS_GUID()));
    END IF;
    sp_etl_job_begin('ECI', c_workflow, c_mapping, l_job_run_id);

    -- ---- GATHER config --------------------------------------------------
    -- One SELECT for all flags + consumed strings. MAX over zero rows
    -- is NULL, so COALESCE yields the pre-initialised defaults when a
    -- config row is absent. On any error (e.g. table missing) the
    -- nested handler leaves the defaults standing and records a note.
    BEGIN
        SELECT
            COALESCE(MAX(CASE WHEN STEP_NO = 0 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
            COALESCE(MAX(CASE WHEN STEP_NO = 10 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
            COALESCE(MAX(CASE WHEN STEP_NO = 20 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
            COALESCE(MAX(CASE WHEN STEP_NO = 30 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
            COALESCE(MAX(CASE WHEN STEP_NO = 40 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
            COALESCE(MAX(CASE WHEN STEP_NO = 50 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
            COALESCE(MAX(CASE WHEN STEP_NO = 60 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
            COALESCE(MAX(CASE WHEN STEP_NO = 70 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
            COALESCE(MAX(CASE WHEN STEP_NO = 10 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), ''),
            COALESCE(MAX(CASE WHEN STEP_NO = 20 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_ALT_S10_SRC'),
            COALESCE(MAX(CASE WHEN STEP_NO = 30 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_ALT_S20_ACTIVE'),
            COALESCE(MAX(CASE WHEN STEP_NO = 40 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_ALT_S30_ROUTED'),
            COALESCE(MAX(CASE WHEN STEP_NO = 50 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_ALT_S40_READY'),
            COALESCE(MAX(CASE WHEN STEP_NO = 60 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_ALT_S40_READY'),
            COALESCE(MAX(CASE WHEN STEP_NO = 70 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_ALT_S40_READY')
          INTO l_flag_ECI_ALT_DRIVER, l_flag_ECI_ALT_S10_SRC, l_flag_ECI_ALT_S20_ACTIVE, l_flag_ECI_ALT_S30_ROUTED, l_flag_ECI_ALT_S40_READY, l_flag_ECI_ALT_C_S_ECI_PTY_RLE_ALT_ID,
               l_flag_ECI_ALT_EXC_STG_BAD_REC_MEMB_SSN, l_flag_ECI_ALT_EXC_STG_BAD_REC_MEMB_MEDICAID, l_in_ECI_ALT_S10_SRC, l_in_ECI_ALT_S20_ACTIVE, l_in_ECI_ALT_S30_ROUTED, l_in_ECI_ALT_S40_READY,
               l_in_ECI_ALT_C_S_ECI_PTY_RLE_ALT_ID, l_in_ECI_ALT_EXC_STG_BAD_REC_MEMB_SSN, l_in_ECI_ALT_EXC_STG_BAD_REC_MEMB_MEDICAID
          FROM COMMON.ETL_RUN_CONFIG_TBL
         WHERE WORKFLOW_NAME = c_workflow AND MAPPING_NAME = c_mapping;
    WHEN OTHERS THEN
            l_config_note := 'ETL_RUN_CONFIG_TBL unreadable or missing; defaults used '
                || '(all steps enabled, default work-table inputs).';
    END;
    IF (l_config_note <> '') THEN
        l_summary := l_summary || 'Config note: ' || l_config_note || CHR(10);
    END IF;

    -- ---- Driver-row gate (STEP_NO 0) -- BEFORE step 5 cleanup -----------
    IF (l_flag_ECI_ALT_DRIVER = 'N') THEN
        sp_etl_checkpoint('ECI',
            l_job_run_id,
            c_workflow,
            c_mapping,
            'WORKING',
            'MAPPING_SKIPPED',
            'SKIPPED',
            NULL,
            'Mapping skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N for STEP_NO 0). '
            || 'No work tables were cleaned and no step ran.',
            NULL);
        sp_etl_job_finish('ECI', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_ECI_Pty_Rle_Alt_Id skipped by config (IS_RUN_ENABLED = N for STEP_NO 0). '
            || 'JOB_RUN_ID = ' || l_job_run_id);
        RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary
            || 'm_Tgt_C_S_ECI_Pty_Rle_Alt_Id SKIPPED by config (IS_RUN_ENABLED = N for STEP_NO 0).' || CHR(10);
    END IF;

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Drops only, no checkpoint call for drops. UNCHANGED from current main.
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_ALT_S10_SRC';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_ALT_S20_ACTIVE';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_ALT_S30_ROUTED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_ALT_S40_READY';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;

    -- ---- Step 10: ALTERNATE-ID BRANCHES ----------------------------------
    IF (l_flag_ECI_ALT_S10_SRC = 'Y') THEN
        l_rows := sp_snow_step_ECI_ALT_S10_SRC(l_job_run_id, l_run_ts, l_in_ECI_ALT_S10_SRC);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 10 SRC_ALT_IDS', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI',
            l_job_run_id,
            c_workflow,
            c_mapping,
            'WORKING',
            'SRC_ALT_IDS',
            'SKIPPED',
            NULL,
            'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)',
            NULL);
        l_summary := l_summary || 'step 10 SRC_ALT_IDS: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 20: ACTIVE PARTIES ONLY ------------------------------------
    IF (l_flag_ECI_ALT_S20_ACTIVE = 'Y') THEN
        l_rows := sp_snow_step_ECI_ALT_S20_ACTIVE(l_job_run_id, l_run_ts, l_in_ECI_ALT_S20_ACTIVE);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 20 ACTIVE_ALT_IDS', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI',
            l_job_run_id,
            c_workflow,
            c_mapping,
            'WORKING',
            'ACTIVE_ALT_IDS',
            'SKIPPED',
            NULL,
            'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)',
            NULL);
        l_summary := l_summary || 'step 20 ACTIVE_ALT_IDS: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 30: VALIDATION + ROUTING -----------------------------------
    IF (l_flag_ECI_ALT_S30_ROUTED = 'Y') THEN
        l_rows := sp_snow_step_ECI_ALT_S30_ROUTED(l_job_run_id, l_run_ts, l_in_ECI_ALT_S30_ROUTED);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 30 VALIDATED_ROUTED', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI',
            l_job_run_id,
            c_workflow,
            c_mapping,
            'WORKING',
            'VALIDATED_ROUTED',
            'SKIPPED',
            NULL,
            'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)',
            NULL);
        l_summary := l_summary || 'step 30 VALIDATED_ROUTED: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 40: READY -- guards -----------------------------------------
    IF (l_flag_ECI_ALT_S40_READY = 'Y') THEN
        l_rows := sp_snow_step_ECI_ALT_S40_READY(l_job_run_id, l_run_ts, l_in_ECI_ALT_S40_READY);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 40 READY_TO_PUBLISH', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI',
            l_job_run_id,
            c_workflow,
            c_mapping,
            'WORKING',
            'READY_TO_PUBLISH',
            'SKIPPED',
            NULL,
            'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)',
            NULL);
        l_summary := l_summary || 'step 40 READY_TO_PUBLISH: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Steps 50/60/70: PUBLISH -- one transaction, all branches -------
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction. Each branch proc holds one
    -- branch of the original INSERT ALL, in the same order, with the
    -- same column lists, values and WHERE conditions. No TRUNCATE,
    -- no DELETE. Branch procs contain no checkpoint calls: checkpoints
    -- are written AFTER COMMIT, below (framework rule).
    -- (Snowflake BEGIN TRANSACTION removed: Oracle transactions are implicit)
    -- 50. Valid alternate ids -> C_S_ECI_PTY_RLE_ALT_ID (SPINE)
    IF (l_flag_ECI_ALT_C_S_ECI_PTY_RLE_ALT_ID = 'Y') THEN
        l_pub_ECI_ALT_C_S_ECI_PTY_RLE_ALT_ID := sp_snow_pub_ECI_ALT_C_S_ECI_PTY_RLE_ALT_ID(l_job_run_id, l_run_ts, l_in_ECI_ALT_C_S_ECI_PTY_RLE_ALT_ID);
    END IF;
    -- 60. Invalid SSN -> EXC_STG_BAD_REC_MEMB (NON-SPINE)
    IF (l_flag_ECI_ALT_EXC_STG_BAD_REC_MEMB_SSN = 'Y') THEN
        l_pub_ECI_ALT_EXC_STG_BAD_REC_MEMB_SSN := sp_snow_pub_ECI_ALT_EXC_STG_BAD_REC_MEMB_SSN(l_job_run_id, l_run_ts, l_in_ECI_ALT_EXC_STG_BAD_REC_MEMB_SSN);
    END IF;
    -- 70. Invalid Medicaid id -> EXC_STG_BAD_REC_MEMB (NON-SPINE)
    IF (l_flag_ECI_ALT_EXC_STG_BAD_REC_MEMB_MEDICAID = 'Y') THEN
        l_pub_ECI_ALT_EXC_STG_BAD_REC_MEMB_MEDICAID := sp_snow_pub_ECI_ALT_EXC_STG_BAD_REC_MEMB_MEDICAID(l_job_run_id, l_run_ts, l_in_ECI_ALT_EXC_STG_BAD_REC_MEMB_MEDICAID);
    END IF;
    COMMIT;

    -- ---- Publish checkpoints -- AFTER COMMIT only ------------------------
    IF (l_flag_ECI_ALT_C_S_ECI_PTY_RLE_ALT_ID = 'Y') THEN
        sp_etl_checkpoint('ECI',
            l_job_run_id,
            c_workflow,
            c_mapping,
            'WORKING',
            'PUBLISH_C_S_ECI_PTY_RLE_ALT_ID',
            'COMPLETED',
            'C_S_ECI_PTY_RLE_ALT_ID',
            'Published in one transaction: valid alternate ids to C_S_ECI_PTY_RLE_ALT_ID.',
            NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 50 PUBLISH_C_S_ECI_PTY_RLE_ALT_ID', l_pub_ECI_ALT_C_S_ECI_PTY_RLE_ALT_ID) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI',
            l_job_run_id,
            c_workflow,
            c_mapping,
            'WORKING',
            'PUBLISH_C_S_ECI_PTY_RLE_ALT_ID',
            'SKIPPED',
            'C_S_ECI_PTY_RLE_ALT_ID',
            'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)',
            NULL);
        l_summary := l_summary || 'step 50 PUBLISH_C_S_ECI_PTY_RLE_ALT_ID: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_ECI_ALT_EXC_STG_BAD_REC_MEMB_SSN = 'Y') THEN
        sp_etl_checkpoint('ECI',
            l_job_run_id,
            c_workflow,
            c_mapping,
            'WORKING',
            'PUBLISH_EXC_STG_BAD_REC_MEMB_SSN',
            'COMPLETED',
            'EXC_STG_BAD_REC_MEMB',
            'Published in one transaction: invalid-SSN exception rows to EXC_STG_BAD_REC_MEMB.',
            NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 60 PUBLISH_EXC_STG_BAD_REC_MEMB_SSN', l_pub_ECI_ALT_EXC_STG_BAD_REC_MEMB_SSN) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI',
            l_job_run_id,
            c_workflow,
            c_mapping,
            'WORKING',
            'PUBLISH_EXC_STG_BAD_REC_MEMB_SSN',
            'SKIPPED',
            'EXC_STG_BAD_REC_MEMB',
            'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)',
            NULL);
        l_summary := l_summary || 'step 60 PUBLISH_EXC_STG_BAD_REC_MEMB_SSN: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_ECI_ALT_EXC_STG_BAD_REC_MEMB_MEDICAID = 'Y') THEN
        sp_etl_checkpoint('ECI',
            l_job_run_id,
            c_workflow,
            c_mapping,
            'WORKING',
            'PUBLISH_EXC_STG_BAD_REC_MEMB_MEDICAID',
            'COMPLETED',
            'EXC_STG_BAD_REC_MEMB',
            'Published in one transaction: invalid-Medicaid exception rows to EXC_STG_BAD_REC_MEMB.',
            NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 70 PUBLISH_EXC_STG_BAD_REC_MEMB_MEDICAID', l_pub_ECI_ALT_EXC_STG_BAD_REC_MEMB_MEDICAID) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI',
            l_job_run_id,
            c_workflow,
            c_mapping,
            'WORKING',
            'PUBLISH_EXC_STG_BAD_REC_MEMB_MEDICAID',
            'SKIPPED',
            'EXC_STG_BAD_REC_MEMB',
            'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)',
            NULL);
        l_summary := l_summary || 'step 70 PUBLISH_EXC_STG_BAD_REC_MEMB_MEDICAID: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- TERMINATING ------------------------------------------------------
    sp_etl_job_finish('ECI', l_job_run_id, c_workflow, c_mapping,
        'm_Tgt_C_S_ECI_Pty_Rle_Alt_Id completed. JOB_RUN_ID = ' || l_job_run_id);
    RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
WHEN OTHERS THEN
        ROLLBACK;
        sp_etl_checkpoint('ECI',
            l_job_run_id,
            c_workflow,
            c_mapping,
            'TERMINATING',
            'JOB_END',
            'FAILED',
            NULL,
            'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. '
            || 'See ALL_TABLES for WRK_% tables in this schema and VW_ETL_JOB_STORY for the last completed step.',
            'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        sp_etl_job_fail('ECI', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_ECI_Pty_Rle_Alt_Id failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id;
/

