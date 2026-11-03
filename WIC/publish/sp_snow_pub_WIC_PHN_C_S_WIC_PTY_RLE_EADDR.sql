-- ============================================================================
-- sp_snow_pub_WIC_PHN_C_S_WIC_PTY_RLE_EADDR  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (WIC)
--
-- Mapping: m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr, workflow wf_WIC_Stage_Load.
-- Publish branch STEP_NO 70, checkpoint STEP_NAME PUBLISH_C_S_WIC_PTY_RLE_EADDR.
-- Target: C_S_WIC_PTY_RLE_EADDR. Kind: SPINE (valid e-mails).
-- Branch in original order; WHERE guard: grp_email_good AND uq_eaddr.
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
CREATE OR REPLACE FUNCTION sp_snow_pub_WIC_PHN_C_S_WIC_PTY_RLE_EADDR (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_WIC_PHN_S40_READY') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    INSERT INTO C_S_WIC_PTY_RLE_EADDR
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID,
            HUB_STATE_IND, PTY_RLE_FK, ELEC_ADDR, USG_TP, STS_CD, IS_VLD, SRC_LAST_UPD_DT, ADDR_TP)
    SELECT eaddr_pkey, DATEKEY, version_seq, run_ts, run_ts, eaddr_pkey, hub_state_ind, pty_rle_fk,
           std_email, NULL, eaddr_sts_cd, eaddr_is_vld, DATEKEY, eaddr_addr_tp
      FROM WRK_WIC_PHN_S40_READY
     WHERE grp_email_good = 1 AND uq_eaddr = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_WIC_PHN_C_S_WIC_PTY_RLE_EADDR;
/

