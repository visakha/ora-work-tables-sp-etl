-- ============================================================================
-- sp_snow_pub_TRS_ADDR1_STG_TRS_D_UNQ_ADDR  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Addr_1, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 50, driver checkpoint STEP_NAME PUBLISH_STG_TRS_D_UNQ_ADDR.
-- Target: STG_TRS_D_UNQ_ADDR. Kind: STATUS (Validated unique addresses).
--
-- INPUTS
--   Reads ONLY WRK_TRS_ADDR1_S40_READY (P_INPUT_TABLES default). The INSERT below may use
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_ADDR1_STG_TRS_D_UNQ_ADDR (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_ADDR1_S40_READY') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO STG_TRS_D_UNQ_ADDR
           (ADDR_ID, ADDR_LN_1, ADDR_LN_2, BLDNG_NM, FLR_NUM, CITY, COUNTY, STATE, CNTRY_CD, PSTL_CD, PSTL_CD_EXT, LATTD,
            LNGTD, VLDTN_MSG, VLDTN_DESC, MLBLTY_SCR, ADDR_TP_CD, ORG_DESC, ORG_NM, BLDG_NMBR, SUB_BLDG_NM,
            SUB_BLDG_DESC, GEOCD_STS_CD, RSDNTL_DLVRY_IND, ADDRDR_RSLT_PCT, ERLY_WRNG_CD, CASS_ERR_CD, DLVRY_PNT_VLDN,
            SRC_ADDR_LN_1, SRC_ADDR_LN_2, SRC_CITY, SRC_COUNTY, SRC_STATE, SRC_CNTRY, SRC_PSTL_CD, SRC_PSTL_CD_EXT,
            ORG_DEPT)
    SELECT ADDR_ID, ADDR_LN_1, ADDR_LN_2, BLDNG_NM, FLR_NUM, CITY, COUNTY, STATE, CNTRY_CD, PSTL_CD, PSTL_CD_EXT, LATTD,
           LNGTD, VLDTN_MSG, VLDTN_DESC, MLBLTY_SCR, ADDR_TP_CD, ORG_DESC, ORG_NM, BLDG_NMBR, SUB_BLDG_NM,
           SUB_BLDG_DESC, GEOCD_STS_CD, RSDNTL_DLVRY_IND, ADDRDR_RSLT_PCT, ERLY_WRNG_CD, CASS_ERR_CD, DLVRY_PNT_VLDN,
           SRC_ADDR_LN_1, SRC_ADDR_LN_2, SRC_CITY, SRC_COUNTY, SRC_STATE, SRC_CNTRY, SRC_PSTL_CD, SRC_PSTL_CD_EXT,
           ORG_DEPT
      FROM WRK_TRS_ADDR1_S40_READY;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_ADDR1_STG_TRS_D_UNQ_ADDR;
/

