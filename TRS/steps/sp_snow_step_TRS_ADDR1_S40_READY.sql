-- ============================================================================
-- sp_snow_step_TRS_ADDR1_S40_READY  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Addr_1, workflow wf_TRS_Stage_Load_1_Ongoing, step 40.
-- Step name (checkpoint): READY_TO_PUBLISH.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_ADDR1_S40_READY: READY -- match-code description, guards
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (pipe-delimited). Default: 'WRK_TRS_ADDR1_S30_VALIDATED'.
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-40 SELECT verbatim. Only
--   substitution: :l_run_ts -> :P_RUN_TS (where used); :c_mapping is
--   the local constant below. No business expression, filter, guard
--   or column list was changed. This step uses original parameters:
--   none.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   in the 10-argument form. P_JOB_RUN_ID is present in every new proc
--   in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_ADDR1_S40_READY (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_ADDR1_S30_VALIDATED') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TRS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Addr_1';
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

    -- ---- Step 40: READY_TO_PUBLISH (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_ADDR1_S40_READY';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_ADDR1_S40_READY AS WITH
    lkp_mc AS (SELECT * FROM TABLE(fn_snow_helper46_common()))
    SELECT * FROM (SELECT v.ADDR_ID, CAST(v.av.delivery_address_line1 AS VARCHAR2(4000)) AS ADDR_LN_1,
           CAST(v.av.delivery_address_line2 AS VARCHAR2(4000)) AS ADDR_LN_2,
           CAST(v.av.building_name AS VARCHAR2(4000)) AS BLDNG_NM, CAST(v.av.sub_building_number AS VARCHAR2(4000)) AS FLR_NUM,
           CAST(v.av.city AS VARCHAR2(4000)) AS CITY, CAST(v.av.county_fips_cd AS VARCHAR2(4000)) AS COUNTY,
           CAST(v.av.state_fips_cd AS VARCHAR2(4000)) AS STATE, CAST(v.av.country_iso2_char AS VARCHAR2(4000)) AS CNTRY_CD,
           CAST(v.av.zip_cd_5 AS VARCHAR2(4000)) AS PSTL_CD, CAST(v.av.zip_cd_4_extn AS VARCHAR2(4000)) AS PSTL_CD_EXT,
           CAST(v.av.geocoding_latitude AS NUMBER(38, 6)) AS LATTD,
           CAST(v.av.geocoding_longitude AS NUMBER(38, 6)) AS LNGTD,
           CAST(v.av.match_code AS VARCHAR2(4000)) AS VLDTN_MSG, mc.DESCRIPTION AS VLDTN_DESC,
           CAST(v.av.mailability_score AS VARCHAR2(4000)) AS MLBLTY_SCR, CAST(v.av.address_type AS VARCHAR2(4000)) AS ADDR_TP_CD,
           CAST(v.av.organization_descriptor AS VARCHAR2(4000)) AS ORG_DESC,
           CAST(v.av.organization_name AS VARCHAR2(4000)) AS ORG_NM, CAST(v.av.building_number AS VARCHAR2(4000)) AS BLDG_NMBR,
           CAST(v.av.sub_building_complete AS VARCHAR2(4000)) AS SUB_BLDG_NM,
           CAST(v.av.sub_building_descriptor AS VARCHAR2(4000)) AS SUB_BLDG_DESC,
           CAST(v.av.geocoding_status AS VARCHAR2(4000)) AS GEOCD_STS_CD,
           CAST(v.av.residential_delivery_indicator AS VARCHAR2(4000)) AS RSDNTL_DLVRY_IND,
           CAST(v.av.status_info_result_percentage AS VARCHAR2(4000)) AS ADDRDR_RSLT_PCT,
           CAST(v.av.early_warning_system_return_cd AS VARCHAR2(4000)) AS ERLY_WRNG_CD,
           CAST(v.av.cass_error_code AS VARCHAR2(4000)) AS CASS_ERR_CD,
           CAST(v.av.dpv_confirmation AS VARCHAR2(4000)) AS DLVRY_PNT_VLDN,
           v.addr_line_1 AS SRC_ADDR_LN_1, v.addr_line_2 AS SRC_ADDR_LN_2,
           v.ADDR_CITY AS SRC_CITY, NULL AS SRC_COUNTY,
           v.ADDR_STATE_CD AS SRC_STATE, 'US' AS SRC_CNTRY,
           v.ADDR_ZIP5 AS SRC_PSTL_CD, v.ADDR_ZIP4 AS SRC_PSTL_CD_EXT,
           CAST(v.av.organization_department AS VARCHAR2(4000)) AS ORG_DEPT
      , ROW_NUMBER() OVER (PARTITION BY v.ADDR_ID ORDER BY v.addr_line_1) AS __qual_rn FROM WRK_TRS_ADDR1_S30_VALIDATED v
      LEFT JOIN lkp_mc mc ON mc.MATCH_CODE = CAST(v.av.status_info_match_code AS VARCHAR2(4000))
      LEFT JOIN (SELECT DISTINCT ADDR_ID FROM STG_TRS_D_UNQ_ADDR) xu ON xu.ADDR_ID = v.ADDR_ID
     WHERE xu.ADDR_ID IS NULL) WHERE __qual_rn = 1]';
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_ADDR1_S40_READY;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'READY_TO_PUBLISH', 'COMPLETED', 'STG_TRS_D_UNQ_ADDR', 'Step 40 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_ADDR1_S40_READY;
/

