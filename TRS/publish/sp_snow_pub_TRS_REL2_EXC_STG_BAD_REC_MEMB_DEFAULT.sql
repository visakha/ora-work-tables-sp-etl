-- ============================================================================
-- sp_snow_pub_TRS_REL2_EXC_STG_BAD_REC_MEMB_DEFAULT  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 80, driver checkpoint STEP_NAME PUBLISH_EXC_DEFAULT.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: EXCEPTION (Default exception).
--
-- INPUTS
--   Reads ONLY WRK_TRS_REL2_S3_ROUTER (P_INPUT_TABLES default). The INSERT below may use
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_REL2_EXC_STG_BAD_REC_MEMB_DEFAULT (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_REL2_S3_ROUTER') RETURN NUMBER AUTHID CURRENT_USER AS
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP';
BEGIN
INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, RUN_DATE, MAPPING_NAME, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, PERIOD_START_DATE,
            PERIOD_END_DATE, SRC_SYS_ID_1, SRC_SYS_ID_2, ATTRIBUTE_VALUE, ATTRIBUTE_NAME)
    SELECT 'TRS', P_RUN_TS, c_mapping, exc_default_code, exc_default_desc, exc_default_type, BEGIN_DT,
           END_DT, INDV_ID, PROVIDER_NUM, PROVIDER_NUM, attr_provider
      FROM WRK_TRS_REL2_S3_ROUTER
     WHERE is_valid = 0 AND dates_reversed = 0 AND uq_exc_default = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_REL2_EXC_STG_BAD_REC_MEMB_DEFAULT;
/

