-- ============================================================================
-- sp_snow_pub_TRS_PTYDEACT_STG_TRS_DEACTIVED_MEMBERS  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Deactivation_1, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 40, driver checkpoint STEP_NAME PUBLISH_STG_TRS_DEACTIVED_MEMBERS.
-- Target: STG_TRS_DEACTIVED_MEMBERS. Kind: STATUS (Deactivated members).
--
-- INPUTS
--   Reads ONLY WRK_TRS_DEACT1_S30_READY (P_INPUT_TABLES default). The INSERT below may use
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_PTYDEACT_STG_TRS_DEACTIVED_MEMBERS (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_DEACT1_S30_READY') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO STG_TRS_DEACTIVED_MEMBERS
           (INDV_ID, PTY_PK, SRC_TBL, CREATE_DATE, SRC_DEACTIVATION_DATE, LOAD_DATE, INACTIVE_IND, DELETE_SW,
            PROCESSED_YN)
    SELECT INDV_ID, PTY_PK, SRC_TBL, CREATE_DATE, SRC_DEACTIVATION_DATE, LOAD_DATE, INACTIVE_IND, DELETE_SW,
           PROCESSED_YN
      FROM WRK_TRS_DEACT1_S30_READY;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_PTYDEACT_STG_TRS_DEACTIVED_MEMBERS;
/

