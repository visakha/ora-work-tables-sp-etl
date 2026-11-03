-- ============================================================================
-- sp_snow_step_WIC_PTY_S40_ROUTED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (WIC)
--
-- Mapping: m_Tgt_C_S_WIC_Pty, workflow wf_WIC_Stage_Load, step 40.
-- Step name (checkpoint): ROUTED.
--
-- WHAT THIS STEP PRODUCES
--   WRK_WIC_PTY_S40_ROUTED: Party and role keys, exception routing groups, run constants, birth weight in grams, and the insert-only guards (uq_pty, uq_rle, uq_gender, uq_birth, uq_ethnicity, uq_race, uq_language). Guards evaluated here, before publish, as in the original single query.
--
-- DOES IT FEED THE SPINE?
--   Directly: the publish branches read ONLY this table. It writes no target itself.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only. Default: 'WRK_WIC_PTY_S30_DQ2'. Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT dynamic SQL: the CTAS below still names its sources literally, as in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-40 SELECT verbatim. Only substitution: :l_run_ts -> :P_RUN_TS (used by this step), :c_mapping -> the local constant below (used by the checkpoint). Original-parameter refs: :P_PTY_BO_CLASS_CD_MEMBER, :P_RLE_BO_CLASS_CD_MEMBER. No business expression, filter, guard or column list was changed.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no transactions, no target writes. This proc writes its own checkpoint in the v2 10-argument form (STEP_NAME, STEP_STATUS, TARGET_TABLE, MESSAGE, ERROR_MESSAGE; STEP_NO, row count and work-table arguments dropped per the new signature). P_JOB_RUN_ID is present in every new proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_WIC_PTY_S40_ROUTED (P_PTY_BO_CLASS_CD_MEMBER IN VARCHAR2 DEFAULT 'Indv', P_RLE_BO_CLASS_CD_MEMBER IN VARCHAR2 DEFAULT 'Member', -- Live-compile fix: Snowflake forbids a required parameter after an
    -- optional one, so P_JOB_RUN_ID / P_RUN_TS carry DEFAULT NULL here.
    -- Drivers always pass all parameters positionally, so behaviour is unchanged.
    P_JOB_RUN_ID             VARCHAR DEFAULT NULL IN , P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_WIC_PTY_S30_DQ2') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'WIC';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_WIC_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_WIC_Pty';
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

    -- ---- Step 40: ROUTED (verbatim from current main)
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_WIC_PTY_S40_ROUTED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_WIC_PTY_S40_ROUTED AS WITH
    routed AS (
        SELECT d.*,
               TRIM(d.PTY_SRC_KEY)                                                    AS pkey_trim,
               TRIM(d.PTY_SRC_KEY) || '|' || :1                 AS rle_pkey,
               CASE WHEN (d.gender_exception_description IS NOT NULL AND d.SOURCE_TABLE = 'CLIENT') THEN 1 ELSE 0 END AS grp_gender,
               CASE WHEN d.birth_exception_code IS NOT NULL THEN 1 ELSE 0 END AS grp_birth,
               CASE WHEN (d.ethnicity_exception_code IS NOT NULL AND d.SOURCE_TABLE = 'CLIENT') THEN 1 ELSE 0 END AS grp_ethnicity,
               CASE WHEN (d.race_exception_desc IS NOT NULL AND d.SOURCE_TABLE = 'CLIENT') THEN 1 ELSE 0 END AS grp_race,
               CASE WHEN d.language_exception_code IS NOT NULL THEN 1 ELSE 0 END AS grp_language
          FROM WRK_WIC_PTY_S30_DQ2 d
    )
    SELECT r.*,
           1 /* TIMELINE: VERSION_SEQ hard-coded */         AS version_seq,
           1                                                 AS hub_state_ind,
           'WIC'                                             AS src_sys,
           :2                                         AS run_ts,
           :3                                        AS mapping_name,
           :4                         AS pty_bo_class_cd,
           :1                         AS rle_bo_class_cd,
           r.BIRTH_WT_OZ * 28.35                             AS birth_wght_grms,
           TO_CHAR(r.DOB, 'MM/DD/YYYY')                   AS dob_text,
           'Gender'                                          AS attr_gender,
           'Birth Date'                                      AS attr_birth,
           'Ethnicity_Cd'                                    AS attr_ethnicity,
           'Race_Cd'                                         AS attr_race,
           'Language_Cd'                                     AS attr_language,
           /* BAD DATA: unique keys Snowflake does not enforce */
           (ROW_NUMBER() OVER (PARTITION BY r.pkey_trim ORDER BY r.DATEKEY DESC, r.ID) = 1
            AND xp.PKEY_SRC_OBJECT IS NULL)                  AS uq_pty,
           CASE WHEN (ROW_NUMBER() OVER (PARTITION BY r.rle_pkey ORDER BY r.DATEKEY DESC, r.ID) = 1
            AND xr2.PKEY_SRC_OBJECT IS NULL) THEN 1 ELSE 0 END AS uq_rle,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.grp_gender, r.PTY_SRC_KEY, r.ID, r.gender_exception_type,
                                           r.gender_exception_code ORDER BY r.DATEKEY DESC) = 1 THEN 1 ELSE 0 END AS uq_gender,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.grp_birth, r.PTY_SRC_KEY, r.ID, r.birth_exception_type,
                                           r.birth_exception_code ORDER BY r.DATEKEY DESC) = 1 THEN 1 ELSE 0 END AS uq_birth,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.grp_ethnicity, r.PTY_SRC_KEY, r.ID, r.ethnicity_exception_type,
                                           r.ethnicity_exception_code ORDER BY r.DATEKEY DESC) = 1 THEN 1 ELSE 0 END AS uq_ethnicity,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.grp_race, r.PTY_SRC_KEY, r.ID, r.race_exception_type,
                                           r.race_exception_cd ORDER BY r.DATEKEY DESC) = 1 THEN 1 ELSE 0 END AS uq_race,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.grp_language, r.PTY_SRC_KEY, r.ID, r.language_exception_type,
                                           r.language_exception_code ORDER BY r.DATEKEY DESC) = 1 THEN 1 ELSE 0 END AS uq_language
      FROM routed r
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_WIC_PTY WHERE VERSION_SEQ = 1) xp
             ON xp.PKEY_SRC_OBJECT = r.pkey_trim
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_WIC_PTY_RLE WHERE VERSION_SEQ = 1) xr2
             ON xr2.PKEY_SRC_OBJECT = r.rle_pkey]' USING P_RLE_BO_CLASS_CD_MEMBER, P_RUN_TS, c_mapping, P_PTY_BO_CLASS_CD_MEMBER;
    SELECT COUNT(*) INTO l_rows FROM WRK_WIC_PTY_S40_ROUTED;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'ROUTED', 'COMPLETED', NULL, 'Step 40 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_WIC_PTY_S40_ROUTED;
/

