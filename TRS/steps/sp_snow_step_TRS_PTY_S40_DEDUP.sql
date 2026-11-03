-- ============================================================================
-- sp_snow_step_TRS_PTY_S40_DEDUP  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_OnGoing, workflow wf_TRS_Stage_Load_1_Ongoing, step 40.
-- Step name (checkpoint): DEDUP_VALID.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_PTY_S4_DEDUP: DEDUP + RANK -- valid rows (BR-12)
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (pipe-delimited). Default: 'WRK_TRS_PTY_S2_DQ'.
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-40 SELECT verbatim. Only
--   substitution: :l_run_ts -> :P_RUN_TS (where used); :c_mapping is
--   the local constant below. No business expression, filter, guard
--   or column list was changed. This step uses original parameters:
--   P_RLE_BO_CLASS_CD_MEMBER.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   in the 10-argument form. P_JOB_RUN_ID is present in every new proc
--   in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_PTY_S40_DEDUP (P_RLE_BO_CLASS_CD_MEMBER IN VARCHAR2 DEFAULT 'Member', P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_PTY_S2_DQ') RETURN NUMBER AUTHID CURRENT_USER AS
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

    -- ---- Step 40: DEDUP_VALID (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_PTY_S4_DEDUP';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_PTY_S4_DEDUP AS WITH
    dedup AS (
        SELECT DISTINCT pkey_trim, CREATE_DT, INDV_ID, SRC_TBL, mdm_gender_code, std_sfx_name, std_first_name,
               std_prfx_name, std_lst_name, std_mdl_name, std_birth_date, std_full_name, DEATH_DT, src_full_name,
               RACE_CD, race_mstr, race_exception_code, race_exception_desc, race_exception_type, ETHNICITY_CD,
               ethnicity_mstr, ethnicity_exception_code, ethnicity_exception_desc, ethnicity_exception_type
          FROM WRK_TRS_PTY_S2_DQ
         WHERE std_first_name IS NOT NULL OR std_lst_name IS NOT NULL
    )
    SELECT x.*,
           ROW_NUMBER() OVER (PARTITION BY x.pkey_trim
                              ORDER BY x.CREATE_DT DESC NULLS FIRST, x.INDV_ID DESC NULLS FIRST,
                                       x.SRC_TBL DESC NULLS FIRST, x.mdm_gender_code DESC NULLS FIRST,
                                       x.std_sfx_name DESC NULLS FIRST, x.std_first_name DESC NULLS FIRST,
                                       x.std_prfx_name DESC NULLS FIRST, x.std_lst_name DESC NULLS FIRST,
                                       x.std_mdl_name DESC NULLS FIRST, x.std_birth_date DESC NULLS FIRST,
                                       x.std_full_name DESC NULLS FIRST)               AS rn_pty,
           CASE WHEN vm.PTY_PK IS NOT NULL THEN 1 ELSE 0 END AS is_valid_member,
           CASE WHEN xp.PKEY_SRC_OBJECT IS NULL THEN 1 ELSE 0 END AS uq_pty,
           CASE WHEN xr2.PKEY_SRC_OBJECT IS NULL THEN 1 ELSE 0 END AS uq_rle,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY x.race_exception_code IS NOT NULL, x.pkey_trim,
                                           x.race_exception_type, x.race_exception_code
                                  ORDER BY x.CREATE_DT DESC NULLS FIRST, x.INDV_ID) = 1 THEN 1 ELSE 0 END AS uq_exc_race,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY x.ethnicity_exception_code IS NOT NULL, x.pkey_trim,
                                           x.ethnicity_exception_type, x.ethnicity_exception_code
                                  ORDER BY x.CREATE_DT DESC NULLS FIRST, x.INDV_ID) = 1 THEN 1 ELSE 0 END AS uq_exc_ethnicity
      FROM dedup x
      LEFT JOIN (SELECT DISTINCT PTY_PK FROM STG_TRS_VALID_MEMBERS) vm ON vm.PTY_PK = x.pkey_trim
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TRS_PTY WHERE VERSION_SEQ = 1) xp
             ON xp.PKEY_SRC_OBJECT = x.pkey_trim
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TRS_PTY_RLE WHERE VERSION_SEQ = 1) xr2
             ON xr2.PKEY_SRC_OBJECT = x.pkey_trim || '|' || :1]' USING P_RLE_BO_CLASS_CD_MEMBER;
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_PTY_S4_DEDUP;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'DEDUP_VALID', 'COMPLETED', NULL, 'Step 40 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_PTY_S40_DEDUP;
/

