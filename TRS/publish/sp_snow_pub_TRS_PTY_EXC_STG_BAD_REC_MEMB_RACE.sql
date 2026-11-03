-- ============================================================================
-- sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_RACE  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_OnGoing, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 120, driver checkpoint STEP_NAME PUBLISH_EXC_RACE.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: EXCEPTION (Race exceptions).
--
-- INPUTS
--   Reads ONLY WRK_TRS_PTY_S4_DEDUP (P_INPUT_TABLES default). The INSERT below may use
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_RACE (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_PTY_S4_DEDUP') RETURN NUMBER AUTHID CURRENT_USER AS
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_OnGoing';
BEGIN
INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_TYPE, EXCEPTION_DESC, EXCEPTION_CODE, ATTRIBUTE_NAME,
            ATTRIBUTE_VALUE, DEATH_DT, GENDER, BIRTH_DATE, MIDDLE_NAME, LAST_NAME, PREFIX, FIRST_NAME, SUFFIX,
            PERIOD_START_DATE, RUN_DATE, MAPPING_NAME)
    SELECT 'TRS', pkey_trim, race_exception_type, race_exception_desc, race_exception_code, 'Race_Cd',
           race_mstr, DEATH_DT, mdm_gender_code, std_birth_date, std_mdl_name, std_lst_name, std_prfx_name,
           std_first_name, std_sfx_name, CREATE_DT, P_RUN_TS, c_mapping
      FROM WRK_TRS_PTY_S4_DEDUP
     WHERE race_exception_code IS NOT NULL AND uq_exc_race = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_RACE;
/

