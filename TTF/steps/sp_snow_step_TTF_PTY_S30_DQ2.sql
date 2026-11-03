-- ============================================================================
-- sp_snow_step_TTF_PTY_S30_DQ2  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TTF)
--
-- Mapping: m_Tgt_C_S_TTF_Pty, workflow wf_TTF_Stage_Load, step 30.
-- Step name (checkpoint): DQ2.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TTF_PTY_S3_DQ2. Reads ONLY WRK_TTF_PTY_S2_DQ (plus reference lookups / target guard tables where the original reads them; those are not work-table dependencies).
--
-- DOES IT FEED THE SPINE?
--   Indirectly: it is an early staged step; every later step reads (transitively) from it, and the publish branches read the final routed table, which derives from it. It writes no target itself.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only. Snowflake cannot
--   parameterise table names in static SQL, so P_INPUT_TABLES is a
--   dependency declaration + runtime check, NOT dynamic SQL: the CTAS
--   below still names its source work table literally, as in the
--   current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-30 SELECT verbatim. Only
--   substitution: :l_run_ts -> :P_RUN_TS; :c_mapping resolves to the
--   local constant below (used by the checkpoint and, where the
--   original used it, materialised into the work table). No business
--   expression, filter, guard or column list was changed. This step uses no original parameter.
--   It does not reference the run timestamp directly; P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   in the v2 10-argument form. P_JOB_RUN_ID is present in every new
--   proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_TTF_PTY_S30_DQ2 (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TTF_PTY_S2_DQ') RETURN NUMBER AUTHID CURRENT_USER AS
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

    -- ---- Step 30: DQ2 (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TTF_PTY_S3_DQ2';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TTF_PTY_S3_DQ2 AS WITH
    lkp_exc  AS (SELECT * FROM TABLE(fn_snow_helper40_common()))
    SELECT d.*,
           CAST(d.nm.first_name AS VARCHAR2(4000))          AS std_first_name,
           CAST(d.nm.middle_name AS VARCHAR2(4000))         AS std_mdl_name,
           CAST(d.nm.last_name AS VARCHAR2(4000))           AS std_lst_name,
           CAST(d.nm.full_name AS VARCHAR2(4000))           AS std_full_name,
           CAST(d.nm.src_full_name AS VARCHAR2(4000))       AS std_src_full_name,
           CAST(d.nm.prfx_name AS VARCHAR2(4000))           AS std_prfx_name,
           CAST(d.gd.mdm_gender_code AS VARCHAR2(4000))     AS mdm_gender_code,
           CAST(d.gd.exception_code AS VARCHAR2(4000))      AS gender_exception_code,
           xg.EXCEPTION_DESC                 AS gender_exception_description,
           xg.EXCEPTION_TYPE                 AS gender_exception_type,
           /* BAD DATA */ CASE WHEN d.birth_exception_code IS NULL THEN d.DOB ELSE NULL END AS std_birth_date,
           xb.EXCEPTION_DESC                 AS birth_exception_description,
           xb.EXCEPTION_TYPE                 AS birth_exception_type,
           xe.EXCEPTION_CODE                 AS ethnicity_exception_code,
           xe.EXCEPTION_DESC                 AS ethnicity_exception_desc,
           xe.EXCEPTION_TYPE                 AS ethnicity_exception_type,
           xr.EXCEPTION_CODE                 AS race_exception_code,
           xr.EXCEPTION_DESC                 AS race_exception_desc,
           xr.EXCEPTION_TYPE                 AS race_exception_type
      FROM WRK_TTF_PTY_S2_DQ d
      LEFT JOIN lkp_exc xg ON xg.EXCEPTION_CODE = CAST(d.gd.exception_code AS VARCHAR2(4000))
      LEFT JOIN lkp_exc xb ON xb.EXCEPTION_CODE = d.birth_exception_code
      LEFT JOIN lkp_exc xe ON xe.EXCEPTION_CODE = fn_snow_helper18_common(d.ethnicity_mstr, 'Invalid_Ethnicity')
      LEFT JOIN lkp_exc xr ON xr.EXCEPTION_CODE = fn_snow_helper18_common(d.race_mstr, 'Invalid_Race')]';
    SELECT COUNT(*) INTO l_rows FROM WRK_TTF_PTY_S3_DQ2;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'DQ2', 'COMPLETED', NULL, 'Step 30 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TTF_PTY_S30_DQ2;
/

