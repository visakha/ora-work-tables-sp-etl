-- ============================================================================
-- sp_snow_pub_TRS_PHN_EXC_STG_BAD_REC_MEMB_PHONE  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 90, driver checkpoint STEP_NAME PUBLISH_EXC_PHONE.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: EXCEPTION (Invalid phones).
--
-- INPUTS
--   Reads ONLY WRK_TRS_PHN_S4_PHONES (P_INPUT_TABLES default). The INSERT below may use
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_PHN_EXC_STG_BAD_REC_MEMB_PHONE (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_PHN_S4_PHONES') RETURN NUMBER AUTHID CURRENT_USER AS
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr';
BEGIN
INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, PRIMARY_PHONE, WORK_PHONE, SECONDARY_PHONE,
            MAPPING_NAME, SRC_SYS_ID_1, EXCEPTION_TYPE, SRC_SYS_ID_3, PERIOD_START_DATE, ATTRIBUTE_VALUE,
            SRC_SYS_ID_2, ATTRIBUTE_NAME)
    SELECT 'TRS', dq_exception_code, dq_exception, P_RUN_TS,
           CASE WHEN pref_lvl = 'Primary' THEN phn_num ELSE NULL END,
           CASE WHEN usg_tp = 'Work' THEN phn_num ELSE NULL END,
           CASE WHEN pref_lvl = 'Secondary' THEN phn_num ELSE NULL END,
           c_mapping, pty_fk, 'Bad Value', usg_tp, period_start_date, phn_num, case_number,
           DECODE(usg_tp, '001', 'Main Phone', '002', 'Work Phone', '003', 'Other Phone')
      FROM WRK_TRS_PHN_S4_PHONES
     WHERE dq_exception_code IS NOT NULL AND uq_exc = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_PHN_EXC_STG_BAD_REC_MEMB_PHONE;
/

