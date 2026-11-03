-- ============================================================================
-- sp_snow_step_TRS_ADDR1_S10_SRC  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Addr_1, workflow wf_TRS_Stage_Load_1_Ongoing, step 10.
-- Step name (checkpoint): SRC_DISTINCT_ADDR.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_ADDR1_S10_SRC: DISTINCT ADDRESSES FROM THE EXTRACT (BR-31)
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (pipe-delimited). Default: ''.
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-10 SELECT verbatim. Only
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
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_ADDR1_S10_SRC (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT '') RETURN NUMBER AUTHID CURRENT_USER AS
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

    -- ---- Step 10: SRC_DISTINCT_ADDR (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_ADDR1_S10_SRC';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_ADDR1_S10_SRC AS SELECT DISTINCT
           NVL(TO_CHAR(a.addr_st_num), '') || '|' || NVL(a.addr_st_num_frac, '') || '|' || NVL(a.addr_st_nm, '')
           || '|' || NVL(CASE WHEN a.addr_st_dir_cd = 1 THEN 1 ELSE 0 END, '') || '|' || NVL(a.addr_st_type_cd, '') || '|'
           || NVL(a.addr_dwelling_type_cd, '') || '|' || NVL(a.addr_apt_num, '') || '|' || NVL(a.addr_line, '')
           || '|' || NVL(CASE WHEN a.addr_city = 1 THEN 1 ELSE 0 END, '') || '|' || NVL(CASE WHEN a.addr_state_cd = 1 THEN 1 ELSE 0 END, '') || '|' || NVL(TO_CHAR(a.addr_zip5), '')
           || '|' || NVL(TO_CHAR(a.addr_zip4), '')                                   AS ADDR_ID,
           a.addr_st_num AS ADDR_ST_NUM, a.addr_st_num_frac AS ADDR_ST_NUM_FRAC, a.addr_st_nm AS ADDR_ST_NM,
           a.addr_apt_num AS ADDR_APT_NUM, a.addr_line AS ADDR_LINE, a.addr_city AS ADDR_CITY,
           a.addr_state_cd AS ADDR_STATE_CD, a.addr_zip5 AS ADDR_ZIP5, a.addr_zip4 AS ADDR_ZIP4,
           a.addr_dwelling_type_cd AS ADDR_DWELLING_TYPE_CD, a.addr_st_type_cd AS ADDR_ST_TYPE_CD,
           a.addr_st_dir_cd AS ADDR_ST_DIR_CD
      FROM STG_TRS_D_INDV_ADDR a]';
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_ADDR1_S10_SRC;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'SRC_DISTINCT_ADDR', 'COMPLETED', NULL, 'Step 10 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_ADDR1_S10_SRC;
/

