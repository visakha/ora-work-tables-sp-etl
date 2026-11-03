-- ============================================================================
-- sp_snow_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_LOOKUP  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 90, driver checkpoint STEP_NAME PUBLISH_EXC_LOOKUP.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: EXCEPTION (Invalid lookup).
--
-- INPUTS
--   Reads ONLY WRK_TRS_REL1_S3_ROUTER (P_INPUT_TABLES default). The INSERT below may use
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_LOOKUP (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_REL1_S3_ROUTER') RETURN NUMBER AUTHID CURRENT_USER AS
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem';
BEGIN
INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, MAPPING_NAME, RUN_DATE, SRC_SYS_ID_3, ATTRIBUTE_VALUE,
            ATTRIBUTE_NAME, PERIOD_START_DATE, PERIOD_END_DATE, EXCEPTION_TYPE, EXCEPTION_DESC, EXCEPTION_CODE)
    SELECT 'TRS', INDV_ID, REF_INDV_ID, c_mapping, P_RUN_TS, RELATIONSHIP_TYPE_CD, RELATIONSHIP_TYPE_CD,
           attr_rel_type, EFF_BEGIN_DT, EFF_END_DT, exc_type_type, exc_type_desc, exc_type_lkp_code
      FROM WRK_TRS_REL1_S3_ROUTER
     WHERE rel_type_code IS NULL AND uq_exc_type = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_LOOKUP;
/

