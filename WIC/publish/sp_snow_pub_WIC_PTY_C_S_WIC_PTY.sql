-- ============================================================================
-- sp_snow_pub_WIC_PTY_C_S_WIC_PTY  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (WIC)
--
-- Mapping: m_Tgt_C_S_WIC_Pty, workflow wf_WIC_Stage_Load.
-- Publish branch STEP_NO 50, checkpoint STEP_NAME PUBLISH_C_S_WIC_PTY.
-- Target: C_S_WIC_PTY. Kind: SPINE (valid parties).
-- Branch in original order; WHERE guard: uq_pty.
--
-- INPUTS
--   Reads ONLY WRK_WIC_PTY_S40_ROUTED (P_INPUT_TABLES default). The INSERT reads the run_ts / mapping_name columns materialised in the final step; it references neither original parameter nor the run timestamp directly, so P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same columns, values and WHERE guard. No business expression, filter, guard or column list was changed.
--
-- FRAMEWORK RULE
--   NO transaction control and NO checkpoint calls in this proc. The driver calls it inside ONE publish transaction (all branches together, so a publish either lands completely or not at all), COMMITs, and only then checkpoints this branch. Never call a checkpoint between BEGIN TRANSACTION and COMMIT.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_WIC_PTY_C_S_WIC_PTY (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_WIC_PTY_S40_ROUTED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    INSERT INTO C_S_WIC_PTY
           (PKEY_SRC_OBJECT, VERSION_SEQ, LAST_UPDATE_DATE, SRC_ROWID, HUB_STATE_IND, PTY_BO_CLASS_CD,
            BIRTH_WGHT_GRMS, PERIOD_START_DATE, CREATE_DATE, PRFX_NM, FRST_NM, MDL_NM, LST_NM, FULL_NM, GNDR_CD,
            BIRTH_DT, SRC_RACE_CD, RACE_CD, ETHNCTY, SRC_ETHNCTY, PRFRD_LANG_CD, SRC_LAST_UPD_DT,
            SRC_PRFRD_LANG_CD, SRC_FULL_NM)
    SELECT pkey_trim, version_seq, run_ts, pkey_trim, hub_state_ind, pty_bo_class_cd, birth_wght_grms,
           DATEKEY, DATEKEY, std_prfx_name, std_first_name, std_mdl_name, std_lst_name, std_full_name,
           mdm_gender_code, DOB, src_race_ind_list, mdm_race_cd, ethnicity_mstr, ETHNICITY, language_mstr,
           DATEKEY, LANGUAGE_CD, std_src_full_name
      FROM WRK_WIC_PTY_S40_ROUTED
     WHERE uq_pty = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_WIC_PTY_C_S_WIC_PTY;
/

