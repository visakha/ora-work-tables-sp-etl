-- ============================================================================
-- sp_snow_pub_TRS_ADDR2_EXC_STG_BAD_REC_MEMB  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Addr_2, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 80, driver checkpoint STEP_NAME PUBLISH_EXC_STG_BAD_REC_MEMB.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: EXCEPTION (Score 40 exceptions).
--
-- INPUTS
--   Reads ONLY WRK_TRS_ADDR2_S50_READY (P_INPUT_TABLES default). The INSERT below may use
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_ADDR2_EXC_STG_BAD_REC_MEMB (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_ADDR2_S50_READY') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, ADDRESS_DR_ERROR_CODE, ADDRESS_DR_ERROR_DESC, ADDRESS_DR_MAILABILITY_SCORE, ATTRIBUTE_NAME,
            ATTRIBUTE_VALUE, MAPPING_NAME, ADDRESS_TYPE, PERIOD_START_DATE, PERIOD_END_DATE, RUN_DATE,
            ADDRESS_LINE_1, ADDRESS_LINE_2, ADDRESS_CITY, ADDRESS_COUNTY, ADDRESS_STATE, ADDRESS_ZIP,
            ADDRESS_ZIP_EXT, ADDRESS_COUNTRY, SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3, EXCEPTION_CODE,
            EXCEPTION_DESC, EXCEPTION_TYPE)
    SELECT src_sys, VLDTN_MSG, VLDTN_DESC, MLBLTY_SCR, exc_attribute_name, exc_attribute_value, mapping_name,
           ADDR_TYPE_CD, EFF_BEGIN_DT, EFF_END_DT, run_ts, SRC_ADDR_LN_1, SRC_ADDR_LN_2, SRC_CITY,
           SRC_COUNTY, SRC_STATE, SRC_PSTL_CD, SRC_PSTL_CD_EXT, SRC_CNTRY, INDV_ID, CASE_NUM, EDG_NUM,
           exc_code, exc_desc, exc_type
      FROM WRK_TRS_ADDR2_S50_READY
     WHERE score = '40' AND uq_addr_exc = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_ADDR2_EXC_STG_BAD_REC_MEMB;
/

