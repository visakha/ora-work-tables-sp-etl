-- ============================================================================
-- sp_snow_step_ECI_VAL_S20_ENRICHED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI)
--
-- Mapping: m_Tgt_C_S_ECI_Pty_Validation, workflow wf_ECI_Stage_Load,
-- step 20. Step name (checkpoint): ENRICHED_STD_NAMES.
--
-- WHAT THIS STEP PRODUCES
--   WRK_ECI_VAL_S20_ENRICHED: each step-10 party joined to its current
--   deactivation status, its hub cross-reference state, the
--   duplicate-case list and the family validation list, with
--   standardised names (nm). Reads ONLY step 10 (plus the reference
--   lookups). This is the original sts / xref / dup / fam CTEs plus
--   the enriched CTE.
--
-- DOES IT FEED THE STATUS PATH?
--   Yes, upstream: the routing step reads only this table, and the
--   publish STATUS branches (STG_ECI_PTY_INACTIVE_LOG /
--   STG_ECI_PTY_INACTIVE_STS) derive from it via step 30. It writes
--   no target itself.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only; default
--   'WRK_ECI_VAL_S10_SRC'. Base source tables and target guard tables
--   (STG_ECI_PTY_INACTIVE_STS, C_B_PTY_XREF, V_ECI_ETL_LU_DUP_CASES,
--   V_ECI_ETL_LU_FAMILY_VALIDATION) are NOT work-table dependencies
--   and are not listed. Snowflake cannot parameterise table names in
--   static SQL, so P_INPUT_TABLES is a dependency declaration +
--   runtime check, NOT dynamic SQL: the CTAS below still names its
--   sources literally, as in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-20 SELECT verbatim. Only
--   substitutions: :l_run_ts -> :P_RUN_TS (not used by this step),
--   :c_mapping -> the local constant below (used by the checkpoint).
--   No business expression, filter, guard or column list was changed.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   with the same STEP_NAME and message as the current step-20 checkpoint (v2 10-argument form; STEP_NO, row count, and work-table arguments dropped).
--   P_JOB_RUN_ID is present in every new proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_ECI_VAL_S20_ENRICHED (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_VAL_S10_SRC') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_ECI_Pty_Validation';
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

    -- ---- Step 20: LOOKUPS + NAME STANDARDISATION (verbatim from current main)
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_VAL_S20_ENRICHED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_ECI_VAL_S20_ENRICHED AS WITH
    lkp_junk AS (SELECT * FROM TABLE(fn_snow_helper43_common())),
    sts AS (
        SELECT * FROM (SELECT i.SRC_KEY, i.ROWID_SYSTEM, i.DEACTIVATION_STS
          , ROW_NUMBER() OVER (PARTITION BY i.SRC_KEY, i.ROWID_SYSTEM
                                      ORDER BY i.DEACTIVATION_DT DESC NULLS LAST) AS __qual_rn FROM STG_ECI_PTY_INACTIVE_STS i) WHERE __qual_rn = 1
    ),
    xref AS (
        SELECT * FROM (SELECT x.PKEY_SRC_OBJECT, x.HUB_STATE_IND
          , ROW_NUMBER() OVER (PARTITION BY x.PKEY_SRC_OBJECT ORDER BY x.HUB_STATE_IND DESC NULLS LAST) AS __qual_rn FROM C_B_PTY_XREF x
         WHERE TRIM(x.ROWID_SYSTEM) = 'ECI') WHERE __qual_rn = 1
    ),
    dup AS (
        SELECT DISTINCT d.SOURCE_TABLE, d.ID FROM V_ECI_ETL_LU_DUP_CASES d
    ),
    fam AS (
        SELECT * FROM (SELECT f.SOURCE_TABLE, f.ID_FAMILY, f.FAM_NAME_STATUS, f.FAM_PHONE_AND_ADDRESS_STS, f.FAM_INACTIVE_STS
          , ROW_NUMBER() OVER (PARTITION BY f.SOURCE_TABLE, f.ID_FAMILY ORDER BY f.ID_FAMILY) AS __qual_rn FROM V_ECI_ETL_LU_FAMILY_VALIDATION f) WHERE __qual_rn = 1
    )
    SELECT e.*,
           sts.DEACTIVATION_STS                                                    AS deactivation_sts,
           xref.HUB_STATE_IND                                                      AS hub_state_ind,
           dup.ID                                                                  AS omit_id,
           CASE WHEN fam.FAM_NAME_STATUS IS NULL AND fam.FAM_PHONE_AND_ADDRESS_STS IS NULL
               AND fam.FAM_INACTIVE_STS IS NULL THEN 'N' ELSE 'Y' END                         AS fam_inactive_yn,
           fn_snow_helper15_common(e.FIRST_NAME, e.MIDDLE_INITIAL, e.LAST_NAME, e.full_name, NULL, NULL,
                                   NULL, NULL, jf.NAME IS NOT NULL, jl.NAME IS NOT NULL) AS nm
      FROM WRK_ECI_VAL_S10_SRC e
      LEFT JOIN sts  ON sts.SRC_KEY = e.pkey_src_object = 1 AND sts.ROWID_SYSTEM = e.src_system
      LEFT JOIN xref ON xref.PKEY_SRC_OBJECT = e.pkey_src_object
      LEFT JOIN dup  ON dup.SOURCE_TABLE = e.SOURCE_TABLE = 1 AND dup.ID = e.ID
      LEFT JOIN fam  ON fam.SOURCE_TABLE = e.SOURCE_TABLE = 1 AND fam.ID_FAMILY = e.ID
      LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(e.FIRST_NAME)) AND jf.IS_FIRST_JUNK = 1
      LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(e.LAST_NAME)) AND jl.IS_LAST_JUNK = 1]';
    SELECT COUNT(*) INTO l_rows FROM WRK_ECI_VAL_S20_ENRICHED;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'ENRICHED_STD_NAMES', 'COMPLETED', NULL,
        'Step 20 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_ECI_VAL_S20_ENRICHED;
/

