-- ============================================================================
-- sp_snow_step_TRS_AUTHREP_S10_PAYEE  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing, workflow wf_TRS_Stage_Load_1_Ongoing, step 10.
-- Step name (checkpoint): PAYEE_CASE_ROWS.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_MNGAR_S10_PAYEE: PAYEE / CASE / EDG ROWS (BR-35)
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
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_AUTHREP_S10_PAYEE (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT '') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TRS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing';
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

    -- ---- Step 10: PAYEE_CASE_ROWS (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_MNGAR_S10_PAYEE';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_MNGAR_S10_PAYEE AS SELECT ed.indv_id, 'Y' AS AR_FLAG, ed.elig_eff_begin_dt AS eff_begin_dt, ed.elig_eff_end_dt AS eff_end_dt,
           p.create_dt AS create_dt
      FROM STG_TRS_D_DC_PRIMARY_PAYEE p
      JOIN STG_TRS_CV_ED_MCI_EDG_INDV ed
        ON p.case_num = ed.case_num = 1 AND p.edg_num = ed.edg_num = 1 AND ed.elig_eff_end_dt IS NULL
      JOIN STG_TRS_DC_CASES c ON p.case_num = c.case_num
     WHERE (p.ADDR_TYPE_CD = 'MA' OR p.ADDR_TYPE_CD IS NULL) AND p.ALT_PAYEE_EXISTS_SW = 'Y'
       AND c.AUTHREP_VERF_CD IN ('CS', 'FH', 'LD', 'OA') AND c.SENT_AUTHREP_SW = 'Y'
    UNION ALL
    SELECT ed.indv_id, 'Y', ed.elig_eff_begin_dt, ed.elig_eff_end_dt, p.create_dt
      FROM STG_TRS_D_DC_CASES c
      JOIN STG_TRS_DC_PRIMARY_PAYEE p ON p.case_num = c.case_num
      JOIN STG_TRS_CV_ED_MCI_EDG_INDV ed
        ON p.case_num = ed.case_num = 1 AND p.edg_num = ed.edg_num = 1 AND ed.elig_eff_end_dt IS NULL
     WHERE (p.ADDR_TYPE_CD = 'MA' OR p.ADDR_TYPE_CD IS NULL) AND p.ALT_PAYEE_EXISTS_SW = 'Y'
       AND c.AUTHREP_VERF_CD IN ('CS', 'FH', 'LD', 'OA') AND c.SENT_AUTHREP_SW = 'Y'
    UNION ALL
    SELECT ed.indv_id, 'Y', ed.elig_eff_begin_dt, ed.elig_eff_end_dt, p.create_dt
      FROM STG_TRS_DC_CASES c
      JOIN STG_TRS_DC_PRIMARY_PAYEE p ON p.case_num = c.case_num
      JOIN STG_TRS_D_CV_ED_MCI_EDG_INDV ed
        ON p.case_num = ed.case_num = 1 AND p.edg_num = ed.edg_num = 1 AND ed.elig_eff_end_dt IS NULL
     WHERE (p.ADDR_TYPE_CD = 'MA' OR p.ADDR_TYPE_CD IS NULL) AND p.ALT_PAYEE_EXISTS_SW = 'Y'
       AND c.AUTHREP_VERF_CD IN ('CS', 'FH', 'LD', 'OA') AND c.SENT_AUTHREP_SW = 'Y'
    UNION ALL
    SELECT ci.indv_id, 'Y', ed.elig_eff_begin_dt, ed.elig_eff_end_dt, NVL(p.create_dt, ed.create_dt)
      FROM STG_TRS_D_CV_ED_MCI_EDG_INDV ed
      LEFT JOIN STG_TRS_DC_PRIMARY_PAYEE p
        ON ed.case_num = p.case_num = 1 AND ed.edg_num = p.edg_num = 1 AND ed.elig_eff_end_dt IS NULL
       AND (p.ADDR_TYPE_CD = 'MA' OR p.ADDR_TYPE_CD IS NULL) AND p.ALT_PAYEE_EXISTS_SW = 'Y'
       AND p.edg_num IS NULL
      JOIN STG_TRS_DC_CASES c ON ed.case_num = c.case_num
      JOIN STG_TRS_DC_CASE_INDV ci ON c.case_num = ci.case_num
     WHERE c.AUTHREP_VERF_CD IN ('CS', 'FH', 'LD', 'OA') AND c.SENT_AUTHREP_SW = 'Y'
    UNION ALL
    SELECT ci.indv_id, 'Y', ed.elig_eff_begin_dt, ed.elig_eff_end_dt, p.create_dt
      FROM STG_TRS_CV_ED_MCI_EDG_INDV ed
      JOIN STG_TRS_D_DC_PRIMARY_PAYEE p
        ON ed.case_num = ed.case_num = 1 AND ed.edg_num = ed.edg_num = 1 AND ed.elig_eff_end_dt IS NULL
       AND (p.ADDR_TYPE_CD = 'MA' OR p.ADDR_TYPE_CD IS NULL) AND p.ALT_PAYEE_EXISTS_SW = 'Y'
       AND p.edg_num IS NULL
      JOIN STG_TRS_DC_CASES c ON ed.case_num = c.case_num
      JOIN STG_TRS_DC_CASE_INDV ci ON c.case_num = ci.case_num
     WHERE c.AUTHREP_VERF_CD IN ('CS', 'FH', 'LD', 'OA') AND c.SENT_AUTHREP_SW = 'Y'
    UNION ALL
    SELECT ci.indv_id, 'Y', ed.elig_eff_begin_dt, ed.elig_eff_end_dt, NVL(p.create_dt, ed.create_dt)
      FROM STG_TRS_CV_ED_MCI_EDG_INDV ed
      LEFT JOIN STG_TRS_DC_PRIMARY_PAYEE p
        ON ed.case_num = p.case_num = 1 AND ed.edg_num = p.edg_num = 1 AND ed.elig_eff_end_dt IS NULL
       AND (p.ADDR_TYPE_CD = 'MA' OR p.ADDR_TYPE_CD IS NULL) AND p.ALT_PAYEE_EXISTS_SW = 'Y'
       AND p.edg_num IS NULL
      JOIN STG_TRS_DC_CASES c ON ed.case_num = c.case_num
      JOIN STG_TRS_DC_CASE_INDV ci ON c.case_num = ci.case_num
     WHERE c.AUTHREP_VERF_CD IN ('CS', 'FH', 'LD', 'OA') AND c.SENT_AUTHREP_SW = 'Y']';
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_MNGAR_S10_PAYEE;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'PAYEE_CASE_ROWS', 'COMPLETED', NULL, 'Step 10 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_AUTHREP_S10_PAYEE;
/

