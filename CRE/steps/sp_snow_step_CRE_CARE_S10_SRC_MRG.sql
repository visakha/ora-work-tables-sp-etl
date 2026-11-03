-- ============================================================================
-- sp_snow_step_CRE_CARE_S10_SRC_MRG  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (CRE)
--
-- Mapping: m_Tgt_C_S_CRE_CARE_Clients, workflow wf_CRE_Stage_Load_Ongoing, step 10.
-- Step name (checkpoint): SRC_MERGE_ROUTING.
--
-- WHAT THIS STEP PRODUCES
--   WRK_CRE_CARE_S1_SRC_MRG: CARE snapshot + merge routing (src + xref + hmrg + routed).
--   CARE client snapshot -- new and changed clients, deleted and moved cases, and move targets -- with merge routing from the party cross-reference and merge history. Rows that are not regular or deleted, with no merge history at all, are the ones the publish step writes to CRE_SRC_MRG. Every later step reads this table, never the raw sources again.
--
-- DOES IT FEED THE SPINE?
--   Indirectly: it is the first staged step; every later step reads (transitively) from it, and the publish branches read step 50, which derives from it. It writes no target itself.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only. Default: ''
--   (empty for step 10: it reads base source tables, not work tables, so
--   the existence check below is skipped). Snowflake cannot parameterise
--   table names in static SQL, so P_INPUT_TABLES is a dependency
--   declaration + runtime check, NOT dynamic SQL: the CTAS below still
--   names its sources literally, as in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-10 SELECT verbatim. Only
--   substitutions: :l_run_ts -> :P_RUN_TS, :c_mapping -> the local
--   constant below (used by the checkpoint), no original-parameter refs in this step. No business
--   expression, filter, guard or column list was changed. This step uses
--   original parameters: none.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   with the same STEP_NAME and message as the current step-10
--   checkpoint (v2 10-argument form; STEP_NO, row count, and work-table
--   arguments dropped). P_JOB_RUN_ID is present in every new proc in
--   this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_CRE_CARE_S10_SRC_MRG (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT '') RETURN NUMBER AUTHID CURRENT_USER AS
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

    -- ---- Step 10: SRC_MERGE_ROUTING (verbatim from current main)
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_CRE_CARE_S1_SRC_MRG';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_CRE_CARE_S1_SRC_MRG AS WITH
    -- Read_Stg_CRE_D_CARE_Clients (custom SQL; the parallel hint and commented test filters left out)
    src AS (
        SELECT DISTINCT CLIENTS.CARE_ID, CLIENTS.CARE_LASTUP_DT, CLIENTS.FIRSTNM, CLIENTS.LASTNM, CLIENTS.LAST_SUF,
               CLIENTS.BIRTH_DT, CLIENTS.SEX, CLIENTS.STREET, CLIENTS.CITY, CLIENTS.CNTY, CLIENTS.STATE,
               CLIENTS.ZIP, CLIENTS.ZIPSUF, CLIENTS.PHONE, CLIENTS.RECIP_NO, CLIENTS.MAINT_FLAG, CLIENTS.SSN,
               CLIENTS.INSERT_DATE, CLIENTS.FEDETH, CLIENTS.RACE, CAST(NULL AS VARCHAR2(4000)) AS SOURCE_ID,
               CAST(NULL AS VARCHAR2(4000)) AS TARGET_ID, CAST(NULL AS VARCHAR2(4000)) AS REC, 'I' AS REC_TYPE
          FROM STG_CRE_D_CARE_CLIENTS CLIENTS
         WHERE CLIENTS.MAINT_FLAG IS NULL
        UNION ALL
        SELECT DISTINCT CLIENTS.CARE_ID, CLIENTS.CARE_LASTUP_DT, CLIENTS.FIRSTNM, CLIENTS.LASTNM, CLIENTS.LAST_SUF,
               CLIENTS.BIRTH_DT, CLIENTS.SEX, CLIENTS.STREET, CLIENTS.CITY, CLIENTS.CNTY, CLIENTS.STATE,
               CLIENTS.ZIP, CLIENTS.ZIPSUF, CLIENTS.PHONE, CLIENTS.RECIP_NO, DELTAS.MAINT_FLAG, CLIENTS.SSN,
               CLIENTS.INSERT_DATE, CLIENTS.FEDETH, CLIENTS.RACE, MAINT.SOURCE_ID, MAINT.TARGET_ID, MAINT.REC,
               DECODE(MAINT.REC, 'CASEMOV', 'B', 'D')
          FROM STG_CRE_D_CARE_CLIENTS DELTAS
          LEFT JOIN STG_CRE_SN_CARE_CLIENTS CLIENTS
            ON DELTAS.CARE_ID = CLIENTS.CARE_ID
          JOIN STG_CRE_D_CARE_CASE_MAINT MAINT
            ON CLIENTS.CARE_ID = MAINT.SOURCE_ID = 1 AND DELTAS.MAINT_FLAG = 'D'
           AND MAINT.REC IN ('CASEMOV', 'CASEDEL')
        UNION ALL
        SELECT DISTINCT CLIENTS.CARE_ID, CLIENTS.CARE_LASTUP_DT, CLIENTS.FIRSTNM, CLIENTS.LASTNM, CLIENTS.LAST_SUF,
               CLIENTS.BIRTH_DT, CLIENTS.SEX, CLIENTS.STREET, CLIENTS.CITY, CLIENTS.CNTY, CLIENTS.STATE,
               CLIENTS.ZIP, CLIENTS.ZIPSUF, CLIENTS.PHONE, CLIENTS.RECIP_NO, CLIENTS.MAINT_FLAG, CLIENTS.SSN,
               CLIENTS.INSERT_DATE, CLIENTS.FEDETH, CLIENTS.RACE, MAINT.SOURCE_ID, MAINT.TARGET_ID, MAINT.REC,
               'A' AS REC_TYPE
          FROM STG_CRE_SN_CARE_CLIENTS CLIENTS
          JOIN STG_CRE_D_CARE_CASE_MAINT MAINT
            ON CLIENTS.CARE_ID = MAINT.TARGET_ID = 1 AND MAINT.REC = 'CASEMOV'
    ),
    -- LKP_XREF_SRC / LKP_XREF_TGT: CHAR columns are not compared blank-padded in Snowflake, hence the trims
    xref AS (
        SELECT * FROM (SELECT x.PKEY_SRC_OBJECT, RTRIM(x.ROWID_OBJECT) AS ROWID_OBJECT,
               RTRIM(x.ORIG_ROWID_OBJECT) AS ORIG_ROWID_OBJECT
          , ROW_NUMBER() OVER (PARTITION BY x.PKEY_SRC_OBJECT ORDER BY x.ROWID_XREF) AS __qual_rn FROM C_B_PTY_XREF x
         WHERE TRIM(x.ROWID_SYSTEM) = 'CRE') WHERE __qual_rn = 1
    ),
    -- LKP_HMRG_SRC1 / LKP_HMRG_TGT1 (by SRC_ROWID_OBJECT) and LKP_HMRG_SRC2 / LKP_HMRG_TGT2 (by TGT_ROWID_OBJECT)
    hmrg_src AS (SELECT DISTINCT RTRIM(SRC_ROWID_OBJECT) AS ROWID_OBJECT FROM C_B_PTY_HMRG
                  WHERE SRC_ROWID_OBJECT IS NOT NULL),
    hmrg_tgt AS (SELECT DISTINCT RTRIM(TGT_ROWID_OBJECT) AS ROWID_OBJECT FROM C_B_PTY_HMRG
                  WHERE TGT_ROWID_OBJECT IS NOT NULL)
    -- RTR_MERGES (VALIDATION: NULL conditions route to the default group) + EXP_SRC_TGT_MRG_RSLT
    SELECT s.*,
           NVL(CASE WHEN s.MAINT_FLAG IS NULL OR (s.MAINT_FLAG = 'D' AND s.REC = 'CASEDEL') THEN 1 ELSE 0 END, 0) AS grp_deletes,
           xs.ROWID_OBJECT AS src_rowid_object,
           xt.ROWID_OBJECT AS tgt_rowid_object,
           (h1.ROWID_OBJECT IS NULL AND h2.ROWID_OBJECT IS NULL AND h3.ROWID_OBJECT IS NULL
            AND h4.ROWID_OBJECT IS NULL) AS no_merge_history
      FROM src s
      LEFT JOIN xref xs ON xs.PKEY_SRC_OBJECT = s.SOURCE_ID
      LEFT JOIN xref xt ON xt.PKEY_SRC_OBJECT = s.TARGET_ID
      LEFT JOIN hmrg_src h1 ON h1.ROWID_OBJECT = xs.ORIG_ROWID_OBJECT
      LEFT JOIN hmrg_tgt h2 ON h2.ROWID_OBJECT = xs.ORIG_ROWID_OBJECT
      LEFT JOIN hmrg_src h3 ON h3.ROWID_OBJECT = xt.ORIG_ROWID_OBJECT
      LEFT JOIN hmrg_tgt h4 ON h4.ROWID_OBJECT = xt.ORIG_ROWID_OBJECT]';
    SELECT COUNT(*) INTO l_rows FROM WRK_CRE_CARE_S1_SRC_MRG;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'SRC_MERGE_ROUTING', 'COMPLETED', NULL, 'Step 10 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_CRE_CARE_S10_SRC_MRG;
/

