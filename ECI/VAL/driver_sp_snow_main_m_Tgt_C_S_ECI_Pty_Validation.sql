-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_ECI_Pty_Validation  --  CONFIG-DRIVEN STEP DRIVER
-- REFACTOR (ECI ONLY, example for user feedback). Name and signature
-- are EXACTLY the current main's, so installing this file replaces the
-- current main procedure; the steps and publish branches below it are
-- new procedures that this driver calls.
--
-- IDQ mapping: m_Tgt_C_S_ECI_Pty_Validation, workflow wf_ECI_Stage_Load
-- (first step of the workflow). Install schema is ECI_ETL_WRK in
-- database MDM_ETL_ECI; all table names below are unqualified, except
-- the config table, which is qualified as COMMON.ETL_RUN_CONFIG_TBL.
--
-- WHAT THIS MAPPING DOES, IN PLAIN WORDS
--   Checks every ECI child and family party of the delta and maintains
--   the deactivation list that every later ECI mapping uses as a filter:
--   parties whose standardised first or last name is blank are written
--   to the exception table and to the deactivation log; parties that
--   are blank-named, duplicate cases, or from an inactive family are
--   deactivated (log row, plus a status row only when the party has no
--   status yet); parties that already have a status, have names
--   present, are not duplicates and are from an active family are
--   reactivated (log row). A row goes to every group whose condition is
--   true, so blank-name rows are also deactivation rows.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow)
--   Step 5   CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                  previous run (drops only, no
--                                  checkpoint), then rebuild from step 10
--   Step 10  WRK_ECI_VAL_S10_SRC      child + family delta rows, party
--                                     key and 10-character full name
--                                     (FEEDS-STATUS, upstream)
--   Step 20  WRK_ECI_VAL_S20_ENRICHED status / hub / duplicate / family
--                                     lookups + standardised names
--                                     (FEEDS-STATUS, upstream)
--   Step 30  WRK_ECI_VAL_S30_ROUTED   exception groups (blank name,
--                                     deactivation, reactivation) with
--                                     exception descriptions and the
--                                     first-row-per-exception-key flag
--                                     (FEEDS-STATUS, direct: sole source
--                                     of every publish branch)
--   Step 40  PUBLISH_EXC_STG_BAD_REC_MEMB  blank-name exceptions
--                                     (NON-SPINE branch)
--   Step 50  PUBLISH_STG_ECI_PTY_INACTIVE_LOG_DEACTIVATION
--                                     deactivation log rows
--                                     (STATUS branch -- spine/status path)
--   Step 60  PUBLISH_STG_ECI_PTY_INACTIVE_STS
--                                     new deactivation status rows only
--                                     (STATUS branch -- spine/status path)
--   Step 70  PUBLISH_STG_ECI_PTY_INACTIVE_LOG_REACTIVATION
--                                     reactivation log rows
--                                     (STATUS branch -- spine/status path)
--   End    TERMINATING           work tables are NOT dropped: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- KIND NOTE -- WHAT "SPINE/STATUS" MEANS FOR THIS MAPPING
--   For THIS mapping the spine/status outcome IS the LOG/STS tables:
--   STG_ECI_PTY_INACTIVE_LOG and STG_ECI_PTY_INACTIVE_STS are the
--   deactivation state itself -- the list every later ECI mapping
--   filters on -- so branches 50/60/70 are marked STATUS (the
--   spine/status path, the writes the user cares about). EXC_STG_BAD_REC_MEMB
--   (branch 40) is the NON-SPINE branch: it logs blank-name
--   exceptions and carries no deactivation state. There is no separate
--   hub/spine target table in this mapping.
--
-- CONFIG-DRIVEN EXECUTION (COMMON.ETL_RUN_CONFIG_TBL)
--   Before step 5, the driver reads one config row per STEP_NO for this
--   workflow + mapping (STEP_NO 0 = the driver row, 10/20/30 = steps,
--   40/50/60/70 = publish branches) and gathers:
--     * IS_RUN_ENABLED per STEP_NO -> a run flag, default 'Y';
--     * WORK_TABLES_CONSUMED per STEP_NO -> the P_INPUT_TABLES string
--       passed to that step/branch, defaulted per step/branch (see the
--       manifest; step 10's default is empty: it reads base tables).
--   A missing or unreadable config table does NOT fail the run: the
--   GATHER block swallows the error and the pre-initialised defaults
--   stand, so the mapping runs fully. (An aggregate SELECT with no
--   GROUP BY always returns one row, so an empty config table also
--   yields defaults, not an error.)
--   If the driver row (STEP_NO 0) is 'N', the driver writes a SKIPPED
--   checkpoint, finishes, and returns BEFORE step 5 cleanup -- no work
--   table is dropped and no step runs. If a step/branch flag is 'N',
--   that step/branch is not called: a SKIPPED checkpoint row is
--   written instead and the summary records the skip in plain text
--   (helper36 is NOT used for skips -- it renders NULL as '0 row(s)').
--   Skipping an upstream step while a downstream step stays enabled
--   fails at the downstream step's input-existence check, by design:
--   the config cannot silently run a step over a missing input.
--   IS_DRIVER, IS_DEPENDENT, DEPENDENT_ON and WORK_TABLES_PRODUCED
--   are NOT consumed by this driver: step order is the fixed order
--   below, and produced tables are the step procs' own checkpoints.
--
-- SKIPPED VOCABULARY NOTE (choice to confirm)
--   JOB_CONTROL_ETL.STEP_STATUS has NO CHECK constraint -- only a DDL
--   comment listing STARTED | COMPLETED | FAILED -- so 'SKIPPED' rows
--   are written for config-skipped steps/branches and for a
--   config-skipped mapping. Flagged to the user as a choice to confirm:
--   either keep 'SKIPPED' as a fourth STEP_STATUS value, or add it to
--   the DDL comment / a constraint.
--
-- TRANSACTION EDGES (framework rule)
--   Step checkpoints autocommit (the step procs run outside any
--   explicit transaction). The publish transaction is the ONLY explicit
--   transaction: BEGIN TRANSACTION, the enabled branch calls, COMMIT --
--   and NO checkpoint call sits between BEGIN TRANSACTION and COMMIT,
--   because a checkpoint written inside it would roll back with the
--   publish. Branch checkpoints and summary lines are written only
--   AFTER COMMIT, one per executed branch (plus SKIPPED rows for
--   skipped branches). The single old step-40 'PUBLISH' checkpoint
--   (combined count) is replaced by these four branch checkpoints.
--   On any error the driver exception handler rolls back (which also
--   undoes any uncommitted publish inserts) and then writes the
--   TERMINATING 999 FAILED checkpoint + job-fail row outside the
--   rolled-back transaction.
--
-- WORK TABLES (all TRANSIENT, same names as now)
--   WRK_ECI_VAL_S10_SRC, WRK_ECI_VAL_S20_ENRICHED,
--   WRK_ECI_VAL_S30_ROUTED. They live in the same schema as the targets
--   (unqualified names, as in the original code) and are prefixed
--   WRK_ECI_. They survive a session crash (TRANSIENT, not TEMP), which
--   is what makes inspection after a run possible. No CURSOR was used:
--   every step here is set-based by design.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets. The IDQ delete of STG_ECI_PTY_INACTIVE_STS
--     (Upd_Delete_Inactive) is NOT performed, exactly as in the
--     original. That means reactivation here writes a log row only;
--     it does not delete the status row.
--   * The full name passed to name standardisation is cut at 10
--     characters (the IDQ port is declared string(10)); preserved.
--   * No prefix / suffix is passed to name standardisation, so their
--     lookups cannot match; preserved.
--   * The exception row takes its description and type from
--     EXC_LOOKUP_CODE_VALUE (NULL when the code is not configured);
--     preserved. A second row with the same exception key in this run
--     is not written (uq_exc_name flag).
--   * The hub cross-reference lookup trims ROWID_SYSTEM to 'ECI'
--     (the MDM column is blank-padded); preserved.
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
--
-- COMPILE-TIME VERIFICATION ITEMS (no live Snowflake here)
--   * Procedure-call return capture uses the Snowflake Scripting
--     scalar-call form `l_rows := (CALL proc(...));` -- confirm at
--     first compile.
--   * Step procs use `RAISE EXCEPTION '...' || :l_missing;` for the
--     input-existence check -- confirm at first compile; the fallback
--     is EXECUTE IMMEDIATE 'SELECT 1 FROM <missing table>' to surface
--     the native object-not-exists error.
--   * IS_RUN_ENABLED is assumed VARCHAR 'Y'/'N'; WORK_TABLES_CONSUMED
--     is assumed a pipe-delimited VARCHAR. If the config table types
--     differ, the GATHER SELECT needs adjusting (defaults still stand
--     on error, so a type mismatch degrades to a full run, not a fail).
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_main_m_Tgt_C_S_ECI_Pty_Validation (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_ECI_Pty_Validation';
    l_run_ts TIMESTAMP DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP);
    l_job_run_id VARCHAR2(4000);
    l_rows NUMBER DEFAULT 0;
    l_pub_ECI_VAL_EXC_STG_BAD_REC_MEMB NUMBER DEFAULT 0;
    l_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_DEACTIVATION NUMBER DEFAULT 0;
    l_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_STS NUMBER DEFAULT 0;
    l_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_REACTIVATION NUMBER DEFAULT 0;
    l_summary VARCHAR2(4000) DEFAULT '';
    l_config_ok VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_VAL_DRIVER VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_VAL_S10_SRC VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_VAL_S20_ENRICHED VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_VAL_S30_ROUTED VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_VAL_EXC_STG_BAD_REC_MEMB VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_DEACTIVATION VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_VAL_STG_ECI_PTY_INACTIVE_STS VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_REACTIVATION VARCHAR2(4000) DEFAULT 'Y';
    l_in_ECI_VAL_S10_SRC VARCHAR2(4000) DEFAULT '';
    l_in_ECI_VAL_S20_ENRICHED VARCHAR2(4000) DEFAULT 'WRK_ECI_VAL_S10_SRC';
    l_in_ECI_VAL_S30_ROUTED VARCHAR2(4000) DEFAULT 'WRK_ECI_VAL_S20_ENRICHED';
    l_in_ECI_VAL_EXC_STG_BAD_REC_MEMB VARCHAR2(4000) DEFAULT 'WRK_ECI_VAL_S30_ROUTED';
    l_in_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_DEACTIVATION VARCHAR2(4000) DEFAULT 'WRK_ECI_VAL_S30_ROUTED';
    l_in_ECI_VAL_STG_ECI_PTY_INACTIVE_STS VARCHAR2(4000) DEFAULT 'WRK_ECI_VAL_S30_ROUTED';
    l_in_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_REACTIVATION VARCHAR2(4000) DEFAULT 'WRK_ECI_VAL_S30_ROUTED';
BEGIN
    -- ---- STARTING -------------------------------------------------------
    -- Job-run-id generation exactly as now (l_job_run_id starts NULL,
    -- so the branch below always takes the supplied id or generates one).
    IF (l_job_run_id IS NULL OR l_job_run_id = '') THEN
        l_job_run_id := COALESCE(NULLIF(P_JOB_RUN_ID, ''),
            'ECI_' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDD_HH24MISS')
            || '_' || RAWTOHEX(SYS_GUID()));
    END IF;
    sp_etl_job_begin(c_source, c_workflow, c_mapping, l_job_run_id);

    -- ---- GATHER config --------------------------------------------------
    -- Flags pre-initialised to 'Y', consumed strings to their defaults.
    -- On any error (missing/unreadable config table) the defaults stand.
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
            COALESCE(MAX(CASE WHEN STEP_NO = 20 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_VAL_S10_SRC'),
            COALESCE(MAX(CASE WHEN STEP_NO = 30 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_VAL_S20_ENRICHED'),
            COALESCE(MAX(CASE WHEN STEP_NO = 40 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_VAL_S30_ROUTED'),
            COALESCE(MAX(CASE WHEN STEP_NO = 50 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_VAL_S30_ROUTED'),
            COALESCE(MAX(CASE WHEN STEP_NO = 60 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_VAL_S30_ROUTED'),
            COALESCE(MAX(CASE WHEN STEP_NO = 70 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_VAL_S30_ROUTED')
          INTO l_flag_ECI_VAL_DRIVER, l_flag_ECI_VAL_S10_SRC, l_flag_ECI_VAL_S20_ENRICHED, l_flag_ECI_VAL_S30_ROUTED,
               l_flag_ECI_VAL_EXC_STG_BAD_REC_MEMB, l_flag_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_DEACTIVATION, l_flag_ECI_VAL_STG_ECI_PTY_INACTIVE_STS, l_flag_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_REACTIVATION,
               l_in_ECI_VAL_S10_SRC, l_in_ECI_VAL_S20_ENRICHED, l_in_ECI_VAL_S30_ROUTED,
               l_in_ECI_VAL_EXC_STG_BAD_REC_MEMB, l_in_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_DEACTIVATION, l_in_ECI_VAL_STG_ECI_PTY_INACTIVE_STS, l_in_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_REACTIVATION
          FROM COMMON.ETL_RUN_CONFIG_TBL
         WHERE WORKFLOW_NAME = c_workflow AND MAPPING_NAME = c_mapping;
    WHEN OTHERS THEN
            l_config_ok := 'N';
    END;

    -- ---- Driver-row disable: skip the whole mapping BEFORE step 5 ------
    IF (l_flag_ECI_VAL_DRIVER = 'N') THEN
        sp_etl_checkpoint(c_source, l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'MAPPING_SKIPPED', 'SKIPPED', NULL,
            'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N for STEP_NO 0). ' || 'No work tables were cleaned and no step ran.', NULL);
        sp_etl_job_finish(c_source, l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_ECI_Pty_Validation skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N for STEP_NO 0). JOB_RUN_ID = ' || l_job_run_id);
        l_summary := 'MAPPING_SKIPPED by config (IS_RUN_ENABLED = N for STEP_NO 0)' || CHR(10);
        RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
    END IF;

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Drops only, no checkpoint call for drops.
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_VAL_S10_SRC';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_VAL_S20_ENRICHED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_VAL_S30_ROUTED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;

    -- ---- Step 10: CHILD + FAMILY DELTA ROWS ------------------------------
    IF (l_flag_ECI_VAL_S10_SRC = 'Y') THEN
        l_rows := sp_snow_step_ECI_VAL_S10_SRC(l_job_run_id, l_run_ts, l_in_ECI_VAL_S10_SRC);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 10 SRC_DELTA_PARTIES', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint(c_source, l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'SRC_DELTA_PARTIES', 'SKIPPED', NULL,
            'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 10 SRC_DELTA_PARTIES: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 20: LOOKUPS + NAME STANDARDISATION ------------------------
    IF (l_flag_ECI_VAL_S20_ENRICHED = 'Y') THEN
        l_rows := sp_snow_step_ECI_VAL_S20_ENRICHED(l_job_run_id, l_run_ts, l_in_ECI_VAL_S20_ENRICHED);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 20 ENRICHED_STD_NAMES', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint(c_source, l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'ENRICHED_STD_NAMES', 'SKIPPED', NULL,
            'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 20 ENRICHED_STD_NAMES: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 30: ROUTING -- exception / deactivation / reactivation ----
    IF (l_flag_ECI_VAL_S30_ROUTED = 'Y') THEN
        l_rows := sp_snow_step_ECI_VAL_S30_ROUTED(l_job_run_id, l_run_ts, l_in_ECI_VAL_S30_ROUTED);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 30 ROUTED_GROUPS', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint(c_source, l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'ROUTED_GROUPS', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB, STG_ECI_PTY_INACTIVE_LOG, STG_ECI_PTY_INACTIVE_STS',
            'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 30 ROUTED_GROUPS: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- PUBLISH -- one transaction, all enabled branches ---------------
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction. The four branch INSERTs are
    -- the four branches of the original INSERT ALL, in the same order.
    -- No checkpoint call sits between BEGIN TRANSACTION and COMMIT.
    -- No TRUNCATE, no DELETE: the IDQ delete of the inactive-status
    -- table is not performed, as in the original.
    -- (Snowflake BEGIN TRANSACTION removed: Oracle transactions are implicit)
    IF (l_flag_ECI_VAL_EXC_STG_BAD_REC_MEMB = 'Y') THEN
        l_pub_ECI_VAL_EXC_STG_BAD_REC_MEMB := sp_snow_pub_ECI_VAL_EXC_STG_BAD_REC_MEMB(l_job_run_id, l_run_ts, l_in_ECI_VAL_EXC_STG_BAD_REC_MEMB);
    END IF;
    IF (l_flag_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_DEACTIVATION = 'Y') THEN
        l_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_DEACTIVATION := sp_snow_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_DEACTIVATION(l_job_run_id, l_run_ts, l_in_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_DEACTIVATION);
    END IF;
    IF (l_flag_ECI_VAL_STG_ECI_PTY_INACTIVE_STS = 'Y') THEN
        l_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_STS := sp_snow_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_STS(l_job_run_id, l_run_ts, l_in_ECI_VAL_STG_ECI_PTY_INACTIVE_STS);
    END IF;
    IF (l_flag_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_REACTIVATION = 'Y') THEN
        l_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_REACTIVATION := sp_snow_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_REACTIVATION(l_job_run_id, l_run_ts, l_in_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_REACTIVATION);
    END IF;
    COMMIT;

    -- ---- Publish checkpoints + summary -- AFTER COMMIT only ------------
    IF (l_flag_ECI_VAL_EXC_STG_BAD_REC_MEMB = 'Y') THEN
        sp_etl_checkpoint(c_source, l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_STG_BAD_REC_MEMB', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB',
            'Published blank-name exceptions to EXC_STG_BAD_REC_MEMB (non-spine branch).', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 40 PUBLISH_EXC_STG_BAD_REC_MEMB', l_pub_ECI_VAL_EXC_STG_BAD_REC_MEMB) || CHR(10);
    ELSE
        sp_etl_checkpoint(c_source, l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_STG_BAD_REC_MEMB', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB',
            'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 40 PUBLISH_EXC_STG_BAD_REC_MEMB: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_DEACTIVATION = 'Y') THEN
        sp_etl_checkpoint(c_source, l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_STG_ECI_PTY_INACTIVE_LOG_DEACTIVATION', 'COMPLETED', 'STG_ECI_PTY_INACTIVE_LOG',
            'Published deactivation log rows to STG_ECI_PTY_INACTIVE_LOG (STATUS branch).', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 50 PUBLISH_STG_ECI_PTY_INACTIVE_LOG_DEACTIVATION', l_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_DEACTIVATION) || CHR(10);
    ELSE
        sp_etl_checkpoint(c_source, l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_STG_ECI_PTY_INACTIVE_LOG_DEACTIVATION', 'SKIPPED', 'STG_ECI_PTY_INACTIVE_LOG',
            'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 50 PUBLISH_STG_ECI_PTY_INACTIVE_LOG_DEACTIVATION: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_ECI_VAL_STG_ECI_PTY_INACTIVE_STS = 'Y') THEN
        sp_etl_checkpoint(c_source, l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_STG_ECI_PTY_INACTIVE_STS', 'COMPLETED', 'STG_ECI_PTY_INACTIVE_STS',
            'Published new deactivation status rows to STG_ECI_PTY_INACTIVE_STS (STATUS branch).', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 60 PUBLISH_STG_ECI_PTY_INACTIVE_STS', l_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_STS) || CHR(10);
    ELSE
        sp_etl_checkpoint(c_source, l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_STG_ECI_PTY_INACTIVE_STS', 'SKIPPED', 'STG_ECI_PTY_INACTIVE_STS',
            'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 60 PUBLISH_STG_ECI_PTY_INACTIVE_STS: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_REACTIVATION = 'Y') THEN
        sp_etl_checkpoint(c_source, l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_STG_ECI_PTY_INACTIVE_LOG_REACTIVATION', 'COMPLETED', 'STG_ECI_PTY_INACTIVE_LOG',
            'Published reactivation log rows to STG_ECI_PTY_INACTIVE_LOG (STATUS branch).', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 70 PUBLISH_STG_ECI_PTY_INACTIVE_LOG_REACTIVATION', l_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_REACTIVATION) || CHR(10);
    ELSE
        sp_etl_checkpoint(c_source, l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_STG_ECI_PTY_INACTIVE_LOG_REACTIVATION', 'SKIPPED', 'STG_ECI_PTY_INACTIVE_LOG',
            'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 70 PUBLISH_STG_ECI_PTY_INACTIVE_LOG_REACTIVATION: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- TERMINATING ------------------------------------------------------
    sp_etl_job_finish(c_source, l_job_run_id, c_workflow, c_mapping,
        'm_Tgt_C_S_ECI_Pty_Validation completed. JOB_RUN_ID = ' || l_job_run_id);
    RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
WHEN OTHERS THEN
        ROLLBACK;
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'TERMINATING',
            'JOB_END', 'FAILED', NULL,
            'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. ' || 'See ALL_TABLES for WRK_% tables in this schema and VW_ETL_JOB_STORY for the last completed step.', 'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        sp_etl_job_fail('ECI', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_ECI_Pty_Validation failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END sp_snow_main_m_Tgt_C_S_ECI_Pty_Validation;
/

