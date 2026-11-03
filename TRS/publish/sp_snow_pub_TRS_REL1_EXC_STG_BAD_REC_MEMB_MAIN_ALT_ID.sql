-- ============================================================================
-- sp_snow_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_MAIN_ALT_ID  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 70, driver checkpoint STEP_NAME PUBLISH_EXC_MAIN_ALT_ID.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: EXCEPTION (Invalid main alt id).
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_MAIN_ALT_ID (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_REL1_S3_ROUTER') RETURN NUMBER AUTHID CURRENT_USER AS
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem';
BEGIN
INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, RUN_DATE, MAPPING_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3, PERIOD_START_DATE,
            PERIOD_END_DATE, EXCEPTION_DESC, EXCEPTION_TYPE, EXCEPTION_CODE)
    SELECT 'TRS', P_RUN_TS, c_mapping, INDV_ID, REF_INDV_ID, rel_type_code, EFF_BEGIN_DT, EFF_END_DT,
           exc_member_desc, exc_member_type, exc_member_code
      FROM WRK_TRS_REL1_S3_ROUTER
     WHERE pty_rle_fk_1 IS NULL AND uq_exc_member = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_MAIN_ALT_ID;
/

