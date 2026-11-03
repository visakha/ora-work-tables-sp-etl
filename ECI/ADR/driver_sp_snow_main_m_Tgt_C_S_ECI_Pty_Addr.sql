-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_ECI_Pty_Addr  --  CONFIG-DRIVEN STEP DRIVER REFACTOR
--
-- IDQ mapping: m_Tgt_C_S_ECI_Pty_Addr, workflow wf_ECI_Stage_Load.
-- Install schema is ECI_ETL_WRK in database MDM_ETL_ECI; all table
-- names below are unqualified, except the config table, which is
-- qualified as COMMON.ETL_RUN_CONFIG_TBL.
--
-- WHAT THIS MAPPING DOES, IN PLAIN WORDS
--   Validates the ECI child and family addresses and loads the good
--   ones into the party-role address table. Every active address is
--   also written to the address-quality table, and bad addresses are
--   logged as exceptions instead of loading.
--
-- WHAT CHANGED FROM THE CURRENT MAIN PROCEDURE
--   The current main procedure ran every step inline and published in
--   one transaction. This driver runs the SAME business SQL, re-housed:
--   each staged step is now its own procedure (ECI/ADR/steps/) and each
--   publish INSERT is now its own procedure (ECI/ADR/publish/). No
--   business expression was changed; each step's SELECT and each
--   publish INSERT is the current one, with its FROM pointed at the
--   fixed work-table names as now. The driver only decides, per
--   COMMON.ETL_RUN_CONFIG_TBL, whether each step / branch runs, calls
--   it, and records checkpoints and the summary.
--
-- DATA FLOW (read this top to bottom -- it IS the business flow,
-- in execution order; the SPINE / NON-SPINE grouping below it is a
-- classification of the publish branches, not a second execution order)
--   Step  0  DRIVER ROW (config)  STEP_NO 0 in ETL_RUN_CONFIG_TBL:
--                                 'N' skips the whole mapping (before
--                                 step 5 cleanup) with a SKIPPED row
--   Step  5  CLEANUP_PREVIOUS_RUN drop any work tables left by the
--                                 previous run (drops only, no
--                                 checkpoint), then rebuild from step 10
--   Step 10  WRK_ECI_ADR_S10_SRC      address source rows with party /
--                                     role keys and the translated
--                                     address type
--   Step 20  WRK_ECI_ADR_S20_KEYED    record keys + active addresses
--                                     only (no deactivation status)
--   Step 30  WRK_ECI_ADR_S30_VALIDATED address validation result
--                                     (pass-through stand-in) + state
--                                     lookup
--   Step 40  WRK_ECI_ADR_S40_FLAT     validation result unpacked +
--                                     match-code description
--   Step 50  WRK_ECI_ADR_S50_READY    score, issue description, held
--                                     address lines and insert-only
--                                     guards
--   Step 60  PUBLISH_DQM_ADDRESS     every active address ->
--                                     DQM_ADDRESS (NON-SPINE, first)
--   Step 70  PUBLISH_C_S_ECI_PTY_RLE_ADDR  good addresses (score 100)
--                                     -> C_S_ECI_PTY_RLE_ADDR (SPINE)
--   Step 80  PUBLISH_EXC_STG_BAD_REC_MEMB  exception addresses
--                                     (score 40) -> EXC_STG_BAD_REC_MEMB
--                                     (NON-SPINE, last)
--   End    TERMINATING           work tables are NOT removed: they
--                                stay in the database until the next
--                                run of this mapping cleans them up
--
-- PUBLISH BRANCHES, GROUPED (classification only -- execution order
-- above, 60 -> 70 -> 80, is the current file's INSERT order and is
-- preserved)
--   SPINE branches (write the hub party-role address spine):
--     Step 70  C_S_ECI_PTY_RLE_ADDR
--   NON-SPINE branches (do not write the spine):
--     Step 60  DQM_ADDRESS (address-quality table, every active address)
--     Step 80  EXC_STG_BAD_REC_MEMB (exception log, score 40 only)
--
-- CONFIG-DRIVEN NOTES
--   * One SELECT from COMMON.ETL_RUN_CONFIG_TBL (WORKFLOW_NAME =
--     wf_ECI_Stage_Load, MAPPING_NAME = m_Tgt_C_S_ECI_Pty_Addr) gathers
--     every IS_RUN_ENABLED flag and every WORK_TABLES_CONSUMED string.
--     Flags are pre-initialised to 'Y' and consumed strings to their
--     defaults, so if the config table is missing or unreadable the
--     nested BEGIN/EXCEPTION leaves the defaults standing and the run
--     proceeds exactly as the current main procedure did.
--   * A step or branch whose flag is 'N' is NOT called. Instead the
--     driver writes a SKIPPED checkpoint row (STATE 'WORKING', the
--     step's own STEP_NAME, STEP_STATUS 'SKIPPED', message
--     'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)') and a
--     plain-text summary line (helper36 is NOT used for skips: it
--     renders NULL as '0 row(s)'). Skipping a step does NOT skip later
--     steps: a later step that needs the skipped step's work table will
--     fail its own input-existence check and surface the missing table.
--   * Step procs receive the gathered WORK_TABLES_CONSUMED string as
--     P_INPUT_TABLES. That string is a dependency declaration + runtime
--     existence check only, NOT dynamic SQL: Snowflake cannot
--     parameterise table names in static SQL, so each step's CTAS still
--     names its sources literally, as in the current main procedure.
--   * 'SKIPPED' vocabulary: JOB_CONTROL_ETL.STEP_STATUS has NO CHECK
--     constraint (a DDL comment that in v2 lists STARTED | COMPLETED | FAILED | SKIPPED), so 'SKIPPED' rows are written and are flagged to the
--     user as a choice to confirm.
--
-- TRANSACTION EDGES (framework rule)
--   Never call a checkpoint between BEGIN TRANSACTION and COMMIT.
--   Step checkpoints are written by the step procs themselves, outside
--   any transaction, so they autocommit. The publish transaction
--   contains ONLY the branch-proc calls (which contain no transaction
--   control and no checkpoint calls); the driver checkpoints each
--   publish branch ONLY AFTER COMMIT, and writes SKIPPED rows for
--   skipped branches after COMMIT as well.
--
-- WORK TABLES (all TRANSIENT, same names as now)
--   WRK_ECI_ADR_S10_SRC, WRK_ECI_ADR_S20_KEYED,
--   WRK_ECI_ADR_S30_VALIDATED, WRK_ECI_ADR_S40_FLAT,
--   WRK_ECI_ADR_S50_READY. They live in the same schema as the targets
--   (unqualified names, as in the original code) and are prefixed
--   WRK_ECI_. They survive a session crash (TRANSIENT, not TEMP). No
--   row-by-row iteration was used: every step here is set-based by design.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently -- adapted
-- from the current main procedure)
--   * Insert-only, as in the current Snowflake code: no TRUNCATE, no
--     DELETE of targets. IDQ truncates C_S_ECI_PTY_RLE_ADDR; the
--     Snowflake version instead skips keys already present (uq_addr
--     guard).
--   * Score '40' means: address type not physical mail (002) and
--     mailability <= '3'; physical mail with mailability < '3' and a
--     match code starting I / N; or an address type that does not
--     translate. Comparisons are on strings, as in IDQ; preserved via
--     fn_snow_helper05_common.
--   * The address validator is the pass-through stand-in for
--     AddressDoctor: mailability and match code are NULL, so every
--     address with a known type scores '100'; preserved via
--     fn_snow_helper34_common.
--   * An exception address is not loaded, only logged, with the
--     hard-coded description 'Invalid Address per Address Doctor' and
--     type 'Bad Value' (no exception-catalogue lookup in this mapping);
--     preserved. Scores are always '40' or '100', so no row reaches
--     the router default group; preserved.
--   * Ports linked to targets but fed by nothing in IDQ are written as
--     NULL (ROWID_OBJECT, DELETED_*, CREATOR, PSTL_BRCD, RGN_CD,
--     LCTN_CRDNT_DESC, EFF_END_DT, the exception PERIOD_END_DATE, and
--     FLR_NUM: the router port Sub_buildingNumber has no input link);
--     preserved.
--   * VERSION_SEQ is 1. PERIOD_REFERENCE_TIME is the run start when
--     EFF_END_DT is set; EFF_END_DT is not linked in IDQ, so it is
--     NULL and PERIOD_REFERENCE_TIME is NULL; preserved.
--   * PERIOD_START_DATE / EFF_STRT_DT is source LAST_UPDATE_DATE;
--     preserved.
--   * DEVIATION FROM THE REFACTOR BRIEF (file wins): the brief described
--     publish step 60 as 2 INSERTs (spine, then exception) with branch
--     STEP_NOs 60 and 70. The current file in fact contains 3 INSERTs
--     in one step-60 transaction (DQM_ADDRESS first, then the spine,
--     then the exception log). All 3 are preserved as branches, in
--     file order, with STEP_NOs 60, 70 and 80. See ADR_MANIFEST.md.
--
-- SIGNATURE
--   The current main procedure's name and signature are unchanged and
--   in the same order, so every existing CALL still works. One
--   parameter was already appended in the current procedure:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run
--                                             (a run id is generated and
--                                             returned in the summary).
--   A restart is simply a new run: the mapping cleans up the
--   previous run's work tables at its start (step 5) and runs
--   every step from scratch. There is no step-level restart.
--
-- COMPILE-TIME VERIFICATION ITEMS (no live Snowflake here)
--   * Procedure-call return capture uses the Snowflake Scripting
--     scalar-call form `l_rows := (CALL proc(...));` -- verify on
--     compile in Snowflake.
--   * The nested BEGIN/EXCEPTION around the config GATHER, and the
--     RAISE EXCEPTION form in the step procs, are likewise compile
--     items (see the step procs and ADR_MANIFEST.md).
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_main_m_Tgt_C_S_ECI_Pty_Addr (P_MEMBER_HIERARCHY_CODE IN VARCHAR2 DEFAULT 'Member', P_MEMBER_HM_REL_TP_CD IN VARCHAR2 DEFAULT 'Member Addr', P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_ECI_Pty_Addr';
    l_run_ts TIMESTAMP DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP);
    l_job_run_id VARCHAR2(4000);
    l_rows NUMBER DEFAULT 0;
    l_pub_ECI_ADR_DQM_ADDRESS NUMBER DEFAULT 0;
    l_pub_ECI_ADR_C_S_ECI_PTY_RLE_ADDR NUMBER DEFAULT 0;
    l_pub_ECI_ADR_EXC_STG_BAD_REC_MEMB NUMBER DEFAULT 0;
    l_pub_ECI_ADR_DQM_ADDRESS_run NUMBER(1) DEFAULT 0;
    l_pub_ECI_ADR_C_S_ECI_PTY_RLE_ADDR_run NUMBER(1) DEFAULT 0;
    l_pub_ECI_ADR_EXC_STG_BAD_REC_MEMB_run NUMBER(1) DEFAULT 0;
    l_summary VARCHAR2(4000) DEFAULT '';
    l_config_ok NUMBER(1) DEFAULT 1;
