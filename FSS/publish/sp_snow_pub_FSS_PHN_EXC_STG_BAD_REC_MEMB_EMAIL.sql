-- ============================================================================
-- sp_snow_pub_FSS_PHN_EXC_STG_BAD_REC_MEMB_EMAIL  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (FSS)
--
-- Mapping: m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr, workflow wf_FSS_Stage_Load.
-- Publish branch STEP_NO 60, checkpoint STEP_NAME PUBLISH_EXC_EMAIL.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: EXCEPTION. Bad e-mails.
-- Branch 2 of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_FSS_PHN_S4_ROUTED (P_INPUT_TABLES default). The INSERT references neither original parameter nor the run timestamp directly, so P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same
--   columns, values and WHERE guard (grp_email_bad AND uq_email_exc). No business expression,
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
CREATE OR REPLACE FUNCTION sp_snow_pub_FSS_PHN_EXC_STG_BAD_REC_MEMB_EMAIL (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_FSS_PHN_S4_ROUTED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, EMAIL, MAPPING_NAME, EXCEPTION_TYPE,
            PERIOD_START_DATE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2)
    SELECT src_sys, email_exception_code, email_exception_desc, run_ts, ADDR_EMAIL, mapping_name,
           email_exception_type, DT_LAST_UPDATE, ADDR_EMAIL, attr_email, PTY_SRC_KEY, ID_REGISTRATION_CLIENT
      FROM WRK_FSS_PHN_S4_ROUTED
     WHERE grp_email_bad = 1 AND uq_email_exc = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_FSS_PHN_EXC_STG_BAD_REC_MEMB_EMAIL;
/

