-- ============================================================================
-- sp_snow_pub_FSS_REL_C_S_FSS_PTY_RLE_REL  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (FSS)
--
-- Mapping: m_Tgt_C_S_FSS_Pty_Rle_Rel, workflow wf_FSS_Stage_Load.
-- Publish branch STEP_NO 50, checkpoint STEP_NAME PUBLISH_C_S_FSS_PTY_RLE_REL.
-- Target: C_S_FSS_PTY_RLE_REL. Kind: SPINE. Valid relationships.
-- Branch 1 of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_FSS_REL_S4_FINAL (P_INPUT_TABLES default). The INSERT references neither original parameter nor the run timestamp directly, so P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same
--   columns, values and WHERE guard (mstr_ref_code IS NOT NULL AND uq_rel). No business expression,
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
CREATE OR REPLACE FUNCTION sp_snow_pub_FSS_REL_C_S_FSS_PTY_RLE_REL (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_FSS_REL_S4_FINAL') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO C_S_FSS_PTY_RLE_REL
           (REL_TP, VERSION_SEQ, HUB_STATE_IND, REL_TYPE_CODE, HIERARCHY_CODE, UPDATED_BY, LAST_UPDATE_DATE,
            PERIOD_START_DATE, PKEY_SRC_OBJECT, PTY_RLE_FK_1, PTY_RLE_FK_2, SRC_LAST_UPD_DT, CREATOR, SRC_ROWID,
            CREATE_DATE)
    SELECT mstr_ref_code, version_seq, hub_state_ind, rel_type_code, hierarchy_code, batch_user, run_ts,
           RELN_DT_CREATED, rel_pkey, rel_fk_1, rel_fk_2, RELN_DT_LAST_UPDATE, batch_user, rel_pkey,
           RELN_DT_LAST_UPDATE
      FROM WRK_FSS_REL_S4_FINAL
     WHERE mstr_ref_code IS NOT NULL AND uq_rel = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_FSS_REL_C_S_FSS_PTY_RLE_REL;
/