-- Config flags, pre-initialised to 'Y' (run) -- defaults stand if
    -- the config table is missing/unreadable (see GATHER below).
    l_flag_ECI_ADR_DRIVER VARCHAR DEFAULT 'Y'
    l_flag_ECI_ADR_S10_SRC VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_ADR_S20_KEYED VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_ADR_S30_VALIDATED VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_ADR_S40_FLAT VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_ADR_S50_READY VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_ADR_DQM_ADDRESS VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_ADR_C_S_ECI_PTY_RLE_ADDR VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_ADR_EXC_STG_BAD_REC_MEMB VARCHAR2(4000) DEFAULT 'Y';
-- Config consumed strings, pre-initialised to their defaults.
    l_in_ECI_ADR_S10_SRC VARCHAR DEFAULT ''
    l_in_ECI_ADR_S20_KEYED VARCHAR2(4000) DEFAULT 'WRK_ECI_ADR_S10_SRC';
    l_in_ECI_ADR_S30_VALIDATED VARCHAR2(4000) DEFAULT 'WRK_ECI_ADR_S20_KEYED';
    l_in_ECI_ADR_S40_FLAT VARCHAR2(4000) DEFAULT 'WRK_ECI_ADR_S30_VALIDATED';
    l_in_ECI_ADR_S50_READY VARCHAR2(4000) DEFAULT 'WRK_ECI_ADR_S40_FLAT';
    l_in_ECI_ADR_DQM_ADDRESS VARCHAR2(4000) DEFAULT 'WRK_ECI_ADR_S50_READY';
    l_in_ECI_ADR_C_S_ECI_PTY_RLE_ADDR VARCHAR2(4000) DEFAULT 'WRK_ECI_ADR_S50_READY';
    l_in_ECI_ADR_EXC_STG_BAD_REC_MEMB VARCHAR2(4000) DEFAULT 'WRK_ECI_ADR_S50_READY';
