-- ============================================================================
-- sp_snow_pub_TRS_REL2_C_S_TRS_PTY_RLE_REL_PROV  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 90, driver checkpoint STEP_NAME PUBLISH_C_S_TRS_PTY_RLE_REL_PROV.
-- Target: C_S_TRS_PTY_RLE_REL_PROV. Kind: SPINE (Valid PCP relationships).
--
-- INPUTS
--   Reads ONLY WRK_TRS_REL2_S6_TIMELINE (P_INPUT_TABLES default). The INSERT below may use
--   :P_RUN_TS (run timestamp) and :c_mapping (local constant) where
--   the original INSERT used :l_run_ts / :c_mapping; it uses original
--   parameters: P_PCP_REL_TP.
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_REL2_C_S_TRS_PTY_RLE_REL_PROV (P_PCP_REL_TP IN VARCHAR2 DEFAULT '100', P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_REL2_S6_TIMELINE') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO C_S_TRS_PTY_RLE_REL_PROV
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, PERIOD_END_DATE, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE,
            SRC_ROWID, HUB_STATE_IND, PTY_RLE_FK_1, PTY_RLE_FK_2, REL_TYPE_CODE, HIERARCHY_CODE, REL_TP,
            SRC_LAST_UPD_DT, PERIOD_REFERENCE_TIME, TIMELINE_ACTION, ROWID_OBJECT, DELETED_IND, DELETED_DATE,
            DELETED_BY, UPDATED_BY, CREATOR)
    SELECT pkey_src_object, BEGIN_DT, tl_period_end_date, tl_version_seq, P_RUN_TS, NULL, pkey_src_object,
           tl_hub_state_ind, pty_rle_fk_1, pty_rle_fk_2, rel_type_code, 'Member', P_PCP_REL_TP, CREATE_DT,
           tl_period_end_date, tl_timeline_action, NULL, NULL, NULL, NULL, NULL, NULL
      FROM WRK_TRS_REL2_S6_TIMELINE
     WHERE uq_rel = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_REL2_C_S_TRS_PTY_RLE_REL_PROV;
/

