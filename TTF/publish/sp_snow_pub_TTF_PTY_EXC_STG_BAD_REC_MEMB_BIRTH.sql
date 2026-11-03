-- ============================================================================
-- sp_snow_pub_TTF_PTY_EXC_STG_BAD_REC_MEMB_BIRTH  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TTF)
--
-- Mapping: m_Tgt_C_S_TTF_Pty, workflow wf_TTF_Stage_Load.
-- Publish branch STEP_NO 80. Target: EXC_STG_BAD_REC_MEMB. Kind: EXCEPTION (invalid-birth-date exceptions).
-- Branch 80 of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_TTF_PTY_S4_ROUTED (P_INPUT_TABLES default). It references neither original parameter nor the run timestamp directly (it reads the run_ts / mapping_name columns materialised in the final routed table), so P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same
--   columns, values and WHERE guard. No business expression, filter,
--   guard or column list was changed.
--
-- FRAMEWORK RULE
--   NO transaction control and NO checkpoint calls in this proc. The
--   driver calls it inside ONE publish transaction (all branches
--   together, so a publish either lands completely or not at all),
--   COMMITs, and only then checkpoints this branch with the returned
--   row count. Never call a checkpoint between BEGIN TRANSACTION and
--   COMMIT.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_TTF_PTY_EXC_STG_BAD_REC_MEMB_BIRTH (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TTF_PTY_S4_ROUTED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE, MAPPING_NAME,
            GENDER, ATTRIBUTE_NAME, SRC_SYS_ID_2, PREFIX, FIRST_NAME, LAST_NAME, MIDDLE_NAME, ATTRIBUTE_VALUE,
            BIRTH_DATE)
    SELECT src_sys, PTY_SRC_KEY, birth_exception_code, birth_exception_description, birth_exception_type,
           run_ts, mapping_name, gender, attr_birth, CLIENTS_ID, std_prfx_name, FIRSTNAME, LASTNAME,
           MIDDLENAME, dob_text, DOB
      FROM WRK_TTF_PTY_S4_ROUTED
     WHERE grp_birth = 1 AND uq_birth = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TTF_PTY_EXC_STG_BAD_REC_MEMB_BIRTH;
/

