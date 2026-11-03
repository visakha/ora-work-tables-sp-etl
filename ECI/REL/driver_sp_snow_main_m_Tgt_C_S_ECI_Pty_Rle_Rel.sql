-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel  --  CONFIG-DRIVEN STEP DRIVER
-- REFACTOR (ECI ONLY, example for user feedback; no other source)
--
-- IDQ mapping: m_Tgt_C_S_ECI_Pty_Rle_Rel, workflow wf_ECI_Stage_Load.
-- Install schema is ECI_ETL_WRK in database MDM_ETL_ECI; all table
-- names below are unqualified, except the config table, which is
-- COMMON-qualified (COMMON.ETL_RUN_CONFIG_TBL).
-- Name and signature are EXACTLY as the current main: one appended
-- parameter, P_JOB_RUN_ID VARCHAR DEFAULT NULL (the original procedure
-- took no parameters).
--
-- WHAT THIS MAPPING DOES, IN PLAIN WORDS
--   Loads family-to-child relationships into the relationship table.
--   Every family row is read twice: once as family-to-child (code =
--   family code) and once as child-to-family (code = family code plus
--   the child's gender). A relationship whose code translates in the
--   code-value table loads; one whose code does not translate is only
--   logged as an exception.
--
-- BUSINESS FLOW (read this top to bottom -- it IS the business flow)
--   Step 10  WRK_ECI_REL_S10_SRC      family rows doubled (one row per
--                                     direction)
--   Step 20  WRK_ECI_REL_S20_KEYED    child / family party keys +
--                                     both parties must be active
--   Step 30  WRK_ECI_REL_S30_TYPED    relationship code built (child
--                                     gender for the reverse direction)
--                                     and translated
--   Step 40  WRK_ECI_REL_S40_READY    relationship keys, exception
--                                     details and insert-only guards
--   Start  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                previous run (step 5, drops only, no
--                                checkpoint), then rebuild from step 10
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- PUBLISH BRANCHES (one transaction; branches in original order)
--   SPINE branches (write the relationship spine):
--     Step 50  C_S_ECI_PTY_RLE_REL    valid relationships
--                                     (mstr_ref_code IS NOT NULL AND uq_rel)
--   NON-SPINE branches (write exception / log tables, never the spine):
--     Step 60  EXC_STG_BAD_REC_MEMB   relationship exceptions
--                                     (mstr_ref_code IS NULL AND uq_rel_exc)
--   The current main numbers its whole publish step 50 with one
--   checkpoint and a combined row total. This driver numbers the
--   branches 50 and 60 so each branch has its own checkpoint row and
--   its own count; there is no combined-total publish checkpoint any
--   more (the per-branch helper36 summary lines carry the counts).
--
-- CONFIG-DRIVEN NOTES (COMMON.ETL_RUN_CONFIG_TBL)
--   Before step 5, the driver GATHERs one row-set for this workflow +
--   mapping: IS_RUN_ENABLED per STEP_NO (driver row 0, steps 10/20/30/40,
--   publish branches 50/60) and WORK_TABLES_CONSUMED per step/branch.
--   Flags default to 'Y' and consumed strings to their defaults below,
--   so a missing/unreadable config table (or no rows for this mapping)
--   runs everything, exactly as the current main does. A flag of exactly
--   'N' skips that step/branch: a SKIPPED checkpoint row is written and
--   a plain-text summary line is appended -- helper36 is NOT used for
--   skips, because it renders NULL as '0 row(s)'. A driver-row flag
--   (STEP_NO = 0) of 'N' skips the whole mapping BEFORE step 5 cleanup
--   (MAPPING_SKIPPED checkpoint, job finish, early RETURN).
--   Only the exact value 'Y' runs a step/branch; any other flag value
--   is treated as skip for that step/branch (driver row excepted: only
--   exactly 'N' triggers the early mapping-skipped return).
--   SKIPPED VOCABULARY NOTE: JOB_CONTROL_ETL.STEP_STATUS has NO CHECK
--   constraint (a DDL comment that in v2 lists STARTED | COMPLETED | FAILED | SKIPPED),
--   so 'SKIPPED' rows are used here and are flagged to the user as a
--   choice to confirm.
--   Caveat: skipping is per-step, not chain-aware. Step 5 drops all
--   work tables, so skipping step 10 while step 20 is enabled fails at
--   step 20's input existence check (by design: it surfaces the broken
--   chain instead of silently reusing a stale table). Skipping step 40
--   while a publish branch is enabled fails natively on the branch
--   INSERT (publish branches run no existence check, per spec).
--
-- TRANSACTION EDGES (framework rule -- do not move these)
--   Steps run outside any transaction (their checkpoints autocommit, so
--   they survive a later rollback). The publish is the ONLY explicit
--   transaction: BEGIN TRANSACTION -> branch calls -> COMMIT -> branch
--   checkpoints AFTER COMMIT. Never call a checkpoint between BEGIN
--   TRANSACTION and COMMIT. The exception handler ROLLBACKs, then writes
--   its TERMINATING checkpoint and failure row (after the rollback, so
--   they are not rolled back).
--
-- HOW THIS DIFFERS FROM THE CURRENT MAIN (re-housing only)
--   The four step CTAS statements and the two publish INSERTs are
--   unchanged business SQL, moved into their own procedures; this
--   driver only orchestrates: config GATHER, step-5 cleanup, conditional
--   step calls, the publish transaction, and checkpoints. No business
--   expression, filter, guard or column list was changed.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets. Keys already present are skipped (uq_rel
--     guard).
--   * The relationship code must translate in LOOKUP_CODE_VALUE (code
--     types REL_TP / INVERSE_REL, source ECI); preserved as a direct
--     table lookup, not a helper, exactly as in the original.
--   * An untranslated relationship is not loaded, only logged. The
--     exception row writes the exception code returned by the
--     exception-catalogue lookup (NULL when 'Invalid_Relationship' is
--     not configured); preserved. Its key SRC_SYS_ID_3 ends in '|'
--     (the master code is NULL; IDQ concatenates NULL as ''); preserved.
--   * VERSION_SEQ is 1; PERIOD_START_DATE is family DATE_CREATED;
--     CREATE_DATE is DATE_MODIFIED (as IDQ links it); preserved.
--
-- COMPILE-TIME VERIFICATION ITEMS (no live Snowflake here -- verify on install)
--   * Scalar procedure-call capture `l_rows := (CALL proc(...));` is
--     the Snowflake Scripting scalar-call form per the refactor spec;
--     confirm it compiles and returns the step/branch row count.
--   * The step existence check uses `RAISE EXCEPTION '...' || :l_missing;`
--     confirm the concatenated-message form compiles; if it does not,
--     the prescribed fallback is EXECUTE IMMEDIATE
--     'SELECT 1 FROM <missing table>' to surface the native
--     object-not-exists error.
--   * If BOTH publish branches are skipped, BEGIN TRANSACTION ... COMMIT
--     encloses no statements; confirm an empty transaction is accepted.
--
-- SIGNATURE (identical to the current main)
--   The original procedure took no parameters, so there are no original
--   parameters to preserve. One parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run
--                                             (a run id is generated and
--                                             returned in the summary).
--   A restart is simply a new run: the mapping cleans up the
--   previous run's work tables at its start (step 5) and runs
--   every step from scratch. There is no step-level restart.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_ECI_Pty_Rle_Rel';
    l_run_ts TIMESTAMP DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP);
    l_job_run_id VARCHAR2(4000);
    l_rows NUMBER DEFAULT 0;
    l_pub_ECI_REL_C_S_ECI_PTY_RLE_REL_rows NUMBER;
    l_pub_ECI_REL_EXC_STG_BAD_REC_MEMB_rows NUMBER;
    l_pub_ECI_REL_C_S_ECI_PTY_RLE_REL_skipped NUMBER(1) DEFAULT 0;
    l_pub_ECI_REL_EXC_STG_BAD_REC_MEMB_skipped NUMBER(1) DEFAULT 0;
    l_summary VARCHAR2(4000) DEFAULT '';
