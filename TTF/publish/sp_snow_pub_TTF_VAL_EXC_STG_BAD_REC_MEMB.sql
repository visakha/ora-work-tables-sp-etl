-- ============================================================================
-- sp_snow_pub_TTF_VAL_EXC_STG_BAD_REC_MEMB  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TTF)
--
-- Mapping: m_Tgt_C_S_TTF_Pty_Validation, workflow wf_TTF_Stage_Load.
-- Publish branch STEP_NO 40. Target: EXC_STG_BAD_REC_MEMB. Kind: EXCEPTION (invalid-name exceptions).
-- Branch 40 of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_TTF_VAL_S3_ROUTED (P_INPUT_TABLES default). It references neither original parameter nor the run timestamp directly (it reads the run_ts / mapping_name columns materialised in the final routed table), so P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same
--   columns, values and WHERE guard. No business expression, filter,
--   guard or column list was changed.
--
-- FRAMEWORK RULE
--   NO transaction control and NO checkpoint calls in this proc. The
--   driver calls it inside ONE publish transaction (all branches
--   together, so a publish either lands completely or not at all),
--   COMMITs, and only then checkpoints this branch with the returned
--   row count. Never call a checkpoint between BEGIN TRANSACTION and
--   COMMIT.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_TTF_VAL_EXC_STG_BAD_REC_MEMB (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TTF_VAL_S3_ROUTED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO EXC_STG_BAD_REC_MEMB
           (PERIOD_START_DATE, MAPPING_NAME, ATTRIBUTE_NAME, FIRST_NAME, MIDDLE_NAME, LAST_NAME, RUN_DATE,
            SRC_SYS, SRC_SYS_ID_1, EXCEPTION_DESC, EXCEPTION_TYPE, EXCEPTION_CODE, BIRTH_DATE, ATTRIBUTE_VALUE)
    SELECT CREATEDDATE, mapping_name, exc_code_name /* ATTRIBUTE_NAME_Name has the same expression */,
           std_first_name, std_mdl_name, std_lst_name, run_ts, src_sys, pkey_src_object, exc_desc_name,
           exc_type_name, exc_code_name, DOB, std_src_full_name
      FROM WRK_TTF_VAL_S3_ROUTED
     WHERE grp_invalid_party_name = 1 AND uq_exc_name = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TTF_VAL_EXC_STG_BAD_REC_MEMB;
/

