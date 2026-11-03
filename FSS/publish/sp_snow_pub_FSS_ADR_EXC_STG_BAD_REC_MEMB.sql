-- ============================================================================
-- sp_snow_pub_FSS_ADR_EXC_STG_BAD_REC_MEMB  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (FSS)
--
-- Mapping: m_Tgt_C_S_FSS_Pty_Addr, workflow wf_FSS_Stage_Load.
-- Publish branch STEP_NO 70, checkpoint STEP_NAME PUBLISH_EXC.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: EXCEPTION. Exception addresses.
-- Branch 3 of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_FSS_ADDR_S4_SCORED (P_INPUT_TABLES default). The INSERT references neither original parameter nor the run timestamp directly, so P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same
--   columns, values and WHERE guard (score = '40' AND uq_addr_exc). No business expression,
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
CREATE OR REPLACE FUNCTION sp_snow_pub_FSS_ADR_EXC_STG_BAD_REC_MEMB (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_FSS_ADDR_S4_SCORED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, ADDRESS_DR_ERROR_CODE, ADDRESS_DR_ERROR_DESC, ADDRESS_DR_MAILABILITY_SCORE,
            ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME, ADDRESS_TYPE, PERIOD_START_DATE, PERIOD_END_DATE,
            EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, EXCEPTION_TYPE, ADDRESS_LINE_1, ADDRESS_LINE_2,
            ADDRESS_CITY, ADDRESS_COUNTY, ADDRESS_STATE, ADDRESS_ZIP, ADDRESS_ZIP_EXT, ADDRESS_COUNTRY,
            SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3)
    SELECT src_sys, a_match_code, a_match_code_description, a_mailability_score, exc_attribute_name,
           exc_attribute_value, mapping_name, addr_tp, DT_LAST_UPDATE, NULL, exc_code, exc_desc, run_ts,
           exc_type, ADDR_LINE1, ADDR_LINE2, ADDR_CITY, CD_CNTY, ADDR_STATE, ADDR_ZIP, NULL, src_cntry,
           ID_CLIENT, ID_REGISTRATION_CLIENT, SOURCE_TYPE
      FROM WRK_FSS_ADDR_S4_SCORED
     WHERE score = '40' AND uq_addr_exc = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_FSS_ADR_EXC_STG_BAD_REC_MEMB;
/

