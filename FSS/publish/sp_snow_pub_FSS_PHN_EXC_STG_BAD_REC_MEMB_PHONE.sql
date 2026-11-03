-- ============================================================================
-- sp_snow_pub_FSS_PHN_EXC_STG_BAD_REC_MEMB_PHONE  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (FSS)
--
-- Mapping: m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr, workflow wf_FSS_Stage_Load.
-- Publish branch STEP_NO 80, checkpoint STEP_NAME PUBLISH_EXC_PHONE.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: EXCEPTION. Bad phones.
-- Branch 4 of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_FSS_PHN_S4_ROUTED (P_INPUT_TABLES default). The INSERT references neither original parameter nor the run timestamp directly, so P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same
--   columns, values and WHERE guard (grp_phone_bad AND uq_phone_exc). No business expression,
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
CREATE OR REPLACE FUNCTION sp_snow_pub_FSS_PHN_EXC_STG_BAD_REC_MEMB_PHONE (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_FSS_PHN_S4_ROUTED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, PRIMARY_PHONE, WORK_PHONE, SECONDARY_PHONE,
            MAPPING_NAME, SRC_SYS_ID_1, EXCEPTION_TYPE, PERIOD_START_DATE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME,
            SRC_SYS_ID_2)
    SELECT src_sys, phone_exception_code, phone_exception_desc, run_ts, NBR_PHONE, NULL, NULL,
           mapping_name, PTY_SRC_KEY, exc_type_rejected, DT_LAST_UPDATE, NBR_PHONE, attr_phone,
           ID_REGISTRATION_CLIENT
      FROM WRK_FSS_PHN_S4_ROUTED
     WHERE grp_phone_bad = 1 AND uq_phone_exc = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_FSS_PHN_EXC_STG_BAD_REC_MEMB_PHONE;
/

