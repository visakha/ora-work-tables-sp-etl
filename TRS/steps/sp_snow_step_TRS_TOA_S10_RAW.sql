-- ============================================================================
-- sp_snow_step_TRS_TOA_S10_RAW  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_TOA, workflow wf_TRS_Stage_Load_1_Ongoing, step 10.
-- Step name (checkpoint): TOA_SRC_RANKED.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_TOA_S10_RAW: TOA SOURCE ROWS, RANKED (BR-27/10)
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
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_TOA_S10_RAW (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT '') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TRS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_TOA';
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

    -- ---- Step 10: TOA_SRC_RANKED (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_TOA_S10_RAW';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_TOA_S10_RAW AS SELECT TO_CHAR(toa.INDV_ID) AS INDV_ID, toa.TYPE_OF_ASSISTANCE_CD, toa.ELIG_EFF_BEGIN_DT AS BEGIN_DT,
           toa.ELIG_EFF_END_DT AS END_DT, 'MCI_EDG_INDV' AS SRC_TBL,
           ROW_NUMBER() OVER (PARTITION BY TO_CHAR(toa.INDV_ID) || '|' || NVL(TO_CHAR(toa.EDG_NUM), '')
                                           || '|' || NVL(TO_CHAR(toa.PROGRAM_CD), '') || '|'
                                           || NVL(TO_CHAR(toa.MCI_CREATE_SEQ), '')
                              ORDER BY toa.CREATE_DT DESC) AS VERSION_SEQ,
           TO_CHAR(toa.INDV_ID) AS PTY_PK, toa.EDG_NUM, toa.CASE_NUM, toa.MCI_CREATE_SEQ, toa.PROGRAM_CD,
           toa.PART_STATUS_CD, toa.SYSTEM_CD, toa.CONVERT_DT, toa.CREATE_DT
      FROM STG_TRS_D_CV_MCI_EDG_INDV_TOA toa
      JOIN STG_TRS_VALID_MEMBERS vm ON TO_CHAR(toa.INDV_ID) = vm.PTY_PK
     WHERE toa.TYPE_OF_ASSISTANCE_CD IS NOT NULL
       AND (toa.CONVERSION_IND IS NULL OR toa.CONVERSION_IND = 'C')]';
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_TOA_S10_RAW;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'TOA_SRC_RANKED', 'COMPLETED', NULL, 'Step 10 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_TOA_S10_RAW;
/

