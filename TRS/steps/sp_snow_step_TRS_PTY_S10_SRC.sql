-- ============================================================================
-- sp_snow_step_TRS_PTY_S10_SRC  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_OnGoing, workflow wf_TRS_Stage_Load_1_Ongoing, step 10.
-- Step name (checkpoint): SRC_VALID_LIST.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_PTY_S1_SRC: SOURCE + VALID-MEMBER LIST (BR-09)
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
--   P_DC_INDV_TBL_SRC, P_MCI_TBL_SRC.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   in the 10-argument form. P_JOB_RUN_ID is present in every new proc
--   in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_PTY_S10_SRC (P_DC_INDV_TBL_SRC IN VARCHAR2 DEFAULT 'DC_INDV', P_MCI_TBL_SRC IN VARCHAR2 DEFAULT 'MCI', P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT '') RETURN NUMBER AUTHID CURRENT_USER AS
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

    -- ---- Step 10: SRC_VALID_LIST (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_PTY_S1_SRC';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_PTY_S1_SRC AS WITH
    new_valid_indvs AS (
        SELECT DISTINCT indv_id FROM STG_TRS_D_CV_MCI_EDG_INDV_TOA WHERE conversion_ind = 'C'
        UNION
        SELECT DISTINCT indv_id FROM STG_TRS_D_DC_INDV
         WHERE FILE_CLEARANCE_SW = 'Y' AND Inactive_ind = 'N' AND delete_sw = 'N'
        UNION
        SELECT DISTINCT indv_id FROM STG_TRS_D_CV_DC_MCI_INDV WHERE Inactive_ind = 'N'
        UNION
        SELECT DISTINCT indv_id FROM STG_TRS_VALID_MEMBERS
        MINUS
        SELECT DISTINCT indv_id FROM STG_TRS_D_DC_INDV WHERE Inactive_ind = 'Y' OR delete_sw = 'Y'
        MINUS
        SELECT DISTINCT indv_id FROM STG_TRS_D_CV_DC_MCI_INDV WHERE Inactive_ind = 'Y'
        MINUS
        SELECT indv_id FROM STG_TRS_DEACTIVED_MEMBERS
    ),
    all_indv AS (
        SELECT INDV_ID, FIRST_NAME, MID_NAME, LAST_NAME, SUFX_NAME, PREFIX_NAME, GENDER_CD, RACE_CD, ETHNICITY_CD,
               NULL AS SSA_VAL_SW, NULL AS FILE_CL_SW, DOB_DT, NULL AS DEATH_DT, CREATE_DT,
               :1 AS SRC_TBL
          FROM STG_TRS_D_CV_DC_MCI_INDV
        UNION ALL
        SELECT INDV_ID, FIRST_NAME, MID_NAME, LAST_NAME, SUFX_NAME, PREFIX_NAME, GENDER_CD, RACE_CD, ETHNICITY_CD,
               SSA_VALIDATION_SW, FILE_CLEARANCE_SW, DOB_DT, DEATH_DT, CREATE_DT, :2
          FROM STG_TRS_D_DC_INDV
    )
    SELECT DISTINCT a.INDV_ID, RTRIM(LTRIM(a.FIRST_NAME)) AS FIRST_NAME, RTRIM(LTRIM(a.MID_NAME)) AS MID_NAME,
           RTRIM(LTRIM(a.LAST_NAME)) AS LAST_NAME, RTRIM(a.SUFX_NAME) AS SUFX_NAME,
           RTRIM(a.PREFIX_NAME) AS PREFIX_NAME, a.GENDER_CD, a.RACE_CD, a.ETHNICITY_CD, a.SSA_VAL_SW,
           a.FILE_CL_SW, a.DOB_DT, a.CREATE_DT, a.SRC_TBL, a.DEATH_DT
      FROM all_indv a
     INNER JOIN new_valid_indvs f ON f.indv_id = a.indv_id]' USING P_MCI_TBL_SRC, P_DC_INDV_TBL_SRC;
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_PTY_S1_SRC;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'SRC_VALID_LIST', 'COMPLETED', NULL, 'Step 10 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_PTY_S10_SRC;
/

