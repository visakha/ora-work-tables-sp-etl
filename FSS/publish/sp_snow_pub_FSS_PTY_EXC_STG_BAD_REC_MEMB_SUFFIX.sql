-- ============================================================================
-- sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_SUFFIX  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (FSS)
--
-- Mapping: m_Tgt_C_S_FSS_Pty, workflow wf_FSS_Stage_Load.
-- Publish branch STEP_NO 120, checkpoint STEP_NAME PUBLISH_EXC_SUFFIX.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: EXCEPTION. Invalid suffix.
-- Branch 8 of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_FSS_PTY_S4_ROUTED (P_INPUT_TABLES default). The INSERT references neither original parameter nor the run timestamp directly, so P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same
--   columns, values and WHERE guard (grp_suffix AND uq_suffix). No business expression,
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
CREATE OR REPLACE FUNCTION sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_SUFFIX (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_FSS_PTY_S4_ROUTED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE,
            FIRST_NAME, MIDDLE_NAME, LAST_NAME, SUFFIX, ALIAS_SUFFIX, BIRTH_DATE, ATTRIBUTE_NAME,
            ATTRIBUTE_VALUE, MAPPING_NAME)
    SELECT src_sys, PTY_SRC_KEY, ID_CLIENT, suffix_exception_type, suffix_exception_code,
           suffix_exception_desc, run_ts, NM_FIRST, NM_MIDDLE, NM_LAST, CD_SUFFIX, std_suffix, DT_DOB,
           attr_suffix, CD_SUFFIX, mapping_name
      FROM WRK_FSS_PTY_S4_ROUTED
     WHERE grp_suffix = 1 AND uq_suffix = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_SUFFIX;
/

