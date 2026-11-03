-- ============================================================================
-- sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_GENDER  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (FSS)
--
-- Mapping: m_Tgt_C_S_FSS_Pty, workflow wf_FSS_Stage_Load.
-- Publish branch STEP_NO 70, checkpoint STEP_NAME PUBLISH_EXC_GENDER.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: EXCEPTION. Invalid gender.
-- Branch 3 of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_FSS_PTY_S4_ROUTED (P_INPUT_TABLES default). The INSERT references neither original parameter nor the run timestamp directly, so P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same
--   columns, values and WHERE guard (grp_gender AND uq_gender). No business expression,
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
CREATE OR REPLACE FUNCTION sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_GENDER (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_FSS_PTY_S4_ROUTED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, ATTRIBUTE_NAME, ATTRIBUTE_VALUE,
            MAPPING_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2, GENDER, BIRTH_DATE, RUN_DATE, FIRST_NAME, MIDDLE_NAME,
            LAST_NAME)
    SELECT src_sys, gender_exception_type, gender_exception_code, gender_exception_description, attr_gender,
           CD_GENDER, mapping_name, PTY_SRC_KEY, ID_CLIENT, CD_GENDER, DT_DOB, run_ts, NM_FIRST, NM_MIDDLE,
           NM_LAST
      FROM WRK_FSS_PTY_S4_ROUTED
     WHERE grp_gender = 1 AND uq_gender = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_GENDER;
/