-- Config GATHER: flags pre-initialised to 'Y', consumed strings to
    -- their defaults, so a missing/unreadable config table leaves the
    -- defaults standing (see nested BEGIN/EXCEPTION below).
    l_flag_ECI_REL_DRIVER VARCHAR DEFAULT 'Y'
    l_flag_ECI_REL_S10_SRC VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_REL_S20_KEYED VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_REL_S30_TYPED VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_REL_S40_READY VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_REL_C_S_ECI_PTY_RLE_REL VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_REL_EXC_STG_BAD_REC_MEMB VARCHAR2(4000) DEFAULT 'Y';
    l_in_ECI_REL_S10_SRC VARCHAR2(4000) DEFAULT '';
    l_in_ECI_REL_S20_KEYED VARCHAR2(4000) DEFAULT 'WRK_ECI_REL_S10_SRC';
    l_in_ECI_REL_S30_TYPED VARCHAR2(4000) DEFAULT 'WRK_ECI_REL_S20_KEYED';
    l_in_ECI_REL_S40_READY VARCHAR2(4000) DEFAULT 'WRK_ECI_REL_S30_TYPED';
    l_in_ECI_REL_C_S_ECI_PTY_RLE_REL VARCHAR2(4000) DEFAULT 'WRK_ECI_REL_S40_READY';
    l_in_ECI_REL_EXC_STG_BAD_REC_MEMB VARCHAR2(4000) DEFAULT 'WRK_ECI_REL_S40_READY';
    l_config_ok NUMBER(1) DEFAULT 1;
