-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr  --  CONFIG-DRIVEN DRIVER
-- (ECI ONLY -- example for user feedback; no other source)
--
-- IDQ mapping: m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr, workflow
-- wf_ECI_Stage_Load. Install schema is ECI_ETL_WRK in database
-- MDM_ETL_ECI; all table names below are unqualified, except the config
-- table, which is COMMON-qualified (COMMON.ETL_RUN_CONFIG_TBL).
--
-- WHAT THIS MAPPING DOES, IN PLAIN WORDS
--   Loads phones and e-mail addresses of the ECI parties into the
--   phone and e-mail tables. E-mail rows are validated as e-mails;
--   every other row (including a NULL type) is treated as a phone and
--   standardised. A phone with a missing area code is both loaded AND
--   logged, and a bad phone or e-mail is only logged.
--
-- BUSINESS FLOW, TOP TO BOTTOM (read this first -- it IS the flow)
--   Staged steps (each a separate procedure; each writes its own
--   checkpoint and returns its row count):
--     Step 10  SRC_PHN_EADDR      WRK_ECI_PHN_S10_SRC
--     Step 20  ACTIVE_PHN_EADDR   WRK_ECI_PHN_S20_ACTIVE
--     Step 30  DQ_CLEAN_VALIDATE  WRK_ECI_PHN_S30_DQ
--     Step 40  ROUTED_GROUPS      WRK_ECI_PHN_S40_ROUTED
--     Step 50  READY_TO_PUBLISH   WRK_ECI_PHN_S50_READY
--   Publish (one transaction; each branch a separate procedure;
--   driver checkpoints each branch only AFTER COMMIT):
--     SPINE branches (write the hub spine targets):
--       Step 60  PUBLISH_C_S_ECI_PTY_RLE_PHN    -> C_S_ECI_PTY_RLE_PHN
--       Step 80  PUBLISH_C_S_ECI_PTY_RLE_EADDR  -> C_S_ECI_PTY_RLE_EADDR
--     NON-SPINE branches (write exception rows only, never the spine):
--       Step 70  PUBLISH_EXC_STG_BAD_REC_MEMB_PHONE -> EXC_STG_BAD_REC_MEMB
--       Step 90  PUBLISH_EXC_STG_BAD_REC_MEMB_EMAIL -> EXC_STG_BAD_REC_MEMB
--   Every staged step feeds the spine indirectly: steps 10-50 build one
--   combined phone/e-mail work-table chain, and step 50 is read directly
--   by all four publish branches. A step or branch disabled by config
--   therefore starves or removes only its own output; see the
--   config-driven notes below for what a skipped step does (and does
--   not) imply for later steps.
--
-- CONFIG-DRIVEN NOTES (COMMON.ETL_RUN_CONFIG_TBL)
--   Before any cleanup, the driver GATHERs, in one SELECT, one
--   IS_RUN_ENABLED flag per STEP_NO (driver row 0, steps 10-50, publish
--   branches 60-90) and one WORK_TABLES_CONSUMED string per step/branch,
--   for this WORKFLOW_NAME + MAPPING_NAME. Flags and consumed strings
--   are pre-initialised to their defaults ('Y' for every flag; the
--   work-table defaults listed in PHN_MANIFEST.md), and the GATHER sits
--   in a nested BEGIN/EXCEPTION block: if the config table is missing
--   or unreadable, the exception is swallowed and the pre-initialised
--   defaults stand, so the mapping runs exactly as before config.
--   IS_DRIVER / IS_DEPENDENT / DEPENDENT_ON are NOT used for gating
--   here: gating is by IS_RUN_ENABLED alone, in step order.
--   * Driver row (STEP_NO = 0) = 'N': the whole mapping is skipped --
--     a SKIPPED checkpoint row (STEP_NO 0, STEP_NAME 'MAPPING_SKIPPED')
--     is written, sp_etl_job_finish is called with a skipped message,
--     and the driver RETURNs early, BEFORE step 5 cleanup. No work
--     table is dropped and no step runs.
--   * A step = 'N': that step procedure is NOT called. A SKIPPED
--     checkpoint row (same STEP_NAME as the step) is written
--     and a plain-text summary line is appended. helper36 is NOT used
--     for skips (it would render a NULL count as '0 row(s)').
--   * A publish branch = 'N': that branch procedure is NOT called
--     inside the transaction. After COMMIT it gets a SKIPPED checkpoint
--     row and a plain-text summary line, exactly like a skipped step.
--   * Skipping a step does NOT auto-skip later steps. If step 20 is
--     enabled but step 10 was skipped, step 20's input-existence check
--     fails loudly (missing WRK_ECI_PHN_S10_SRC) and the driver
--     exception handler fires. That loud failure is deliberate: a
--     config that skips a producer but enables its consumer is a
--     config error, not a silent partial load.
--   * 'SKIPPED' vocabulary: JOB_CONTROL_ETL.STEP_STATUS has NO CHECK
--     constraint (a DDL comment that in v2 lists STARTED | COMPLETED | FAILED | SKIPPED),
--     so SKIPPED rows are written as-is. This is a choice to confirm
--     with the user, not a constraint violation.
--   * Assumption to confirm at install: IS_RUN_ENABLED is read as a
--     VARCHAR 'Y'/'N' value (the task's vocabulary). If the column is
--     BOOLEAN, the flag comparisons in this driver must be adapted.
--
-- TRANSACTION EDGES (framework rule -- never call a checkpoint between
-- BEGIN TRANSACTION and COMMIT)
--   Staged steps run outside any transaction (each step's checkpoint
--   autocommits). The publish is the ONLY explicit transaction: BEGIN
--   TRANSACTION, then the enabled branch calls (skipped branches are
--   simply not called), then COMMIT, and only THEN the per-branch
--   checkpoints and summary lines. Publish-branch procedures contain
--   no transaction control and no checkpoint calls of their own.
--   The exception handler ROLLBACKs (which, after COMMIT, is a no-op
--   for the publish, and undoes nothing for the autocommitted steps)
--   and then writes the TERMINATING 999 FAILED row and calls
--   sp_etl_job_fail -- both after the rollback, so they survive it.
--
-- CLEANUP / RESTART (unchanged from the simplified v2 main)
--   Step 5 CLEANUP_PREVIOUS_RUN drops all 5 work tables (bare DROP
--   TABLE IF EXISTS, no checkpoint for drops), then every step runs
--   from scratch. There is no step-level restart. Work tables are NOT
--   dropped at the end of a run: they stay until the next run cleans
--   them up. No step-level restart, and no checkpoint is written for drops.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently -- copied
-- from the original main procedure, adapted only for branch STEP_NOs)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets. Keys already present are skipped (uq_phn /
--     uq_eaddr guards).
--   * A 'Missing_AreaCode' phone matches both phone groups, so it is
--     loaded AND logged; preserved (grp_phone_good includes it and
--     grp_phone_bad includes every non-NULL code).
--   * An e-mail whose 'Invalid_Email' code is not configured in the
--     exception catalogue is treated as valid and loaded, because the
--     router tests the looked-up code; preserved.
--   * The phone exception SRC_SYS_ID_1 is written NULL (linked to an
--     unfed port in IDQ) and its type is the literal 'Bad Value';
--     preserved. The phone is written cleaned and cut to 10 characters
--     (port precision of the rule); preserved via fn_snow_helper23_common.
--   * VERSION_SEQ is '1' on both targets; PERIOD_START_DATE is source
--     PERIOD_START_DATE; the e-mail PERIOD_REFERENCE_TIME port is not
--     fed (NULL); preserved.
--   * The area-code lookup (fn_snow_helper44_common) reads the phone
--     area-code reference table; its internal table reference is a
--     framework/install concern (see the step map), not changed here.
--   * The original single step-60 publish checkpoint (total rows across
--     all branches) is replaced by one checkpoint per branch (60/70/
--     80/90) after COMMIT, each with its own branch count. The sum of
--     the four branch counts equals the original publish total when
--     all four branches run.
--   * Step 50's checkpoint message still says "Published in step 60"
--     (verbatim from the original); in this refactor publish spans
--     branches 60-90. The wording was preserved, not silently edited.
--
-- SIGNATURE (EXACTLY as the current main procedure)
--   The original procedure took no parameters, so there are no original
--   parameters to preserve. One parameter was APPENDED:
--     P_JOB_RUN_ID   VARCHAR  DEFAULT NULL  -- NULL = start a new run
--                                             (a run id is generated and
--                                             returned in the summary).
--   Procedure-call return capture uses `l_rows := (CALL proc(...));`
--   (Snowflake Scripting scalar-call form) -- a compile-time
--   verification item, since there is no live Snowflake here.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr';
    l_run_ts TIMESTAMP DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP);
    l_job_run_id VARCHAR2(4000);
    l_rows NUMBER DEFAULT 0;
    l_pub_ECI_PHN_C_S_ECI_PTY_RLE_PHN NUMBER DEFAULT 0;
    l_pub_ECI_PHN_EXC_STG_BAD_REC_MEMB_PHONE NUMBER DEFAULT 0;
    l_pub_ECI_PHN_C_S_ECI_PTY_RLE_EADDR NUMBER DEFAULT 0;
    l_pub_ECI_PHN_EXC_STG_BAD_REC_MEMB_EMAIL NUMBER DEFAULT 0;
    l_summary VARCHAR2(4000) DEFAULT '';
    l_config_read_ok NUMBER(1) DEFAULT 1;
