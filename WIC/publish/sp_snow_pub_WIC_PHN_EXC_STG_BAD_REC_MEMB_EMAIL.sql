-- ============================================================================
-- sp_snow_pub_WIC_PHN_EXC_STG_BAD_REC_MEMB_EMAIL  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (WIC)
--
-- Mapping: m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr, workflow wf_WIC_Stage_Load.
-- Publish branch STEP_NO 80, checkpoint STEP_NAME PUBLISH_EXC_STG_BAD_REC_MEMB_EMAIL.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: EXCEPTION (bad-e-mail exceptions).
-- Branch in original order; WHERE guard: grp_email_bad AND uq_email_exc.
--
-- INPUTS
--   Reads ONLY WRK_WIC_PHN_S40_READY (P_INPUT_TABLES default). The INSERT reads the run_ts / mapping_name columns materialised in the final step; it references neither original parameter nor the run timestamp directly, so P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same columns, values and WHERE guard. No business expression, filter, guard or column list was changed.
--
-- FRAMEWORK RULE
--   NO transaction control and NO checkpoint calls in this proc. The driver calls it inside ONE publish transaction (all branches together, so a publish either lands completely or not at all), COMMITs, and only then checkpoints this branch. Never call a checkpoint between BEGIN TRANSACTION and COMMIT.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_WIC_PHN_EXC_STG_BAD_REC_MEMB_EMAIL (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_WIC_PHN_S40_READY') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, EMAIL, MAPPING_NAME, EXCEPTION_TYPE,
            PERIOD_START_DATE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2)
    SELECT src_sys, email_exception_code, email_exception_desc, run_ts, EMAIL, mapping_name,
           email_exception_type, DATEKEY, EMAIL, attr_email, PTY_SRC_KEY, FID
      FROM WRK_WIC_PHN_S40_READY
     WHERE grp_email_bad = 1 AND uq_email_exc = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_WIC_PHN_EXC_STG_BAD_REC_MEMB_EMAIL;
/

