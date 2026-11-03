-- ============================================================================
-- sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_FIRST_NAME  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (CRE)
--
-- Mapping: m_Tgt_C_S_CRE_CARE_Clients, workflow wf_CRE_Stage_Load_Ongoing.
-- Publish branch STEP_NO 70, checkpoint STEP_NAME PUBLISH_EXC_FIRST_NAME.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: NON-SPINE (exception log only; the member itself is still loaded unless the member itself is invalid).
-- Branch 60b of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_CRE_CARE_S5_KEYED (P_INPUT_TABLES default). The
--   INSERT reads the run_ts / mapping_name columns materialised in step
--   50; it references neither original parameter nor the run timestamp
--   directly, so P_RUN_TS is carried for a uniform driver call
--   signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch-60b INSERT verbatim: same
--   columns, values and WHERE guard (grp_first_name AND uq_first_name). No business expression,
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
CREATE OR REPLACE FUNCTION sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_FIRST_NAME (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_CRE_CARE_S5_KEYED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS_ID_1, RUN_DATE, MAPPING_NAME, FIRST_NAME, LAST_NAME, ATTRIBUTE_NAME, GENDER, BIRTH_DATE,
            SUFFIX, SRC_SYS, ATTRIBUTE_VALUE, EXCEPTION_TYPE, EXCEPTION_DESC, EXCEPTION_CODE)
    SELECT CARE_ID, run_ts, mapping_name, std_first_name, std_lst_name, attr_first_name, SEX, BIRTH_DT,
           std_sfx_name, src_sys, FIRSTNM, fn_exception_type, fn_exception_desc, fn_exception_code
      FROM WRK_CRE_CARE_S5_KEYED
     WHERE grp_first_name = 1 AND uq_first_name = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_FIRST_NAME;
/

