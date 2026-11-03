-- ============================================================================
-- sp_snow_step_TRS_STGTOA_S10_KEYED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Stg_TOA, workflow wf_TRS_Stage_Load_TOA, step 10.
-- Step name (checkpoint): CATALOGUE_KEYED.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_LUTOA_S10_KEYED: CATALOGUE ROWS, KEYED (BR-51)
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
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_STGTOA_S10_KEYED (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT '') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TRS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TRS_Stage_Load_TOA';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Stg_TOA';
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

    -- ---- Step 10: CATALOGUE_KEYED (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_LUTOA_S10_KEYED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_LUTOA_S10_KEYED AS WITH
    lkp_toa AS (
        SELECT * FROM (SELECT l.MSTR_REF_LABEL, l.MSTR_REF_CODE , ROW_NUMBER() OVER (PARTITION BY l.MSTR_REF_LABEL ORDER BY l.MSTR_REF_CODE) AS __qual_rn FROM LOOKUP_CODE_VALUE l
         WHERE l.CODE_TYPE = 'TOA') WHERE __qual_rn = 1
    ),
    lkp_pgm AS (
        SELECT * FROM (SELECT l.MSTR_REF_LABEL, l.MSTR_REF_CODE , ROW_NUMBER() OVER (PARTITION BY l.MSTR_REF_LABEL ORDER BY l.MSTR_REF_CODE) AS __qual_rn FROM LOOKUP_CODE_VALUE l
         WHERE l.CODE_TYPE = 'MEMBER_PRG') WHERE __qual_rn = 1
    )
    SELECT s.*,
           SUBSTR(lt.MSTR_REF_CODE, 1, 10) AS pkey_src_object,
           lt.MSTR_REF_LABEL AS toa_lbl,
           SUBSTR(lp.MSTR_REF_CODE, 1, 9) AS mbr_prg_cd
      FROM STG_TRS_D_LU_TOA s
      LEFT JOIN lkp_toa lt ON lt.MSTR_REF_LABEL = s.TOA_CODE
      LEFT JOIN lkp_pgm lp ON lp.MSTR_REF_LABEL = s.PROGRAM_CODE]';
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_LUTOA_S10_KEYED;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'CATALOGUE_KEYED', 'COMPLETED', NULL, 'Step 10 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_STGTOA_S10_KEYED;
/

