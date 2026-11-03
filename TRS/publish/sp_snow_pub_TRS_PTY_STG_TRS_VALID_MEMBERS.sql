-- ============================================================================
-- sp_snow_pub_TRS_PTY_STG_TRS_VALID_MEMBERS  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_OnGoing, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 110, driver checkpoint STEP_NAME PUBLISH_STG_TRS_VALID_MEMBERS.
-- Target: STG_TRS_VALID_MEMBERS. Kind: SPINE (New valid members).
--
-- INPUTS
--   Reads ONLY WRK_TRS_PTY_S4_DEDUP (P_INPUT_TABLES default). The INSERT below may use
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_PTY_STG_TRS_VALID_MEMBERS (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_PTY_S4_DEDUP') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO STG_TRS_VALID_MEMBERS (SRC_TBL, PTY_PK, INDV_ID, CREATE_DATE)
    SELECT SRC_TBL, pkey_trim, INDV_ID, P_RUN_TS
      FROM WRK_TRS_PTY_S4_DEDUP
     WHERE rn_pty = 1 AND is_valid_member = 0;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_PTY_STG_TRS_VALID_MEMBERS;
/

