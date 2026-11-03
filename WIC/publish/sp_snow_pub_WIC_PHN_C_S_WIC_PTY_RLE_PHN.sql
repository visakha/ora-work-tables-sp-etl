-- ============================================================================
-- sp_snow_pub_WIC_PHN_C_S_WIC_PTY_RLE_PHN  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (WIC)
--
-- Mapping: m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr, workflow wf_WIC_Stage_Load.
-- Publish branch STEP_NO 50, checkpoint STEP_NAME PUBLISH_C_S_WIC_PTY_RLE_PHN.
-- Target: C_S_WIC_PTY_RLE_PHN. Kind: SPINE (good phones).
-- Branch in original order; WHERE guard: grp_phone_good AND uq_phn.
--
-- INPUTS
--   Reads ONLY WRK_WIC_PHN_S40_READY (P_INPUT_TABLES default). The INSERT reads the run_ts / mapping_name columns materialised in the final step; it references neither original parameter nor the run timestamp directly, so P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same columns, values and WHERE guard. No business expression, filter, guard or column list was changed.
--
-- FRAMEWORK RULE
--   NO transaction control and NO checkpoint calls in this proc. The driver calls it inside ONE publish transaction (all branches together, so a publish either lands completely or not at all), COMMITs, and only then checkpoints this branch. Never call a checkpoint between BEGIN TRANSACTION and COMMIT.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_WIC_PHN_C_S_WIC_PTY_RLE_PHN (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_WIC_PHN_S40_READY') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    INSERT INTO C_S_WIC_PTY_RLE_PHN
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, SRC_ROWID, PTY_RLE_FK, PHN_TP,
            USG_TP, PHN_NUM, PREF_LVL, SRC_LAST_UPD_DT, HUB_STATE_IND)
    SELECT phn_pkey, DATEKEY, version_seq, run_ts, phn_pkey, pty_rle_fk, phn_tp, usg_tp, std_phone, pref_lvl,
           DATEKEY, hub_state_ind
      FROM WRK_WIC_PHN_S40_READY
     WHERE grp_phone_good = 1 AND uq_phn = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_WIC_PHN_C_S_WIC_PTY_RLE_PHN;
/

