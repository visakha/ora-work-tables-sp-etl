-- ============================================================================
-- sp_snow_pub_FSS_REL_EXC_STG_BAD_REC_MEMB  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (FSS)
--
-- Mapping: m_Tgt_C_S_FSS_Pty_Rle_Rel, workflow wf_FSS_Stage_Load.
-- Publish branch STEP_NO 60, checkpoint STEP_NAME PUBLISH_EXC.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: EXCEPTION. Untranslated relationships.
-- Branch 2 of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_FSS_REL_S4_FINAL (P_INPUT_TABLES default). The INSERT references neither original parameter nor the run timestamp directly, so P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same
--   columns, values and WHERE guard (mstr_ref_code IS NULL AND uq_rel_exc). No business expression,
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
CREATE OR REPLACE FUNCTION sp_snow_pub_FSS_REL_EXC_STG_BAD_REC_MEMB (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_FSS_REL_S4_FINAL') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, RUN_DATE, MAPPING_NAME, ATTRIBUTE_NAME, PERIOD_START_DATE,
            EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, ATTRIBUTE_VALUE, SRC_SYS_ID_3, GENDER)
    SELECT src_sys, RELN_ID_CLIENT, ID_CLIENT, run_ts, mapping_name, attr_relationship, RELN_DT_CREATED,
           exc_type, exc_code, exc_desc, relation_cd, ID_REGISTRATION, out_gender_cd
      FROM WRK_FSS_REL_S4_FINAL
     WHERE mstr_ref_code IS NULL AND uq_rel_exc = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_FSS_REL_EXC_STG_BAD_REC_MEMB;
/

