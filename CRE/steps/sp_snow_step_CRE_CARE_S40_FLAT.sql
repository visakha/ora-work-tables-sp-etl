-- ============================================================================
-- sp_snow_step_CRE_CARE_S40_FLAT  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (CRE)
--
-- Mapping: m_Tgt_C_S_CRE_CARE_Clients, workflow wf_CRE_Stage_Load_Ongoing, step 40.
-- Step name (checkpoint): FLAT_ADDR_ALTID.
--
-- WHAT THIS STEP PRODUCES
--   WRK_CRE_CARE_S4_FLAT: flattened load-ready rows (alt_tp + flat).
--   Load-ready rows. The US-vs-abroad address split (US: validated fields, valid only with mailability score >= 3 or a match code not starting I / N, plus a state FIPS; abroad: source street/city with state 99 and country ZZ, needing city and street present), the phone key, the three alternate-id keys and values (type looked up by source value, no code-type filter), every exception code/description/type resolved from the exception lookup, and the timeline dates (end-dated B / D rows get start = last-update - 1 day, end = last-update, action 2). Reads ONLY step 30 (plus the reference lookups).
--
-- DOES IT FEED THE SPINE?
--   Directly upstream of the spine: it builds the address, phone and alternate-id fields the spine branches write.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only. Default: 'WRK_CRE_CARE_S3_RANKED'
--   (empty for step 10: it reads base source tables, not work tables, so
--   the existence check below is skipped). Snowflake cannot parameterise
--   table names in static SQL, so P_INPUT_TABLES is a dependency
--   declaration + runtime check, NOT dynamic SQL: the CTAS below still
--   names its sources literally, as in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-40 SELECT verbatim. Only
--   substitutions: :l_run_ts -> :P_RUN_TS, :c_mapping -> the local
--   constant below (used by the checkpoint), original-parameter refs -> this proc's params of the same names. No business
--   expression, filter, guard or column list was changed. This step uses
--   original parameters: P_RLE_BO_CLASS_CD_MEMBER, P_DEFAULT_NONUS_STATE_CD.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   with the same STEP_NAME and message as the current step-40
--   checkpoint (v2 10-argument form; STEP_NO, row count, and work-table
--   arguments dropped). P_JOB_RUN_ID is present in every new proc in
--   this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_CRE_CARE_S40_FLAT (P_RLE_BO_CLASS_CD_MEMBER IN VARCHAR2 DEFAULT 'Member', P_DEFAULT_NONUS_STATE_CD IN VARCHAR2 DEFAULT '99', -- Live-compile fix: Snowflake forbids a required parameter after an
    -- optional one, so P_JOB_RUN_ID / P_RUN_TS carry DEFAULT NULL here.
    -- Drivers always pass all parameters positionally, so behaviour is unchanged.
    P_JOB_RUN_ID             VARCHAR DEFAULT NULL IN , P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_CRE_CARE_S3_RANKED') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'CRE';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_CRE_Stage_Load_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_CRE_CARE_Clients';
    l_rows NUMBER DEFAULT 0;
    l_missing VARCHAR2(4000) DEFAULT NULL;
    l_probe_sql VARCHAR2(4000);
    l_probe_dummy NUMBER;
BEGIN
    -- ---- Input existence check (skipped when P_INPUT_TABLES is empty)
    IF (P_INPUT_TABLES IS NOT NULL AND TRIM(P_INPUT_TABLES) <> '') THEN
        SELECT LISTAGG(tbl, ', ') WITHIN GROUP (ORDER BY tbl) INTO l_missing FROM (SELECT UPPER(TRIM(REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL))) AS tbl FROM DUAL CONNECT BY REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL) IS NOT NULL) f WHERE NOT EXISTS (SELECT 1 FROM ALL_TABLES t WHERE t.OWNER = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AND t.TABLE_NAME = f.tbl);
        IF (l_missing IS NOT NULL) THEN
            l_probe_sql := 'SELECT COUNT(*) FROM ' || TRIM(REGEXP_SUBSTR(l_missing, '[^,]+', 1, 1));
            EXECUTE IMMEDIATE l_probe_sql INTO l_probe_dummy;
        END IF;
    END IF;

    -- ---- Step 40: FLAT_ADDR_ALTID (verbatim from current main)
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_CRE_CARE_S4_FLAT';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_CRE_CARE_S4_FLAT AS WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    lkp_mc  AS (SELECT * FROM TABLE(fn_snow_helper46_common())),
    -- lkp_ALT_ID_MSTR_REF_CODE: LOOKUP_CODE_VALUE of SRC_SYS CRE by source value (no code-type filter), any row
    alt_tp AS (
        SELECT * FROM (SELECT l.SRC_CODE_VALUE, l.MSTR_REF_CODE, l.MSTR_REF_LABEL, l.SRC_SYS
          , ROW_NUMBER() OVER (PARTITION BY l.SRC_CODE_VALUE ORDER BY l.CODE_TYPE) AS __qual_rn FROM LOOKUP_CODE_VALUE l
         WHERE l.SRC_SYS = 'CRE' AND l.SRC_CODE_VALUE IN ('CARE ID', 'Medicaid ID', 'SSN')) WHERE __qual_rn = 1
    )
    SELECT d.*,
           d.CARE_ID                                                               AS pty_key,
           NVL(d.CARE_ID, '') || '|' || :1                  AS rle_key,
           NVL(d.CARE_ID, '') || '|Member'                                         AS member_rle_fk,
           /* TIMELINE: EXP_VALID_MEMBERS, EXP_PTY_HOLD / EXP_PTY_RLE_HOLD */
           CASE WHEN d.end_dated = 1 THEN (d.CARE_LASTUP_DT + -1) ELSE d.CARE_LASTUP_DT END  AS period_start,
           CASE WHEN d.end_dated = 1 THEN d.CARE_LASTUP_DT ELSE NULL END                                AS period_end,
           CASE WHEN d.end_dated = 1 THEN 2 ELSE NULL END                                               AS timeline_action,
           CASE WHEN d.end_dated = 1 THEN (d.CARE_LASTUP_DT + -1) ELSE NULL END              AS period_reference_time,
           CASE WHEN d.end_dated = 1 THEN (:2 + (-1) / 24) ELSE :2 END               AS last_update,
           CASE WHEN d.end_dated = 1 THEN ((d.CARE_LASTUP_DT + -1) + 1) ELSE NULL END AS pty_period_end,
           CASE WHEN d.end_dated = 1 THEN (d.CARE_LASTUP_DT + -1) ELSE NULL END              AS pty_period_reference_time,
           NVL(d.CARE_LASTUP_DT, d.INSERT_DATE)                                    AS src_last_update,
           CAST(d.gd.mdm_gender_code AS VARCHAR2(4000))                                           AS mdm_gender_code,
           CAST(d.gd.exception_code AS VARCHAR2(4000))                                            AS gender_exception_code,
           xg.EXCEPTION_DESC                                                       AS gender_exception_description,
           xg.EXCEPTION_TYPE                                                       AS gender_exception_type,
           xs.EXCEPTION_DESC                                                       AS suffix_exception_desc,
           xs.EXCEPTION_TYPE                                                       AS suffix_exception_type,
           xe.EXCEPTION_CODE AS ethnicity_exception_code, xe.EXCEPTION_DESC AS ethnicity_exception_desc,
           xe.EXCEPTION_TYPE AS ethnicity_exception_type,
           xr.EXCEPTION_CODE AS race_exception_code, xr.EXCEPTION_DESC AS race_exception_desc,
           xr.EXCEPTION_TYPE AS race_exception_type,
           xp.EXCEPTION_CODE AS phone_exception_code, xp.EXCEPTION_DESC AS phone_exception_desc,
           xp.EXCEPTION_TYPE AS phone_exception_type,
           NVL(d.CARE_ID, '') || '|Member|Telephone|001|' || NVL(d.phone_std, '')  AS phn_key,
           /* VALIDATION: RTR_VALID_ADDRESS / RTR_VALID_NON_US_ADDRESSES */
           CASE WHEN d.addr_us = 1 THEN NVL(CASE WHEN (TRUNC(TO_NUMBER(CAST(d.av.mailability_score AS VARCHAR2(4000)) DEFAULT NULL ON CONVERSION ERROR)) >= 3
                    OR LEFT(CAST(d.av.match_code AS VARCHAR2(4000)), 1) NOT IN ('I', 'N'))
                   AND CAST(d.av.state_fips_cd AS VARCHAR2(4000)) IS NOT NULL THEN 1 ELSE 0 END, 0) ELSE d.CITY IS NOT NULL AND d.STREET IS NOT NULL END                       AS addr_valid,
           CASE WHEN d.addr_us = 1 THEN CAST(d.av.delivery_address_line1 AS VARCHAR2(4000)) ELSE INITCAP(d.STREET) END AS a_line1,
           CASE WHEN d.addr_us = 1 THEN CAST(d.av.delivery_address_line2 AS VARCHAR2(4000)) ELSE NULL END             AS a_line2,
           CASE WHEN d.addr_us = 1 THEN CAST(d.av.city AS VARCHAR2(4000)) ELSE INITCAP(d.CITY) END                    AS a_city,
           CASE WHEN d.addr_us = 1 THEN CAST(d.av.state_fips_cd AS VARCHAR2(4000)) ELSE :3 END AS a_state,
           CASE WHEN d.addr_us = 1 THEN CAST(d.av.county_fips_cd AS VARCHAR2(4000)) ELSE d.CNTY END                   AS a_county_fips,
           CASE WHEN d.addr_us = 1 THEN CAST(d.av.country_iso2_char AS VARCHAR2(4000)) ELSE 'ZZ' END                  AS a_country,
           CASE WHEN d.addr_us = 1 THEN CAST(d.av.zip_cd_5 AS VARCHAR2(4000)) ELSE d.ZIP END                          AS a_postcode,
           CASE WHEN d.addr_us = 1 THEN CAST(d.av.zip_cd_4_extn AS VARCHAR2(4000)) ELSE d.ZIPSUF END                  AS a_postcode_ext,
           CAST(d.av.geocoding_latitude AS NUMBER(38, 6))                                  AS a_latitude,
           CAST(d.av.geocoding_longitude AS NUMBER(38, 6))                                 AS a_longitude,
           CAST(d.av.mailability_score AS VARCHAR2(4000))                                         AS a_mailability_score,
           CAST(d.av.match_code AS VARCHAR2(4000))                                                AS a_match_code,
           CAST(d.av.address_type AS VARCHAR2(4000))                                              AS a_address_type,
           CAST(d.av.sub_building_number AS VARCHAR2(4000))                                       AS a_sub_building_number,
           CAST(d.av.sub_building_descriptor AS VARCHAR2(4000))                                   AS a_sub_building_descriptor,
           CAST(d.av.sub_building_complete AS VARCHAR2(4000))                                     AS a_sub_building_complete,
           CAST(d.av.building_number AS VARCHAR2(4000))                                           AS a_building_number,
           CAST(d.av.building_name AS VARCHAR2(4000))                                             AS a_building_name,
           CAST(d.av.residential_delivery_indicator AS VARCHAR2(4000))                           AS a_residential,
           CAST(d.av.geocoding_status AS VARCHAR2(4000))                                          AS a_geocoding_status,
           CAST(d.av.organization_name AS VARCHAR2(4000))                                         AS a_org_name,
           CAST(d.av.organization_descriptor AS VARCHAR2(4000))                                   AS a_org_descriptor,
           TO_NUMBER(CAST(d.av.mailability_score AS VARCHAR2(4000)) DEFAULT NULL ON CONVERSION ERROR)                          AS a_dr_mailability_score,
           mc.DESCRIPTION                                                          AS a_dr_error_desc,
           CAST(d.av.match_code AS VARCHAR2(4000))                                                AS a_dr_error_code,
           NVL(CASE WHEN d.STREET = 1 THEN 1 ELSE 0 END, '') || ' ' || '' || ' ' || NVL(CASE WHEN d.CITY = 1 THEN 1 ELSE 0 END, '') || ' ' || NVL(CASE WHEN d.STATE = 1 THEN 1 ELSE 0 END, '') || ' '
           || NVL(d.ZIP, '')                                                       AS addr_attribute_value,
           xa.EXCEPTION_CODE AS addr_exception_code, xa.EXCEPTION_DESC AS addr_exception_desc,
           xa.EXCEPTION_TYPE AS addr_exception_type,
           -- NRML_ALT_ID occurrences and lkp_ALT_ID_MSTR_REF_CODE
           CAST(d.ci.id_value AS VARCHAR2(4000))                                                  AS care_alt_id,
           t1.MSTR_REF_CODE                                                        AS care_tp_cd,
           CAST(d.md.id_value AS VARCHAR2(4000))                                                  AS medicaid_alt_id,
           CAST(d.md.exception_code AS VARCHAR2(4000))                                            AS medicaid_exception_code,
           xm.EXCEPTION_DESC AS medicaid_exception_desc, xm.EXCEPTION_TYPE AS medicaid_exception_type,
           t2.MSTR_REF_CODE AS medicaid_tp_cd, t2.MSTR_REF_LABEL AS medicaid_tp_lbl,
           t2.SRC_SYS AS medicaid_tp_sys,
           /* VALIDATION: exp_validate_ssn + Lkp_EXC_LOOKUP_CODE_VALUE_SSN (looked-up code) */
           xn.EXCEPTION_CODE AS ssn_exception_code, xn.EXCEPTION_DESC AS ssn_exception_desc,
           xn.EXCEPTION_TYPE AS ssn_exception_type,
           t3.MSTR_REF_CODE AS ssn_tp_cd, t3.MSTR_REF_LABEL AS ssn_tp_lbl, t3.SRC_SYS AS ssn_tp_sys
      FROM WRK_CRE_CARE_S3_RANKED d
      LEFT JOIN lkp_exc xg ON xg.EXCEPTION_CODE = CAST(d.gd.exception_code AS VARCHAR2(4000))
      LEFT JOIN lkp_exc xs ON xs.EXCEPTION_CODE = d.suffix_exception_code
      LEFT JOIN lkp_exc xe ON xe.EXCEPTION_CODE = fn_snow_helper18_common(d.ethnicity_mstr, 'Invalid_Ethnicity')
      LEFT JOIN lkp_exc xr ON xr.EXCEPTION_CODE = fn_snow_helper18_common(d.race_mstr, 'Invalid_Race')
      LEFT JOIN lkp_exc xp ON xp.EXCEPTION_CODE = d.phone_code
      LEFT JOIN lkp_exc xm ON xm.EXCEPTION_CODE = CAST(d.md.exception_code AS VARCHAR2(4000))
      LEFT JOIN lkp_exc xn ON xn.EXCEPTION_CODE = CASE WHEN CAST(d.sn.ssn_status AS VARCHAR2(4000)) = 'Invalid'
                                                      AND d.ssn_out IS NOT NULL THEN 'Invalid_SSN' ELSE NULL END
      LEFT JOIN lkp_exc xa ON xa.EXCEPTION_CODE = 'Invalid_Address'
      LEFT JOIN lkp_mc mc ON mc.MATCH_CODE = CAST(d.av.match_code AS VARCHAR2(4000))
      LEFT JOIN alt_tp t1 ON t1.SRC_CODE_VALUE = 'CARE ID'
      LEFT JOIN alt_tp t2 ON t2.SRC_CODE_VALUE = 'Medicaid ID'
      LEFT JOIN alt_tp t3 ON t3.SRC_CODE_VALUE = 'SSN']' USING P_RLE_BO_CLASS_CD_MEMBER, P_RUN_TS, P_DEFAULT_NONUS_STATE_CD;
    SELECT COUNT(*) INTO l_rows FROM WRK_CRE_CARE_S4_FLAT;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'FLAT_ADDR_ALTID', 'COMPLETED', NULL, 'Step 40 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_CRE_CARE_S40_FLAT;
/

