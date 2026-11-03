-- ============================================================================
-- sp_snow_pub_TTF_ALT_C_S_TTF_PTY_RLE_ALT_ID  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TTF)
--
-- Mapping: m_Tgt_C_S_TTF_Pty_Rle_Alt_Id, workflow wf_TTF_Stage_Load.
-- Publish branch STEP_NO 30. Target: C_S_TTF_PTY_RLE_ALT_ID. Kind: SPINE (one alternate id per active client, type 024).
-- Branch 30 of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_TTF_ALT_S2_DEDUP (P_INPUT_TABLES default). It references the run timestamp (:P_RUN_TS).
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TTF_ALT_C_S_TTF_PTY_RLE_ALT_ID (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TTF_ALT_S2_DEDUP') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO C_S_TTF_PTY_RLE_ALT_ID
           (PKEY_SRC_OBJECT, HUB_STATE_IND, SRC_ROWID, LAST_UPDATE_DATE, VERSION_SEQ, CREATE_DATE, PTY_RLE_FK,
            ALT_ID_TP, ALT_ID_VAL, ALT_ID_TP_FLTR, STS_CD, PERIOD_START_DATE, SRC_LAST_UPD_DT)
    SELECT k.pkey_src_object, 1, k.pkey_src_object, P_RUN_TS, 1 /* TIMELINE: VERSION_SEQ */, k.SUBMITDATE,
           NVL(CASE WHEN k.PTY_SRC_KEY = 1 THEN 1 ELSE 0 END, '') || '|Member', '024', k.PTY_SRC_KEY, '024', 'Issued',
           P_RUN_TS /* TIMELINE: $sys.MappingRunStartTime */, k.SUBMITDATE
      FROM WRK_TTF_ALT_S2_DEDUP k;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TTF_ALT_C_S_TTF_PTY_RLE_ALT_ID;
/

