-- ============================================================================
-- sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_PHN  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (CRE)
--
-- Mapping: m_Tgt_C_S_CRE_CARE_Clients, workflow wf_CRE_Stage_Load_Ongoing.
-- Publish branch STEP_NO 170, checkpoint STEP_NAME PUBLISH_C_S_CRE_PTY_RLE_PHN.
-- Target: C_S_CRE_PTY_RLE_PHN. Kind: SPINE (party spine itself).
-- Branch 60l of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_CRE_CARE_S5_KEYED (P_INPUT_TABLES default). The
--   INSERT reads the run_ts / mapping_name columns materialised in step
--   50; it references neither original parameter nor the run timestamp
--   directly, so P_RUN_TS is carried for a uniform driver call
--   signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch-60l INSERT verbatim: same
--   columns, values and WHERE guard (grp_phone AND uq_phone). No business expression,
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
CREATE OR REPLACE FUNCTION sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_PHN (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_CRE_CARE_S5_KEYED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    INSERT INTO C_S_CRE_PTY_RLE_PHN
           (PKEY_SRC_OBJECT, SRC_ROWID, PHN_NUM, VERSION_SEQ, LAST_UPDATE_DATE, PHN_TP, PTY_RLE_FK, USG_TP,
            PREF_LVL, PERIOD_START_DATE, PERIOD_END_DATE, TIMELINE_ACTION, PERIOD_REFERENCE_TIME, CREATE_DATE,
            SRC_LAST_UPD_DT)
    SELECT phn_key, phn_src_rowid, phone_std, version_seq_num, last_update, phn_tp, member_rle_fk,
           usg_tp_phone, pref_lvl, period_start, period_end, timeline_action, period_reference_time,
           last_update, CARE_LASTUP_DT
      FROM WRK_CRE_CARE_S5_KEYED
     WHERE grp_phone = 1 AND uq_phone = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_PHN;
/

