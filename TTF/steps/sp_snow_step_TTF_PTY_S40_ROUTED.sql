-- ============================================================================
-- sp_snow_step_TTF_PTY_S40_ROUTED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TTF)
--
-- Mapping: m_Tgt_C_S_TTF_Pty, workflow wf_TTF_Stage_Load, step 40.
-- Step name (checkpoint): ROUTED.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TTF_PTY_S4_ROUTED. Reads ONLY WRK_TTF_PTY_S3_DQ2 (plus reference lookups / target guard tables where the original reads them; those are not work-table dependencies).
--
-- DOES IT FEED THE SPINE?
--   YES, directly: all publish branches in this mapping read ONLY this table. It writes no target itself.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only. Snowflake cannot
--   parameterise table names in static SQL, so P_INPUT_TABLES is a
--   dependency declaration + runtime check, NOT dynamic SQL: the CTAS
--   below still names its source work table literally, as in the
--   current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-40 SELECT verbatim. Only
--   substitution: :l_run_ts -> :P_RUN_TS; :c_mapping resolves to the
--   local constant below (used by the checkpoint and, where the
--   original used it, materialised into the work table). No business
--   expression, filter, guard or column list was changed. This step uses original parameter(s) P_PTY_BO_CLASS_CD_MEMBER, P_RLE_BO_CLASS_CD_MEMBER (in original order, with their original defaults). Because those defaults precede P_JOB_RUN_ID / P_RUN_TS, the trailing params carry DEFAULT NULL (live-compile fix: Snowflake forbids a required parameter after an optional one); drivers pass all params positionally, so behaviour is unchanged.
--   It references the run timestamp (:P_RUN_TS).
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   in the v2 10-argument form. P_JOB_RUN_ID is present in every new
--   proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_TTF_PTY_S40_ROUTED (P_PTY_BO_CLASS_CD_MEMBER IN VARCHAR2 DEFAULT 'Indv', P_RLE_BO_CLASS_CD_MEMBER IN VARCHAR2 DEFAULT 'Member', P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TTF_PTY_S3_DQ2') RETURN NUMBER AUTHID CURRENT_USER AS
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

    -- ---- Step 40: ROUTED (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TTF_PTY_S4_ROUTED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TTF_PTY_S4_ROUTED AS WITH
    routed AS (
        SELECT d.*,
               TRIM(d.PTY_SRC_KEY)                                        AS pkey_trim,
               TRIM(d.PTY_SRC_KEY) || '|' || :1     AS rle_pkey,
               CASE WHEN d.gender_exception_description IS NOT NULL THEN 1 ELSE 0 END AS grp_gender,
               CASE WHEN d.birth_exception_code IS NOT NULL THEN 1 ELSE 0 END AS grp_birth,
               CASE WHEN d.ethnicity_exception_code IS NOT NULL THEN 1 ELSE 0 END AS grp_ethnicity,
               CASE WHEN d.race_exception_desc IS NOT NULL THEN 1 ELSE 0 END AS grp_race
          FROM WRK_TTF_PTY_S3_DQ2 d
    )
    SELECT r.*,
           1 /* TIMELINE: VERSION_SEQ hard-coded */         AS version_seq,
           1                                                 AS hub_state_ind,
           'TTF'                                             AS src_sys,
           :2                                         AS run_ts,
           :3                                        AS mapping_name,
           :4                         AS pty_bo_class_cd,
           :1                         AS rle_bo_class_cd,
           TO_CHAR(r.DOB, 'MM/DD/YYYY')                   AS dob_text,
           'Gender'                                          AS attr_gender,
           'Birth Date'                                      AS attr_birth,
           'Ethnicity_Cd'                                    AS attr_ethnicity,
           'Race_Cd'                                         AS attr_race,
           /* BAD DATA: unique keys Snowflake does not enforce */
           (ROW_NUMBER() OVER (PARTITION BY r.pkey_trim ORDER BY r.SUBMITDATE DESC, r.CLIENTS_ID) = 1
            AND xp.PKEY_SRC_OBJECT IS NULL)                  AS uq_pty,
           CASE WHEN (ROW_NUMBER() OVER (PARTITION BY r.rle_pkey ORDER BY r.SUBMITDATE DESC, r.CLIENTS_ID) = 1
            AND xr2.PKEY_SRC_OBJECT IS NULL) THEN 1 ELSE 0 END AS uq_rle,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.grp_gender, r.PTY_SRC_KEY, r.CLIENTS_ID, r.gender_exception_type,
                                           r.gender_exception_code ORDER BY r.SUBMITDATE DESC) = 1 THEN 1 ELSE 0 END AS uq_gender,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.grp_birth, r.PTY_SRC_KEY, r.CLIENTS_ID, r.birth_exception_type,
                                           r.birth_exception_code ORDER BY r.SUBMITDATE DESC) = 1 THEN 1 ELSE 0 END AS uq_birth,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.grp_ethnicity, r.PTY_SRC_KEY, r.CLIENTS_ID,
                                           r.ethnicity_exception_type, r.ethnicity_exception_code
                                  ORDER BY r.SUBMITDATE DESC) = 1 THEN 1 ELSE 0 END AS uq_ethnicity,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.grp_race, r.PTY_SRC_KEY, r.CLIENTS_ID, r.race_exception_type,
                                           r.race_exception_code ORDER BY r.SUBMITDATE DESC) = 1 THEN 1 ELSE 0 END AS uq_race
      FROM routed r
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TTF_PTY WHERE VERSION_SEQ = 1) xp
             ON xp.PKEY_SRC_OBJECT = r.pkey_trim
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TTF_PTY_RLE WHERE VERSION_SEQ = 1) xr2
             ON xr2.PKEY_SRC_OBJECT = r.rle_pkey]' USING P_RLE_BO_CLASS_CD_MEMBER, P_RUN_TS, c_mapping, P_PTY_BO_CLASS_CD_MEMBER;
    SELECT COUNT(*) INTO l_rows FROM WRK_TTF_PTY_S4_ROUTED;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'ROUTED', 'COMPLETED', NULL, 'Step 40 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TTF_PTY_S40_ROUTED;
/

