-- ============================================================================
-- sp_snow_pub_ECI_ADR_EXC_STG_BAD_REC_MEMB  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI)
--
-- Mapping: m_Tgt_C_S_ECI_Pty_Addr, workflow wf_ECI_Stage_Load.
-- Publish branch STEP_NO 80, STEP_NAME PUBLISH_EXC_STG_BAD_REC_MEMB.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: NON-SPINE.
--   Exception addresses (score 40, uq_addr_exc) -> EXC_STG_BAD_REC_MEMB (exception log). Original publish branch 60c, third INSERT in file order.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (default
--   'WRK_ECI_ADR_S50_READY'). The INSERT below still names its source
--   literally, as in the current main procedure: Snowflake cannot
--   parameterise table names in static SQL, so P_INPUT_TABLES is a
--   dependency declaration + runtime check for the driver, NOT dynamic
--   SQL. This proc itself performs no existence check; the driver
--   passes the config-declared consumed string.
--   Original params used by this INSERT: none (it reads only columns
--   already materialised in WRK_ECI_ADR_S50_READY, including
--   hierarchy_code / hm_rel_tp_cd), so none are in this signature.
--   P_RUN_TS is carried for signature uniformity; the INSERT uses the
--   run_ts column already stored in step 50, as in the current code.
--
-- BUSINESS SQL
--   The INSERT below is the current publish-branch INSERT verbatim:
--   same columns, values and WHERE guards. No business expression,
--   filter, guard or column list was changed.
--
-- FRAMEWORK RULE (read before changing anything)
--   NO transaction control and NO checkpoint calls in this proc.
--   The driver owns the publish transaction and checkpoints each
--   branch ONLY AFTER the driver commits, so a checkpoint can never roll back with
--   the publish. This proc only inserts and returns SQLROWCOUNT.
--   P_JOB_RUN_ID is present in every new proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_ECI_ADR_EXC_STG_BAD_REC_MEMB (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_ADR_S50_READY') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    -- ---- Publish branch 80: PUBLISH_EXC_STG_BAD_REC_MEMB (verbatim from current main)
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, ADDRESS_DR_ERROR_CODE, ADDRESS_DR_ERROR_DESC, ADDRESS_DR_MAILABILITY_SCORE,
            ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME, ADDRESS_TYPE, PERIOD_START_DATE, PERIOD_END_DATE,
            EXCEPTION_CODE, EXCEPTION_DESC, RUN_DATE, EXCEPTION_TYPE, ADDRESS_LINE_1, ADDRESS_LINE_2,
            ADDRESS_CITY, ADDRESS_COUNTY, ADDRESS_STATE, ADDRESS_ZIP, ADDRESS_ZIP_EXT, ADDRESS_COUNTRY,
            SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3)
    SELECT src_sys, a_match_code, a_match_code_description, a_mailability_score, exc_attribute_name,
           exc_attribute_value, mapping_name, ADDRESS_CD, LAST_UPDATE_DATE, NULL, exc_code, exc_desc,
           run_ts, exc_type, ADDRESS1, ADDRESS2, CITY_NAME, COUNTY_NAME, STATE_ABBREV, ZIP_CODE, ZIP_SFX,
           src_cntry, ID, ID_FAMILY_ADDRESS, SOURCE_TABLE
      FROM WRK_ECI_ADR_S50_READY
     WHERE score = '40' AND uq_addr_exc = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_ECI_ADR_EXC_STG_BAD_REC_MEMB;
/

