-- ============================================================================
-- sp_snow_pub_ECI_ADR_DQM_ADDRESS  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI)
--
-- Mapping: m_Tgt_C_S_ECI_Pty_Addr, workflow wf_ECI_Stage_Load.
-- Publish branch STEP_NO 60, STEP_NAME PUBLISH_DQM_ADDRESS.
-- Target: DQM_ADDRESS. Kind: NON-SPINE.
--   Every active address -> DQM_ADDRESS (address-quality table). Original publish branch 60a, first INSERT in file order.
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
CREATE OR REPLACE FUNCTION sp_snow_pub_ECI_ADR_DQM_ADDRESS (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_ADR_S50_READY') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    -- ---- Publish branch 60: PUBLISH_DQM_ADDRESS (verbatim from current main)
    INSERT INTO DQM_ADDRESS
           (MLBLTY_SCR, SRC_ADDR_1, SRC_ADDR_2, SRC_CITY, SRC_STATE, SRC_PSTL_CD, SRC_CNTRY, SRC_COUNTY,
            RSLT_ADDR_1, RSLT_ADDR_2, RSLT_CITY, RSLT_PSTL_CD, RSLT_CNTRY, RSLT_COUNTY, COUNTY_FIPS, STATE_FIPS,
            LATTD, LNGTD, GEOCD_STS_CD, RSDNTL_DLVRY_IND, ORG_NM, ORG_DESC, ORG_DEPT, BLDG, SUB_BLDG,
            ADDRDR_MTCH_CD, ADDRDR_RSLT_PCT, ADDRDR_ADDR_TP_CD, ERLY_WRNG_CD, CASS_ERR_CD, DLVRY_PNT_VLDN,
            MDM_ADDR_TP, SRC_SYSTEM, ADDR_SRC_KEY, LOAD_DT, PTY_SRC_KEY, RSLT_STATE)
    SELECT a_mailability_score, ADDRESS1, ADDRESS2, CITY_NAME, STATE_ABBREV, ZIP_CODE, src_cntry, COUNTY_NAME,
           a_line1, a_line2, a_city, a_postcode_complete, a_country, a_county_fips, a_county_fips,
           a_state_fips, a_latitude, a_longitude, a_geocoding_status, a_residential, a_org_name,
           a_org_descriptor, a_org_department, a_building_complete, a_sub_building_complete, a_match_code,
           a_result_pct, a_address_type, a_early_warning, a_cass_error, a_dpv, mstr_addr_tp, src_sys,
           pkey_src_object, run_ts, pty_src_key, a_state_fips
      FROM WRK_ECI_ADR_S50_READY;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_ECI_ADR_DQM_ADDRESS;
/

