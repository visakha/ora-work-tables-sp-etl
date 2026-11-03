-- ============================================================================
-- sp_snow_pub_FSS_PTY_C_S_FSS_PTY  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (FSS)
--
-- Mapping: m_Tgt_C_S_FSS_Pty, workflow wf_FSS_Stage_Load.
-- Publish branch STEP_NO 50, checkpoint STEP_NAME PUBLISH_C_S_FSS_PTY.
-- Target: C_S_FSS_PTY. Kind: SPINE. Valid parties.
-- Branch 1 of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_FSS_PTY_S4_ROUTED (P_INPUT_TABLES default). The INSERT references neither original parameter nor the run timestamp directly, so P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same
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
CREATE OR REPLACE FUNCTION sp_snow_pub_FSS_PTY_C_S_FSS_PTY (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_FSS_PTY_S4_ROUTED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO C_S_FSS_PTY
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID,
            HUB_STATE_IND, PTY_BO_CLASS_CD, PRFX_NM, FRST_NM, MDL_NM, LST_NM, FULL_NM, GNDR_CD, BIRTH_DT,
            SRC_FULL_NM, ETHNCTY, SRC_ETHNCTY, RACE_CD, SRC_RACE_CD, SRC_LAST_UPD_DT, PRFRD_LANG_CD, SFX_NM)
    SELECT pkey_trim, DT_LAST_UPDATE, version_seq, run_ts, DT_LAST_UPDATE, pkey_trim, hub_state_ind,
           pty_bo_class_cd, std_prfx_name, std_first_name, std_mdl_name, std_lst_name, std_full_name,
           mdm_gender_code, DT_DOB, std_src_full_name, ethnicity_mstr, CD_HISPANIC, mdm_race_cd,
           src_race_ind_list, DT_LAST_UPDATE, language_mstr, std_suffix
      FROM WRK_FSS_PTY_S4_ROUTED
     WHERE uq_pty = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_FSS_PTY_C_S_FSS_PTY;
/

