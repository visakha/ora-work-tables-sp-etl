-- ============================================================================
-- sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (FSS)
--
-- Mapping: m_Tgt_C_S_FSS_Pty, workflow wf_FSS_Stage_Load.
-- Publish branch STEP_NO 110, checkpoint STEP_NAME PUBLISH_EXC_LANGUAGE.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: EXCEPTION. Invalid language.
-- Branch 7 of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_FSS_PTY_S4_ROUTED (P_INPUT_TABLES default). The INSERT references neither original parameter nor the run timestamp directly, so P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same
--   columns, values and WHERE guard (grp_language AND uq_language). No business expression,
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
CREATE OR REPLACE FUNCTION sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_FSS_PTY_S4_ROUTED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE,
            FIRST_NAME, MIDDLE_NAME, LAST_NAME, BIRTH_DATE, GENDER, ATTRIBUTE_NAME, ATTRIBUTE_VALUE,
            MAPPING_NAME, PERIOD_START_DATE)
    SELECT src_sys, PTY_SRC_KEY, ID_CLIENT, language_exception_type, language_exception_code,
           language_exception_desc, run_ts, NM_FIRST, std_mdl_name, std_lst_name, std_birth_date,
           CD_GENDER, attr_language, LANGUAGE_CD, mapping_name, DT_LAST_UPDATE
      FROM WRK_FSS_PTY_S4_ROUTED
     WHERE grp_language = 1 AND uq_language = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE;
/

