-- ============================================================================
-- sp_snow_step_CRE_CARE_S20_NAMED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (CRE)
--
-- Mapping: m_Tgt_C_S_CRE_CARE_Clients, workflow wf_CRE_Stage_Load_Ongoing, step 20.
-- Step name (checkpoint): NAME_STANDARDISE_VALIDATE.
--
-- WHAT THIS STEP PRODUCES
--   WRK_CRE_CARE_S2_NAMED: name standardisation + member validity (named + members).
--   One standardised row per source record, with the valid-member flag (a standardised first AND last name must both be present) and the end-dated flag for moved/deleted rows. Reads ONLY step 10 (plus the reference lookups).
--
-- DOES IT FEED THE SPINE?
--   Indirectly: invalid members are dropped from the load here (their missing-name exceptions are logged at publish); valid members flow on to the spine branches via step 50.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only. Default: 'WRK_CRE_CARE_S1_SRC_MRG'
--   (empty for step 10: it reads base source tables, not work tables, so
--   the existence check below is skipped). Snowflake cannot parameterise
--   table names in static SQL, so P_INPUT_TABLES is a dependency
--   declaration + runtime check, NOT dynamic SQL: the CTAS below still
--   names its sources literally, as in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-20 SELECT verbatim. Only
--   substitutions: :l_run_ts -> :P_RUN_TS, :c_mapping -> the local
--   constant below (used by the checkpoint), no original-parameter refs in this step. No business
--   expression, filter, guard or column list was changed. This step uses
--   original parameters: none.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   with the same STEP_NAME and message as the current step-20
--   checkpoint (v2 10-argument form; STEP_NO, row count, and work-table
--   arguments dropped). P_JOB_RUN_ID is present in every new proc in
--   this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_CRE_CARE_S20_NAMED (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_CRE_CARE_S1_SRC_MRG') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'CRE';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_CRE_Stage_Load_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_CRE_CARE_Clients';
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

    -- ---- Step 20: NAME_STANDARDISE_VALIDATE (verbatim from current main)
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_CRE_CARE_S2_NAMED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_CRE_CARE_S2_NAMED AS WITH
    lkp_junk AS (SELECT * FROM TABLE(fn_snow_helper43_common())),
    lkp_cv   AS (SELECT * FROM TABLE(fn_snow_helper41_common())),
    -- Union + mplt_Name_Standardization_Indv_Member (first, last, suffix and source system linked)
    named AS (
        SELECT r.*,
               CASE WHEN r.grp_deletes = 1 THEN NULL ELSE CASE WHEN r.no_merge_history = 1 THEN 'N' ELSE 'Y' END END            AS orig_rowid_object_desc,
               fn_snow_helper15_common(r.FIRSTNM, NULL, r.LASTNM, NULL, NULL, r.LAST_SUF, NULL,
                                       sf.MSTR_CODE_VALUE, jf.NAME IS NOT NULL, jl.NAME IS NOT NULL) AS nm
          FROM WRK_CRE_CARE_S1_SRC_MRG r
          LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(r.FIRSTNM)) AND jf.IS_FIRST_JUNK = 1
          LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(r.LASTNM)) AND jl.IS_LAST_JUNK = 1
          LEFT JOIN lkp_cv sf ON sf.CODE_TYPE = 'SUFFIX' AND sf.SRC_SYS = 'CRE' AND sf.SRC_CODE_VALUE = r.LAST_SUF
    )
    -- rtr_Valid_Members, EXP_INVALID_MEMBERS, EXP_VALID_MEMBERS
    SELECT n.*,
           CAST(n.nm.first_name AS VARCHAR2(4000))                                                AS std_first_name,
           CAST(n.nm.last_name AS VARCHAR2(4000))                                                 AS std_lst_name,
           CAST(n.nm.full_name AS VARCHAR2(4000))                                                 AS std_full_name,
           CAST(n.nm.src_full_name AS VARCHAR2(4000))                                             AS std_src_full_name,
           CAST(n.nm.sfx_name AS VARCHAR2(4000))                                                  AS std_sfx_name,
           CAST(n.nm.src_suffix AS VARCHAR2(4000))                                                AS src_suffix,
           CAST(n.nm.suffix_exception_code AS VARCHAR2(4000))                                     AS suffix_exception_code,
           /* VALIDATION */
           NVL(CASE WHEN LENGTH(TRIM(CAST(n.nm.first_name AS VARCHAR2(4000)))) > 0 AND LENGTH(TRIM(CAST(n.nm.last_name AS VARCHAR2(4000)))) > 0 THEN 1 ELSE 0 END, 0)                                                              AS valid_member,
           CASE WHEN fn_snow_helper03_common(CAST(n.nm.first_name AS VARCHAR2(4000))) = 1 THEN 'Missing_First_Name' ELSE NULL END AS fn_missing_code,
           CASE WHEN fn_snow_helper03_common(CAST(n.nm.last_name AS VARCHAR2(4000))) = 1 THEN 'Missing_Last_Name' ELSE NULL END   AS ln_missing_code,
           n.REC_TYPE IN ('B', 'D')                                                AS end_dated
      FROM named n]';
    SELECT COUNT(*) INTO l_rows FROM WRK_CRE_CARE_S2_NAMED;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'NAME_STANDARDISE_VALIDATE', 'COMPLETED', NULL, 'Step 20 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_CRE_CARE_S20_NAMED;
/

