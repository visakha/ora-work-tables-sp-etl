-- ============================================================================
-- sp_snow_pub_TTF_PTY_C_S_TTF_PTY  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TTF)
--
-- Mapping: m_Tgt_C_S_TTF_Pty, workflow wf_TTF_Stage_Load.
-- Publish branch STEP_NO 50. Target: C_S_TTF_PTY. Kind: SPINE (valid parties).
-- Branch 50 of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_TTF_PTY_S4_ROUTED (P_INPUT_TABLES default). It references neither original parameter nor the run timestamp directly (it reads the run_ts / mapping_name columns materialised in the final routed table), so P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same
--   columns, values and WHERE guard. No business expression, filter,
--   guard or column list was changed.
--
-- FRAMEWORK RULE
--   NO transaction control and NO checkpoint calls in this proc. The
--   driver calls it inside ONE publish transaction (all branches
--   together, so a publish either lands completely or not at all),
--   COMMITs, and only then checkpoints this branch with the returned
--   row count. Never call a checkpoint between BEGIN TRANSACTION and
--   COMMIT.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_TTF_PTY_C_S_TTF_PTY (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TTF_PTY_S4_ROUTED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO C_S_TTF_PTY
           (PKEY_SRC_OBJECT, VERSION_SEQ, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID, HUB_STATE_IND,
            PTY_BO_CLASS_CD, PRFX_NM, FRST_NM, MDL_NM, LST_NM, FULL_NM, GNDR_CD, SRC_FULL_NM, ETHNCTY,
            SRC_ETHNCTY, RACE_CD, SRC_RACE_CD, SRC_LAST_UPD_DT, PRFRD_LANG_CD, SFX_NM, PERIOD_START_DATE,
            BIRTH_DT)
    SELECT pkey_trim, version_seq, run_ts, SUBMITDATE, pkey_trim, hub_state_ind, pty_bo_class_cd,
           std_prfx_name, std_first_name, std_mdl_name, std_lst_name, std_full_name, mdm_gender_code,
           std_src_full_name, ethnicity_mstr, ethnicity, race_mstr, RACEETHNICITYID, SUBMITDATE, NULL, NULL,
           run_ts, std_birth_date
      FROM WRK_TTF_PTY_S4_ROUTED
     WHERE uq_pty = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TTF_PTY_C_S_TTF_PTY;
/

