-- ============================================================================
-- sp_snow_pub_CRE_CARE_C_S_CRE_PTY  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (CRE)
--
-- Mapping: m_Tgt_C_S_CRE_CARE_Clients, workflow wf_CRE_Stage_Load_Ongoing.
-- Publish branch STEP_NO 90, checkpoint STEP_NAME PUBLISH_C_S_CRE_PTY.
-- Target: C_S_CRE_PTY. Kind: SPINE (party spine itself).
-- Branch 60d of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_CRE_CARE_S5_KEYED (P_INPUT_TABLES default). The
--   INSERT reads the run_ts / mapping_name columns materialised in step
--   50; it references neither original parameter nor the run timestamp
--   directly, so P_RUN_TS is carried for a uniform driver call
--   signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch-60d INSERT verbatim: same
--   columns, values and WHERE guard (is_member AND uq_pty). No business expression,
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
CREATE OR REPLACE FUNCTION sp_snow_pub_CRE_CARE_C_S_CRE_PTY (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_CRE_CARE_S5_KEYED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    INSERT INTO C_S_CRE_PTY
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, PERIOD_END_DATE, VERSION_SEQ, PERIOD_REFERENCE_TIME,
            TIMELINE_ACTION, LAST_UPDATE_DATE, CREATE_DATE, SRC_ROWID, BIRTH_DT, FULL_NM, GNDR_CD, SFX_NM,
            LST_NM, FRST_NM, PTY_BO_CLASS_CD, SRC_FULL_NM, SRC_LAST_UPD_DT, ETHNCTY, RACE_CD, SRC_ETHNCTY,
            SRC_RACE_CD)
    SELECT pty_key, period_start, pty_period_end, version_seq_num, pty_period_reference_time,
           timeline_action, last_update, last_update, pty_key, BIRTH_DT, std_full_name, mdm_gender_code,
           std_sfx_name, std_lst_name, std_first_name, pty_bo_class_cd, std_src_full_name, src_last_update,
           ethnicity_mstr, race_mstr, FEDETH, RACE
      FROM WRK_CRE_CARE_S5_KEYED
     WHERE is_member = 1 AND uq_pty = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_CRE_CARE_C_S_CRE_PTY;
/

