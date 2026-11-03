-- ============================================================================
-- sp_snow_pub_TRS_ADDR2_DQM_ADDRESS  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Addr_2, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 60, driver checkpoint STEP_NAME PUBLISH_DQM_ADDRESS.
-- Target: DQM_ADDRESS. Kind: VALIDATION (Address validation mart).
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_ADDR2_DQM_ADDRESS (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_ADDR2_S50_READY') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO DQM_ADDRESS
           (ADDR_SRC_KEY, SRC_SYSTEM, PTY_SRC_KEY, LOAD_DT, SRC_ADDR_1, SRC_ADDR_2, SRC_CITY, SRC_CNTRY,
            RSLT_ADDR_1, RSLT_ADDR_2, RSLT_CITY, RSLT_STATE, RSLT_CNTRY, COUNTY_FIPS, STATE_FIPS, LATTD, LNGTD,
            RSLT_PSTL_CD, GEOCD_STS_CD, RSDNTL_DLVRY_IND, ORG_DESC, BLDG, SUB_BLDG, MLBLTY_SCR, ADDRDR_MTCH_CD,
            ERLY_WRNG_CD, CASS_ERR_CD, DLVRY_PNT_VLDN, ADDRDR_RSLT_PCT, ADDRDR_ADDR_TP_CD, RSLT_COUNTY, ORG_DEPT,
            ORG_NM, SRC_COUNTY, SRC_STATE, SRC_PSTL_CD, MDM_ADDR_TP)
    SELECT dqm_addr_src_key, src_sys, PTY_PK, run_ts, SRC_ADDR_LN_1, SRC_ADDR_LN_2, SRC_CITY, SRC_CNTRY,
           ADDR_LN_1, ADDR_LN_2, CITY, STATE, CNTRY_CD, COUNTY, STATE, LATTD, LNGTD, rslt_pstl_cd,
           GEOCD_STS_CD, RSDNTL_DLVRY_IND, ORG_DESC, BLDG_NMBR, SUB_BLDG_NM, MLBLTY_SCR, VLDTN_MSG,
           ERLY_WRNG_CD, CASS_ERR_CD, DLVRY_PNT_VLDN, ADDRDR_RSLT_PCT, ADDR_TP_CD, COUNTY, ORG_DEPT, ORG_NM,
           SRC_COUNTY, SRC_STATE, dqm_src_pstl_cd, ADDR_TYPE_CD
      FROM WRK_TRS_ADDR2_S50_READY;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_ADDR2_DQM_ADDRESS;
/

