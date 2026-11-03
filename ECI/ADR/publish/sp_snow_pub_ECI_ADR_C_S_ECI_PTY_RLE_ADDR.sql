-- ============================================================================
-- sp_snow_pub_ECI_ADR_C_S_ECI_PTY_RLE_ADDR  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI)
--
-- Mapping: m_Tgt_C_S_ECI_Pty_Addr, workflow wf_ECI_Stage_Load.
-- Publish branch STEP_NO 70, STEP_NAME PUBLISH_C_S_ECI_PTY_RLE_ADDR.
-- Target: C_S_ECI_PTY_RLE_ADDR. Kind: SPINE.
--   Good addresses (score 100, uq_addr) -> C_S_ECI_PTY_RLE_ADDR (party-role address spine). Original publish branch 60b, second INSERT in file order.
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
CREATE OR REPLACE FUNCTION sp_snow_pub_ECI_ADR_C_S_ECI_PTY_RLE_ADDR (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_ADR_S50_READY') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    -- ---- Publish branch 70: PUBLISH_C_S_ECI_PTY_RLE_ADDR (verbatim from current main)
    INSERT INTO C_S_ECI_PTY_RLE_ADDR
           (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE,
            VERSION_SEQ, UPDATED_BY, CREATE_DATE, CREATOR, ADDR_TP, LAST_UPDATE_DATE, PREF_LVL, LOC_IDN,
            SRC_ROWID, HUB_STATE_IND, HIERARCHY_CODE, HM_REL_TP_CD, PERIOD_REFERENCE_TIME, ADDR_LN_1,
            ADDR_LN_2, CITY, PSTL_CD, CNTRY_CD, VLDTN_MSG, LATTD, LNGTD, PSTL_BRCD, RGN_CD, COUNTY,
            LCTN_CRDNT_DESC, MLBLTY_SCR, STATE, RSDNTL_DLVRY_IND, ORG_DESC, ADDR_TP_CD, ORG_NM, FLR_NUM,
            BLDNG_NM, GEOCD_STS_CD, SUB_BLDG_NM, SUB_BLDG_DESC, BLDG_NMBR, SRC_ADDR_LN_1, SRC_ADDR_LN_2,
            SRC_CITY, SRC_COUNTY, SRC_STATE, SRC_CNTRY, SRC_PSTL_CD, SRC_PSTL_CD_EXT, EFF_STRT_DT, EFF_END_DT,
            PTY_RLE_FK, SRC_LAST_UPD_DT, PSTL_CD_EXT)
    SELECT pkey_src_object, NULL, NULL, NULL, NULL, LAST_UPDATE_DATE, version_seq, mapping_name,
           LAST_UPDATE_DATE, NULL, mstr_addr_tp, run_ts, pref_lvl, loc_idn, pkey_src_object, hub_state_ind,
           hierarchy_code, hm_rel_tp_cd, NULL, hold_line1, hold_line2, a_city, a_zip_cd_5, a_country,
           a_match_code, a_latitude, a_longitude, NULL, NULL, a_county_fips, NULL, a_mailability_score,
           a_state_fips, a_residential, a_org_descriptor, a_address_type, a_org_name, NULL,
           a_building_name, a_geocoding_status, a_sub_building_complete, a_sub_building_descriptor,
           a_building_number, ADDRESS1, ADDRESS2, CITY_NAME, COUNTY_NAME, STATE_ABBREV, src_cntry, ZIP_CODE,
           ZIP_SFX, LAST_UPDATE_DATE, NULL, pty_rle_fk, LAST_UPDATE_DATE, a_zip_cd_4_extn
      FROM WRK_ECI_ADR_S50_READY
     WHERE score = '100' AND uq_addr = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_ECI_ADR_C_S_ECI_PTY_RLE_ADDR;
/

