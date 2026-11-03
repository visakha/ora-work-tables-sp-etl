-- ============================================================================
-- sp_snow_pub_TRS_TOA_EXC_STG_BAD_REC_MEMB_DATES  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_TOA, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 60, driver checkpoint STEP_NAME PUBLISH_EXC_DATES.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: EXCEPTION (Inverted dates).
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_TOA_EXC_STG_BAD_REC_MEMB_DATES (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_TOA_S40_RANKED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS_ID_1, SRC_SYS_ID_2, MAPPING_NAME, RUN_DATE, ATTRIBUTE_NAME, PERIOD_START_DATE,
            PERIOD_END_DATE, SRC_SYS, EXCEPTION_DESC, EXCEPTION_TYPE, EXCEPTION_CODE)
    SELECT pkey_src_object, pty_rle_fk, mapping_name, run_ts, attr_dates, BEGIN_DT, END_DT, src_sys,
           date_exc_desc, date_exc_type, date_exc_code
      FROM WRK_TRS_TOA_S40_RANKED
     WHERE grp_dates = 1 AND uq_exc_dates = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_TOA_EXC_STG_BAD_REC_MEMB_DATES;
/

