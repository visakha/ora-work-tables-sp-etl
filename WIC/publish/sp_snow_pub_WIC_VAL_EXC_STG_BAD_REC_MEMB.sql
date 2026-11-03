-- ============================================================================
-- sp_snow_pub_WIC_VAL_EXC_STG_BAD_REC_MEMB  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (WIC)
--
-- Mapping: m_Tgt_C_S_WIC_Pty_Validation, workflow wf_WIC_Stage_Load.
-- Publish branch STEP_NO 40, checkpoint STEP_NAME PUBLISH_EXC_STG_BAD_REC_MEMB.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: EXCEPTION (invalid-name exceptions).
-- Branch in original order; WHERE guard: name_missing AND uq_exc_name.
--
-- INPUTS
--   Reads ONLY WRK_WIC_VAL_S30_ROUTED (P_INPUT_TABLES default). The INSERT reads the run_ts / mapping_name columns materialised in the final step; it references neither original parameter nor the run timestamp directly, so P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same columns, values and WHERE guard. No business expression, filter, guard or column list was changed.
--
-- FRAMEWORK RULE
--   NO transaction control and NO checkpoint calls in this proc. The driver calls it inside ONE publish transaction (all branches together, so a publish either lands completely or not at all), COMMITs, and only then checkpoints this branch. Never call a checkpoint between BEGIN TRANSACTION and COMMIT.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_WIC_VAL_EXC_STG_BAD_REC_MEMB (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_WIC_VAL_S30_ROUTED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (PERIOD_START_DATE, MAPPING_NAME, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, FIRST_NAME, MIDDLE_NAME,
            LAST_NAME, RUN_DATE, SRC_SYS, SRC_SYS_ID_1, EXCEPTION_DESC, EXCEPTION_TYPE, EXCEPTION_CODE,
            BIRTH_DATE)
    SELECT DATEKEY, mapping_name, exc_attribute_name, exc_attribute_value, std_first_name, std_mdl_name,
           std_lst_name, run_ts, src_sys, PTY_SRC_KEY, exc_desc_name, exc_type_name, exc_code_name, DOB
      FROM WRK_WIC_VAL_S30_ROUTED
     WHERE name_missing = 1 AND uq_exc_name = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_WIC_VAL_EXC_STG_BAD_REC_MEMB;
/

