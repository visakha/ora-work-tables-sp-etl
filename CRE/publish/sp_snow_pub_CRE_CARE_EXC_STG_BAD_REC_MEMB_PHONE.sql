-- ============================================================================
-- sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_PHONE  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (CRE)
--
-- Mapping: m_Tgt_C_S_CRE_CARE_Clients, workflow wf_CRE_Stage_Load_Ongoing.
-- Publish branch STEP_NO 180, checkpoint STEP_NAME PUBLISH_EXC_PHONE.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: NON-SPINE (exception log only; the member itself is still loaded unless the member itself is invalid).
-- Branch 60m of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_CRE_CARE_S5_KEYED (P_INPUT_TABLES default). The
--   INSERT reads the run_ts / mapping_name columns materialised in step
--   50; it references neither original parameter nor the run timestamp
--   directly, so P_RUN_TS is carried for a uniform driver call
--   signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch-60m INSERT verbatim: same
--   columns, values and WHERE guard (grp_phone_exc). No business expression,
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
CREATE OR REPLACE FUNCTION sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_PHONE (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_CRE_CARE_S5_KEYED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, PRIMARY_PHONE, MAPPING_NAME, RUN_DATE, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, SRC_SYS_ID_1,
            EXCEPTION_CODE, EXCEPTION_TYPE, EXCEPTION_DESC)
    SELECT src_sys, phone_std, mapping_name, run_ts, attr_phone, phone_std, CARE_ID, phone_exception_code,
           phone_exception_type, phone_exception_desc
      FROM WRK_CRE_CARE_S5_KEYED
     WHERE grp_phone_exc = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_PHONE;
/

