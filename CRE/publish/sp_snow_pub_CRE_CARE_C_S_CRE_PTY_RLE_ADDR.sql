-- ============================================================================
-- sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_ADDR  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (CRE)
--
-- Mapping: m_Tgt_C_S_CRE_CARE_Clients, workflow wf_CRE_Stage_Load_Ongoing.
-- Publish branch STEP_NO 150, checkpoint STEP_NAME PUBLISH_C_S_CRE_PTY_RLE_ADDR.
-- Target: C_S_CRE_PTY_RLE_ADDR. Kind: SPINE (party spine itself).
-- Branch 60j of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_CRE_CARE_S5_KEYED (P_INPUT_TABLES default). The
--   INSERT reads the run_ts / mapping_name columns materialised in step
--   50; it references neither original parameter nor the run timestamp
--   directly, so P_RUN_TS is carried for a uniform driver call
--   signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch-60j INSERT verbatim: same
--   columns, values and WHERE guard (grp_addr AND uq_addr). No business expression,
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
CREATE OR REPLACE FUNCTION sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_ADDR (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_CRE_CARE_S5_KEYED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    INSERT INTO C_S_CRE_PTY_RLE_ADDR
           (PKEY_SRC_OBJECT, SRC_ROWID, VERSION_SEQ, LAST_UPDATE_DATE, PERIOD_START_DATE, PERIOD_END_DATE,
            PERIOD_REFERENCE_TIME, TIMELINE_ACTION, CREATE_DATE, HIERARCHY_CODE, PREF_LVL, ADDR_TP, HM_REL_TP_CD,
            ADDR_LN_1, ADDR_LN_2, CITY, COUNTY, STATE, CNTRY_CD, PSTL_CD, PSTL_CD_EXT, LATTD, LNGTD, MLBLTY_SCR,
            PTY_RLE_FK, USG_TP, SRC_ADDR_LN_1, SRC_CITY, SRC_COUNTY, SRC_STATE, SRC_CNTRY, SRC_PSTL_CD,
            SRC_PSTL_CD_EXT, SRC_LAST_UPD_DT, FLR_NUM, ADDR_TP_CD, SUB_BLDG_DESC, SUB_BLDG_NM, BLDG_NMBR,
            BLDNG_NM, RSDNTL_DLVRY_IND, GEOCD_STS_CD, ORG_NM, ORG_DESC, VLDTN_MSG)
    SELECT addr_key, addr_src_rowid, version_seq_num, last_update, period_start, period_end,
           period_reference_time, timeline_action, last_update, hierarchy_code, pref_lvl, addr_tp,
           hm_rel_tp_cd, a_line1, a_line2, a_city, a_county, a_state, a_country, a_postcode, a_postcode_ext,
           a_latitude, a_longitude, a_mailability_score, rle_key, addr_tp, STREET, CITY, CNTY, STATE,
           src_cntry, ZIP, ZIPSUF, CARE_LASTUP_DT, a_sub_building_number, a_address_type,
           a_sub_building_descriptor, a_sub_building_complete, a_building_number, a_building_name,
           a_residential, a_geocoding_status, a_org_name, a_org_descriptor, a_match_code
      FROM WRK_CRE_CARE_S5_KEYED
     WHERE grp_addr = 1 AND uq_addr = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_ADDR;
/

