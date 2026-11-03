-- ============================================================================
-- sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_SUFFIX  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (CRE)
--
-- Mapping: m_Tgt_C_S_CRE_CARE_Clients, workflow wf_CRE_Stage_Load_Ongoing.
-- Publish branch STEP_NO 120, checkpoint STEP_NAME PUBLISH_EXC_SUFFIX.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: NON-SPINE (exception log only; the member itself is still loaded unless the member itself is invalid).
-- Branch 60g of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_CRE_CARE_S5_KEYED (P_INPUT_TABLES default). The
--   INSERT reads the run_ts / mapping_name columns materialised in step
--   50; it references neither original parameter nor the run timestamp
--   directly, so P_RUN_TS is carried for a uniform driver call
--   signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch-60g INSERT verbatim: same
--   columns, values and WHERE guard (grp_suffix). No business expression,
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
CREATE OR REPLACE FUNCTION sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_SUFFIX (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_CRE_CARE_S5_KEYED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, ATTRIBUTE_NAME,
            ATTRIBUTE_VALUE, MAPPING_NAME)
    SELECT src_sys, CARE_ID, suffix_exception_type, suffix_exception_code, suffix_exception_desc, run_ts,
           attr_suffix, src_suffix, mapping_name
      FROM WRK_CRE_CARE_S5_KEYED
     WHERE grp_suffix = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_SUFFIX;
/

