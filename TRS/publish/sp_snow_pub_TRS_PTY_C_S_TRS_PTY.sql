-- ============================================================================
-- sp_snow_pub_TRS_PTY_C_S_TRS_PTY  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_OnGoing, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 90, driver checkpoint STEP_NAME PUBLISH_C_S_TRS_PTY.
-- Target: C_S_TRS_PTY. Kind: SPINE (Valid parties).
--
-- INPUTS
--   Reads ONLY WRK_TRS_PTY_S4_DEDUP (P_INPUT_TABLES default). The INSERT below may use
--   :P_RUN_TS (run timestamp) and :c_mapping (local constant) where
--   the original INSERT used :l_run_ts / :c_mapping; it uses original
--   parameters: P_PTY_BO_CLASS_CD_MEMBER.
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_PTY_C_S_TRS_PTY (P_PTY_BO_CLASS_CD_MEMBER IN VARCHAR2 DEFAULT 'Indv', P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_PTY_S4_DEDUP') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO C_S_TRS_PTY
           (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, GNDR_CD, SFX_NM,
            PTY_BO_CLASS_CD, FRST_NM, PRFX_NM, LST_NM, MDL_NM, FULL_NM, BIRTH_DT, VERSION_SEQ,
            PERIOD_REFERENCE_TIME, TIMELINE_ACTION, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE, CREATOR,
            HUB_STATE_IND, FLAG_SRC, DEATH_DT, SRC_FULL_NM, PERIOD_START_DATE, PERIOD_END_DATE, SRC_LAST_UPD_DT,
            SRC_ROWID, RACE_CD, ETHNCTY, SRC_ETHNCTY, SRC_RACE_CD)
    SELECT pkey_trim, NULL, NULL, NULL, NULL, mdm_gender_code, std_sfx_name, P_PTY_BO_CLASS_CD_MEMBER,
           std_first_name, std_prfx_name, std_lst_name, std_mdl_name, std_full_name, std_birth_date,
           1, NULL, NULL, P_RUN_TS, NULL, NULL, NULL, NULL, NULL, DEATH_DT, src_full_name,
           CREATE_DT, NULL, CREATE_DT, pkey_trim, race_mstr, ethnicity_mstr, ETHNICITY_CD, RACE_CD
      FROM WRK_TRS_PTY_S4_DEDUP
     WHERE rn_pty = 1 AND uq_pty = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_PTY_C_S_TRS_PTY;
/

