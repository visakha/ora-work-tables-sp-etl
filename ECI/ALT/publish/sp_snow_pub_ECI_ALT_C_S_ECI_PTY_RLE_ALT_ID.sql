-- ============================================================================
-- sp_snow_pub_ECI_ALT_C_S_ECI_PTY_RLE_ALT_ID  --  CONFIG-DRIVEN STEP DRIVER
-- REFACTOR (ECI), publish branch, STEP_NO 50
--
-- Mapping: m_Tgt_C_S_ECI_Pty_Rle_Alt_Id, workflow wf_ECI_Stage_Load.
--
-- TARGET / BRANCH / KIND
--   Target: C_S_ECI_PTY_RLE_ALT_ID. Branch: valid alternate ids
--   (branch 50a of the current step-50 publish, first INSERT of the
--   original INSERT ALL, in the original order). Kind: SPINE -- this
--   is the mapping's hub load.
--
-- WHAT THIS BRANCH WRITES
--   Valid alternate ids only (grp_valid AND uq_alt_id): child ECI id
--   018, valid child SSN 004, valid Medicaid number 002, family ECI
--   id 019. Insert-only: no TRUNCATE, no DELETE; keys already present
--   are skipped by the uq_alt_id guard computed in step 40.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only: WRK_ECI_ALT_S40_READY
--   by default. It is a dependency declaration carried for uniformity
--   and for the driver to pass the config value; this proc does NOT
--   run an existence check on it (only step procs do), and the INSERT
--   below still names its source literally, as in the current main
--   procedure -- Snowflake cannot parameterise table names in static
--   SQL, so P_INPUT_TABLES is NOT dynamic SQL. A missing S40 table
--   therefore surfaces as the native INSERT error from this proc.
--   run_ts in the SELECT is the S40 work-table column, not P_RUN_TS:
--   P_RUN_TS is carried for signature uniformity and is unused by
--   this branch. mapping_name likewise flows from the S40 column, not
--   from the local constant below.
--
-- BUSINESS SQL
--   The INSERT below is the current publish branch 50a verbatim: same
--   columns, values and WHERE guards. Only substitutions: :l_run_ts
--   -> :P_RUN_TS (not referenced by this branch), mapping-name refs
--   -> the local constant below (not referenced; mapping_name is an
--   S40 column here). No business expression, filter, guard or column
--   list was changed.
--
-- FRAMEWORK RULE (do not move this)
--   NO transaction control and NO checkpoint calls in this proc. It
--   runs inside the driver's publish transaction (BEGIN TRANSACTION
--   ... COMMIT), and the driver writes this branch's checkpoint only
--   AFTER COMMIT -- a checkpoint written inside the transaction would
--   roll back with it. Returns SQLROWCOUNT as NUMBER.
--   P_JOB_RUN_ID is present in every new proc in this refactor (carried
--   for uniformity; this proc writes no checkpoint of its own).
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_ECI_ALT_C_S_ECI_PTY_RLE_ALT_ID (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_ALT_S40_READY') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_ECI_Pty_Rle_Alt_Id';
    l_rows NUMBER DEFAULT 0;
BEGIN
    -- ---- Publish branch 50a: valid alternate ids -> C_S_ECI_PTY_RLE_ALT_ID (SPINE, verbatim)
    INSERT INTO C_S_ECI_PTY_RLE_ALT_ID
           (PTY_RLE_FK, ALT_ID_TP, ALT_ID_VAL, CREATE_DATE, LAST_UPDATE_DATE, PKEY_SRC_OBJECT, SRC_ROWID,
            VERSION_SEQ, STS_CD, HUB_STATE_IND, SRC_LAST_UPD_DT, ALT_ID_TP_FLTR, PERIOD_START_DATE)
    SELECT PTY_REL_FK, ALT_ID_TP, ALT_ID_VAL, DATE_CREATED, run_ts, PKEY_SRC_OBJECT, src_rowid,
           version_seq, sts_cd, hub_state_ind, src_last_upd_dt, ALT_ID_TP, DATE_CREATED
      FROM WRK_ECI_ALT_S40_READY
     WHERE grp_valid = 1 AND uq_alt_id = 1;
    l_rows := SQLROWCOUNT;
    RETURN l_rows;
END sp_snow_pub_ECI_ALT_C_S_ECI_PTY_RLE_ALT_ID;
/

