-- ============================================================================
-- sp_snow_pub_TRS_STGTOA_C_S_LU_TOA  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Stg_TOA, workflow wf_TRS_Stage_Load_TOA.
-- Publish branch STEP_NO 30, driver checkpoint STEP_NAME PUBLISH_C_S_LU_TOA.
-- Target: C_S_LU_TOA. Kind: STATUS (TOA catalogue survivors).
--
-- INPUTS
--   Reads ONLY WRK_TRS_LUTOA_S20_FINAL (P_INPUT_TABLES default). The INSERT below may use
--   :P_RUN_TS (run timestamp) and :c_mapping (local constant) where
--   the original INSERT used :l_run_ts / :c_mapping; it uses original
--   parameters: none.
--
-- BUSINESS SQL
--   The INSERT below is the current publish-branch INSERT verbatim:
--   same columns, values and WHERE guard. No business expression,
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_STGTOA_C_S_LU_TOA (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_LUTOA_S20_FINAL') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO C_S_LU_TOA
           (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE, PERIOD_END_DATE,
            VERSION_SEQ, PERIOD_REFERENCE_TIME, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE, CREATOR, SRC_ROWID,
            HUB_STATE_IND, TOA_CD, TOA_LBL, TOA_DESC, MBR_PRG_CD, EFF_STRT_DT, EFF_END_DT)
    SELECT pkey_src_object, NULL, NULL, NULL, NULL, NULL, NULL,
           1, NULL, P_RUN_TS, SUBSTR(UPDATE_USER_ID, 1, 50), CREATE_DT, 'admin', SUBSTR(pkey_src_object, 1, 30),
           1, pkey_src_object, SUBSTR(toa_lbl, 1, 100), SUBSTR(TOA_DESC, 1, 250), mbr_prg_cd, EFF_BEGIN_DT, EFF_END_DT
      FROM WRK_TRS_LUTOA_S20_FINAL;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_STGTOA_C_S_LU_TOA;
/

