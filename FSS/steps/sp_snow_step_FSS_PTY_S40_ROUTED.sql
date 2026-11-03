-- ============================================================================
-- sp_snow_step_FSS_PTY_S40_ROUTED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (FSS)
--
-- Mapping: m_Tgt_C_S_FSS_Pty, workflow wf_FSS_Stage_Load, step 40.
-- Step name (checkpoint): ROUTED.
--
-- WHAT THIS STEP PRODUCES
--   WRK_FSS_PTY_S4_ROUTED: Party / role keys, exception groups, insert-only guards.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (default: 'WRK_FSS_PTY_S3_DQ2').
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-40 SELECT verbatim. Only
--   substitution: :l_run_ts -> :P_RUN_TS,
--   :c_mapping -> the local constant below (used by the checkpoint).
--   No business expression, filter, guard or column list was changed.
--   Original parameters used by this step: P_PTY_BO_CLASS_CD_MEMBER, P_RLE_BO_CLASS_CD_MEMBER.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   in the v2 10-argument form (TARGET_TABLE NULL, as in the current
--   main's step checkpoints; row count survives in the RETURN value
--   and the driver's helper36 summary line).
--   P_JOB_RUN_ID is present in every new proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_FSS_PTY_S40_ROUTED (P_PTY_BO_CLASS_CD_MEMBER IN VARCHAR2 DEFAULT 'Indv', P_RLE_BO_CLASS_CD_MEMBER IN VARCHAR2 DEFAULT 'Member', -- Live-compile fix (ECI v2.1): Snowflake forbids a required parameter after an
    -- optional one, so P_JOB_RUN_ID / P_RUN_TS carry DEFAULT NULL here.
    -- Drivers always pass all parameters positionally, so behaviour is unchanged.
    P_JOB_RUN_ID   VARCHAR DEFAULT NULL IN , P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_FSS_PTY_S3_DQ2') RETURN NUMBER AUTHID CURRENT_USER AS
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

    -- ---- Step 40: ROUTED (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_FSS_PTY_S4_ROUTED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_FSS_PTY_S4_ROUTED AS WITH
    routed AS (
        SELECT d.*,
               TRIM(d.PTY_SRC_KEY)                                                   AS pkey_trim,
               TRIM(d.PTY_SRC_KEY) || '|' || :1                AS rle_pkey,
               CASE WHEN (d.gender_exception_description IS NOT NULL AND d.SOURCE_TYPE = 'CLIENT') THEN 1 ELSE 0 END AS grp_gender,
               CASE WHEN d.birth_exception_code IS NOT NULL THEN 1 ELSE 0 END AS grp_birth,
               CASE WHEN (d.ethnicity_exception_code IS NOT NULL AND d.SOURCE_TYPE = 'CLIENT') THEN 1 ELSE 0 END AS grp_ethnicity,
               CASE WHEN (d.race_exception_desc IS NOT NULL AND d.SOURCE_TYPE = 'CLIENT') THEN 1 ELSE 0 END AS grp_race,
               CASE WHEN d.language_exception_code IS NOT NULL THEN 1 ELSE 0 END AS grp_language,
               CASE WHEN d.suffix_exception_code IS NOT NULL THEN 1 ELSE 0 END AS grp_suffix
          FROM WRK_FSS_PTY_S3_DQ2 d
    )
    SELECT r.*,
           1 /* TIMELINE: VERSION_SEQ hard-coded */                  AS version_seq,
           1                                                          AS hub_state_ind,
           'FSS'                                                      AS src_sys,
           :2                                                  AS run_ts,
           :3                                                 AS mapping_name,
           :4                                  AS pty_bo_class_cd,
           :1                                  AS rle_bo_class_cd,
           TO_CHAR(r.DT_DOB, 'MM/DD/YYYY')                         AS dob_text,
           'Gender'                                                   AS attr_gender,
           'Birth Date'                                               AS attr_birth,
           'Ethnicity_Cd'                                             AS attr_ethnicity,
           'Race_Cd'                                                  AS attr_race,
           'Language_Cd'                                              AS attr_language,
           'Name Suffix'                                              AS attr_suffix,
           /* BAD DATA: unique keys Snowflake does not enforce */
           (ROW_NUMBER() OVER (PARTITION BY r.pkey_trim ORDER BY r.DT_LAST_UPDATE DESC, r.ID_CLIENT) = 1
            AND xp.PKEY_SRC_OBJECT IS NULL)                           AS uq_pty,
           CASE WHEN (ROW_NUMBER() OVER (PARTITION BY r.rle_pkey ORDER BY r.DT_LAST_UPDATE DESC, r.ID_CLIENT) = 1
            AND xr2.PKEY_SRC_OBJECT IS NULL) THEN 1 ELSE 0 END AS uq_rle,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.grp_gender, r.PTY_SRC_KEY, r.ID_CLIENT, r.gender_exception_type,
                                           r.gender_exception_code ORDER BY r.DT_LAST_UPDATE DESC) = 1 THEN 1 ELSE 0 END AS uq_gender,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.grp_birth, r.PTY_SRC_KEY, r.ID_CLIENT, r.birth_exception_type,
                                           r.birth_exception_code ORDER BY r.DT_LAST_UPDATE DESC) = 1 THEN 1 ELSE 0 END AS uq_birth,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.grp_ethnicity, r.PTY_SRC_KEY, r.ID_CLIENT,
                                           r.ethnicity_exception_type, r.ethnicity_exception_code
                                  ORDER BY r.DT_LAST_UPDATE DESC) = 1 THEN 1 ELSE 0 END AS uq_ethnicity,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.grp_race, r.PTY_SRC_KEY, r.ID_CLIENT, r.race_exception_type,
                                           r.race_exception_cd ORDER BY r.DT_LAST_UPDATE DESC) = 1 THEN 1 ELSE 0 END AS uq_race,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.grp_language, r.PTY_SRC_KEY, r.ID_CLIENT,
                                           r.language_exception_type, r.language_exception_code
                                  ORDER BY r.DT_LAST_UPDATE DESC) = 1 THEN 1 ELSE 0 END AS uq_language,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.grp_suffix, r.PTY_SRC_KEY, r.ID_CLIENT, r.suffix_exception_type,
                                           r.suffix_exception_code ORDER BY r.DT_LAST_UPDATE DESC) = 1 THEN 1 ELSE 0 END AS uq_suffix
      FROM routed r
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_FSS_PTY WHERE VERSION_SEQ = 1) xp
             ON xp.PKEY_SRC_OBJECT = r.pkey_trim
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_FSS_PTY_RLE WHERE VERSION_SEQ = 1) xr2
             ON xr2.PKEY_SRC_OBJECT = r.rle_pkey]' USING P_RLE_BO_CLASS_CD_MEMBER, P_RUN_TS, c_mapping, P_PTY_BO_CLASS_CD_MEMBER;
    SELECT COUNT(*) INTO l_rows FROM WRK_FSS_PTY_S4_ROUTED;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'ROUTED', 'COMPLETED', NULL, 'Step 40 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_FSS_PTY_S40_ROUTED;
/

