-- ============================================================================
-- sp_snow_step_TTF_PTY_S20_DQ  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TTF)
--
-- Mapping: m_Tgt_C_S_TTF_Pty, workflow wf_TTF_Stage_Load, step 20.
-- Step name (checkpoint): DQ.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TTF_PTY_S2_DQ. Reads ONLY WRK_TTF_PTY_S1_ACTIVE (plus reference lookups / target guard tables where the original reads them; those are not work-table dependencies).
--
-- DOES IT FEED THE SPINE?
--   Indirectly: it is an early staged step; every later step reads (transitively) from it, and the publish branches read the final routed table, which derives from it. It writes no target itself.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only. Snowflake cannot
--   parameterise table names in static SQL, so P_INPUT_TABLES is a
--   dependency declaration + runtime check, NOT dynamic SQL: the CTAS
--   below still names its source work table literally, as in the
--   current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-20 SELECT verbatim. Only
--   substitution: :l_run_ts -> :P_RUN_TS; :c_mapping resolves to the
--   local constant below (used by the checkpoint and, where the
--   original used it, materialised into the work table). No business
--   expression, filter, guard or column list was changed. This step uses no original parameter.
--   It references the run timestamp (:P_RUN_TS).
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   in the v2 10-argument form. P_JOB_RUN_ID is present in every new
--   proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_TTF_PTY_S20_DQ (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TTF_PTY_S1_ACTIVE') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TTF';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TTF_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TTF_Pty';
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

    -- ---- Step 20: DQ (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TTF_PTY_S2_DQ';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TTF_PTY_S2_DQ AS WITH
    lkp_cv   AS (SELECT * FROM TABLE(fn_snow_helper41_common())),
    lkp_junk AS (SELECT * FROM TABLE(fn_snow_helper43_common()))
    SELECT a.*,
           fn_snow_helper15_common(a.FIRSTNAME, a.MIDDLENAME, a.LASTNAME,
               TRIM(NVL(CASE WHEN a.FIRSTNAME = 1 THEN 1 ELSE 0 END, '') || CASE WHEN a.MIDDLENAME IS NOT NULL THEN ' ' || TRIM(a.MIDDLENAME) ELSE '' END
                    || ' ' || NVL(LTRIM(a.LASTNAME), '')),
               NULL, NULL, NULL, NULL, jf.NAME IS NOT NULL, jl.NAME IS NOT NULL)        AS nm,
           fn_snow_helper17_common(a.gender, 'Indv', 'TTF')                            AS gd,
           /* VALIDATION */ fn_snow_helper16_common(a.DOB, 'Indv', 'TTF', :1)  AS birth_exception_code,
           et.MSTR_CODE_VALUE                                                          AS ethnicity_mstr,
           rc.MSTR_CODE_VALUE                                                          AS race_mstr
      FROM WRK_TTF_PTY_S1_ACTIVE a
      LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(a.FIRSTNAME)) AND jf.IS_FIRST_JUNK = 1
      LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(a.LASTNAME)) AND jl.IS_LAST_JUNK = 1
      LEFT JOIN lkp_cv et ON et.CODE_TYPE = 'ETHNICITY' AND et.SRC_SYS = 'TTF' AND et.SRC_CODE_VALUE = a.ethnicity
      LEFT JOIN lkp_cv rc ON rc.CODE_TYPE = 'RACE' AND rc.SRC_SYS = 'TTF' AND rc.SRC_CODE_VALUE = a.RACEETHNICITYID]' USING P_RUN_TS;
    SELECT COUNT(*) INTO l_rows FROM WRK_TTF_PTY_S2_DQ;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'DQ', 'COMPLETED', NULL, 'Step 20 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TTF_PTY_S20_DQ;
/

