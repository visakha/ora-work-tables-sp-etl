-- ============================================================================
-- sp_snow_pub_TRS_NM_C_S_TRS_PTY_NM  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Nm, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 50, driver checkpoint STEP_NAME PUBLISH_C_S_TRS_PTY_NM.
-- Target: C_S_TRS_PTY_NM. Kind: SPINE (Alias names).
--
-- INPUTS
--   Reads ONLY WRK_TRS_NM_S40_DEDUP (P_INPUT_TABLES default). The INSERT below may use
--   :P_RUN_TS (run timestamp) and :c_mapping (local constant) where
--   the original INSERT used :l_run_ts / :c_mapping; it uses original
--   parameters: P_MEMBER_NAME_TYPE_CODE.
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_NM_C_S_TRS_PTY_NM (P_MEMBER_NAME_TYPE_CODE IN VARCHAR2 DEFAULT '002', P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_NM_S40_DEDUP') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO C_S_TRS_PTY_NM
           (PTY_FK, SFX_NM, FRST_NM, PFX_NM, LST_NM, MDL_NM, FULL_NM, VERSION_SEQ, LAST_UPDATE_DATE, NM_TP, SRC_ROWID,
            ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_END_DATE, PERIOD_REFERENCE_TIME, UPDATED_BY,
            CREATE_DATE, CREATOR, HUB_STATE_IND, SRC_FULL_NM, SRC_LAST_UPD_DT, PKEY_SRC_OBJECT, PERIOD_START_DATE)
    SELECT * FROM (SELECT d.PKEY_PTY, d.sfx_nm, d.frst_nm, d.prfx_nm, d.lst_nm, d.mdl_nm, d.full_nm,
           1, P_RUN_TS, P_MEMBER_NAME_TYPE_CODE, d.pkey_src_object,
           NULL, NULL, NULL, NULL, NULL, NULL, NULL, d.CREATE_DT, NULL,
           NULL, d.src_full_name, d.CREATE_DT, d.pkey_src_object,
           d.CREATE_DT
      , ROW_NUMBER() OVER (PARTITION BY d.pkey_src_object ORDER BY d.CREATE_DT DESC NULLS LAST, d.full_nm) AS __qual_rn FROM WRK_TRS_NM_S40_DEDUP d
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TRS_PTY_NM WHERE VERSION_SEQ = 1) xn
             ON xn.PKEY_SRC_OBJECT = d.pkey_src_object
     WHERE xn.PKEY_SRC_OBJECT IS NULL) WHERE __qual_rn = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_NM_C_S_TRS_PTY_NM;
/