-- Config flags (pre-initialised to 'Y' = run, as before config).
    l_flag_ECI_PHN_DRIVER                     VARCHAR DEFAULT 'Y'
    l_flag_ECI_PHN_S10_SRC VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_PHN_S20_ACTIVE VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_PHN_S30_DQ VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_PHN_S40_ROUTED VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_PHN_S50_READY VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_PHN_C_S_ECI_PTY_RLE_PHN VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_PHN_EXC_STG_BAD_REC_MEMB_PHONE VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_PHN_C_S_ECI_PTY_RLE_EADDR VARCHAR2(4000) DEFAULT 'Y';
    l_flag_ECI_PHN_EXC_STG_BAD_REC_MEMB_EMAIL VARCHAR2(4000) DEFAULT 'Y';
-- Config consumed strings (pre-initialised to the work-table defaults).
    l_in_ECI_PHN_S10_SRC                      VARCHAR DEFAULT ''
    l_in_ECI_PHN_S20_ACTIVE VARCHAR2(4000) DEFAULT 'WRK_ECI_PHN_S10_SRC';
    l_in_ECI_PHN_S30_DQ VARCHAR2(4000) DEFAULT 'WRK_ECI_PHN_S20_ACTIVE';
    l_in_ECI_PHN_S40_ROUTED VARCHAR2(4000) DEFAULT 'WRK_ECI_PHN_S30_DQ';
    l_in_ECI_PHN_S50_READY VARCHAR2(4000) DEFAULT 'WRK_ECI_PHN_S40_ROUTED';
    l_in_ECI_PHN_C_S_ECI_PTY_RLE_PHN VARCHAR2(4000) DEFAULT 'WRK_ECI_PHN_S50_READY';
    l_in_ECI_PHN_EXC_STG_BAD_REC_MEMB_PHONE VARCHAR2(4000) DEFAULT 'WRK_ECI_PHN_S50_READY';
    l_in_ECI_PHN_C_S_ECI_PTY_RLE_EADDR VARCHAR2(4000) DEFAULT 'WRK_ECI_PHN_S50_READY';
    l_in_ECI_PHN_EXC_STG_BAD_REC_MEMB_EMAIL VARCHAR2(4000) DEFAULT 'WRK_ECI_PHN_S50_READY';
