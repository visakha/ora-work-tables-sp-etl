-- ============================================================================
-- sp_snow_pub_FSS_PTY_C_S_FSS_PTY_RLE  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (FSS)
--
-- Mapping: m_Tgt_C_S_FSS_Pty, workflow wf_FSS_Stage_Load.
-- Publish branch STEP_NO 60, checkpoint STEP_NAME PUBLISH_C_S_FSS_PTY_RLE.
-- Target: C_S_FSS_PTY_RLE. Kind: SPINE. Valid roles.
-- Branch 2 of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_FSS_PTY_S4_ROUTED (P_INPUT_TABLES default). The INSERT references neither original parameter nor the run timestamp directly, so P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same
--   columns, values and WHERE guard (uq_rle). No business expression,
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
CREATE OR REPLACE FUNCTION sp_snow_pub_FSS_PTY_C_S_FSS_PTY_RLE (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_FSS_PTY_S4_ROUTED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO C_S_FSS_PTY_RLE
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID,
            HUB_STATE_IND, PTY_FK, RLE_BO_CLASS_CD, SRC_LAST_UPD_DT)
    SELECT rle_pkey, DT_LAST_UPDATE, version_seq, run_ts, DT_LAST_UPDATE, rle_pkey, hub_state_ind, pkey_trim,
           rle_bo_class_cd, DT_LAST_UPDATE
      FROM WRK_FSS_PTY_S4_ROUTED
     WHERE uq_rle = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_FSS_PTY_C_S_FSS_PTY_RLE;
/

