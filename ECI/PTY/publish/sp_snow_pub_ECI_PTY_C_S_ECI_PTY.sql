-- ============================================================================
-- sp_snow_pub_ECI_PTY_C_S_ECI_PTY  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI)
--
-- Mapping: m_Tgt_C_S_ECI_Pty, workflow wf_ECI_Stage_Load.
-- Publish branch STEP_NO 60, checkpoint STEP_NAME PUBLISH_C_S_ECI_PTY.
-- Target: C_S_ECI_PTY. Kind: SPINE (valid parties).
-- Branch 60a of the original publish, in original order (first).
--
-- INPUTS
--   Reads ONLY WRK_ECI_PTY_S50_READY (P_INPUT_TABLES default). The
--   INSERT reads the run_ts / exc_mapping columns materialised in step
--   50; it references neither original parameter nor the run timestamp
--   directly, so P_RUN_TS is carried for a uniform driver call
--   signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch-60a INSERT verbatim: same
--   columns, values and WHERE guard (uq_pty). No business expression,
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
CREATE OR REPLACE FUNCTION sp_snow_pub_ECI_PTY_C_S_ECI_PTY (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_PTY_S50_READY') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    INSERT INTO C_S_ECI_PTY
           (PKEY_SRC_OBJECT, VERSION_SEQ, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE, CREATOR, SRC_ROWID,
            PTY_BO_CLASS_CD, PRFX_NM, FULL_NM, LST_NM, MDL_NM, FRST_NM, GNDR_CD, BIRTH_DT, SRC_FULL_NM,
            SRC_LAST_UPD_DT, BIRTH_WGHT_GRMS, HUB_STATE_IND, SRC_ETHNCTY, ETHNCTY, RACE_CD, PRFRD_LANG_CD,
            SRC_PRFRD_LANG_CD, SRC_RACE_CD, PERIOD_START_DATE)
    SELECT pkey_trim, version_seq, run_ts, MODIFIED_BY, DATE_CREATED, CREATED_BY, pkey_trim,
           pty_bo_class_cd, std_prfx_name, std_full_name, std_lst_name, std_mdl_name, std_first_name,
           mdm_gender_code, std_birth_date, std_src_full_name, DATE_MODIFIED, birth_wght_grms,
           hub_state_ind, ETHNICITY, ethnicity_mstr, mdm_race_cd, language_mstr, LANGUAGE_CD,
           src_race_ind_list, DATE_MODIFIED
      FROM WRK_ECI_PTY_S50_READY
     WHERE uq_pty = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_ECI_PTY_C_S_ECI_PTY;
/

