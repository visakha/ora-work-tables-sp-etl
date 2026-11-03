-- ============================================================================
-- sp_snow_step_TRS_ADDR2_S20_SRC  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Addr_2, workflow wf_TRS_Stage_Load_1_Ongoing, step 20.
-- Step name (checkpoint): SRC_VALIDATED_JOIN.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_ADDR2_S20_SRC: JOIN TO VALIDATED ADDRESSES + VALID MEMBERS
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (pipe-delimited). Default: 'WRK_TRS_ADDR2_S10_DEDUP'.
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-20 SELECT verbatim. Only
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
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_ADDR2_S20_SRC (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_ADDR2_S10_DEDUP') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TRS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Addr_2';
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

    -- ---- Step 20: SRC_VALIDATED_JOIN (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_ADDR2_S20_SRC';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_ADDR2_S20_SRC AS SELECT a.indv_id AS INDV_ID, a.case_num AS CASE_NUM, a.edg_num AS EDG_NUM, vm.pty_pk AS PTY_PK,
           a.addr_type_cd AS ADDR_TYPE_CD, a.create_dt AS CREATE_DT, a.eff_begin_dt AS EFF_BEGIN_DT,
           a.eff_end_dt AS EFF_END_DT, u.addr_id AS ADDR_ID, u.addr_ln_1 AS ADDR_LN_1, u.addr_ln_2 AS ADDR_LN_2,
           u.bldng_nm AS BLDNG_NM, u.flr_num AS FLR_NUM, u.city AS CITY, u.county AS COUNTY, u.state AS STATE,
           u.cntry_cd AS CNTRY_CD, u.pstl_cd AS PSTL_CD, u.pstl_cd_ext AS PSTL_CD_EXT, u.lattd AS LATTD,
           u.lngtd AS LNGTD, u.vldtn_msg AS VLDTN_MSG, u.vldtn_desc AS VLDTN_DESC, u.mlblty_scr AS MLBLTY_SCR,
           u.addr_tp_cd AS ADDR_TP_CD, u.org_desc AS ORG_DESC, u.org_dept AS ORG_DEPT, u.org_nm AS ORG_NM,
           u.bldg_nmbr AS BLDG_NMBR, u.sub_bldg_nm AS SUB_BLDG_NM, u.sub_bldg_desc AS SUB_BLDG_DESC,
           u.geocd_sts_cd AS GEOCD_STS_CD, u.rsdntl_dlvry_ind AS RSDNTL_DLVRY_IND,
           u.addrdr_rslt_pct AS ADDRDR_RSLT_PCT, u.erly_wrng_cd AS ERLY_WRNG_CD, u.cass_err_cd AS CASS_ERR_CD,
           u.dlvry_pnt_vldn AS DLVRY_PNT_VLDN, u.src_addr_ln_1 AS SRC_ADDR_LN_1,
           u.src_addr_ln_2 AS SRC_ADDR_LN_2, u.src_city AS SRC_CITY, u.src_county AS SRC_COUNTY,
           u.src_state AS SRC_STATE, u.src_cntry AS SRC_CNTRY, u.src_pstl_cd AS SRC_PSTL_CD,
           u.src_pstl_cd_ext AS SRC_PSTL_CD_EXT
      FROM WRK_TRS_ADDR2_S10_DEDUP a
      JOIN STG_TRS_D_UNQ_ADDR u ON a.addr_id = u.addr_id
      JOIN STG_TRS_VALID_MEMBERS vm ON a.indv_id = vm.indv_id
     WHERE a.key_rn = 1]';
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_ADDR2_S20_SRC;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'SRC_VALIDATED_JOIN', 'COMPLETED', NULL, 'Step 20 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_ADDR2_S20_SRC;
/

