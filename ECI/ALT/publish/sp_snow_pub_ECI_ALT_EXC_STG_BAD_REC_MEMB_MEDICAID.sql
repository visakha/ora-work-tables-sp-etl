-- ============================================================================
-- sp_snow_pub_ECI_ALT_EXC_STG_BAD_REC_MEMB_MEDICAID  --  CONFIG-DRIVEN STEP
-- DRIVER REFACTOR (ECI), publish branch, STEP_NO 70
--
-- Mapping: m_Tgt_C_S_ECI_Pty_Rle_Alt_Id, workflow wf_ECI_Stage_Load.
--
-- TARGET / BRANCH / KIND
--   Target: EXC_STG_BAD_REC_MEMB. Branch: invalid Medicaid id (branch
--   50c of the current step-50 publish, third INSERT of the original
--   INSERT ALL, in the original order). Kind: NON-SPINE -- exception
--   logging only; it never writes a hub table.
--
-- WHAT THIS BRANCH WRITES
--   Invalid-Medicaid exception rows only (grp_mcd_exc AND uq_mcd_exc).
--   Unlike the SSN branch, this row IS linked to the run (RUN_DATE =
--   run_ts) and writes the computed exception code.
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
--   The INSERT below is the current publish branch 50c verbatim: same
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
CREATE OR REPLACE FUNCTION sp_snow_pub_ECI_ALT_EXC_STG_BAD_REC_MEMB_MEDICAID (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_ALT_S40_READY') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_ECI_Pty_Rle_Alt_Id';
    l_rows NUMBER DEFAULT 0;
BEGIN
    -- ---- Publish branch 50c: invalid Medicaid id -> EXC_STG_BAD_REC_MEMB (NON-SPINE, verbatim)
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, RUN_DATE, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, MAPPING_NAME, ATTRIBUTE_VALUE,
            ATTRIBUTE_NAME, SRC_SYS_ID_2, SRC_SYS_ID_1)
    SELECT src_sys, run_ts, medicaid_exception_type, medicaid_exception_code, medicaid_exception_desc,
           mapping_name, ALT_ID_VAL, attr_medicaid, PTY_REL_FK, PKEY_SRC_OBJECT
      FROM WRK_ECI_ALT_S40_READY
     WHERE grp_mcd_exc = 1 AND uq_mcd_exc = 1;
    l_rows := SQLROWCOUNT;
    RETURN l_rows;
END sp_snow_pub_ECI_ALT_EXC_STG_BAD_REC_MEMB_MEDICAID;
/

