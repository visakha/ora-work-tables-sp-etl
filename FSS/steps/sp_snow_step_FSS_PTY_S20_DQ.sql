-- ============================================================================
-- sp_snow_step_FSS_PTY_S20_DQ  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (FSS)
--
-- Mapping: m_Tgt_C_S_FSS_Pty, workflow wf_FSS_Stage_Load, step 20.
-- Step name (checkpoint): DQ_CHECKS.
--
-- WHAT THIS STEP PRODUCES
--   WRK_FSS_PTY_S2_DQ: Name standardisation, gender, birth date, ethnicity, race, language, suffix checks.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (default: 'WRK_FSS_PTY_S1_SRC').
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-20 SELECT verbatim. Only
--   substitution: :l_run_ts -> :P_RUN_TS,
--   :c_mapping -> the local constant below (used by the checkpoint).
--   No business expression, filter, guard or column list was changed.
--   Original parameters used by this step: none; this step uses :P_RUN_TS (substituted from :l_run_ts).
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   in the v2 10-argument form (TARGET_TABLE NULL, as in the current
--   main's step checkpoints; row count survives in the RETURN value
--   and the driver's helper36 summary line).
--   P_JOB_RUN_ID is present in every new proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_FSS_PTY_S20_DQ (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_FSS_PTY_S1_SRC') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'FSS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_FSS_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_FSS_Pty';
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

    -- ---- Step 20: DQ_CHECKS (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_FSS_PTY_S2_DQ';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_FSS_PTY_S2_DQ AS WITH
    lkp_cv     AS (SELECT * FROM TABLE(fn_snow_helper41_common())),
    lkp_cv_any AS (SELECT * FROM TABLE(fn_snow_helper42_common())),
    lkp_junk   AS (SELECT * FROM TABLE(fn_snow_helper43_common()))
    SELECT a.*,
           fn_snow_helper15_common(a.NM_FIRST, a.NM_MIDDLE, a.NM_LAST,
               TRIM(NVL(CASE WHEN a.NM_FIRST = 1 THEN 1 ELSE 0 END, '') || CASE WHEN a.NM_MIDDLE IS NOT NULL THEN ' ' || TRIM(a.NM_MIDDLE) ELSE '' END
                    || ' ' || NVL(LTRIM(a.NM_LAST), '')),
               NULL, a.CD_SUFFIX, NULL, nsx.MSTR_CODE_VALUE,
               jf.NAME IS NOT NULL, jl.NAME IS NOT NULL)                                    AS nm,
           fn_snow_helper17_common(a.CD_GENDER, 'Indv', 'FSS')                              AS gd,
           /* VALIDATION */ fn_snow_helper16_common(a.DT_DOB, 'Indv', 'FSS', :1)     AS birth_exception_code,
           et.MSTR_CODE_VALUE                                                               AS ethnicity_mstr,
           fn_snow_helper19_common(a.RACE_WHITE, a.RACE_AA, a.RACE_ASIAN, a.RACE_PI, a.RACE_AN) AS rc,
           lg.MSTR_CODE_VALUE                                                               AS language_mstr,
           sx.MSTR_CODE_VALUE                                                               AS std_suffix,
           /* VALIDATION */ fn_snow_helper20_common(a.CD_SUFFIX, sx.MSTR_CODE_VALUE)       AS suffix_exception_code
      FROM WRK_FSS_PTY_S1_SRC a
      LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(a.NM_FIRST)) AND jf.IS_FIRST_JUNK = 1
      LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(a.NM_LAST)) AND jl.IS_LAST_JUNK = 1
      -- lkp_V_Lookup_Sfx_Code_Value inside the name mapplet (CODE_TYPE 'SUFFIX')
      LEFT JOIN lkp_cv nsx ON nsx.CODE_TYPE = 'SUFFIX' AND nsx.SRC_SYS = 'FSS' AND nsx.SRC_CODE_VALUE = a.CD_SUFFIX
      LEFT JOIN lkp_cv et  ON et.CODE_TYPE = 'ETHNICITY' AND et.SRC_SYS = 'FSS' AND et.SRC_CODE_VALUE = a.CD_HISPANIC
      LEFT JOIN lkp_cv lg  ON lg.CODE_TYPE = 'LANGUAGE_CD' AND lg.SRC_SYS = 'FSS' AND lg.SRC_CODE_VALUE = a.LANGUAGE_CD
      -- rule_Suffix_Std's lkp_V_LOOKUP_CODE_VALUE (no code-type filter)
      LEFT JOIN lkp_cv_any sx ON sx.SRC_SYS = 'FSS' AND sx.SRC_CODE_VALUE = a.CD_SUFFIX]' USING P_RUN_TS;
    SELECT COUNT(*) INTO l_rows FROM WRK_FSS_PTY_S2_DQ;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'DQ_CHECKS', 'COMPLETED', NULL, 'Step 20 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_FSS_PTY_S20_DQ;
/

