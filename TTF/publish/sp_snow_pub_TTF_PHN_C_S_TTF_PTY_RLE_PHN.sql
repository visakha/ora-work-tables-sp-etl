-- ============================================================================
-- sp_snow_pub_TTF_PHN_C_S_TTF_PTY_RLE_PHN  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TTF)
--
-- Mapping: m_Tgt_C_S_TTF_Pty_Rle_Phn, workflow wf_TTF_Stage_Load.
-- Publish branch STEP_NO 40. Target: C_S_TTF_PTY_RLE_PHN. Kind: SPINE (good phones).
-- Branch 40 of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_TTF_PHN_S3_ROUTED (P_INPUT_TABLES default). It references neither original parameter nor the run timestamp directly (it reads the run_ts / mapping_name columns materialised in the final routed table), so P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same
--   columns, values and WHERE guard. No business expression, filter,
--   guard or column list was changed.
--
-- FRAMEWORK RULE
--   NO transaction control and NO checkpoint calls in this proc. The
--   driver calls it inside ONE publish transaction (all branches
--   together, so a publish either lands completely or not at all),
--   COMMITs, and only then checkpoints this branch with the returned
--   row count. Never call a checkpoint between BEGIN TRANSACTION and
--   COMMIT.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_TTF_PHN_C_S_TTF_PTY_RLE_PHN (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TTF_PHN_S3_ROUTED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO C_S_TTF_PTY_RLE_PHN
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, SRC_ROWID, HUB_STATE_IND,
            PTY_RLE_FK, PHN_TP, USG_TP, PHN_NUM, PREF_LVL, SRC_LAST_UPD_DT)
    SELECT phn_pkey, SUBMITDATE, version_seq, run_ts, phn_pkey, hub_state_ind, pty_rle_fk, phn_tp, usg_tp,
           std_phone, pref_lvl, SUBMITDATE
      FROM WRK_TTF_PHN_S3_ROUTED
     WHERE phone_exception_code IS NULL AND uq_phn = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TTF_PHN_C_S_TTF_PTY_RLE_PHN;
/

