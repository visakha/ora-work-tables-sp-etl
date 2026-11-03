-- ============================================================================
-- sp_snow_step_WIC_ADR_S30_FLAT  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (WIC)
--
-- Mapping: m_Tgt_C_S_WIC_Pty_Addr, workflow wf_WIC_Stage_Load, step 30.
-- Step name (checkpoint): FLAT.
--
-- WHAT THIS STEP PRODUCES
--   WRK_WIC_ADDR_S30_FLAT: Validation result pulled out into flat columns; match-code description resolved.
--
-- DOES IT FEED THE SPINE?
--   Indirectly: it is a staged step; every later step reads (transitively) from it, and the publish branches read the final step, which derives from it. It writes no target itself.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only. Default: 'WRK_WIC_ADDR_S20_VALIDATED'. Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT dynamic SQL: the CTAS below still names its sources literally, as in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-30 SELECT verbatim. Only substitution: :l_run_ts -> :P_RUN_TS (not used by this step), :c_mapping -> the local constant below (used by the checkpoint). Original-parameter refs: none. No business expression, filter, guard or column list was changed.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no transactions, no target writes. This proc writes its own checkpoint in the v2 10-argument form (STEP_NAME, STEP_STATUS, TARGET_TABLE, MESSAGE, ERROR_MESSAGE; STEP_NO, row count and work-table arguments dropped per the new signature). P_JOB_RUN_ID is present in every new proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_WIC_ADR_S30_FLAT (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_WIC_ADDR_S20_VALIDATED') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'WIC';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_WIC_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_WIC_Pty_Addr';
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

    -- ---- Step 30: FLAT (verbatim from current main)
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_WIC_ADDR_S30_FLAT';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_WIC_ADDR_S30_FLAT AS WITH
    lkp_mc AS (SELECT * FROM TABLE(fn_snow_helper46_common()))
    SELECT v.*,
           CAST(v.av.delivery_address_line1 AS VARCHAR2(4000))          AS a_line1,
           CAST(v.av.delivery_address_line2 AS VARCHAR2(4000))          AS a_line2,
           CAST(v.av.city AS VARCHAR2(4000))                            AS a_city,
           CAST(v.av.postcode_complete AS VARCHAR2(4000))               AS a_postcode_complete,
           CAST(v.av.zip_cd_5 AS VARCHAR2(4000))                        AS a_zip_cd_5,
           CAST(v.av.zip_cd_4_extn AS VARCHAR2(4000))                   AS a_zip_cd_4_extn,
           CAST(v.av.country_iso2_char AS VARCHAR2(4000))               AS a_country,
           CAST(v.av.mailability_score AS VARCHAR2(4000))               AS a_mailability_score,
           CAST(v.av.match_code AS VARCHAR2(4000))                      AS a_match_code,
           mc.DESCRIPTION                                AS a_match_code_description,
           fn_snow_helper04_common(CAST(v.av.status_info_result_percentage AS VARCHAR2(4000)), 2) AS a_result_pct,
           CAST(v.av.address_type AS VARCHAR2(4000))                    AS a_address_type,
           CAST(v.av.county_fips_cd AS VARCHAR2(4000))                  AS a_county_fips,
           CAST(v.av.state_fips_cd AS VARCHAR2(4000))                   AS a_state_fips,
           CAST(v.av.geocoding_latitude AS NUMBER(38, 6))        AS a_latitude,
           CAST(v.av.geocoding_longitude AS NUMBER(38, 6))       AS a_longitude,
           CAST(v.av.geocoding_status AS VARCHAR2(4000))                AS a_geocoding_status,
           CAST(v.av.residential_delivery_indicator AS VARCHAR2(4000))  AS a_residential,
           CAST(v.av.organization_name AS VARCHAR2(4000))               AS a_org_name,
           CAST(v.av.organization_descriptor AS VARCHAR2(4000))         AS a_org_descriptor,
           CAST(v.av.organization_department AS VARCHAR2(4000))         AS a_org_department,
           CAST(v.av.building_complete AS VARCHAR2(4000))               AS a_building_complete,
           CAST(v.av.building_name AS VARCHAR2(4000))                   AS a_building_name,
           CAST(v.av.building_number AS VARCHAR2(4000))                 AS a_building_number,
           CAST(v.av.sub_building_complete AS VARCHAR2(4000))           AS a_sub_building_complete,
           CAST(v.av.sub_building_descriptor AS VARCHAR2(4000))         AS a_sub_building_descriptor,
           CAST(v.av.early_warning_system_return_cd AS VARCHAR2(4000))  AS a_early_warning,
           CAST(v.av.cass_error_code AS VARCHAR2(4000))                 AS a_cass_error,
           CAST(v.av.dpv_confirmation AS VARCHAR2(4000))                AS a_dpv
      FROM WRK_WIC_ADDR_S20_VALIDATED v
      LEFT JOIN lkp_mc mc ON mc.MATCH_CODE = CAST(v.av.status_info_match_code AS VARCHAR2(4000))]';
    SELECT COUNT(*) INTO l_rows FROM WRK_WIC_ADDR_S30_FLAT;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'FLAT', 'COMPLETED', NULL, 'Step 30 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_WIC_ADR_S30_FLAT;
/

