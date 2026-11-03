-- ============================================================================
-- sp_snow_pub_TRS_TOA_EXC_STG_BAD_REC_MEMB_BAD_VALUE  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_TOA, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 50, driver checkpoint STEP_NAME PUBLISH_EXC_BAD_VALUE.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: EXCEPTION (Bad value).
--
-- INPUTS
--   Reads ONLY WRK_TRS_TOA_S40_RANKED (P_INPUT_TABLES default). The INSERT below may use
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_TOA_EXC_STG_BAD_REC_MEMB_BAD_VALUE (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_TOA_S40_RANKED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, RUN_DATE, ATTRIBUTE_NAME, MAPPING_NAME, PERIOD_START_DATE, PERIOD_END_DATE, EXCEPTION_CODE,
            EXCEPTION_DESC, EXCEPTION_TYPE, ATTRIBUTE_VALUE, SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3)
    SELECT src_sys, run_ts, attr_toa, mapping_name, BEGIN_DT, END_DT, toa_exc_code, toa_exc_desc,
           toa_exc_type, TYPE_OF_ASSISTANCE_CD, INDV_ID, EDG_NUM, MCI_CREATE_SEQ
      FROM WRK_TRS_TOA_S40_RANKED
     WHERE grp_bad_value = 1 AND uq_exc_toa = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_TOA_EXC_STG_BAD_REC_MEMB_BAD_VALUE;
/

