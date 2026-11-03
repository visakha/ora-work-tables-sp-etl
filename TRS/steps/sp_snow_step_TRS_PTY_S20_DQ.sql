-- ============================================================================
-- sp_snow_step_TRS_PTY_S20_DQ  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_OnGoing, workflow wf_TRS_Stage_Load_1_Ongoing, step 20.
-- Step name (checkpoint): DQ_STANDARDISE_VALIDATE.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_PTY_S2_DQ: STANDARDISE + VALIDATE (BR-15..19)
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (pipe-delimited). Default: 'WRK_TRS_PTY_S1_SRC'.
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
--   P_DC_INDV_TBL_SRC.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   in the 10-argument form. P_JOB_RUN_ID is present in every new proc
--   in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_PTY_S20_DQ (P_DC_INDV_TBL_SRC IN VARCHAR2 DEFAULT 'DC_INDV', P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_PTY_S1_SRC') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TRS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_OnGoing';
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

    -- ---- Step 20: DQ_STANDARDISE_VALIDATE (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_PTY_S2_DQ';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_PTY_S2_DQ AS WITH
    lkp_cv   AS (SELECT * FROM TABLE(fn_snow_helper41_common())),
    lkp_junk AS (SELECT * FROM TABLE(fn_snow_helper43_common())),
    lkp_exc  AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    dq AS (
        SELECT s.*,
               CASE WHEN s.SRC_TBL = :1 THEN TO_CHAR(s.INDV_ID) || '|' || :1 ELSE TO_CHAR(s.INDV_ID) END                                                     AS pkey_src_object,
               TRIM(NVL(CASE WHEN s.FIRST_NAME = 1 THEN 1 ELSE 0 END, '') || CASE WHEN s.MID_NAME IS NOT NULL THEN ' ' || TRIM(s.MID_NAME) ELSE '' END
                    || ' ' || NVL(LTRIM(s.LAST_NAME), ''))                                    AS src_full_name,
               fn_snow_helper15_common(s.FIRST_NAME, s.MID_NAME, s.LAST_NAME,
                   TRIM(NVL(CASE WHEN s.FIRST_NAME = 1 THEN 1 ELSE 0 END, '') || CASE WHEN s.MID_NAME IS NOT NULL THEN ' ' || TRIM(s.MID_NAME) ELSE '' END
                        || ' ' || NVL(LTRIM(s.LAST_NAME), '')),
                   s.PREFIX_NAME, s.SUFX_NAME, pfx.MSTR_CODE_VALUE, sfx.MSTR_CODE_VALUE,
                   jf.NAME IS NOT NULL, jl.NAME IS NOT NULL)                                  AS nm,
               fn_snow_helper17_common(s.GENDER_CD, 'Indv', 'TRS')                            AS gd,
               fn_snow_helper16_common(s.DOB_DT, 'Indv', 'TRS', :2)                    AS birth_exception_code,
               rc.MSTR_CODE_VALUE                                                             AS race_mstr,
               et.MSTR_CODE_VALUE                                                             AS ethnicity_mstr,
               CASE WHEN s.DEATH_DT > :2 THEN 'Invalid_Death_Date' ELSE NULL END                        AS death_exception_code
          FROM WRK_TRS_PTY_S1_SRC s
          LEFT JOIN lkp_cv pfx ON pfx.CODE_TYPE = 'PREFIX' AND pfx.SRC_SYS = 'TRS' AND pfx.SRC_CODE_VALUE = s.PREFIX_NAME
          LEFT JOIN lkp_cv sfx ON sfx.CODE_TYPE = 'SUFFIX' AND sfx.SRC_SYS = 'TRS' AND sfx.SRC_CODE_VALUE = s.SUFX_NAME
          LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(s.FIRST_NAME)) AND jf.IS_FIRST_JUNK = 1
          LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(s.LAST_NAME)) AND jl.IS_LAST_JUNK = 1
          LEFT JOIN lkp_cv rc ON rc.CODE_TYPE = 'RACE' AND rc.SRC_SYS = 'TRS' AND rc.SRC_CODE_VALUE = s.RACE_CD
          LEFT JOIN lkp_cv et ON et.CODE_TYPE = 'ETHNICITY' AND et.SRC_SYS = 'TRS' AND et.SRC_CODE_VALUE = s.ETHNICITY_CD
    )
    SELECT d.*,
           TRIM(d.pkey_src_object)               AS pkey_trim,
           CAST(d.nm.first_name AS VARCHAR2(4000))              AS std_first_name,
           CAST(d.nm.middle_name AS VARCHAR2(4000))             AS std_mdl_name,
           CAST(d.nm.last_name AS VARCHAR2(4000))               AS std_lst_name,
           CAST(d.nm.full_name AS VARCHAR2(4000))               AS std_full_name,
           CAST(d.nm.prfx_name AS VARCHAR2(4000))               AS std_prfx_name,
           CAST(d.nm.sfx_name AS VARCHAR2(4000))                AS std_sfx_name,
           CAST(d.gd.mdm_gender_code AS VARCHAR2(4000))         AS mdm_gender_code,
           CAST(d.gd.exception_code AS VARCHAR2(4000))          AS gender_exception_code,
           xg.EXCEPTION_DESC                     AS gender_exception_description,
           xg.EXCEPTION_TYPE                     AS gender_exception_type,
           CASE WHEN d.birth_exception_code IS NULL THEN d.DOB_DT ELSE NULL END AS std_birth_date,
           xb.EXCEPTION_DESC                     AS birth_exception_description,
           xb.EXCEPTION_TYPE                     AS birth_exception_type,
           xr.EXCEPTION_CODE                     AS race_exception_code,
           xr.EXCEPTION_DESC                     AS race_exception_desc,
           xr.EXCEPTION_TYPE                     AS race_exception_type,
           xe.EXCEPTION_CODE                     AS ethnicity_exception_code,
           xe.EXCEPTION_DESC                     AS ethnicity_exception_desc,
           xe.EXCEPTION_TYPE                     AS ethnicity_exception_type,
           xd.EXCEPTION_CODE                     AS death_exception_lkp_code,
           xd.EXCEPTION_DESC                     AS death_exception_desc,
           xd.EXCEPTION_TYPE                     AS death_exception_type,
           (fn_snow_helper03_common(CAST(d.nm.first_name AS VARCHAR2(4000)))
            OR fn_snow_helper03_common(CAST(d.nm.last_name AS VARCHAR2(4000))) = 1) AS name_missing
      FROM dq d
      LEFT JOIN lkp_exc xg ON xg.EXCEPTION_CODE = CAST(d.gd.exception_code AS VARCHAR2(4000))
      LEFT JOIN lkp_exc xb ON xb.EXCEPTION_CODE = d.birth_exception_code
      LEFT JOIN lkp_exc xr ON xr.EXCEPTION_CODE = fn_snow_helper18_common(d.race_mstr, 'Invalid_Race')
      LEFT JOIN lkp_exc xe ON xe.EXCEPTION_CODE = fn_snow_helper18_common(d.ethnicity_mstr, 'Invalid_Ethnicity')
      LEFT JOIN lkp_exc xd ON xd.EXCEPTION_CODE = d.death_exception_code]' USING P_DC_INDV_TBL_SRC, P_RUN_TS;
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_PTY_S2_DQ;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'DQ_STANDARDISE_VALIDATE', 'COMPLETED', NULL, 'Step 20 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_PTY_S20_DQ;
/