BEGIN
    -- ---- STARTING -------------------------------------------------------
    IF (l_job_run_id IS NULL OR l_job_run_id = '') THEN
        l_job_run_id := COALESCE(NULLIF(P_JOB_RUN_ID, ''),
            'ECI_' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDD_HH24MISS')
            || '_' || RAWTOHEX(SYS_GUID()));
    END IF;
    sp_etl_job_begin('ECI', c_workflow, c_mapping, l_job_run_id);

    -- ---- CONFIG GATHER ----------------------------------------------------
    -- One SELECT for this workflow + mapping. On any exception (e.g. a
    -- missing/unreadable config table) the pre-initialised defaults stand.
    BEGIN
        SELECT COALESCE(MAX(CASE WHEN STEP_NO = 0 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 10 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 20 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 30 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 40 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 50 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 60 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 10 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), ''),
               COALESCE(MAX(CASE WHEN STEP_NO = 20 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_REL_S10_SRC'),
               COALESCE(MAX(CASE WHEN STEP_NO = 30 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_REL_S20_KEYED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 40 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_REL_S30_TYPED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 50 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_REL_S40_READY'),
               COALESCE(MAX(CASE WHEN STEP_NO = 60 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_REL_S40_READY')
          INTO l_flag_ECI_REL_DRIVER, l_flag_ECI_REL_S10_SRC, l_flag_ECI_REL_S20_KEYED, l_flag_ECI_REL_S30_TYPED, l_flag_ECI_REL_S40_READY,
               l_flag_ECI_REL_C_S_ECI_PTY_RLE_REL, l_flag_ECI_REL_EXC_STG_BAD_REC_MEMB,
               l_in_ECI_REL_S10_SRC, l_in_ECI_REL_S20_KEYED, l_in_ECI_REL_S30_TYPED, l_in_ECI_REL_S40_READY, l_in_ECI_REL_C_S_ECI_PTY_RLE_REL, l_in_ECI_REL_EXC_STG_BAD_REC_MEMB
          FROM COMMON.ETL_RUN_CONFIG_TBL
         WHERE WORKFLOW_NAME = c_workflow AND MAPPING_NAME = c_mapping;
    WHEN OTHERS THEN
            l_config_ok := 0;
    END;

    -- ---- MAPPING SKIPPED BY CONFIG (before step 5 cleanup) ----------------
    IF (l_flag_ECI_REL_DRIVER = 'N') THEN
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'MAPPING_SKIPPED', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N for STEP_NO 0).', NULL);
        l_summary := l_summary || 'm_Tgt_C_S_ECI_Pty_Rle_Rel: SKIPPED by config (IS_RUN_ENABLED = N for STEP_NO 0)' || CHR(10);
        sp_etl_job_finish('ECI', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_ECI_Pty_Rle_Rel skipped by config. JOB_RUN_ID = ' || l_job_run_id);
        RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
    END IF;

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Drops only, no checkpoint call for drops.
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_REL_S10_SRC';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_REL_S20_KEYED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_REL_S30_TYPED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_REL_S40_READY';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;

    -- ---- Step 10: FAMILY ROWS, BOTH DIRECTIONS ----------------------------
    IF (l_flag_ECI_REL_S10_SRC = 'Y') THEN
        l_rows := sp_snow_step_ECI_REL_S10_SRC(l_job_run_id, l_run_ts, l_in_ECI_REL_S10_SRC);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 10 SRC_BOTH_DIRECTIONS', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'SRC_BOTH_DIRECTIONS', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 10 SRC_BOTH_DIRECTIONS: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 20: PARTY KEYS + BOTH PARTIES ACTIVE --------------------------
    IF (l_flag_ECI_REL_S20_KEYED = 'Y') THEN
        l_rows := sp_snow_step_ECI_REL_S20_KEYED(l_job_run_id, l_run_ts, l_in_ECI_REL_S20_KEYED);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 20 KEYED_BOTH_ACTIVE', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'KEYED_BOTH_ACTIVE', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 20 KEYED_BOTH_ACTIVE: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 30: RELATIONSHIP CODE + TRANSLATION -----------------------------
    IF (l_flag_ECI_REL_S30_TYPED = 'Y') THEN
        l_rows := sp_snow_step_ECI_REL_S30_TYPED(l_job_run_id, l_run_ts, l_in_ECI_REL_S30_TYPED);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 30 CODED_TRANSLATED', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'CODED_TRANSLATED', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 30 CODED_TRANSLATED: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 40: READY -- keys, exception details, guards ---------------------
    IF (l_flag_ECI_REL_S40_READY = 'Y') THEN
        l_rows := sp_snow_step_ECI_REL_S40_READY(l_job_run_id, l_run_ts, l_in_ECI_REL_S40_READY);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 40 READY_TO_PUBLISH', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'READY_TO_PUBLISH', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 40 READY_TO_PUBLISH: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Steps 50/60: PUBLISH -- one transaction, all executed branches ----
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction. The two branch INSERTs below
    -- are the two branches of the original INSERT ALL, in the same order,
    -- with the same column lists, values and WHERE conditions -- only
    -- re-housed into branch procedures. No TRUNCATE, no DELETE.
    -- Branch checkpoints are written AFTER COMMIT (never between
    -- BEGIN TRANSACTION and COMMIT).
    -- (Snowflake BEGIN TRANSACTION removed: Oracle transactions are implicit)
    -- 50. SPINE: valid relationships -> C_S_ECI_PTY_RLE_REL
    IF (l_flag_ECI_REL_C_S_ECI_PTY_RLE_REL = 'Y') THEN
        l_pub_ECI_REL_C_S_ECI_PTY_RLE_REL_rows := sp_snow_pub_ECI_REL_C_S_ECI_PTY_RLE_REL(l_job_run_id, l_run_ts, l_in_ECI_REL_C_S_ECI_PTY_RLE_REL);
    ELSE
        l_pub_ECI_REL_C_S_ECI_PTY_RLE_REL_skipped := 1;
    END IF;
    -- 60. NON-SPINE: relationship exceptions -> EXC_STG_BAD_REC_MEMB
    IF (l_flag_ECI_REL_EXC_STG_BAD_REC_MEMB = 'Y') THEN
        l_pub_ECI_REL_EXC_STG_BAD_REC_MEMB_rows := sp_snow_pub_ECI_REL_EXC_STG_BAD_REC_MEMB(l_job_run_id, l_run_ts, l_in_ECI_REL_EXC_STG_BAD_REC_MEMB);
    ELSE
        l_pub_ECI_REL_EXC_STG_BAD_REC_MEMB_skipped := 1;
    END IF;
    COMMIT;
    -- Branch 50 checkpoint (after COMMIT)
    IF (l_pub_ECI_REL_C_S_ECI_PTY_RLE_REL_skipped = 0) THEN
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_ECI_PTY_RLE_REL', 'COMPLETED', 'C_S_ECI_PTY_RLE_REL', 'Published valid relationships in one transaction with the executed exception branch.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 50 PUBLISH_C_S_ECI_PTY_RLE_REL', l_pub_ECI_REL_C_S_ECI_PTY_RLE_REL_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_ECI_PTY_RLE_REL', 'SKIPPED', 'C_S_ECI_PTY_RLE_REL', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 50 PUBLISH_C_S_ECI_PTY_RLE_REL: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    -- Branch 60 checkpoint (after COMMIT)
    IF (l_pub_ECI_REL_EXC_STG_BAD_REC_MEMB_skipped = 0) THEN
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_STG_BAD_REC_MEMB', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published relationship exception rows in one transaction with the executed spine branch.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 60 PUBLISH_EXC_STG_BAD_REC_MEMB', l_pub_ECI_REL_EXC_STG_BAD_REC_MEMB_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_STG_BAD_REC_MEMB', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 60 PUBLISH_EXC_STG_BAD_REC_MEMB: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- TERMINATING ------------------------------------------------------
    sp_etl_job_finish('ECI', l_job_run_id, c_workflow, c_mapping,
        'm_Tgt_C_S_ECI_Pty_Rle_Rel completed. JOB_RUN_ID = ' || l_job_run_id);
    RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
WHEN OTHERS THEN
        ROLLBACK;
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'TERMINATING',
            'JOB_END', 'FAILED', NULL, 'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. ' || 'See ALL_TABLES for WRK_% tables in this schema and VW_ETL_JOB_STORY for the last completed step.', 'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        sp_etl_job_fail('ECI', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_ECI_Pty_Rle_Rel failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel;
/

