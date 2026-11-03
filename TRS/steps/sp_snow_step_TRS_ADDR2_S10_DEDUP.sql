-- ============================================================================
-- sp_snow_step_TRS_ADDR2_S10_DEDUP  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Addr_2, workflow wf_TRS_Stage_Load_1_Ongoing, step 10.
-- Step name (checkpoint): ADDR_DEDUP.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_ADDR2_S10_DEDUP: DE-DUPLICATE ADDRESSES (BR-31)
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
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_ADDR2_S10_DEDUP (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT '') RETURN NUMBER AUTHID CURRENT_USER AS
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

    -- ---- Step 10: ADDR_DEDUP (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_ADDR2_S10_DEDUP';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_ADDR2_S10_DEDUP AS SELECT a.indv_id, a.case_num, a.edg_num, a.addr_type_cd,
           NVL(TO_CHAR(a.addr_st_num), '') || '|' || NVL(a.addr_st_num_frac, '') || '|'
           || NVL(a.addr_st_nm, '') || '|' || NVL(CASE WHEN a.addr_st_dir_cd = 1 THEN 1 ELSE 0 END, '') || '|' || NVL(a.addr_st_type_cd, '')
           || '|' || NVL(a.addr_dwelling_type_cd, '') || '|' || NVL(a.addr_apt_num, '') || '|'
           || NVL(a.addr_line, '') || '|' || NVL(CASE WHEN a.addr_city = 1 THEN 1 ELSE 0 END, '') || '|' || NVL(CASE WHEN a.addr_state_cd = 1 THEN 1 ELSE 0 END, '') || '|'
           || NVL(TO_CHAR(a.addr_zip5), '') || '|' || NVL(TO_CHAR(a.addr_zip4), '') AS addr_id,
           GREATEST(a.create_dt, NVL(a.update_dt, a.create_dt)) AS create_dt, a.eff_begin_dt, a.eff_end_dt,
           ROW_NUMBER() OVER (PARTITION BY a.indv_id, a.addr_type_cd, a.case_num, a.edg_num
                              ORDER BY GREATEST(a.create_dt, NVL(a.update_dt, a.create_dt)) DESC,
                                       a.eff_begin_dt DESC) AS key_rn
      FROM STG_TRS_D_INDV_ADDR a]';
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_ADDR2_S10_DEDUP;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'ADDR_DEDUP', 'COMPLETED', NULL, 'Step 10 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_ADDR2_S10_DEDUP;
/

