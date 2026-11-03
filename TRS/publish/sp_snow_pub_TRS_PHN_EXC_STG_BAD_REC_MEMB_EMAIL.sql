-- ============================================================================
-- sp_snow_pub_TRS_PHN_EXC_STG_BAD_REC_MEMB_EMAIL  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 110, driver checkpoint STEP_NAME PUBLISH_EXC_EMAIL.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: EXCEPTION (Invalid emails).
--
-- INPUTS
--   Reads ONLY WRK_TRS_PHN_S6_EMAILS (P_INPUT_TABLES default). The INSERT below may use
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_PHN_EXC_STG_BAD_REC_MEMB_EMAIL (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_PHN_S6_EMAILS') RETURN NUMBER AUTHID CURRENT_USER AS
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr';
BEGIN
INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, EMAIL, MAPPING_NAME, EXCEPTION_TYPE,
            PERIOD_START_DATE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME, SRC_SYS_ID_2)
    SELECT 'TRS', TO_CHAR(INDV_ID), em_exc_code, em_exc_desc, P_RUN_TS, EMAIL, c_mapping, em_exc_type,
           CREATE_DT, EMAIL, 'Email', TO_CHAR(CASE_NUM)
      FROM WRK_TRS_PHN_S6_EMAILS
     WHERE em_exc_code IS NOT NULL AND uq_exc = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_PHN_EXC_STG_BAD_REC_MEMB_EMAIL;
/

