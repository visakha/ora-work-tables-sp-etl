-- ============================================================================
-- sp_snow_step_ECI_PTY_S50_READY  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI)
--
-- Mapping: m_Tgt_C_S_ECI_Pty, workflow wf_ECI_Stage_Load, step 50.
-- Step name (checkpoint): ROUTED_READY.
--
-- WHAT THIS STEP PRODUCES
--   WRK_ECI_PTY_S50_READY: routed groups, party/role keys and
--   insert-only guards. Every active party loads; each failed rule
--   additionally logs an exception; ethnicity, race and language only
--   for child rows. Reads ONLY step 40. This is the original routed
--   CTE plus the final SELECT (including the target-table guard joins,
--   which still see the pre-run state because nothing has been
--   published yet).
--
-- DOES IT FEED THE SPINE?
--   YES, directly: all seven publish branches read ONLY this table.
--   It writes no target itself.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (the target guard
--   tables C_S_ECI_PTY / C_S_ECI_PTY_RLE read inside this step are not
--   work-table dependencies). Default: 'WRK_ECI_PTY_S40_DQ2'. Snowflake
--   cannot parameterise table names in static SQL, so P_INPUT_TABLES
--   is a dependency declaration + runtime check, NOT dynamic SQL: the
--   CTAS below still names its source literally, as in the current
--   main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-50 SELECT verbatim. Only
--   substitutions: :l_run_ts -> :P_RUN_TS, :c_exc_mapping -> the local
--   constant below, :c_mapping -> the local constant below (used by
--   the checkpoint), original-parameter refs -> this proc's params of
--   the same names. No business expression, filter, guard or column
--   list was changed. This step uses BOTH original parameters.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   with the same STEP_NAME, TARGET_TABLE, and message as the current step-50 checkpoint (v2 10-argument form), including its TARGET_TABLE list of the three publish targets.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_ECI_PTY_S50_READY (P_PTY_BO_CLASS_CD_MEMBER IN VARCHAR2 DEFAULT 'Indv', P_RLE_BO_CLASS_CD_MEMBER IN VARCHAR2 DEFAULT 'Member', -- Live-compile fix: Snowflake forbids a required parameter after an
    -- optional one, so P_JOB_RUN_ID / P_RUN_TS carry DEFAULT NULL here.
    -- Drivers always pass all five positionally, so behaviour is unchanged.
    P_JOB_RUN_ID             VARCHAR DEFAULT NULL IN , P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_PTY_S40_DQ2') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_ECI_Pty';
    c_exc_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_ECI_Pty_OnGoing';
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

    -- ---- Step 50: ROUTED + READY (verbatim from current main)
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_PTY_S50_READY';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_ECI_PTY_S50_READY AS WITH
    routed AS (
        SELECT d.*,
               TRIM(d.pkey_src_object)                                   AS pkey_trim,
               TRIM(d.pkey_src_object) || '|' || :1 AS rle_pkey,
               CASE WHEN d.gender_exception_description IS NOT NULL THEN 1 ELSE 0 END AS grp_gender,
               CASE WHEN d.birth_exception_code IS NOT NULL THEN 1 ELSE 0 END AS grp_birth,
               CASE WHEN (d.ethnicity_exception_code IS NOT NULL AND d.SOURCE_TABLE = 'ECI_CHILD') THEN 1 ELSE 0 END AS grp_ethnicity,
               CASE WHEN (d.race_exception_desc IS NOT NULL AND d.SOURCE_TABLE = 'ECI_CHILD') THEN 1 ELSE 0 END AS grp_race,
               CASE WHEN (d.language_exception_code IS NOT NULL AND d.SOURCE_TABLE = 'ECI_CHILD') THEN 1 ELSE 0 END AS grp_language
          FROM WRK_ECI_PTY_S40_DQ2 d
    )
    SELECT r.*,
           1                                                        AS version_seq,
           1                                                        AS hub_state_ind,
           :2                                                AS run_ts,
           :3                                           AS exc_mapping,
           :4                                AS pty_bo_class_cd,
           :1                                AS rle_bo_class_cd,
           r.BIRTH_WT_LB * 453.6 + r.BIRTH_WT_OZ * 28.35            AS birth_wght_grms,
           TO_CHAR(r.DOB, 'MM/DD/YYYY')                          AS dob_text,
           'Gender'                                                 AS attr_gender,
           'Birth Date'                                             AS attr_birth,
           'Ethnicity_Cd'                                           AS attr_ethnicity,
           'Race_Cd'                                                AS attr_race,
           'Language_Cd'                                            AS attr_language,
           CASE WHEN (ROW_NUMBER() OVER (PARTITION BY r.pkey_trim ORDER BY r.DATE_MODIFIED DESC, r.ID) = 1
            AND xp.PKEY_SRC_OBJECT IS NULL) THEN 1 ELSE 0 END AS uq_pty,
           CASE WHEN (ROW_NUMBER() OVER (PARTITION BY r.rle_pkey ORDER BY r.DATE_MODIFIED DESC, r.ID) = 1
            AND xr2.PKEY_SRC_OBJECT IS NULL) THEN 1 ELSE 0 END AS uq_rle,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.grp_gender, r.pkey_src_object, r.ID, r.gender_exception_type,
                                           r.gender_exception_code ORDER BY r.ID) = 1 THEN 1 ELSE 0 END AS uq_gender,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.grp_birth, r.pkey_src_object, r.ID, r.birth_exception_type,
                                           r.birth_exception_code ORDER BY r.ID) = 1 THEN 1 ELSE 0 END AS uq_birth,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.grp_ethnicity, r.pkey_src_object, r.ID,
                                           r.ethnicity_exception_type, r.ethnicity_exception_code
                                  ORDER BY r.ID) = 1 THEN 1 ELSE 0 END AS uq_ethnicity,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.grp_race, r.pkey_src_object, r.ID, r.race_exception_type,
                                           r.race_exception_cd ORDER BY r.ID) = 1 THEN 1 ELSE 0 END AS uq_race,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.grp_language, r.pkey_src_object, r.ID,
                                           r.language_exception_type, r.language_exception_code
                                  ORDER BY r.ID) = 1 THEN 1 ELSE 0 END AS uq_language
      FROM routed r
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_ECI_PTY WHERE VERSION_SEQ = 1) xp
             ON xp.PKEY_SRC_OBJECT = r.pkey_trim
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_ECI_PTY_RLE WHERE VERSION_SEQ = 1) xr2
             ON xr2.PKEY_SRC_OBJECT = r.rle_pkey]' USING P_RLE_BO_CLASS_CD_MEMBER, P_RUN_TS, c_exc_mapping, P_PTY_BO_CLASS_CD_MEMBER;
    SELECT COUNT(*) INTO l_rows FROM WRK_ECI_PTY_S50_READY;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'ROUTED_READY', 'COMPLETED', 'C_S_ECI_PTY, C_S_ECI_PTY_RLE, EXC_STG_BAD_REC_MEMB', 'Step 50 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_ECI_PTY_S50_READY;
/

