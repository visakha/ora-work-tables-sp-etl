-- ============================================================================
-- sp_snow_pub_TRS_PLN_C_S_TRS_PTY_RLE_PLN  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_Pln, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 40, driver checkpoint STEP_NAME PUBLISH_C_S_TRS_PTY_RLE_PLN.
-- Target: C_S_TRS_PTY_RLE_PLN. Kind: SPINE (Valid plans).
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_PLN_C_S_TRS_PTY_RLE_PLN (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_PLN_S30_RANKED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO C_S_TRS_PTY_RLE_PLN
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, PERIOD_END_DATE, VERSION_SEQ, LAST_UPDATE_DATE, PTY_RLE_FK,
            PLN_FK, UPDATED_BY, CREATOR, HUB_STATE_IND, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY,
            SRC_ROWID, CREATE_DATE, SRC_LAST_UPD_DT)
    SELECT pkey_prty_rl_plan, BEGIN_DT, END_DT, version_seq, run_ts, pty_rle_fk, pln_mstr_cd, NULL, NULL,
           NULL, NULL, NULL, NULL, NULL, pkey_prty_rl_plan, run_ts, CREATE_DT
      FROM WRK_TRS_PLN_S30_RANKED
     WHERE pln_mstr_cd IS NOT NULL AND rn_key = 1 AND uq_pln = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_PLN_C_S_TRS_PTY_RLE_PLN;
/

