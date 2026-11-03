-- ============================================================================
-- sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_NAME  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_OnGoing, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 50, driver checkpoint STEP_NAME PUBLISH_EXC_NAME.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: EXCEPTION (Invalid party name).
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_NAME (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_PTY_S3_ROUTER') RETURN NUMBER AUTHID CURRENT_USER AS
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_OnGoing';
BEGIN
INSERT INTO EXC_STG_BAD_REC_MEMB
           (PERIOD_START_DATE, SRC_SYS, DEATH_DT, MAPPING_NAME, MIDDLE_NAME, LAST_NAME, FIRST_NAME,
            ATTRIBUTE_NAME, ATTRIBUTE_VALUE, RUN_DATE, EXCEPTION_CODE, SRC_SYS_ID_1, EXCEPTION_TYPE,
            EXCEPTION_DESC)
    SELECT CREATE_DT, 'TRS', DEATH_DT, c_mapping, std_mdl_name, std_lst_name, std_first_name,
           name_attribute_name, name_attribute_value, P_RUN_TS, name_exception_code, pkey_src_object,
           name_exception_type, name_exception_desc
      FROM WRK_TRS_PTY_S3_ROUTER
     WHERE name_missing = 1 AND uq_exc_name = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_NAME;
/

