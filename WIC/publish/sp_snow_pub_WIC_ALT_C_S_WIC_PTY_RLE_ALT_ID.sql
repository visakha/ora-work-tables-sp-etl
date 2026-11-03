-- ============================================================================
-- sp_snow_pub_WIC_ALT_C_S_WIC_PTY_RLE_ALT_ID  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (WIC)
--
-- Mapping: m_Tgt_C_S_WIC_Pty_Rle_Alt_Id, workflow wf_WIC_Stage_Load.
-- Publish branch STEP_NO 30, checkpoint STEP_NAME PUBLISH_C_S_WIC_PTY_RLE_ALT_ID.
-- Target: C_S_WIC_PTY_RLE_ALT_ID. Kind: SPINE (one alternate id per active party).
-- Branch in original order; WHERE guard: (unconditional).
--
-- INPUTS
--   Reads ONLY WRK_WIC_ALT_S20_READY (P_INPUT_TABLES default). This INSERT uses the run timestamp directly, so P_RUN_TS is used in the body (unlike most branch procs, where it is carried for a uniform driver call signature and is unused).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same columns, values and WHERE guard. No business expression, filter, guard or column list was changed.
--
-- FRAMEWORK RULE
--   NO transaction control and NO checkpoint calls in this proc. The driver calls it inside ONE publish transaction (all branches together, so a publish either lands completely or not at all), COMMITs, and only then checkpoints this branch. Never call a checkpoint between BEGIN TRANSACTION and COMMIT.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_WIC_ALT_C_S_WIC_PTY_RLE_ALT_ID (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_WIC_ALT_S20_READY') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    INSERT INTO C_S_WIC_PTY_RLE_ALT_ID
           (PKEY_SRC_OBJECT, SRC_ROWID, VERSION_SEQ, PTY_RLE_FK, ALT_ID_TP, ALT_ID_VAL, CREATE_DATE, LAST_UPDATE_DATE,
            ALT_ID_TP_FLTR, SRC_LAST_UPD_DT, STS_CD, PERIOD_START_DATE)
    SELECT x.pkey_src_object, NVL(TO_CHAR(x.ID), '') || '|' || x.alt_id_tp, 1 /* TIMELINE: VERSION_SEQ */,
           x.pty_rle_fk, x.alt_id_tp, LPAD(TO_CHAR(x.ID), 12, '0'), x.DATEKEY, P_RUN_TS, x.alt_id_tp,
           x.DATEKEY /* IIF(IsNull(DATEKEY), DATEKEY, DATEKEY) */, 'Issued', x.DATEKEY /* TIMELINE */
      FROM WRK_WIC_ALT_S20_READY x;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_WIC_ALT_C_S_WIC_PTY_RLE_ALT_ID;
/

