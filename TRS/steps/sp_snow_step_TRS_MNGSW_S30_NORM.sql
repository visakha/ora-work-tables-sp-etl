-- ============================================================================
-- sp_snow_step_TRS_MNGSW_S30_NORM  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw, workflow wf_TRS_Stage_Load_1_Ongoing, step 30.
-- Step name (checkpoint): UNPIVOT_SWITCHES.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_MNGSW_S30_NORM: UNPIVOT -- one row per switch (BR-34)
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (pipe-delimited). Default: 'WRK_TRS_MNGSW_S20_SRC'.
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-30 SELECT verbatim. Only
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
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_MNGSW_S30_NORM (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_MNGSW_S20_SRC') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TRS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_Mng_Attr_Sw';
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

    -- ---- Step 30: UNPIVOT_SWITCHES (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_MNGSW_S30_NORM';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_MNGSW_S30_NORM AS SELECT s.PTY_PK, s.EFF_BEGIN_DT, s.CREATE_DT AS SRC_LAST_UPD_DT, 'File_Clearance_SW' AS ATTR_TYPE,
           TO_CHAR(s.FILE_CLEARANCE_SW) AS ATTR_VALUE FROM WRK_TRS_MNGSW_S20_SRC s
    UNION ALL
    SELECT s.PTY_PK, s.EFF_BEGIN_DT, s.CREATE_DT, 'SSA_Validation_SW', TO_CHAR(s.SSA_VALIDATION_SW) FROM WRK_TRS_MNGSW_S20_SRC s
    UNION ALL
    SELECT s.PTY_PK, s.EFF_BEGIN_DT, s.CREATE_DT, 'TW_Convert_Ind', TO_CHAR(s.TW_CONVERT_IND) FROM WRK_TRS_MNGSW_S20_SRC s
    UNION ALL
    SELECT s.PTY_PK, s.EFF_BEGIN_DT, s.CREATE_DT, 'LTC_Convert_Ind', TO_CHAR(s.LTC_CONVERT_IND) FROM WRK_TRS_MNGSW_S20_SRC s
    UNION ALL
    SELECT s.PTY_PK, s.EFF_BEGIN_DT, s.CREATE_DT, 'Source_Table', TO_CHAR(s.SRC_TBL) FROM WRK_TRS_MNGSW_S20_SRC s]';
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_MNGSW_S30_NORM;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'UNPIVOT_SWITCHES', 'COMPLETED', NULL, 'Step 30 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_MNGSW_S30_NORM;
/

