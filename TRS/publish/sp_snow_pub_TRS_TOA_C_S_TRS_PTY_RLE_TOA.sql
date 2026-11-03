-- ============================================================================
-- sp_snow_pub_TRS_TOA_C_S_TRS_PTY_RLE_TOA  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_TOA, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 70, driver checkpoint STEP_NAME PUBLISH_C_S_TRS_PTY_RLE_TOA.
-- Target: C_S_TRS_PTY_RLE_TOA. Kind: SPINE (Valid TOA rows).
--
-- INPUTS
--   Reads ONLY WRK_TRS_TOA_S40_RANKED (P_INPUT_TABLES default). The INSERT below may use
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_TOA_C_S_TRS_PTY_RLE_TOA (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_TOA_S40_RANKED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO C_S_TRS_PTY_RLE_TOA
           (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE,
            PERIOD_END_DATE, VERSION_SEQ, PERIOD_REFERENCE_TIME, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE,
            CREATOR, SRC_ROWID, HUB_STATE_IND, TOA_SOURCE, TOA_FK, EFF_STRT_DT, EFF_END_DT, PTY_RLE_FK, EDG_NUM,
            CASE_NUM, SGMNT_KEY, CNVRT_DT, CNVRT_SYS_CD, INDV_ID, PRTCPNT_STS_CD, SRC_LAST_UPD_DT)
    SELECT pkey_src_object, NULL, NULL, NULL, NULL, BEGIN_DT, END_DT, VERSION_SEQ, NULL, run_ts, NULL,
           CREATE_DT, NULL, pkey_src_object, NULL, toa_source, toa_cd, BEGIN_DT, END_DT, pty_rle_fk, EDG_NUM,
           CASE_NUM, sgmnt_key, CONVERT_DT, SYSTEM_CD, PTY_PK, PART_STATUS_CD, CREATE_DT
      FROM WRK_TRS_TOA_S40_RANKED
     WHERE grp_bad_value = 0 AND grp_dates = 0 AND uq_toa = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_TOA_C_S_TRS_PTY_RLE_TOA;
/

