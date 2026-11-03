-- ============================================================================
-- sp_snow_pub_TRS_REL1_C_S_TRS_PTY_RLE_REL  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 110, driver checkpoint STEP_NAME PUBLISH_C_S_TRS_PTY_RLE_REL.
-- Target: C_S_TRS_PTY_RLE_REL. Kind: SPINE (Valid relationships).
--
-- INPUTS
--   Reads ONLY WRK_TRS_REL1_S6_TIMELINE (P_INPUT_TABLES default). The INSERT below may use
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_REL1_C_S_TRS_PTY_RLE_REL (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_REL1_S6_TIMELINE') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO C_S_TRS_PTY_RLE_REL
           (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE,
            PERIOD_END_DATE, VERSION_SEQ, PERIOD_REFERENCE_TIME, TIMELINE_ACTION, LAST_UPDATE_DATE, UPDATED_BY,
            CREATE_DATE, CREATOR, SRC_ROWID, HUB_STATE_IND, PTY_RLE_FK_1, PTY_RLE_FK_2, REL_TYPE_CODE,
            HIERARCHY_CODE, REL_TP, SRC_LAST_UPD_DT)
    SELECT pkey_src_object, NULL, NULL, NULL, NULL, EFF_BEGIN_DT, tl_period_end_date, tl_version_seq,
           tl_period_end_date, tl_timeline_action, P_RUN_TS, NULL, CREATE_DT, NULL, pkey_src_object,
           tl_hub_state_ind, pty_rle_fk_1, pty_rle_fk_2, rel_type_code_label, hierarchy_code, rel_type_code,
           src_last_upd_dt
      FROM WRK_TRS_REL1_S6_TIMELINE
     WHERE uq_rel = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_REL1_C_S_TRS_PTY_RLE_REL;
/

