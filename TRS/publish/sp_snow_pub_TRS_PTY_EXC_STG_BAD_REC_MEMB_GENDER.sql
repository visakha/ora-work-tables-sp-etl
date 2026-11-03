-- ============================================================================
-- sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_GENDER  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_OnGoing, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 60, driver checkpoint STEP_NAME PUBLISH_EXC_GENDER.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: EXCEPTION (Invalid gender code).
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_GENDER (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_PTY_S3_ROUTER') RETURN NUMBER AUTHID CURRENT_USER AS
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_OnGoing';
BEGIN
INSERT INTO EXC_STG_BAD_REC_MEMB
           (GENDER, PREFIX, FIRST_NAME, MIDDLE_NAME, LAST_NAME, SUFFIX, SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC,
            EXCEPTION_TYPE, BIRTH_DATE, ATTRIBUTE_NAME, MAPPING_NAME, PERIOD_START_DATE, ATTRIBUTE_VALUE,
            DEATH_DT, RUN_DATE, SRC_SYS_ID_1)
    SELECT GENDER_CD, std_prfx_name, std_first_name, std_mdl_name, std_lst_name, std_sfx_name, 'TRS',
           gender_exception_code, gender_exception_description, gender_exception_type, std_birth_date,
           'Gender', c_mapping, CREATE_DT, GENDER_CD, DEATH_DT, P_RUN_TS, pkey_src_object
      FROM WRK_TRS_PTY_S3_ROUTER
     WHERE gender_exception_description IS NOT NULL AND uq_exc_gender = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_GENDER;
/

