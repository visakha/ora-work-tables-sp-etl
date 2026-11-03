-- ============================================================================
-- sp_snow_pub_TRS_ADDR2_C_S_TRS_PTY_RLE_ADDR  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Addr_2, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 70, driver checkpoint STEP_NAME PUBLISH_C_S_TRS_PTY_RLE_ADDR.
-- Target: C_S_TRS_PTY_RLE_ADDR. Kind: SPINE (Good addresses).
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_ADDR2_C_S_TRS_PTY_RLE_ADDR (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_ADDR2_S50_READY') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO C_S_TRS_PTY_RLE_ADDR
           (PKEY_SRC_OBJECT, PERIOD_START_DATE, VERSION_SEQ, PERIOD_REFERENCE_TIME, HIERARCHY_CODE, HM_REL_TP_CD,
            LAST_UPDATE_DATE, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, UPDATED_BY, SRC_ROWID,
            HUB_STATE_IND, PREF_LVL, LOC_IDN, ADDR_TP, PTY_RLE_FK, USG_TP, ADDR_LN_1, ADDR_LN_2, CITY, PSTL_CD,
            PSTL_CD_EXT, CNTRY_CD, CRDNT_SYS, LATTD, LNGTD, PSTL_BRCD, FLR_NUM, BLDNG_NM, COUNTY, STATE,
            LCTN_CRDNT_DESC, VLDTN_MSG, RGN_CD, MLBLTY_SCR, ADDR_TP_CD, ORG_DESC, ORG_NM, GEOCD_STS_CD,
            SUB_BLDG_NM, BLDG_NMBR, SUB_BLDG_DESC, RSDNTL_DLVRY_IND, SRC_ADDR_LN_1, SRC_ADDR_LN_2, SRC_CITY,
            SRC_COUNTY, SRC_STATE, SRC_CNTRY, SRC_PSTL_CD, SRC_PSTL_CD_EXT, SRC_LAST_UPD_DT, CREATOR, CREATE_DATE,
            EFF_STRT_DT, PERIOD_END_DATE, EFF_END_DT)
    SELECT pkey_pty_rle_addr, EFF_BEGIN_DT, version_seq, period_reference_time, hierarchy_code, hm_rel_tp_cd,
           run_ts, NULL, NULL, NULL, NULL, NULL, src_rowid, NULL, pref_lvl, loc_idn, mstr_addr_tp, pty_rle_fk,
           NULL, hold_line1, hold_line2, CITY, PSTL_CD, PSTL_CD_EXT, CNTRY_CD, NULL, LATTD, LNGTD, NULL,
           FLR_NUM, BLDNG_NM, COUNTY, STATE, NULL, VLDTN_MSG, NULL, MLBLTY_SCR, ADDR_TP_CD, ORG_DESC, ORG_NM,
           GEOCD_STS_CD, SUB_BLDG_NM, BLDG_NMBR, SUB_BLDG_DESC, RSDNTL_DLVRY_IND, SRC_ADDR_LN_1,
           SRC_ADDR_LN_2, SRC_CITY, SRC_COUNTY, SRC_STATE, SRC_CNTRY, SRC_PSTL_CD, SRC_PSTL_CD_EXT, CREATE_DT,
           NULL, NULL, EFF_BEGIN_DT, end_date_50y, end_date_50y
      FROM WRK_TRS_ADDR2_S50_READY
     WHERE score = '100' AND uq_addr = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_ADDR2_C_S_TRS_PTY_RLE_ADDR;
/

