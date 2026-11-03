-- ============================================================================
-- sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY  --  CONFIG-DRIVEN REFACTOR (ECI)
--
-- Mapping: m_Tgt_C_S_ECI_Pty, workflow wf_ECI_Stage_Load.
-- Publish branch STEP_NO 100, checkpoint STEP_NAME PUBLISH_EXC_ETHNICITY.
-- Target: EXC_STG_BAD_REC_MEMB, branch: invalid ethnicity.
-- Kind: NON-SPINE (demographic exception log, child rows only --
-- grp_ethnicity already restricts to SOURCE_TABLE = 'ECI_CHILD').
-- Branch 60e of the original publish, in original order (fifth).
--
-- INPUTS
--   Reads ONLY WRK_ECI_PTY_S50_READY (P_INPUT_TABLES default). The
--   INSERT reads the run_ts / exc_mapping columns materialised in step
--   50; it references neither original parameter nor the run timestamp
--   directly, so P_RUN_TS is carried for a uniform driver call
--   signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch-60e INSERT verbatim: same
--   columns, values and WHERE guard (grp_ethnicity AND uq_ethnicity).
--   No business expression, filter, guard or column list was changed.
--
-- FRAMEWORK RULE
--   NO transaction control and NO checkpoint calls in this proc. The
--   driver calls it inside ONE publish transaction (all branches
--   together), COMMITs, and only then checkpoints this branch with the
--   returned row count. Never call a checkpoint between BEGIN
--   TRANSACTION and COMMIT.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_PTY_S50_READY') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (RUN_DATE, EXCEPTION_CODE, EXCEPTION_TYPE, EXCEPTION_DESC, ATTRIBUTE_NAME, GENDER, SRC_SYS_ID_1,
            SRC_SYS, FIRST_NAME, LAST_NAME, MIDDLE_NAME, MAPPING_NAME, BIRTH_DATE, PERIOD_START_DATE,
            SRC_SYS_ID_2, ATTRIBUTE_VALUE)
    SELECT run_ts, ethnicity_exception_code, ethnicity_exception_type, ethnicity_exception_desc,
           attr_ethnicity, GENDER, pkey_src_object, src_system, FIRST_NAME, std_lst_name, std_mdl_name,
           exc_mapping, DOB, DATE_CREATED, ID, ETHNICITY
      FROM WRK_ECI_PTY_S50_READY
     WHERE grp_ethnicity = 1 AND uq_ethnicity = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY;
/

