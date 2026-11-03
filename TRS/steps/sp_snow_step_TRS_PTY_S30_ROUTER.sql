-- ============================================================================
-- sp_snow_step_TRS_PTY_S30_ROUTER  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_OnGoing, workflow wf_TRS_Stage_Load_1_Ongoing, step 30.
-- Step name (checkpoint): ROUTER_EXCEPTIONS.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_PTY_S3_ROUTER: ROUTER -- exception classes (BR-13/14)
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (pipe-delimited). Default: 'WRK_TRS_PTY_S2_DQ'.
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
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_PTY_S30_ROUTER (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_PTY_S2_DQ') RETURN NUMBER AUTHID CURRENT_USER AS
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

    -- ---- Step 30: ROUTER_EXCEPTIONS (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_PTY_S3_ROUTER';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_PTY_S3_ROUTER AS WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    router AS (
        SELECT b.*,
               CASE WHEN fn_snow_helper03_common(b.std_first_name) = 1 THEN 'Missing_First_Name'
                    WHEN fn_snow_helper03_common(b.std_lst_name) = 1 THEN 'Missing_Last_Name' END  AS name_exception_code,
               CASE WHEN fn_snow_helper03_common(b.std_first_name) = 1 THEN 'First Name'
                    WHEN fn_snow_helper03_common(b.std_lst_name) = 1 THEN 'Last Name' END          AS name_attribute_name,
               CASE WHEN fn_snow_helper03_common(b.std_first_name) = 1 THEN b.std_first_name
                    WHEN fn_snow_helper03_common(b.std_lst_name) = 1 THEN b.std_lst_name END       AS name_attribute_value
          FROM WRK_TRS_PTY_S2_DQ b
    )
    SELECT r.*,
           xn.EXCEPTION_TYPE AS name_exception_type,
           xn.EXCEPTION_DESC AS name_exception_desc,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.name_missing, r.pkey_src_object, xn.EXCEPTION_TYPE,
                                           r.name_exception_code ORDER BY r.CREATE_DT DESC) = 1 THEN 1 ELSE 0 END AS uq_exc_name,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.gender_exception_description IS NOT NULL, r.pkey_src_object,
                                           r.gender_exception_type, r.gender_exception_code
                                  ORDER BY r.CREATE_DT DESC) = 1 THEN 1 ELSE 0 END AS uq_exc_gender,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.death_exception_desc IS NOT NULL, r.pkey_src_object,
                                           r.death_exception_type, r.death_exception_lkp_code
                                  ORDER BY r.CREATE_DT DESC) = 1 THEN 1 ELSE 0 END AS uq_exc_death,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.birth_exception_code IS NOT NULL, r.pkey_src_object,
                                           r.birth_exception_type, r.birth_exception_code
                                  ORDER BY r.CREATE_DT DESC) = 1 THEN 1 ELSE 0 END AS uq_exc_birth
      FROM router r
      LEFT JOIN lkp_exc xn ON xn.EXCEPTION_CODE = r.name_exception_code]';
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_PTY_S3_ROUTER;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'ROUTER_EXCEPTIONS', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Step 30 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_PTY_S30_ROUTER;
/

