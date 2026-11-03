-- ============================================================================
-- sp_snow_pub_TRS_PTY_C_S_TRS_PTY_RLE  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_OnGoing, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 100, driver checkpoint STEP_NAME PUBLISH_C_S_TRS_PTY_RLE.
-- Target: C_S_TRS_PTY_RLE. Kind: SPINE (Valid roles).
--
-- INPUTS
--   Reads ONLY WRK_TRS_PTY_S4_DEDUP (P_INPUT_TABLES default). The INSERT below may use
--   :P_RUN_TS (run timestamp) and :c_mapping (local constant) where
--   the original INSERT used :l_run_ts / :c_mapping; it uses original
--   parameters: P_RLE_BO_CLASS_CD_MEMBER.
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_PTY_C_S_TRS_PTY_RLE (P_RLE_BO_CLASS_CD_MEMBER IN VARCHAR2 DEFAULT 'Member', P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_PTY_S4_DEDUP') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO C_S_TRS_PTY_RLE
           (PTY_FK, PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, RLE_BO_CLASS_CD,
            VERSION_SEQ, PERIOD_END_DATE, PERIOD_START_DATE, TIMELINE_ACTION, PERIOD_REFERENCE_TIME, UPDATED_BY,
            CREATE_DATE, CREATOR, SRC_LAST_UPD_DT, HUB_STATE_IND, SRC_ROWID, LAST_UPDATE_DATE)
    SELECT pkey_trim, pkey_trim || '|' || P_RLE_BO_CLASS_CD_MEMBER, NULL, NULL, NULL, NULL,
           P_RLE_BO_CLASS_CD_MEMBER, 1, NULL, CREATE_DT, NULL,
           NULL, NULL, NULL, NULL, CREATE_DT, NULL, pkey_trim || '|' || P_RLE_BO_CLASS_CD_MEMBER, P_RUN_TS
      FROM WRK_TRS_PTY_S4_DEDUP
     WHERE rn_pty = 1 AND uq_rle = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_PTY_C_S_TRS_PTY_RLE;
/

