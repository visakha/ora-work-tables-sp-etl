-- ============================================================================
-- sp_snow_main_m_Tgt_C_S_CRE_CARE_Clients  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (CRE)
--
-- IDQ mapping: m_Tgt_C_S_CRE_CARE_Clients, workflow wf_CRE_Stage_Load_Ongoing
-- (its only mapping).
-- Install schema is CRE_ETL_WRK in database MDM_ETL_CRE; all table
-- names below are unqualified, except the config table, which is
-- COMMON-qualified (COMMON.ETL_RUN_CONFIG_TBL).
-- Driver name and signature are EXACTLY as the current main procedure,
-- so every existing CALL still works.
--
-- WHAT THIS MAPPING DOES, IN PLAIN WORDS
--   Loads the CARE clients into CRE_SRC_MRG, C_S_CRE_PTY, C_S_CRE_PTY_RLE,
--   C_S_CRE_PTY_RLE_ADDR, C_S_CRE_PTY_RLE_PHN and C_S_CRE_PTY_RLE_ALT_ID
--   (insert only, never truncated) and logs exceptions: new and changed
--   clients, deleted and moved cases, move targets, merge routing, name
--   standardisation, and one row per CARE id into party, role, address,
--   phone and the three alternate ids (CARE ID, Medicaid ID, SSN).
--
-- BUSINESS FLOW (read this top to bottom -- it IS the business flow)
--   Step  5  CLEANUP_PREVIOUS_RUN  drop any work tables left by the
--                                  previous run (drops only, no
--                                  checkpoint), then rebuild from step 10
--   Step  10  SRC_MERGE_ROUTING        CARE snapshot + merge routing (src + xref + hmrg + routed)
--   Step  20  NAME_STANDARDISE_VALIDATE name standardisation + member validity (named + members)
--   Step  30  RANK_ENRICH              rank + validation enrichment (ranked + dq + dq2)
--   Step  40  FLAT_ADDR_ALTID          flattened load-ready rows (alt_tp + flat)
--   Step  50  KEYED_ROUTES_GUARDS      route flags + unique-key guards (keyed + final select)
--   ---- PUBLISH (one transaction; branches below, in order) --------
--   Step  60  PUBLISH_CRE_SRC_MRG          merge rows -> CRE_SRC_MRG
--   Step  70  PUBLISH_EXC_FIRST_NAME       invalid first name -> EXC_STG_BAD_REC_MEMB
--   Step  80  PUBLISH_EXC_LAST_NAME        invalid last name -> EXC_STG_BAD_REC_MEMB
--   Step  90  PUBLISH_C_S_CRE_PTY          valid parties -> C_S_CRE_PTY
--   Step 100  PUBLISH_C_S_CRE_PTY_RLE      valid roles -> C_S_CRE_PTY_RLE
--   Step 110  PUBLISH_EXC_GENDER           invalid gender -> EXC_STG_BAD_REC_MEMB
--   Step 120  PUBLISH_EXC_SUFFIX           invalid name suffix -> EXC_STG_BAD_REC_MEMB
--   Step 130  PUBLISH_EXC_ETHNICITY        invalid ethnicity -> EXC_STG_BAD_REC_MEMB
--   Step 140  PUBLISH_EXC_RACE             invalid race -> EXC_STG_BAD_REC_MEMB
--   Step 150  PUBLISH_C_S_CRE_PTY_RLE_ADDR valid addresses -> C_S_CRE_PTY_RLE_ADDR
--   Step 160  PUBLISH_EXC_ADDR             invalid address -> EXC_STG_BAD_REC_MEMB
--   Step 170  PUBLISH_C_S_CRE_PTY_RLE_PHN  valid phones -> C_S_CRE_PTY_RLE_PHN
--   Step 180  PUBLISH_EXC_PHONE            invalid phone -> EXC_STG_BAD_REC_MEMB
--   Step 190  PUBLISH_ALT_ID_CARE          CARE alternate ids -> C_S_CRE_PTY_RLE_ALT_ID
--   Step 200  PUBLISH_ALT_ID_MEDICAID      Medicaid alternate ids -> C_S_CRE_PTY_RLE_ALT_ID
--   Step 210  PUBLISH_EXC_MEDICAID_ALT     invalid Medicaid alternate id -> EXC_STG_BAD_REC_MEMB
--   Step 220  PUBLISH_ALT_ID_SSN           SSN alternate ids -> C_S_CRE_PTY_RLE_ALT_ID
--   Step 230  PUBLISH_EXC_SSN_ALT          invalid SSN alternate id -> EXC_STG_BAD_REC_MEMB
--   End    TERMINATING             work tables are NOT dropped: they
--                                  stay in the database until the next
--                                  run of this mapping cleans them up
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
--     summary line is appended (helper36 is NOT used for skips -- it
--     renders NULL as '0 row(s)'). No other step is auto-skipped: if a
--     downstream step stays enabled while its input step was skipped,
--     that step's input-existence check raises the missing table
--     loudly instead of running on stale data. Disable downstream
--     steps explicitly if you disable an upstream one.
--   * Config columns IS_DEPENDENT, DEPENDENT_ON and
--     WORK_TABLES_PRODUCED are present in the table but are NOT read
--     by this driver; gating is by IS_RUN_ENABLED only.
--   * SKIPPED vocabulary: JOB_CONTROL_ETL.STEP_STATUS has NO CHECK
--     constraint (a DDL comment that in v2 lists STARTED | COMPLETED | FAILED | SKIPPED), so 'SKIPPED' rows are used here and are flagged to the
--     user as a choice to confirm.
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
--   WRK_CRE_CARE_S1_SRC_MRG, WRK_CRE_CARE_S2_NAMED,
--   WRK_CRE_CARE_S3_RANKED, WRK_CRE_CARE_S4_FLAT,
--   WRK_CRE_CARE_S5_KEYED. They live in the same schema as the targets
--   (unqualified names, as in the original code) and are prefixed
--   WRK_CRE_. They survive a session crash (TRANSIENT, not TEMP),
--   which is what makes inspection after a run possible. Every step
--   here is set-based by design.
--
-- PARITY NOTES (kept deliberately, do not "fix" silently)
--   * Insert-only, as in the original Snowflake code: no TRUNCATE, no
--     DELETE of targets. IDQ truncates the targets; the Snowflake
--     version instead skips keys already present (uq_pty / uq_rle /
--     uq_addr / uq_phone / uq_care_alt / uq_medicaid_alt / uq_ssn_alt
--     guards, VERSION_SEQ = 1 in the targets). A re-run therefore
--     inserts nothing twice, but it also does not remove rows that IDQ
--     would have truncated away.
--   * Invalid members are logged and dropped; a bad address, phone or
--     alternate id is logged instead of loaded (the member itself is
--     still loaded). SSN 'U' / 'N' is blanked and dropped; CARE and
--     Medicaid ids of 'U' / 'N' are blanked for the loaded value (the
--     key still uses the raw id). Ids lose special characters (inside
--     the helpers) and are cut to 10 characters; phones are cut to 10
--     digits; SRC_ROWID is cut to 30 characters.
--   * With the pass-through address validator (no score, no match code)
--     the valid-US-address condition is NULL, so every US address is an
--     exception (the NVL(..., FALSE) in the flat step).
--   * TIMELINE: VERSION_SEQ = VERSION_SEQ_NUM (the rank per CARE id; 1
--     for every written row). 'B' and 'D' rows are end-dated:
--     PERIOD_START_DATE = CARE_LASTUP_DT - 1 day, PERIOD_END_DATE =
--     CARE_LASTUP_DT, TIMELINE_ACTION = 2, PERIOD_REFERENCE_TIME =
--     PERIOD_START_DATE, LAST_UPDATE_DATE = run start - 1 hour (the role
--     keeps the run start). The role and the alternate ids do not link
--     TIMELINE_ACTION / PERIOD_REFERENCE_TIME (written NULL).
--   * IDQ quirks kept: CRE_SRC_MRG also gets moves whose CARE ids have
--     no cross-reference (NULL records), and the move target row again
--     when it carries a MAINT_FLAG; the CARE ID alternate id of an
--     unmerged move is the target id (mrg_care_id); the state and
--     alternate-id type lookups have no code-type filter
--     (fn_snow_helper42_common / LOOKUP_CODE_VALUE by source value), so
--     an untranslated type leaves ALT_ID_TP and the exception's SRC_SYS
--     NULL; the alternate-id type pick is the first row ordered by
--     CODE_TYPE. The phone exception and the address exception rows
--     have no unique-key guard in the original, and none was added.
--     member_rle_fk hard-codes 'Member' while rle_key uses the
--     P_RLE_BO_CLASS_CD_MEMBER parameter (both are 'Member' at the
--     defaults, so they agree unless the parameter is overridden).
--   * The exception rows for a CARE id read twice (name rows) and the
--     Medicaid / SSN rows that the source and the target of an unmerged
--     move both log under the target id are de-duplicated by the
--     uq_first_name / uq_last_name / uq_medicaid_exc / uq_ssn_exc
--     guards, exactly as in the original.
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
CREATE OR REPLACE FUNCTION sp_snow_main_m_Tgt_C_S_CRE_CARE_Clients (P_PHYSICAL_ADDR_TYPE_CD IN VARCHAR2 DEFAULT '002', P_RLE_BO_CLASS_CD_MEMBER IN VARCHAR2 DEFAULT 'Member', P_DEFAULT_TX_STATE_CD IN VARCHAR2 DEFAULT '48', P_COUNTY_CD_NONTX IN VARCHAR2 DEFAULT '996', P_COUNTYCD_DEFAULTALL IN VARCHAR2 DEFAULT '998', P_DEFAULT_NONUS_STATE_CD IN VARCHAR2 DEFAULT '99', P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'CRE';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_CRE_Stage_Load_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_CRE_CARE_Clients';
    l_run_ts TIMESTAMP DEFAULT CAST(SYSTIMESTAMP AS TIMESTAMP);
    l_job_run_id VARCHAR2(4000);
    l_rows NUMBER DEFAULT 0;
    l_summary VARCHAR2(4000) DEFAULT '';
-- Config flags (STEP_NO 0 = driver row, then steps, then branches)
    l_flag_CRE_CARE_DRIVER                               VARCHAR DEFAULT 'Y'
    l_flag_CRE_CARE_S10_SRC_MRG VARCHAR2(4000) DEFAULT 'Y';
    l_flag_CRE_CARE_S20_NAMED VARCHAR2(4000) DEFAULT 'Y';
    l_flag_CRE_CARE_S30_RANKED VARCHAR2(4000) DEFAULT 'Y';
    l_flag_CRE_CARE_S40_FLAT VARCHAR2(4000) DEFAULT 'Y';
    l_flag_CRE_CARE_S50_KEYED VARCHAR2(4000) DEFAULT 'Y';
    l_flag_CRE_CARE_CRE_SRC_MRG VARCHAR2(4000) DEFAULT 'Y';
    l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_FIRST_NAME VARCHAR2(4000) DEFAULT 'Y';
    l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_LAST_NAME VARCHAR2(4000) DEFAULT 'Y';
    l_flag_CRE_CARE_C_S_CRE_PTY VARCHAR2(4000) DEFAULT 'Y';
    l_flag_CRE_CARE_C_S_CRE_PTY_RLE VARCHAR2(4000) DEFAULT 'Y';
    l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_GENDER VARCHAR2(4000) DEFAULT 'Y';
    l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_SUFFIX VARCHAR2(4000) DEFAULT 'Y';
    l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_ETHNICITY VARCHAR2(4000) DEFAULT 'Y';
    l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_RACE VARCHAR2(4000) DEFAULT 'Y';
    l_flag_CRE_CARE_C_S_CRE_PTY_RLE_ADDR VARCHAR2(4000) DEFAULT 'Y';
    l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_ADDR VARCHAR2(4000) DEFAULT 'Y';
    l_flag_CRE_CARE_C_S_CRE_PTY_RLE_PHN VARCHAR2(4000) DEFAULT 'Y';
    l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_PHONE VARCHAR2(4000) DEFAULT 'Y';
    l_flag_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_CARE VARCHAR2(4000) DEFAULT 'Y';
    l_flag_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_MEDICAID VARCHAR2(4000) DEFAULT 'Y';
    l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_MEDICAID_ALT VARCHAR2(4000) DEFAULT 'Y';
    l_flag_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_SSN VARCHAR2(4000) DEFAULT 'Y';
    l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_SSN_ALT VARCHAR2(4000) DEFAULT 'Y';
-- Config consumed strings (work-table inputs, per STEP_NO)
    l_in_CRE_CARE_S10_SRC_MRG                            VARCHAR DEFAULT ''
    l_in_CRE_CARE_S20_NAMED VARCHAR2(4000) DEFAULT 'WRK_CRE_CARE_S1_SRC_MRG';
    l_in_CRE_CARE_S30_RANKED VARCHAR2(4000) DEFAULT 'WRK_CRE_CARE_S2_NAMED';
    l_in_CRE_CARE_S40_FLAT VARCHAR2(4000) DEFAULT 'WRK_CRE_CARE_S3_RANKED';
    l_in_CRE_CARE_S50_KEYED VARCHAR2(4000) DEFAULT 'WRK_CRE_CARE_S4_FLAT';
    l_in_CRE_CARE_CRE_SRC_MRG VARCHAR2(4000) DEFAULT 'WRK_CRE_CARE_S5_KEYED';
    l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_FIRST_NAME VARCHAR2(4000) DEFAULT 'WRK_CRE_CARE_S5_KEYED';
    l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_LAST_NAME VARCHAR2(4000) DEFAULT 'WRK_CRE_CARE_S5_KEYED';
    l_in_CRE_CARE_C_S_CRE_PTY VARCHAR2(4000) DEFAULT 'WRK_CRE_CARE_S5_KEYED';
    l_in_CRE_CARE_C_S_CRE_PTY_RLE VARCHAR2(4000) DEFAULT 'WRK_CRE_CARE_S5_KEYED';
    l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_GENDER VARCHAR2(4000) DEFAULT 'WRK_CRE_CARE_S5_KEYED';
    l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_SUFFIX VARCHAR2(4000) DEFAULT 'WRK_CRE_CARE_S5_KEYED';
    l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_ETHNICITY VARCHAR2(4000) DEFAULT 'WRK_CRE_CARE_S5_KEYED';
    l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_RACE VARCHAR2(4000) DEFAULT 'WRK_CRE_CARE_S5_KEYED';
    l_in_CRE_CARE_C_S_CRE_PTY_RLE_ADDR VARCHAR2(4000) DEFAULT 'WRK_CRE_CARE_S5_KEYED';
    l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_ADDR VARCHAR2(4000) DEFAULT 'WRK_CRE_CARE_S5_KEYED';
    l_in_CRE_CARE_C_S_CRE_PTY_RLE_PHN VARCHAR2(4000) DEFAULT 'WRK_CRE_CARE_S5_KEYED';
    l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_PHONE VARCHAR2(4000) DEFAULT 'WRK_CRE_CARE_S5_KEYED';
    l_in_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_CARE VARCHAR2(4000) DEFAULT 'WRK_CRE_CARE_S5_KEYED';
    l_in_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_MEDICAID VARCHAR2(4000) DEFAULT 'WRK_CRE_CARE_S5_KEYED';
    l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_MEDICAID_ALT VARCHAR2(4000) DEFAULT 'WRK_CRE_CARE_S5_KEYED';
    l_in_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_SSN VARCHAR2(4000) DEFAULT 'WRK_CRE_CARE_S5_KEYED';
    l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_SSN_ALT VARCHAR2(4000) DEFAULT 'WRK_CRE_CARE_S5_KEYED';
-- Per-branch publish counts (one variable per branch)
    l_pub_CRE_CARE_CRE_SRC_MRG                           NUMBER DEFAULT 0
    l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_FIRST_NAME NUMBER DEFAULT 0;
    l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_LAST_NAME NUMBER DEFAULT 0;
    l_pub_CRE_CARE_C_S_CRE_PTY NUMBER DEFAULT 0;
    l_pub_CRE_CARE_C_S_CRE_PTY_RLE NUMBER DEFAULT 0;
    l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_GENDER NUMBER DEFAULT 0;
    l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_SUFFIX NUMBER DEFAULT 0;
    l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_ETHNICITY NUMBER DEFAULT 0;
    l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_RACE NUMBER DEFAULT 0;
    l_pub_CRE_CARE_C_S_CRE_PTY_RLE_ADDR NUMBER DEFAULT 0;
    l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_ADDR NUMBER DEFAULT 0;
    l_pub_CRE_CARE_C_S_CRE_PTY_RLE_PHN NUMBER DEFAULT 0;
    l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_PHONE NUMBER DEFAULT 0;
    l_pub_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_CARE NUMBER DEFAULT 0;
    l_pub_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_MEDICAID NUMBER DEFAULT 0;
    l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_MEDICAID_ALT NUMBER DEFAULT 0;
    l_pub_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_SSN NUMBER DEFAULT 0;
    l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_SSN_ALT NUMBER DEFAULT 0;
BEGIN
    -- ---- STARTING: job-run-id generation exactly as in the current main
    IF (l_job_run_id IS NULL OR l_job_run_id = '') THEN
        l_job_run_id := COALESCE(NULLIF(P_JOB_RUN_ID, ''),
            'CRE_' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDD_HH24MISS')
            || '_' || RAWTOHEX(SYS_GUID()));
    END IF;
    sp_etl_job_begin('CRE', c_workflow, c_mapping, l_job_run_id);

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
               COALESCE(MAX(CASE WHEN STEP_NO = 140 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 150 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 160 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 170 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 180 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 190 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 200 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 210 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 220 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 230 THEN IS_RUN_ENABLED END THEN 1 ELSE 0 END), 'Y'),
               COALESCE(MAX(CASE WHEN STEP_NO = 10 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), ''),
               COALESCE(MAX(CASE WHEN STEP_NO = 20 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_CRE_CARE_S1_SRC_MRG'),
               COALESCE(MAX(CASE WHEN STEP_NO = 30 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_CRE_CARE_S2_NAMED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 40 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_CRE_CARE_S3_RANKED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 50 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_CRE_CARE_S4_FLAT'),
               COALESCE(MAX(CASE WHEN STEP_NO = 60 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_CRE_CARE_S5_KEYED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 70 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_CRE_CARE_S5_KEYED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 80 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_CRE_CARE_S5_KEYED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 90 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_CRE_CARE_S5_KEYED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 100 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_CRE_CARE_S5_KEYED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 110 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_CRE_CARE_S5_KEYED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 120 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_CRE_CARE_S5_KEYED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 130 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_CRE_CARE_S5_KEYED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 140 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_CRE_CARE_S5_KEYED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 150 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_CRE_CARE_S5_KEYED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 160 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_CRE_CARE_S5_KEYED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 170 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_CRE_CARE_S5_KEYED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 180 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_CRE_CARE_S5_KEYED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 190 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_CRE_CARE_S5_KEYED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 200 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_CRE_CARE_S5_KEYED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 210 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_CRE_CARE_S5_KEYED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 220 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_CRE_CARE_S5_KEYED'),
               COALESCE(MAX(CASE WHEN STEP_NO = 230 THEN WORK_TABLES_CONSUMED END THEN 1 ELSE 0 END), 'WRK_CRE_CARE_S5_KEYED')
          INTO l_flag_CRE_CARE_DRIVER, l_flag_CRE_CARE_S10_SRC_MRG, l_flag_CRE_CARE_S20_NAMED, l_flag_CRE_CARE_S30_RANKED, l_flag_CRE_CARE_S40_FLAT, l_flag_CRE_CARE_S50_KEYED, l_flag_CRE_CARE_CRE_SRC_MRG, l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_FIRST_NAME, l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_LAST_NAME, l_flag_CRE_CARE_C_S_CRE_PTY, l_flag_CRE_CARE_C_S_CRE_PTY_RLE, l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_GENDER, l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_SUFFIX, l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_ETHNICITY, l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_RACE, l_flag_CRE_CARE_C_S_CRE_PTY_RLE_ADDR, l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_ADDR, l_flag_CRE_CARE_C_S_CRE_PTY_RLE_PHN, l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_PHONE, l_flag_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_CARE, l_flag_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_MEDICAID, l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_MEDICAID_ALT, l_flag_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_SSN, l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_SSN_ALT,
               l_in_CRE_CARE_S10_SRC_MRG, l_in_CRE_CARE_S20_NAMED, l_in_CRE_CARE_S30_RANKED, l_in_CRE_CARE_S40_FLAT, l_in_CRE_CARE_S50_KEYED, l_in_CRE_CARE_CRE_SRC_MRG, l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_FIRST_NAME, l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_LAST_NAME, l_in_CRE_CARE_C_S_CRE_PTY, l_in_CRE_CARE_C_S_CRE_PTY_RLE, l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_GENDER, l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_SUFFIX, l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_ETHNICITY, l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_RACE, l_in_CRE_CARE_C_S_CRE_PTY_RLE_ADDR, l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_ADDR, l_in_CRE_CARE_C_S_CRE_PTY_RLE_PHN, l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_PHONE, l_in_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_CARE, l_in_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_MEDICAID, l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_MEDICAID_ALT, l_in_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_SSN, l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_SSN_ALT
          FROM COMMON.ETL_RUN_CONFIG_TBL
         WHERE WORKFLOW_NAME = c_workflow
           AND MAPPING_NAME = c_mapping;
    WHEN OTHERS THEN
            -- Defaults stand: re-assert them explicitly.
            l_flag_CRE_CARE_DRIVER := 'Y'; l_flag_CRE_CARE_S10_SRC_MRG := 'Y'; l_flag_CRE_CARE_S20_NAMED := 'Y'; l_flag_CRE_CARE_S30_RANKED := 'Y'; l_flag_CRE_CARE_S40_FLAT := 'Y'; l_flag_CRE_CARE_S50_KEYED := 'Y'; l_flag_CRE_CARE_CRE_SRC_MRG := 'Y'; l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_FIRST_NAME := 'Y'; l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_LAST_NAME := 'Y'; l_flag_CRE_CARE_C_S_CRE_PTY := 'Y'; l_flag_CRE_CARE_C_S_CRE_PTY_RLE := 'Y'; l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_GENDER := 'Y'; l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_SUFFIX := 'Y'; l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_ETHNICITY := 'Y'; l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_RACE := 'Y'; l_flag_CRE_CARE_C_S_CRE_PTY_RLE_ADDR := 'Y'; l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_ADDR := 'Y'; l_flag_CRE_CARE_C_S_CRE_PTY_RLE_PHN := 'Y'; l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_PHONE := 'Y'; l_flag_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_CARE := 'Y'; l_flag_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_MEDICAID := 'Y'; l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_MEDICAID_ALT := 'Y'; l_flag_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_SSN := 'Y'; l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_SSN_ALT := 'Y';
            l_in_CRE_CARE_S10_SRC_MRG := ''; l_in_CRE_CARE_S20_NAMED := 'WRK_CRE_CARE_S1_SRC_MRG'; l_in_CRE_CARE_S30_RANKED := 'WRK_CRE_CARE_S2_NAMED'; l_in_CRE_CARE_S40_FLAT := 'WRK_CRE_CARE_S3_RANKED'; l_in_CRE_CARE_S50_KEYED := 'WRK_CRE_CARE_S4_FLAT'; l_in_CRE_CARE_CRE_SRC_MRG := 'WRK_CRE_CARE_S5_KEYED'; l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_FIRST_NAME := 'WRK_CRE_CARE_S5_KEYED'; l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_LAST_NAME := 'WRK_CRE_CARE_S5_KEYED'; l_in_CRE_CARE_C_S_CRE_PTY := 'WRK_CRE_CARE_S5_KEYED'; l_in_CRE_CARE_C_S_CRE_PTY_RLE := 'WRK_CRE_CARE_S5_KEYED'; l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_GENDER := 'WRK_CRE_CARE_S5_KEYED'; l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_SUFFIX := 'WRK_CRE_CARE_S5_KEYED'; l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_ETHNICITY := 'WRK_CRE_CARE_S5_KEYED'; l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_RACE := 'WRK_CRE_CARE_S5_KEYED'; l_in_CRE_CARE_C_S_CRE_PTY_RLE_ADDR := 'WRK_CRE_CARE_S5_KEYED'; l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_ADDR := 'WRK_CRE_CARE_S5_KEYED'; l_in_CRE_CARE_C_S_CRE_PTY_RLE_PHN := 'WRK_CRE_CARE_S5_KEYED'; l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_PHONE := 'WRK_CRE_CARE_S5_KEYED'; l_in_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_CARE := 'WRK_CRE_CARE_S5_KEYED'; l_in_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_MEDICAID := 'WRK_CRE_CARE_S5_KEYED'; l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_MEDICAID_ALT := 'WRK_CRE_CARE_S5_KEYED'; l_in_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_SSN := 'WRK_CRE_CARE_S5_KEYED'; l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_SSN_ALT := 'WRK_CRE_CARE_S5_KEYED';
    END;

    -- ---- Driver-row disable: skip the whole mapping BEFORE step 5 cleanup
    IF (l_flag_CRE_CARE_DRIVER = 'N') THEN
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'MAPPING_SKIPPED', 'SKIPPED', NULL, 'Mapping skipped by ETL_RUN_CONFIG_TBL (STEP_NO = 0, IS_RUN_ENABLED = N).', NULL);
        l_summary := 'm_Tgt_C_S_CRE_CARE_Clients SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
        sp_etl_job_finish('CRE', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_CRE_CARE_Clients skipped by config. JOB_RUN_ID = ' || l_job_run_id);
        RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
    END IF;

    -- ---- Step 5: CLEANUP_PREVIOUS_RUN -- drop work tables left by a previous run
    -- Drops only, no checkpoint call for drops. UNCHANGED from current main.
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_CRE_CARE_S1_SRC_MRG';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_CRE_CARE_S2_NAMED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_CRE_CARE_S3_RANKED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_CRE_CARE_S4_FLAT';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_CRE_CARE_S5_KEYED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;

    -- ---- Step 10: SRC_MERGE_ROUTING
    IF (l_flag_CRE_CARE_S10_SRC_MRG = 'Y') THEN
        l_rows := sp_snow_step_CRE_CARE_S10_SRC_MRG(l_job_run_id, l_run_ts, l_in_CRE_CARE_S10_SRC_MRG);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 10 SRC_MERGE_ROUTING', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'SRC_MERGE_ROUTING', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 10 SRC_MERGE_ROUTING: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    -- ---- Step 20: NAME_STANDARDISE_VALIDATE
    IF (l_flag_CRE_CARE_S20_NAMED = 'Y') THEN
        l_rows := sp_snow_step_CRE_CARE_S20_NAMED(l_job_run_id, l_run_ts, l_in_CRE_CARE_S20_NAMED);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 20 NAME_STANDARDISE_VALIDATE', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'NAME_STANDARDISE_VALIDATE', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 20 NAME_STANDARDISE_VALIDATE: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    -- ---- Step 30: RANK_ENRICH
    IF (l_flag_CRE_CARE_S30_RANKED = 'Y') THEN
        l_rows := sp_snow_step_CRE_CARE_S30_RANKED(l_job_run_id, l_run_ts, l_in_CRE_CARE_S30_RANKED);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 30 RANK_ENRICH', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'RANK_ENRICH', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 30 RANK_ENRICH: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    -- ---- Step 40: FLAT_ADDR_ALTID
    IF (l_flag_CRE_CARE_S40_FLAT = 'Y') THEN
        l_rows := sp_snow_step_CRE_CARE_S40_FLAT(P_RLE_BO_CLASS_CD_MEMBER, P_DEFAULT_NONUS_STATE_CD, l_job_run_id, l_run_ts, l_in_CRE_CARE_S40_FLAT);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 40 FLAT_ADDR_ALTID', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'FLAT_ADDR_ALTID', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 40 FLAT_ADDR_ALTID: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    -- ---- Step 50: KEYED_ROUTES_GUARDS
    IF (l_flag_CRE_CARE_S50_KEYED = 'Y') THEN
        l_rows := sp_snow_step_CRE_CARE_S50_KEYED(P_PHYSICAL_ADDR_TYPE_CD, P_RLE_BO_CLASS_CD_MEMBER, P_DEFAULT_TX_STATE_CD, P_COUNTY_CD_NONTX, P_COUNTYCD_DEFAULTALL, l_job_run_id, l_run_ts, l_in_CRE_CARE_S50_KEYED);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 50 KEYED_ROUTES_GUARDS', l_rows) || CHR(10);
    ELSE
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'KEYED_ROUTES_GUARDS', 'SKIPPED', NULL, 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 50 KEYED_ROUTES_GUARDS: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- PUBLISH: ONE transaction, all enabled branches, in order ----
    -- This is the ONLY step that writes to final targets. Branch procs
    -- contain no checkpoint calls and no transaction control; the
    -- driver checkpoints each branch AFTER COMMIT below.
    -- (Snowflake BEGIN TRANSACTION removed: Oracle transactions are implicit)
    IF (l_flag_CRE_CARE_CRE_SRC_MRG = 'Y') THEN
        l_pub_CRE_CARE_CRE_SRC_MRG := sp_snow_pub_CRE_CARE_CRE_SRC_MRG(l_job_run_id, l_run_ts, l_in_CRE_CARE_CRE_SRC_MRG);
    END IF;
    IF (l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_FIRST_NAME = 'Y') THEN
        l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_FIRST_NAME := sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_FIRST_NAME(l_job_run_id, l_run_ts, l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_FIRST_NAME);
    END IF;
    IF (l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_LAST_NAME = 'Y') THEN
        l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_LAST_NAME := sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_LAST_NAME(l_job_run_id, l_run_ts, l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_LAST_NAME);
    END IF;
    IF (l_flag_CRE_CARE_C_S_CRE_PTY = 'Y') THEN
        l_pub_CRE_CARE_C_S_CRE_PTY := sp_snow_pub_CRE_CARE_C_S_CRE_PTY(l_job_run_id, l_run_ts, l_in_CRE_CARE_C_S_CRE_PTY);
    END IF;
    IF (l_flag_CRE_CARE_C_S_CRE_PTY_RLE = 'Y') THEN
        l_pub_CRE_CARE_C_S_CRE_PTY_RLE := sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE(l_job_run_id, l_run_ts, l_in_CRE_CARE_C_S_CRE_PTY_RLE);
    END IF;
    IF (l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_GENDER = 'Y') THEN
        l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_GENDER := sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_GENDER(l_job_run_id, l_run_ts, l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_GENDER);
    END IF;
    IF (l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_SUFFIX = 'Y') THEN
        l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_SUFFIX := sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_SUFFIX(l_job_run_id, l_run_ts, l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_SUFFIX);
    END IF;
    IF (l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_ETHNICITY = 'Y') THEN
        l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_ETHNICITY := sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_ETHNICITY(l_job_run_id, l_run_ts, l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_ETHNICITY);
    END IF;
    IF (l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_RACE = 'Y') THEN
        l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_RACE := sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_RACE(l_job_run_id, l_run_ts, l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_RACE);
    END IF;
    IF (l_flag_CRE_CARE_C_S_CRE_PTY_RLE_ADDR = 'Y') THEN
        l_pub_CRE_CARE_C_S_CRE_PTY_RLE_ADDR := sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_ADDR(l_job_run_id, l_run_ts, l_in_CRE_CARE_C_S_CRE_PTY_RLE_ADDR);
    END IF;
    IF (l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_ADDR = 'Y') THEN
        l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_ADDR := sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_ADDR(l_job_run_id, l_run_ts, l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_ADDR);
    END IF;
    IF (l_flag_CRE_CARE_C_S_CRE_PTY_RLE_PHN = 'Y') THEN
        l_pub_CRE_CARE_C_S_CRE_PTY_RLE_PHN := sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_PHN(l_job_run_id, l_run_ts, l_in_CRE_CARE_C_S_CRE_PTY_RLE_PHN);
    END IF;
    IF (l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_PHONE = 'Y') THEN
        l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_PHONE := sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_PHONE(l_job_run_id, l_run_ts, l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_PHONE);
    END IF;
    IF (l_flag_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_CARE = 'Y') THEN
        l_pub_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_CARE := sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_CARE(l_job_run_id, l_run_ts, l_in_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_CARE);
    END IF;
    IF (l_flag_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_MEDICAID = 'Y') THEN
        l_pub_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_MEDICAID := sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_MEDICAID(l_job_run_id, l_run_ts, l_in_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_MEDICAID);
    END IF;
    IF (l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_MEDICAID_ALT = 'Y') THEN
        l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_MEDICAID_ALT := sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_MEDICAID_ALT(l_job_run_id, l_run_ts, l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_MEDICAID_ALT);
    END IF;
    IF (l_flag_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_SSN = 'Y') THEN
        l_pub_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_SSN := sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_SSN(l_job_run_id, l_run_ts, l_in_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_SSN);
    END IF;
    IF (l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_SSN_ALT = 'Y') THEN
        l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_SSN_ALT := sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_SSN_ALT(l_job_run_id, l_run_ts, l_in_CRE_CARE_EXC_STG_BAD_REC_MEMB_SSN_ALT);
    END IF;
    COMMIT;

    -- ---- Publish checkpoints AFTER COMMIT (one per branch) ----
    IF (l_flag_CRE_CARE_CRE_SRC_MRG = 'Y') THEN
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_CRE_SRC_MRG', 'COMPLETED', 'CRE_SRC_MRG', 'Published merge rows to CRE_SRC_MRG.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 60 PUBLISH_CRE_SRC_MRG', l_pub_CRE_CARE_CRE_SRC_MRG) || CHR(10);
    ELSE
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_CRE_SRC_MRG', 'SKIPPED', 'CRE_SRC_MRG', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 60 PUBLISH_CRE_SRC_MRG: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_FIRST_NAME = 'Y') THEN
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_FIRST_NAME', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published invalid first name to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 70 PUBLISH_EXC_FIRST_NAME', l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_FIRST_NAME) || CHR(10);
    ELSE
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_FIRST_NAME', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 70 PUBLISH_EXC_FIRST_NAME: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_LAST_NAME = 'Y') THEN
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_LAST_NAME', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published invalid last name to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 80 PUBLISH_EXC_LAST_NAME', l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_LAST_NAME) || CHR(10);
    ELSE
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_LAST_NAME', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 80 PUBLISH_EXC_LAST_NAME: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_CRE_CARE_C_S_CRE_PTY = 'Y') THEN
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_CRE_PTY', 'COMPLETED', 'C_S_CRE_PTY', 'Published valid parties to C_S_CRE_PTY.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 90 PUBLISH_C_S_CRE_PTY', l_pub_CRE_CARE_C_S_CRE_PTY) || CHR(10);
    ELSE
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_CRE_PTY', 'SKIPPED', 'C_S_CRE_PTY', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 90 PUBLISH_C_S_CRE_PTY: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_CRE_CARE_C_S_CRE_PTY_RLE = 'Y') THEN
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_CRE_PTY_RLE', 'COMPLETED', 'C_S_CRE_PTY_RLE', 'Published valid roles to C_S_CRE_PTY_RLE.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 100 PUBLISH_C_S_CRE_PTY_RLE', l_pub_CRE_CARE_C_S_CRE_PTY_RLE) || CHR(10);
    ELSE
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_CRE_PTY_RLE', 'SKIPPED', 'C_S_CRE_PTY_RLE', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 100 PUBLISH_C_S_CRE_PTY_RLE: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_GENDER = 'Y') THEN
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_GENDER', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published invalid gender to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 110 PUBLISH_EXC_GENDER', l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_GENDER) || CHR(10);
    ELSE
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_GENDER', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 110 PUBLISH_EXC_GENDER: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_SUFFIX = 'Y') THEN
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_SUFFIX', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published invalid name suffix to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 120 PUBLISH_EXC_SUFFIX', l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_SUFFIX) || CHR(10);
    ELSE
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_SUFFIX', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 120 PUBLISH_EXC_SUFFIX: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_ETHNICITY = 'Y') THEN
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_ETHNICITY', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published invalid ethnicity to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 130 PUBLISH_EXC_ETHNICITY', l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_ETHNICITY) || CHR(10);
    ELSE
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_ETHNICITY', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 130 PUBLISH_EXC_ETHNICITY: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_RACE = 'Y') THEN
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_RACE', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published invalid race to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 140 PUBLISH_EXC_RACE', l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_RACE) || CHR(10);
    ELSE
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_RACE', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 140 PUBLISH_EXC_RACE: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_CRE_CARE_C_S_CRE_PTY_RLE_ADDR = 'Y') THEN
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_CRE_PTY_RLE_ADDR', 'COMPLETED', 'C_S_CRE_PTY_RLE_ADDR', 'Published valid addresses to C_S_CRE_PTY_RLE_ADDR.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 150 PUBLISH_C_S_CRE_PTY_RLE_ADDR', l_pub_CRE_CARE_C_S_CRE_PTY_RLE_ADDR) || CHR(10);
    ELSE
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_CRE_PTY_RLE_ADDR', 'SKIPPED', 'C_S_CRE_PTY_RLE_ADDR', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 150 PUBLISH_C_S_CRE_PTY_RLE_ADDR: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_ADDR = 'Y') THEN
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_ADDR', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published invalid address to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 160 PUBLISH_EXC_ADDR', l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_ADDR) || CHR(10);
    ELSE
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_ADDR', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 160 PUBLISH_EXC_ADDR: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_CRE_CARE_C_S_CRE_PTY_RLE_PHN = 'Y') THEN
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_CRE_PTY_RLE_PHN', 'COMPLETED', 'C_S_CRE_PTY_RLE_PHN', 'Published valid phones to C_S_CRE_PTY_RLE_PHN.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 170 PUBLISH_C_S_CRE_PTY_RLE_PHN', l_pub_CRE_CARE_C_S_CRE_PTY_RLE_PHN) || CHR(10);
    ELSE
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_C_S_CRE_PTY_RLE_PHN', 'SKIPPED', 'C_S_CRE_PTY_RLE_PHN', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 170 PUBLISH_C_S_CRE_PTY_RLE_PHN: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_PHONE = 'Y') THEN
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_PHONE', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published invalid phone to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 180 PUBLISH_EXC_PHONE', l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_PHONE) || CHR(10);
    ELSE
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_PHONE', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 180 PUBLISH_EXC_PHONE: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_CARE = 'Y') THEN
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_ALT_ID_CARE', 'COMPLETED', 'C_S_CRE_PTY_RLE_ALT_ID', 'Published CARE alternate ids to C_S_CRE_PTY_RLE_ALT_ID.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 190 PUBLISH_ALT_ID_CARE', l_pub_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_CARE) || CHR(10);
    ELSE
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_ALT_ID_CARE', 'SKIPPED', 'C_S_CRE_PTY_RLE_ALT_ID', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 190 PUBLISH_ALT_ID_CARE: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_MEDICAID = 'Y') THEN
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_ALT_ID_MEDICAID', 'COMPLETED', 'C_S_CRE_PTY_RLE_ALT_ID', 'Published Medicaid alternate ids to C_S_CRE_PTY_RLE_ALT_ID.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 200 PUBLISH_ALT_ID_MEDICAID', l_pub_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_MEDICAID) || CHR(10);
    ELSE
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_ALT_ID_MEDICAID', 'SKIPPED', 'C_S_CRE_PTY_RLE_ALT_ID', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 200 PUBLISH_ALT_ID_MEDICAID: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_MEDICAID_ALT = 'Y') THEN
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_MEDICAID_ALT', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published invalid Medicaid alternate id to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 210 PUBLISH_EXC_MEDICAID_ALT', l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_MEDICAID_ALT) || CHR(10);
    ELSE
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_MEDICAID_ALT', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 210 PUBLISH_EXC_MEDICAID_ALT: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_SSN = 'Y') THEN
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_ALT_ID_SSN', 'COMPLETED', 'C_S_CRE_PTY_RLE_ALT_ID', 'Published SSN alternate ids to C_S_CRE_PTY_RLE_ALT_ID.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 220 PUBLISH_ALT_ID_SSN', l_pub_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_SSN) || CHR(10);
    ELSE
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_ALT_ID_SSN', 'SKIPPED', 'C_S_CRE_PTY_RLE_ALT_ID', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 220 PUBLISH_ALT_ID_SSN: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;
    IF (l_flag_CRE_CARE_EXC_STG_BAD_REC_MEMB_SSN_ALT = 'Y') THEN
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_SSN_ALT', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Published invalid SSN alternate id to EXC_STG_BAD_REC_MEMB.', NULL);
        l_summary := l_summary || fn_snow_helper36_common(c_mapping, 'step 230 PUBLISH_EXC_SSN_ALT', l_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_SSN_ALT) || CHR(10);
    ELSE
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'WORKING',
            'PUBLISH_EXC_SSN_ALT', 'SKIPPED', 'EXC_STG_BAD_REC_MEMB', 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)', NULL);
        l_summary := l_summary || 'step 230 PUBLISH_EXC_SSN_ALT: SKIPPED by config (IS_RUN_ENABLED = N)' || CHR(10);
    END IF;

    -- ---- TERMINATING ------------------------------------------------------
    sp_etl_job_finish('CRE', l_job_run_id, c_workflow, c_mapping,
        'm_Tgt_C_S_CRE_CARE_Clients completed. JOB_RUN_ID = ' || l_job_run_id);
    RETURN 'JOB_RUN_ID=' || l_job_run_id || CHR(10) || l_summary;
WHEN OTHERS THEN
        ROLLBACK;
        sp_etl_checkpoint('CRE', l_job_run_id, c_workflow, c_mapping, 'TERMINATING',
            'JOB_END', 'FAILED', NULL, 'Job failed; work tables left in place until the next run of this mapping cleans them up at its start. ' || 'See ALL_TABLES for WRK_% tables in this schema and VW_ETL_JOB_STORY for the last completed step.', 'See Snowflake query history for this JOB_RUN_ID for the underlying error.');
        sp_etl_job_fail('CRE', l_job_run_id, c_workflow, c_mapping,
            'm_Tgt_C_S_CRE_CARE_Clients failed; work tables left in place until the next run of this mapping cleans them up at its start.');
        RAISE;
END sp_snow_main_m_Tgt_C_S_CRE_CARE_Clients;
/

