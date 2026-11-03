-- ============================================================================
-- sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (FSS)
--
-- Mapping: m_Tgt_C_S_FSS_Pty, workflow wf_FSS_Stage_Load.
-- Publish branch STEP_NO 90, checkpoint STEP_NAME PUBLISH_EXC_ETHNICITY.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: EXCEPTION. Invalid ethnicity.
-- Branch 5 of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_FSS_PTY_S4_ROUTED (P_INPUT_TABLES default). The INSERT references neither original parameter nor the run timestamp directly, so P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same
--   columns, values and WHERE guard (grp_ethnicity AND uq_ethnicity). No business expression,
--   filter, guard or column list was changed.
--
-- FRAMEWORK RULE
--   NO transaction control and NO checkpoint calls in this proc. The
--   driver calls it inside ONE publish transaction (all branches
--   together, so a publish either lands completely or not at all),
--   COMMITs, and only then checkpoints this branch with the returned
--   row count. Never call a checkpoint between BEGIN TRANSACTION and
--   COMMIT.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_FSS_PTY_S4_ROUTED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO EXC_STG_BAD_REC_MEMB
           (RUN_DATE, EXCEPTION_CODE, EXCEPTION_TYPE, EXCEPTION_DESC, ATTRIBUTE_NAME, GENDER, SRC_SYS_ID_1,
            SRC_SYS, FIRST_NAME, LAST_NAME, MIDDLE_NAME, MAPPING_NAME, BIRTH_DATE, PERIOD_START_DATE,
            SRC_SYS_ID_2, ATTRIBUTE_VALUE)
    SELECT run_ts, ethnicity_exception_code, ethnicity_exception_type, ethnicity_exception_desc,
           attr_ethnicity, CD_GENDER, PTY_SRC_KEY, src_sys, NM_FIRST, std_lst_name, std_mdl_name,
           mapping_name, DT_DOB, DT_LAST_UPDATE, ID_CLIENT, CD_HISPANIC
      FROM WRK_FSS_PTY_S4_ROUTED
     WHERE grp_ethnicity = 1 AND uq_ethnicity = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY;
/

