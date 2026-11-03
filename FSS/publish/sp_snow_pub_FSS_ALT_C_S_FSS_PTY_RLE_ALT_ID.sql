-- ============================================================================
-- sp_snow_pub_FSS_ALT_C_S_FSS_PTY_RLE_ALT_ID  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (FSS)
--
-- Mapping: m_Tgt_C_S_FSS_Pty_Rle_Alt_Id, workflow wf_FSS_Stage_Load.
-- Publish branch STEP_NO 50, checkpoint STEP_NAME PUBLISH_C_S_FSS_PTY_RLE_ALT_ID.
-- Target: C_S_FSS_PTY_RLE_ALT_ID. Kind: SPINE. Valid alternate IDs.
-- Branch 1 of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_FSS_ALT_S2_FILTERED (P_INPUT_TABLES default). The INSERT references the run timestamp directly, so P_RUN_TS is used in the body (substituted from :l_run_ts).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same
--   columns, values and WHERE guard (no WHERE guard (filtered rows only)). No business expression,
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
CREATE OR REPLACE FUNCTION sp_snow_pub_FSS_ALT_C_S_FSS_PTY_RLE_ALT_ID (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_FSS_ALT_S2_FILTERED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO C_S_FSS_PTY_RLE_ALT_ID
           (PKEY_SRC_OBJECT, PTY_RLE_FK, ALT_ID_TP, ALT_ID_VAL, SRC_LAST_UPD_DT, HUB_STATE_IND, STS_CD, SRC_ROWID,
            LAST_UPDATE_DATE, VERSION_SEQ, ALT_ID_TP_FLTR, CREATE_DATE, PERIOD_START_DATE)
    SELECT x.pkey_src_object, x.pty_rle_fk, x.alt_id_tp, LPAD(TO_CHAR(x.ID_CLIENT), 10, '0'), P_RUN_TS, 1,
           'Issued', NVL(TO_CHAR(x.ID_CLIENT), '') || '|' || x.alt_id_tp, P_RUN_TS,
           1 /* TIMELINE: VERSION_SEQ */, x.alt_id_tp, x.DT_CREATED, x.DT_CREATED /* TIMELINE */
      FROM WRK_FSS_ALT_S2_FILTERED x;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_FSS_ALT_C_S_FSS_PTY_RLE_ALT_ID;
/

