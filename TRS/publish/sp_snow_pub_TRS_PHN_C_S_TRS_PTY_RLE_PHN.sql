-- ============================================================================
-- sp_snow_pub_TRS_PHN_C_S_TRS_PTY_RLE_PHN  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 80, driver checkpoint STEP_NAME PUBLISH_C_S_TRS_PTY_RLE_PHN.
-- Target: C_S_TRS_PTY_RLE_PHN. Kind: SPINE (Valid phones).
--
-- INPUTS
--   Reads ONLY WRK_TRS_PHN_S5_VERSIONS (P_INPUT_TABLES default). The INSERT below may use
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_PHN_C_S_TRS_PTY_RLE_PHN (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_PHN_S5_VERSIONS') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO C_S_TRS_PTY_RLE_PHN
           (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE, VERSION_SEQ,
            PERIOD_REFERENCE_TIME, TIMELINE_ACTION, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE, CREATOR, SRC_ROWID,
            HUB_STATE_IND, PTY_RLE_FK, USG_TP, PHN_TP, PHN_NUM, PREF_LVL, PERIOD_END_DATE, SRC_LAST_UPD_DT)
    SELECT pkey_src_object, NULL, NULL, NULL, NULL, period_start_date, version_seq, NULL, NULL, P_RUN_TS, NULL,
           period_start_date, NULL, pkey_src_object, NULL, pty_rle_fk, usg_tp, phn_tp, phn_num, pref_lvl,
           NULL, period_start_date
      FROM WRK_TRS_PHN_S5_VERSIONS
     WHERE rn = 1 AND uq_tgt = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_PHN_C_S_TRS_PTY_RLE_PHN;
/