BEGIN
    -- ---- STARTING -------------------------------------------------------
    -- Preserved verbatim from the current main procedure (including
    -- that l_job_run_id starts NULL, so this branch is always entered
    -- and COALESCE then picks the supplied P_JOB_RUN_ID, if any, or
    -- generates one).
    IF (l_job_run_id IS NULL OR l_job_run_id = '') THEN
        l_job_run_id := COALESCE(NULLIF(P_JOB_RUN_ID, ''),
            'ECI_' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDD_HH24MISS')
            || '_' || RAWTOHEX(SYS_GUID()));
    END IF;
    sp_etl_job_begin('ECI', c_workflow, c_mapping, l_job_run_id);

    -- ---- GATHER config (nested BEGIN/EXCEPTION: on any failure the
    -- pre-initialised defaults above stand and the run proceeds as the
    -- current main procedure did) ----------------------------------------
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
               COALESCE(MAX(CASE WHEN STEP_NO = 20 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_ADR_S10_SRC'),
               COALESCE(MAX(CASE WHEN STEP_NO = 30 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_ADR_S20_KEYED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 40 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_ADR_S30_VALIDATED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 50 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_ADR_S40_FLAT'),
               COALESCE(MAX(CASE WHEN STEP_NO = 60 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_ADR_S50_READY'),
               COALESCE(MAX(CASE WHEN STEP_NO = 70 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_ADR_S50_READY'),
               COALESCE(MAX(CASE WHEN STEP_NO = 80 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_ADR_S50_READY')
          INTO l_flag_ECI_ADR_DRIVER, l_flag_ECI_ADR_S10_SRC, l_flag_ECI_ADR_S20_KEYED, l_flag_ECI_ADR_S30_VALIDATED, l_flag_ECI_ADR_S40_FLAT, l_flag_ECI_ADR_S50_READY,
               l_flag_ECI_ADR_DQM_ADDRESS, l_flag_ECI_ADR_C_S_ECI_PTY_RLE_ADDR, l_flag_ECI_ADR_EXC_STG_BAD_REC_MEMB,
               l_in_ECI_ADR_S10_SRC, l_in_ECI_ADR_S20_KEYED, l_in_ECI_ADR_S30_VALIDATED, l_in_ECI_ADR_S40_FLAT, l_in_ECI_ADR_S50_READY,
               l_in_ECI_ADR_DQM_ADDRESS, l_in_ECI_ADR_C_S_ECI_PTY_RLE_ADDR, l_in_ECI_ADR_EXC_STG_BAD_REC_MEMB
          FROM COMMON.ETL_RUN_CONFIG_TBL
         WHERE WORKFLOW_NAME = c_workflow AND MAPPING_NAME = c_mapping;
    WHEN OTHERS THEN
            l_config_ok := 0;
    END;

    -- ---- Driver-row disable: skip the whole mapping BEFORE step 5 -----
    IF (l_flag_ECI_ADR_DRIVER = 'N') THEN
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'MAPPING_SKIPPED', 'SKIPPED', NULL,
            'Mapping skipped: ETL_RUN_CONFIG_TBL IS_RUN_ENABLED = N for STEP_NO 0 (driver row). '
            || 'No work tables cleaned and no steps run.',
            NULL);
        l_summary := 'm_Tgt_C_S_ECI_Pty_Addr: SKIPPED by config (IS_RUN_ENABLED = N for STEP_NO 0)' || CHR(10);
        sp_etl_job_finish('ECI', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_ECI_Pty_Addr skipped by config. JOB_RUN_ID = ' || l_job_run_id);
        RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
    END IF;

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Drops only, no checkpoint call for drops. UNCHANGED from current main.
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_ADR_S10_SRC';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_ADR_S20_KEYED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_ADR_S30_VALIDATED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_ADR_S40_FLAT';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_ADR_S50_READY';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;

    -- ---- Step 10: ADDRESS SOURCE ROWS ------------------------------------
    IF (l_flag_ECI_ADR_S10_SRC = 'Y') THEN
        l_rows := sp_snow_step_ECI_ADR_S10_SRC(l_job_run_id, l_run_ts, l_in_ECI_ADR_S10_SRC);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 10 SRC_ADDRESSES', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'SRC_ADDRESSES', 'SKIPPED', NULL,
            'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 10 SRC_ADDRESSES: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 20: RECORD KEYS + ACTIVE ONLY -------------------------------
    IF (l_flag_ECI_ADR_S20_KEYED = 'Y') THEN
        l_rows := sp_snow_step_ECI_ADR_S20_KEYED(l_job_run_id, l_run_ts, l_in_ECI_ADR_S20_KEYED);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 20 KEYED_ACTIVE', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'KEYED_ACTIVE', 'SKIPPED', NULL,
            'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 20 KEYED_ACTIVE: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 30: ADDRESS VALIDATION --------------------------------------
    IF (l_flag_ECI_ADR_S30_VALIDATED = 'Y') THEN
        l_rows := sp_snow_step_ECI_ADR_S30_VALIDATED(l_job_run_id, l_run_ts, l_in_ECI_ADR_S30_VALIDATED);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 30 ADDR_VALIDATION', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'ADDR_VALIDATION', 'SKIPPED', NULL,
            'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 30 ADDR_VALIDATION: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 40: UNPACK VALIDATION RESULT ---------------------------------
    IF (l_flag_ECI_ADR_S40_FLAT = 'Y') THEN
        l_rows := sp_snow_step_ECI_ADR_S40_FLAT(l_job_run_id, l_run_ts, l_in_ECI_ADR_S40_FLAT);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 40 FLAT_VALIDATION', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'FLAT_VALIDATION', 'SKIPPED', NULL,
            'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 40 FLAT_VALIDATION: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 50: SCORE + READY ----------------------------------------------
    IF (l_flag_ECI_ADR_S50_READY = 'Y') THEN
        l_rows := sp_snow_step_ECI_ADR_S50_READY(P_MEMBER_HIERARCHY_CODE, P_MEMBER_HM_REL_TP_CD, l_job_run_id, l_run_ts, l_in_ECI_ADR_S50_READY);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 50 SCORED_READY', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'SCORED_READY', 'SKIPPED', NULL,
            'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 50 SCORED_READY: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Publish: ONE transaction, branch procs only ---------------------
    -- No checkpoint calls inside this transaction (framework rule).
    -- Branches in current file order: 60 DQM_ADDRESS, 70 spine,
    -- 80 exception log. Skipped branches are NOT called.
    -- (Snowflake BEGIN TRANSACTION removed: Oracle transactions are implicit)
    IF (l_flag_ECI_ADR_DQM_ADDRESS = 'Y') THEN
        l_pub_ECI_ADR_DQM_ADDRESS := sp_snow_pub_ECI_ADR_DQM_ADDRESS(l_job_run_id, l_run_ts, l_in_ECI_ADR_DQM_ADDRESS);
        l_pub_ECI_ADR_DQM_ADDRESS_run := 1;
    END IF;
    IF (l_flag_ECI_ADR_C_S_ECI_PTY_RLE_ADDR = 'Y') THEN
        l_pub_ECI_ADR_C_S_ECI_PTY_RLE_ADDR := sp_snow_pub_ECI_ADR_C_S_ECI_PTY_RLE_ADDR(l_job_run_id, l_run_ts, l_in_ECI_ADR_C_S_ECI_PTY_RLE_ADDR);
        l_pub_ECI_ADR_C_S_ECI_PTY_RLE_ADDR_run := 1;
    END IF;
    IF (l_flag_ECI_ADR_EXC_STG_BAD_REC_MEMB = 'Y') THEN
        l_pub_ECI_ADR_EXC_STG_BAD_REC_MEMB := sp_snow_pub_ECI_ADR_EXC_STG_BAD_REC_MEMB(l_job_run_id, l_run_ts, l_in_ECI_ADR_EXC_STG_BAD_REC_MEMB);
        l_pub_ECI_ADR_EXC_STG_BAD_REC_MEMB_run := 1;
    END IF;
    COMMIT;

    -- ---- Publish checkpoints + summary: AFTER COMMIT only ---------------
    IF (l_pub_ECI_ADR_DQM_ADDRESS_run) THEN
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_DQM_ADDRESS', 'COMPLETED', 'DQM_ADDRESS',
            'Published in one transaction: address-quality rows. Count shown is rows inserted by this branch.',
            NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 60 PUBLISH_DQM_ADDRESS', l_pub_ECI_ADR_DQM_ADDRESS) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_DQM_ADDRESS', 'SKIPPED', 'DQM_ADDRESS',
            'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 60 PUBLISH_DQM_ADDRESS: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_pub_ECI_ADR_C_S_ECI_PTY_RLE_ADDR_run) THEN
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_ECI_PTY_RLE_ADDR', 'COMPLETED', 'C_S_ECI_PTY_RLE_ADDR',
            'Published in one transaction: good addresses to the spine. Count shown is rows inserted by this branch.',
            NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 70 PUBLISH_C_S_ECI_PTY_RLE_ADDR', l_pub_ECI_ADR_C_S_ECI_PTY_RLE_ADDR) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_ECI_PTY_RLE_ADDR', 'SKIPPED', 'C_S_ECI_PTY_RLE_ADDR',
            'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 70 PUBLISH_C_S_ECI_PTY_RLE_ADDR: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_pub_ECI_ADR_EXC_STG_BAD_REC_MEMB_run) THEN
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_STG_BAD_REC_MEMB', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB',
            'Published in one transaction: exception rows. Count shown is rows inserted by this branch.',
            NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 80 PUBLISH_EXC_STG_BAD_REC_MEMB', l_pub_ECI_ADR_EXC_STG_BAD_REC_MEMB) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_STG_BAD_REC_MEMB', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB',
            'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 80 PUBLISH_EXC_STG_BAD_REC_MEMB: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- TERMINATING ------------------------------------------------------
    sp_etl_job_finish('ECI', l_job_run_id, c_workflow, c_mapping,
        'm_Tgt_C_S_ECI_Pty_Addr completed. JOB_RUN_ID = ' || l_job_run_id);
    RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
WHEN OTHERS THEN
        ROLLBACK;
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'TERMINATING',
            'JOB_END', 'FAILED', NULL,
            'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. '
            || 'See ALL_TABLES for WRK_% tables in this schema and VW_ETL_JOB_STORY for the last completed step.',
            'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        sp_etl_job_fail('ECI', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_ECI_Pty_Addr failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END sp_snow_main_m_Tgt_C_S_ECI_Pty_Addr;
/

