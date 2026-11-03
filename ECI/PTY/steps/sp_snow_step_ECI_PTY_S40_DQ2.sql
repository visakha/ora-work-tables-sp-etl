-- ============================================================================
-- sp_snow_step_ECI_PTY_S40_DQ2  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI)
--
-- Mapping: m_Tgt_C_S_ECI_Pty, workflow wf_ECI_Stage_Load, step 40.
-- Step name (checkpoint): DQ_EXCEPTIONS_RESOLVED.
--
-- WHAT THIS STEP PRODUCES
--   WRK_ECI_PTY_S40_DQ2: standardised fields unpacked and every rule's
--   exception code, description and type resolved from the exception
--   catalogue. A future birth date becomes NULL here. Reads ONLY
--   step 30. This is the original dq2 CTE.
--
-- DOES IT FEED THE SPINE?
--   Indirectly: the publish spine branches read step 50, which derives
--   from this step. It writes no target itself.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only. Default:
--   'WRK_ECI_PTY_S30_DQ'. Snowflake cannot parameterise table names
--   in static SQL, so P_INPUT_TABLES is a dependency declaration +
--   runtime check, NOT dynamic SQL: the CTAS below still names its
--   source literally, as in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-40 SELECT verbatim. Only
--   substitution: :c_mapping -> the local constant below (used by the
--   checkpoint). No business expression, filter, guard or column list
--   was changed. This step uses neither original parameter and does
--   not use the run timestamp.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   with the same STEP_NAME and message as the current step-40 checkpoint (v2 10-argument form; STEP_NO, row count, and work-table arguments dropped).
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_ECI_PTY_S40_DQ2 (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_PTY_S30_DQ') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_ECI_Pty';
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

    -- ---- Step 40: VALIDATION RULES, STEP 2 (verbatim from current main)
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_PTY_S40_DQ2';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_ECI_PTY_S40_DQ2 AS WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common()))
    SELECT d.*,
           CAST(d.nm.first_name AS VARCHAR2(4000))                       AS std_first_name,
           CAST(d.nm.middle_name AS VARCHAR2(4000))                      AS std_mdl_name,
           CAST(d.nm.last_name AS VARCHAR2(4000))                        AS std_lst_name,
           CAST(d.nm.full_name AS VARCHAR2(4000))                        AS std_full_name,
           CAST(d.nm.src_full_name AS VARCHAR2(4000))                    AS std_src_full_name,
           CAST(d.nm.prfx_name AS VARCHAR2(4000))                        AS std_prfx_name,
           CAST(d.gd.mdm_gender_code AS VARCHAR2(4000))                  AS mdm_gender_code,
           CAST(d.gd.exception_code AS VARCHAR2(4000))                   AS gender_exception_code,
           xg.EXCEPTION_DESC                              AS gender_exception_description,
           xg.EXCEPTION_TYPE                              AS gender_exception_type,
           CASE WHEN d.birth_exception_code IS NULL THEN d.DOB ELSE NULL END AS std_birth_date,
           xb.EXCEPTION_DESC                              AS birth_exception_description,
           xb.EXCEPTION_TYPE                              AS birth_exception_type,
           xe.EXCEPTION_CODE                              AS ethnicity_exception_code,
           xe.EXCEPTION_DESC                              AS ethnicity_exception_desc,
           xe.EXCEPTION_TYPE                              AS ethnicity_exception_type,
           CAST(d.rc.mdm_race_cd AS VARCHAR2(4000))                      AS mdm_race_cd,
           CAST(d.rc.src_race_ind_list AS VARCHAR2(4000))                AS src_race_ind_list,
           xr.EXCEPTION_CODE                              AS race_exception_cd,
           xr.EXCEPTION_DESC                              AS race_exception_desc,
           xr.EXCEPTION_TYPE                              AS race_exception_type,
           xl.EXCEPTION_CODE                              AS language_exception_code,
           xl.EXCEPTION_DESC                              AS language_exception_desc,
           xl.EXCEPTION_TYPE                              AS language_exception_type
      FROM WRK_ECI_PTY_S30_DQ d
      LEFT JOIN lkp_exc xg ON xg.EXCEPTION_CODE = CAST(d.gd.exception_code AS VARCHAR2(4000))
      LEFT JOIN lkp_exc xb ON xb.EXCEPTION_CODE = d.birth_exception_code
      LEFT JOIN lkp_exc xe ON xe.EXCEPTION_CODE = fn_snow_helper18_common(d.ethnicity_mstr, 'Invalid_Ethnicity')
      LEFT JOIN lkp_exc xr ON xr.EXCEPTION_CODE = CAST(d.rc.exception_code AS VARCHAR2(4000))
      LEFT JOIN lkp_exc xl ON xl.EXCEPTION_CODE = fn_snow_helper18_common(d.language_mstr, 'Invalid_Language')]';
    SELECT COUNT(*) INTO l_rows FROM WRK_ECI_PTY_S40_DQ2;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'DQ_EXCEPTIONS_RESOLVED', 'COMPLETED', NULL, 'Step 40 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_ECI_PTY_S40_DQ2;
/

