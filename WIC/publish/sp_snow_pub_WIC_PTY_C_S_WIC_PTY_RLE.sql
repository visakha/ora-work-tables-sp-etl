-- ============================================================================
-- sp_snow_pub_WIC_PTY_C_S_WIC_PTY_RLE  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (WIC)
--
-- Mapping: m_Tgt_C_S_WIC_Pty, workflow wf_WIC_Stage_Load.
-- Publish branch STEP_NO 60, checkpoint STEP_NAME PUBLISH_C_S_WIC_PTY_RLE.
-- Target: C_S_WIC_PTY_RLE. Kind: SPINE (valid roles).
-- Branch in original order; WHERE guard: uq_rle.
--
-- INPUTS
--   Reads ONLY WRK_WIC_PTY_S40_ROUTED (P_INPUT_TABLES default). The INSERT reads the run_ts / mapping_name columns materialised in the final step; it references neither original parameter nor the run timestamp directly, so P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same columns, values and WHERE guard. No business expression, filter, guard or column list was changed.
--
-- FRAMEWORK RULE
--   NO transaction control and NO checkpoint calls in this proc. The driver calls it inside ONE publish transaction (all branches together, so a publish either lands completely or not at all), COMMITs, and only then checkpoints this branch. Never call a checkpoint between BEGIN TRANSACTION and COMMIT.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_WIC_PTY_C_S_WIC_PTY_RLE (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_WIC_PTY_S40_ROUTED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    INSERT INTO C_S_WIC_PTY_RLE
           (PKEY_SRC_OBJECT, SRC_ROWID, RLE_BO_CLASS_CD, PTY_FK, VERSION_SEQ, LAST_UPDATE_DATE, HUB_STATE_IND,
            CREATE_DATE, PERIOD_START_DATE, SRC_LAST_UPD_DT)
    SELECT rle_pkey, rle_pkey, rle_bo_class_cd, pkey_trim, version_seq, run_ts, hub_state_ind, DATEKEY,
           DATEKEY, DATEKEY
      FROM WRK_WIC_PTY_S40_ROUTED
     WHERE uq_rle = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_WIC_PTY_C_S_WIC_PTY_RLE;
/