BEGIN
    -- ---- STARTING -------------------------------------------------------
    IF (l_job_run_id IS NULL OR l_job_run_id = '') THEN
        l_job_run_id := COALESCE(NULLIF(P_JOB_RUN_ID, ''),
            'ECI_' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDD_HH24MISS')
            || '_' || RAWTOHEX(SYS_GUID()));
    END IF;
    sp_etl_job_begin('ECI', c_workflow, c_mapping, l_job_run_id);

    -- ---- GATHER config (nested block: on exception, defaults stand) ----
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
               COALESCE(MAX(CASE WHEN STEP_NO = 10 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), ''),
               COALESCE(MAX(CASE WHEN STEP_NO = 20 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_PHN_S10_SRC'),
               COALESCE(MAX(CASE WHEN STEP_NO = 30 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_PHN_S20_ACTIVE'),
               COALESCE(MAX(CASE WHEN STEP_NO = 40 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_PHN_S30_DQ'),
               COALESCE(MAX(CASE WHEN STEP_NO = 50 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_PHN_S40_ROUTED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 60 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_PHN_S50_READY'),
               COALESCE(MAX(CASE WHEN STEP_NO = 70 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_PHN_S50_READY'),
               COALESCE(MAX(CASE WHEN STEP_NO = 80 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_PHN_S50_READY'),
               COALESCE(MAX(CASE WHEN STEP_NO = 90 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_ECI_PHN_S50_READY')
          INTO l_flag_ECI_PHN_DRIVER, l_flag_ECI_PHN_S10_SRC, l_flag_ECI_PHN_S20_ACTIVE, l_flag_ECI_PHN_S30_DQ, l_flag_ECI_PHN_S40_ROUTED,
               l_flag_ECI_PHN_S50_READY, l_flag_ECI_PHN_C_S_ECI_PTY_RLE_PHN, l_flag_ECI_PHN_EXC_STG_BAD_REC_MEMB_PHONE, l_flag_ECI_PHN_C_S_ECI_PTY_RLE_EADDR, l_flag_ECI_PHN_EXC_STG_BAD_REC_MEMB_EMAIL,
               l_in_ECI_PHN_S10_SRC, l_in_ECI_PHN_S20_ACTIVE, l_in_ECI_PHN_S30_DQ, l_in_ECI_PHN_S40_ROUTED, l_in_ECI_PHN_S50_READY,
               l_in_ECI_PHN_C_S_ECI_PTY_RLE_PHN, l_in_ECI_PHN_EXC_STG_BAD_REC_MEMB_PHONE, l_in_ECI_PHN_C_S_ECI_PTY_RLE_EADDR, l_in_ECI_PHN_EXC_STG_BAD_REC_MEMB_EMAIL
          FROM COMMON.ETL_RUN_CONFIG_TBL
         WHERE WORKFLOW_NAME = c_workflow
           AND MAPPING_NAME = c_mapping;
    WHEN OTHERS THEN
            l_config_read_ok := 0;
    END;

    -- ---- Driver-row gate: whole mapping skipped by config --------------
    IF (l_flag_ECI_PHN_DRIVER = 'N') THEN
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'MAPPING_SKIPPED', 'SKIPPED', NULL, 'Mapping skipped by ETL_RUN_CONFIG_TBL (STEP_NO = 0 IS_RUN_ENABLED = N). ' || 'No work tables cleaned, no steps run.', NULL);
        sp_etl_job_finish('ECI', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr skipped by config. JOB_RUN_ID = ' || l_job_run_id);
        RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
    END IF;

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Drops only, no checkpoint call for drops.
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_PHN_S10_SRC';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_PHN_S20_ACTIVE';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_PHN_S30_DQ';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_PHN_S40_ROUTED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_PHN_S50_READY';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;

    -- ---- Step 10: SRC_PHN_EADDR ------------------------------------------
    IF (l_flag_ECI_PHN_S10_SRC = 'Y') THEN
        l_rows := sp_snow_step_ECI_PHN_S10_SRC(l_job_run_id, l_run_ts, l_in_ECI_PHN_S10_SRC);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 10 SRC_PHN_EADDR', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'SRC_PHN_EADDR', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 10 SRC_PHN_EADDR: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 20: ACTIVE_PHN_EADDR ---------------------------------------
    IF (l_flag_ECI_PHN_S20_ACTIVE = 'Y') THEN
        l_rows := sp_snow_step_ECI_PHN_S20_ACTIVE(l_job_run_id, l_run_ts, l_in_ECI_PHN_S20_ACTIVE);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 20 ACTIVE_PHN_EADDR', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'ACTIVE_PHN_EADDR', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 20 ACTIVE_PHN_EADDR: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 30: DQ_CLEAN_VALIDATE --------------------------------------
    IF (l_flag_ECI_PHN_S30_DQ = 'Y') THEN
        l_rows := sp_snow_step_ECI_PHN_S30_DQ(l_job_run_id, l_run_ts, l_in_ECI_PHN_S30_DQ);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 30 DQ_CLEAN_VALIDATE', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'DQ_CLEAN_VALIDATE', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 30 DQ_CLEAN_VALIDATE: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 40: ROUTED_GROUPS ------------------------------------------
    IF (l_flag_ECI_PHN_S40_ROUTED = 'Y') THEN
        l_rows := sp_snow_step_ECI_PHN_S40_ROUTED(l_job_run_id, l_run_ts, l_in_ECI_PHN_S40_ROUTED);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 40 ROUTED_GROUPS', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'ROUTED_GROUPS', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 40 ROUTED_GROUPS: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Step 50: READY_TO_PUBLISH ---------------------------------------
    IF (l_flag_ECI_PHN_S50_READY = 'Y') THEN
        l_rows := sp_snow_step_ECI_PHN_S50_READY(l_job_run_id, l_run_ts, l_in_ECI_PHN_S50_READY);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 50 READY_TO_PUBLISH', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'READY_TO_PUBLISH', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 50 READY_TO_PUBLISH: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- Publish: ONE transaction, all enabled branches ----------------
    -- This is the ONLY step that writes to final targets, and the only
    -- step inside an explicit transaction. Skipped branches are simply
    -- not called. No checkpoint calls inside this transaction.
    -- (Snowflake BEGIN TRANSACTION removed: Oracle transactions are implicit)
    -- 60. Good phones -> C_S_ECI_PTY_RLE_PHN (SPINE)
    IF (l_flag_ECI_PHN_C_S_ECI_PTY_RLE_PHN = 'Y') THEN
        l_pub_ECI_PHN_C_S_ECI_PTY_RLE_PHN         := sp_snow_pub_ECI_PHN_C_S_ECI_PTY_RLE_PHN(l_job_run_id, l_run_ts, l_in_ECI_PHN_C_S_ECI_PTY_RLE_PHN);
    END IF;
    -- 70. Bad phones -> EXC_STG_BAD_REC_MEMB (NON-SPINE)
    IF (l_flag_ECI_PHN_EXC_STG_BAD_REC_MEMB_PHONE = 'Y') THEN
        l_pub_ECI_PHN_EXC_STG_BAD_REC_MEMB_PHONE  := sp_snow_pub_ECI_PHN_EXC_STG_BAD_REC_MEMB_PHONE(l_job_run_id, l_run_ts, l_in_ECI_PHN_EXC_STG_BAD_REC_MEMB_PHONE);
    END IF;
    -- 80. Good e-mails -> C_S_ECI_PTY_RLE_EADDR (SPINE)
    IF (l_flag_ECI_PHN_C_S_ECI_PTY_RLE_EADDR = 'Y') THEN
        l_pub_ECI_PHN_C_S_ECI_PTY_RLE_EADDR       := sp_snow_pub_ECI_PHN_C_S_ECI_PTY_RLE_EADDR(l_job_run_id, l_run_ts, l_in_ECI_PHN_C_S_ECI_PTY_RLE_EADDR);
    END IF;
    -- 90. Bad e-mails -> EXC_STG_BAD_REC_MEMB (NON-SPINE)
    IF (l_flag_ECI_PHN_EXC_STG_BAD_REC_MEMB_EMAIL = 'Y') THEN
        l_pub_ECI_PHN_EXC_STG_BAD_REC_MEMB_EMAIL  := sp_snow_pub_ECI_PHN_EXC_STG_BAD_REC_MEMB_EMAIL(l_job_run_id, l_run_ts, l_in_ECI_PHN_EXC_STG_BAD_REC_MEMB_EMAIL);
    END IF;
    COMMIT;

    -- ---- Publish checkpoints: AFTER COMMIT only -------------------------
    IF (l_flag_ECI_PHN_C_S_ECI_PTY_RLE_PHN = 'Y') THEN
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_ECI_PTY_RLE_PHN', 'COMPLETED', 'C_S_ECI_PTY_RLE_PHN', 'Published good phones to the phone spine target in one transaction with the other enabled branches.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 60 PUBLISH_C_S_ECI_PTY_RLE_PHN', l_pub_ECI_PHN_C_S_ECI_PTY_RLE_PHN) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_ECI_PTY_RLE_PHN', 'SKIPPED', 'C_S_ECI_PTY_RLE_PHN', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 60 PUBLISH_C_S_ECI_PTY_RLE_PHN: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    IF (l_flag_ECI_PHN_EXC_STG_BAD_REC_MEMB_PHONE = 'Y') THEN
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_STG_BAD_REC_MEMB_PHONE', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published bad-phone exceptions (non-spine) in one transaction with the other enabled branches.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 70 PUBLISH_EXC_STG_BAD_REC_MEMB_PHONE', l_pub_ECI_PHN_EXC_STG_BAD_REC_MEMB_PHONE) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_STG_BAD_REC_MEMB_PHONE', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 70 PUBLISH_EXC_STG_BAD_REC_MEMB_PHONE: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    IF (l_flag_ECI_PHN_C_S_ECI_PTY_RLE_EADDR = 'Y') THEN
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_ECI_PTY_RLE_EADDR', 'COMPLETED', 'C_S_ECI_PTY_RLE_EADDR', 'Published good e-mails to the e-mail spine target in one transaction with the other enabled branches.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 80 PUBLISH_C_S_ECI_PTY_RLE_EADDR', l_pub_ECI_PHN_C_S_ECI_PTY_RLE_EADDR) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_ECI_PTY_RLE_EADDR', 'SKIPPED', 'C_S_ECI_PTY_RLE_EADDR', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 80 PUBLISH_C_S_ECI_PTY_RLE_EADDR: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    IF (l_flag_ECI_PHN_EXC_STG_BAD_REC_MEMB_EMAIL = 'Y') THEN
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_STG_BAD_REC_MEMB_EMAIL', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published bad-e-mail exceptions (non-spine) in one transaction with the other enabled branches.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 90 PUBLISH_EXC_STG_BAD_REC_MEMB_EMAIL', l_pub_ECI_PHN_EXC_STG_BAD_REC_MEMB_EMAIL) || CHR(10);
    ELSE
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_STG_BAD_REC_MEMB_EMAIL', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 90 PUBLISH_EXC_STG_BAD_REC_MEMB_EMAIL: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- TERMINATING ------------------------------------------------------
    sp_etl_job_finish('ECI', l_job_run_id, c_workflow, c_mapping,
        'm_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr completed. JOB_RUN_ID = ' || l_job_run_id);
    RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
WHEN OTHERS THEN
        ROLLBACK;
        sp_etl_checkpoint('ECI', l_job_run_id, c_workflow, c_mapping, 'TERMINATING',
            'JOB_END', 'FAILED', NULL, 'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. ' || 'See ALL_TABLES for WRK_% tables in this schema and VW_ETL_JOB_STORY for the last completed step.', 'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        sp_etl_job_fail('ECI', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr;
/

