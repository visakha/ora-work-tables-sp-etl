-- ============================================================================
-- sp_snow_pub_FSS_PHN_C_S_FSS_PTY_RLE_EADDR  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (FSS)
--
-- Mapping: m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr, workflow wf_FSS_Stage_Load.
-- Publish branch STEP_NO 50, checkpoint STEP_NAME PUBLISH_C_S_FSS_PTY_RLE_EADDR.
-- Target: C_S_FSS_PTY_RLE_EADDR. Kind: SPINE. Valid e-mails.
-- Branch 1 of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_FSS_PHN_S4_ROUTED (P_INPUT_TABLES default). The INSERT references neither original parameter nor the run timestamp directly, so P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same
--   columns, values and WHERE guard (grp_email_good AND uq_eaddr). No business expression,
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
CREATE OR REPLACE FUNCTION sp_snow_pub_FSS_PHN_C_S_FSS_PTY_RLE_EADDR (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_FSS_PHN_S4_ROUTED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO C_S_FSS_PTY_RLE_EADDR
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID,
            HUB_STATE_IND, PTY_RLE_FK, ADDR_TP, USG_TP, ELEC_ADDR, STS_CD, IS_VLD, SRC_LAST_UPD_DT)
    SELECT eaddr_pkey, DT_LAST_UPDATE, version_seq, run_ts, run_ts, eaddr_pkey, hub_state_ind, pty_rle_fk,
           eaddr_addr_tp, NULL, std_email, eaddr_sts_cd, eaddr_is_vld, DT_LAST_UPDATE
      FROM WRK_FSS_PHN_S4_ROUTED
     WHERE grp_email_good = 1 AND uq_eaddr = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_FSS_PHN_C_S_FSS_PTY_RLE_EADDR;
/

