-- ============================================================================
-- sp_snow_pub_TRS_ALT_C_S_TRS_PTY_RLE_ALT_ID  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_Alt_Id, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 50, driver checkpoint STEP_NAME PUBLISH_C_S_TRS_PTY_RLE_ALT_ID.
-- Target: C_S_TRS_PTY_RLE_ALT_ID. Kind: SPINE (Valid alt ids).
--
-- INPUTS
--   Reads ONLY WRK_TRS_ALT_S4_ROUTED (P_INPUT_TABLES default). The INSERT below may use
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_ALT_C_S_TRS_PTY_RLE_ALT_ID (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_ALT_S4_ROUTED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO C_S_TRS_PTY_RLE_ALT_ID
           (PKEY_SRC_OBJECT, SRC_ROWID, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, ALT_ID_TP, ALT_ID_VAL,
            STS_CD, ALT_ID_TP_FLTR, CV_IND, PTY_RLE_FK, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY,
            PERIOD_END_DATE, PERIOD_REFERENCE_TIME, TIMELINE_ACTION, UPDATED_BY, CREATE_DATE, CREATOR,
            HUB_STATE_IND, SRC_LAST_UPD_DT)
    SELECT pkey_src_object_alt_id, pkey_src_object_alt_id, period_start_date, version_seq, P_RUN_TS,
           alt_id_typ, alt_id_val, sts_cd, alt_id_typ, cv_ind, pty_rle_fk, NULL, NULL, NULL, NULL, NULL,
           NULL, NULL, NULL, period_start_date, NULL, NULL, period_start_date
      FROM WRK_TRS_ALT_S4_ROUTED
     WHERE is_valid = 1 AND uq_alt_id = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_ALT_C_S_TRS_PTY_RLE_ALT_ID;
/

