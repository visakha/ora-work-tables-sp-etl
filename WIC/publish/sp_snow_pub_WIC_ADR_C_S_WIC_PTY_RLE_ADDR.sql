-- ============================================================================
-- sp_snow_pub_WIC_ADR_C_S_WIC_PTY_RLE_ADDR  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (WIC)
--
-- Mapping: m_Tgt_C_S_WIC_Pty_Addr, workflow wf_WIC_Stage_Load.
-- Publish branch STEP_NO 60, checkpoint STEP_NAME PUBLISH_C_S_WIC_PTY_RLE_ADDR.
-- Target: C_S_WIC_PTY_RLE_ADDR. Kind: SPINE (good addresses).
-- Branch in original order; WHERE guard: score = '100' AND uq_addr.
--
-- INPUTS
--   Reads ONLY WRK_WIC_ADDR_S40_SCORED (P_INPUT_TABLES default). The INSERT reads the run_ts / mapping_name columns materialised in the final step; it references neither original parameter nor the run timestamp directly, so P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same columns, values and WHERE guard. No business expression, filter, guard or column list was changed.
--
-- FRAMEWORK RULE
--   NO transaction control and NO checkpoint calls in this proc. The driver calls it inside ONE publish transaction (all branches together, so a publish either lands completely or not at all), COMMITs, and only then checkpoints this branch. Never call a checkpoint between BEGIN TRANSACTION and COMMIT.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_WIC_ADR_C_S_WIC_PTY_RLE_ADDR (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_WIC_ADDR_S40_SCORED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    INSERT INTO C_S_WIC_PTY_RLE_ADDR
           (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE,
            VERSION_SEQ, UPDATED_BY, LAST_UPDATE_DATE, PREF_LVL, LOC_IDN, HM_REL_TP_CD, HUB_STATE_IND,
            SRC_ROWID, USG_TP, HIERARCHY_CODE, ADDR_LN_1, ADDR_LN_2, SRC_LAST_UPD_DT, FLR_NUM, LCTN_CRDNT_DESC,
            PSTL_BRCD, RGN_CD, SRC_ADDR_LN_1, SRC_ADDR_LN_2, SRC_CITY, SRC_COUNTY, SRC_STATE, SRC_CNTRY,
            SRC_PSTL_CD, SRC_PSTL_CD_EXT, EFF_STRT_DT, EFF_END_DT, ADDR_TP, PTY_RLE_FK, CREATE_DATE, CREATOR,
            PERIOD_REFERENCE_TIME, CITY, PSTL_CD, CNTRY_CD, VLDTN_MSG, LATTD, LNGTD, COUNTY, MLBLTY_SCR, STATE,
            RSDNTL_DLVRY_IND, ORG_DESC, ADDR_TP_CD, ORG_NM, BLDNG_NM, GEOCD_STS_CD, SUB_BLDG_NM,
            SUB_BLDG_DESC, BLDG_NMBR, PSTL_CD_EXT)
    SELECT pkey_src_object, NULL, NULL, NULL, NULL, DATE_ADDRESS_VALID_FROM, version_seq, mapping_name,
           run_ts, pref_lvl, loc_idn, hm_rel_tp_cd, hub_state_ind, pkey_src_object, NULL, hierarchy_code,
           hold_line1, hold_line2, DATE_ADDRESS_VALID_FROM, NULL, NULL, NULL, NULL, ADDRESS1, ADDRESS2, CITY,
           COUNTY, NULL, src_cntry, ZIP_CODE, NULL, DATE_ADDRESS_VALID_FROM, NULL, addr_tp, pty_rle_fk,
           DATE_ADDRESS_VALID_FROM, NULL, NULL, a_city, a_zip_cd_5, a_country, a_match_code, a_latitude,
           a_longitude, a_county_fips, a_mailability_score, a_state_fips, a_residential, a_org_descriptor,
           a_address_type, a_org_name, a_building_name, a_geocoding_status, a_sub_building_complete,
           a_sub_building_descriptor, a_building_number, a_zip_cd_4_extn
      FROM WRK_WIC_ADDR_S40_SCORED
     WHERE score = '100' AND uq_addr = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_WIC_ADR_C_S_WIC_PTY_RLE_ADDR;
/

