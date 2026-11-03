-- ============================================================================
-- sp_snow_pub_ECI_PHN_C_S_ECI_PTY_RLE_EADDR  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI ONLY)
--
-- Mapping: m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr, workflow wf_ECI_Stage_Load.
-- Publish branch, STEP_NO 80: Good e-mails -> C_S_ECI_PTY_RLE_EADDR (the e-mail spine target).
-- Target: C_S_ECI_PTY_RLE_EADDR. Kind: SPINE.
--
-- WHAT THIS PROCEDURE IS
--   Exactly one branch of the original step-60 publish, re-housed
--   unchanged. The INSERT below is that branch's original INSERT
--   statement verbatim -- same columns, values and WHERE guards, reading
--   WRK_ECI_PHN_S50_READY. No business expression was changed. The
--   original publish had no :l_run_ts reference in its branches (run_ts
--   and mapping_name are columns of step 50), so P_RUN_TS is carried
--   for a uniform driver call shape but is not referenced by this INSERT.
--
-- FRAMEWORK RULE (read before changing anything)
--   NO transaction control and NO checkpoint calls in this procedure.
--   The driver owns the single publish transaction (BEGIN TRANSACTION
--   ... COMMIT around all branch calls) and checkpoints each branch
--   only AFTER COMMIT. A checkpoint written inside this procedure would
--   roll back with the publish transaction if a later branch failed.
--
-- P_INPUT_TABLES
--   Dependency declaration only: DEFAULT 'WRK_ECI_PHN_S50_READY'. The
--   driver passes the config-supplied consumed string for this branch;
--   the INSERT itself names the fixed work table literally (Snowflake
--   cannot parameterise table names in static SQL). No existence check
--   is performed here -- the step-50 existence check and the driver's
--   step gating cover the input; a missing S50 table surfaces as the
--   native error from the INSERT itself.
--
-- RETURN
--   SQLROWCOUNT from the INSERT, as NUMBER (captured into a local
--   variable first, mirroring the original main procedure's use of
--   SQLROWCOUNT after each INSERT).
--
-- SIGNATURE
--   P_JOB_RUN_ID   VARCHAR  (no default -- the driver always passes it)
--   P_RUN_TS       TIMESTAMP_NTZ
--   P_INPUT_TABLES VARCHAR DEFAULT 'WRK_ECI_PHN_S50_READY'
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_ECI_PHN_C_S_ECI_PTY_RLE_EADDR (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_PHN_S50_READY') RETURN NUMBER AUTHID CURRENT_USER AS
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr';
    l_rows NUMBER DEFAULT 0;
BEGIN
    INSERT INTO C_S_ECI_PTY_RLE_EADDR
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, PERIOD_REFERENCE_TIME, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID,
            PTY_RLE_FK, ELEC_ADDR, USG_TP, ADDR_TP, STS_CD, IS_VLD, SRC_LAST_UPD_DT, VERSION_SEQ, HUB_STATE_IND)
    SELECT pkey_src_object, PERIOD_START_DATE, NULL, run_ts, run_ts, pkey_src_object, pty_rle_fk,
           std_email, NULL, eaddr_addr_tp, eaddr_sts_cd, eaddr_is_vld, PERIOD_START_DATE, version_seq,
           hub_state_ind
      FROM WRK_ECI_PHN_S50_READY
     WHERE grp_email_good = 1 AND uq_eaddr = 1;
    l_rows := SQLROWCOUNT;
    RETURN l_rows;
END sp_snow_pub_ECI_PHN_C_S_ECI_PTY_RLE_EADDR;
/

