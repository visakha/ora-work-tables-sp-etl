-- ============================================================================
-- sp_snow_pub_ECI_ALT_EXC_STG_BAD_REC_MEMB_SSN  --  CONFIG-DRIVEN STEP DRIVER
-- REFACTOR (ECI), publish branch, STEP_NO 60
--
-- Mapping: m_Tgt_C_S_ECI_Pty_Rle_Alt_Id, workflow wf_ECI_Stage_Load.
--
-- TARGET / BRANCH / KIND
--   Target: EXC_STG_BAD_REC_MEMB. Branch: invalid SSN (branch 50b of
--   the current step-50 publish, second INSERT of the original INSERT
--   ALL, in the original order). Kind: NON-SPINE -- exception logging
--   only; it never writes a hub table.
--
-- WHAT THIS BRANCH WRITES
--   Invalid-SSN exception rows only (grp_ssn_exc AND uq_ssn_exc).
--   The row has no RUN_DATE linked (NULL) and writes the exception
--   code returned by the exception lookup (NULL when Invalid_SSN is
--   not configured); preserved. Because RUN_DATE is NULL, the key
--   repeats from run to run: in Oracle the unique constraint rejects
--   the row of every later run, so an invalid SSN is logged only once,
--   ever (reproduced here via the uq_ssn_exc guard).
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
--   P_RUN_TS is carried for signature uniformity and is unused by
--   this branch (its RUN_DATE is deliberately NULL). mapping_name
--   flows from the S40 column, not from the local constant below.
--
-- BUSINESS SQL
--   The INSERT below is the current publish branch 50b verbatim: same
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
CREATE OR REPLACE FUNCTION sp_snow_pub_ECI_ALT_EXC_STG_BAD_REC_MEMB_SSN (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_ALT_S40_READY') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_ECI_Pty_Rle_Alt_Id';
    l_rows NUMBER DEFAULT 0;
BEGIN
    -- ---- Publish branch 50b: invalid SSN -> EXC_STG_BAD_REC_MEMB (NON-SPINE, verbatim)
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, SRC_SYS, ATTRIBUTE_NAME, MAPPING_NAME,
            ATTRIBUTE_VALUE, SRC_SYS_ID_1, SRC_SYS_ID_2)
    SELECT ssn_lkp_code, ssn_lkp_desc, ssn_lkp_type, src_sys, attr_ssn, mapping_name, ALT_ID_VAL,
           PKEY_SRC_OBJECT, PTY_REL_FK
      FROM WRK_ECI_ALT_S40_READY
     WHERE grp_ssn_exc = 1 AND uq_ssn_exc = 1;
    l_rows := SQLROWCOUNT;
    RETURN l_rows;
END sp_snow_pub_ECI_ALT_EXC_STG_BAD_REC_MEMB_SSN;
/

