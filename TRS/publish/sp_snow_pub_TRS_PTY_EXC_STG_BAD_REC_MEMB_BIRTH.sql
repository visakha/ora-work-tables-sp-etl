-- ============================================================================
-- sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_OnGoing, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 80, driver checkpoint STEP_NAME PUBLISH_EXC_BIRTH.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: EXCEPTION (Invalid birth date).
--
-- INPUTS
--   Reads ONLY WRK_TRS_PTY_S3_ROUTER (P_INPUT_TABLES default). The INSERT below may use
--   :P_RUN_TS (run timestamp) and :c_mapping (local constant) where
--   the original INSERT used :l_run_ts / :c_mapping; it uses original
--   parameters: none.
--
-- BUSINESS SQL
--   The INSERT below is the current publish-branch INSERT verbatim:
--   same columns, values and WHERE guard. No business expression,
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_PTY_S3_ROUTER') RETURN NUMBER AUTHID CURRENT_USER AS
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_OnGoing';
BEGIN
INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, FIRST_NAME, MIDDLE_NAME, LAST_NAME, SUFFIX, RUN_DATE, PREFIX, EXCEPTION_CODE, EXCEPTION_TYPE,
            EXCEPTION_DESC, BIRTH_DATE, GENDER, ATTRIBUTE_NAME, MAPPING_NAME, PERIOD_START_DATE, DEATH_DT,
            ATTRIBUTE_VALUE, SRC_SYS_ID_1)
    SELECT 'TRS', std_first_name, std_mdl_name, std_lst_name, std_sfx_name, P_RUN_TS, std_prfx_name,
           birth_exception_code, birth_exception_type, birth_exception_description, std_birth_date,
           GENDER_CD, 'Birth Date', c_mapping, CREATE_DT, DEATH_DT, TO_CHAR(DOB_DT, 'MM/DD/YYYY'), pkey_src_object
      FROM WRK_TRS_PTY_S3_ROUTER
     WHERE birth_exception_code IS NOT NULL AND uq_exc_birth = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH;
/

