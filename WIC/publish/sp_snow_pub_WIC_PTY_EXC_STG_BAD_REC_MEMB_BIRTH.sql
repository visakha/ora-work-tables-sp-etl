-- ============================================================================
-- sp_snow_pub_WIC_PTY_EXC_STG_BAD_REC_MEMB_BIRTH  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (WIC)
--
-- Mapping: m_Tgt_C_S_WIC_Pty, workflow wf_WIC_Stage_Load.
-- Publish branch STEP_NO 80, checkpoint STEP_NAME PUBLISH_EXC_BIRTH.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: EXCEPTION (invalid-birth-date exceptions).
-- Branch in original order; WHERE guard: grp_birth AND uq_birth.
--
-- INPUTS
--   Reads ONLY WRK_WIC_PTY_S40_ROUTED (P_INPUT_TABLES default). The INSERT reads the run_ts / mapping_name columns materialised in the final step; it references neither original parameter nor the run timestamp directly, so P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same columns, values and WHERE guard. No business expression, filter, guard or column list was changed.
--
-- FRAMEWORK RULE
--   NO transaction control and NO checkpoint calls in this proc. The driver calls it inside ONE publish transaction (all branches together, so a publish either lands completely or not at all), COMMITs, and only then checkpoints this branch. Never call a checkpoint between BEGIN TRANSACTION and COMMIT.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_WIC_PTY_EXC_STG_BAD_REC_MEMB_BIRTH (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_WIC_PTY_S40_ROUTED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE, MAPPING_NAME,
            GENDER, ATTRIBUTE_NAME, SRC_SYS_ID_2, PREFIX, FIRST_NAME, LAST_NAME, MIDDLE_NAME, ATTRIBUTE_VALUE,
            BIRTH_DATE)
    SELECT src_sys, PTY_SRC_KEY, birth_exception_code, birth_exception_description, birth_exception_type,
           run_ts, mapping_name, GENDER, attr_birth, ID, std_prfx_name, FIRST_NAME, LAST_NAME, MIDDLE_NAME,
           dob_text, DOB
      FROM WRK_WIC_PTY_S40_ROUTED
     WHERE grp_birth = 1 AND uq_birth = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_WIC_PTY_EXC_STG_BAD_REC_MEMB_BIRTH;
/

