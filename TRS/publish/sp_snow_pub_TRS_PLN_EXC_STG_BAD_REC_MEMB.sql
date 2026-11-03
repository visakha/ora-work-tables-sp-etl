-- ============================================================================
-- sp_snow_pub_TRS_PLN_EXC_STG_BAD_REC_MEMB  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_Pln, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 50, driver checkpoint STEP_NAME PUBLISH_EXC_STG_BAD_REC_MEMB.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: EXCEPTION (Invalid plans).
--
-- INPUTS
--   Reads ONLY WRK_TRS_PLN_S30_RANKED (P_INPUT_TABLES default). The INSERT below may use
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_PLN_EXC_STG_BAD_REC_MEMB (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_PLN_S30_RANKED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_TYPE, EXCEPTION_DESC, EXCEPTION_CODE, ATTRIBUTE_VALUE,
            ATTRIBUTE_NAME, MAPPING_NAME, RUN_DATE, PERIOD_START_DATE, SRC_SYS_ID_2)
    SELECT src_sys, INDV_ID, exc_type, exc_desc, exc_code, MC_PLAN, attr_plan, mapping_name, run_ts,
           BEGIN_DT, begin_dt_text
      FROM WRK_TRS_PLN_S30_RANKED
     WHERE pln_mstr_cd IS NULL AND rn_invalid = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_PLN_EXC_STG_BAD_REC_MEMB;
/

