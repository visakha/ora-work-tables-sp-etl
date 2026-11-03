-- ============================================================================
-- sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_SSN  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (CRE)
--
-- Mapping: m_Tgt_C_S_CRE_CARE_Clients, workflow wf_CRE_Stage_Load_Ongoing.
-- Publish branch STEP_NO 220, checkpoint STEP_NAME PUBLISH_ALT_ID_SSN.
-- Target: C_S_CRE_PTY_RLE_ALT_ID. Kind: SPINE (party spine itself).
-- Branch 60q of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_CRE_CARE_S5_KEYED (P_INPUT_TABLES default). The
--   INSERT reads the run_ts / mapping_name columns materialised in step
--   50; it references neither original parameter nor the run timestamp
--   directly, so P_RUN_TS is carried for a uniform driver call
--   signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch-60q INSERT verbatim: same
--   columns, values and WHERE guard (grp_ssn_alt AND uq_ssn_alt). No business expression,
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
CREATE OR REPLACE FUNCTION sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_SSN (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_CRE_CARE_S5_KEYED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    INSERT INTO C_S_CRE_PTY_RLE_ALT_ID
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, PERIOD_END_DATE, VERSION_SEQ, PTY_RLE_FK, ALT_ID_TP, ALT_ID_VAL,
            ALT_ID_TP_FLTR, STS_CD, SRC_ROWID, SRC_LAST_UPD_DT, LAST_UPDATE_DATE, PERIOD_REFERENCE_TIME,
            TIMELINE_ACTION)
    SELECT ssn_alt_key, period_start, period_end, version_seq_num, rle_key, ssn_tp_cd, ssn_out, ssn_tp_cd,
           sts_cd, ssn_alt_src_rowid, CARE_LASTUP_DT, last_update, null_timestamp, null_number
      FROM WRK_CRE_CARE_S5_KEYED
     WHERE grp_ssn_alt = 1 AND uq_ssn_alt = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_SSN;
/

