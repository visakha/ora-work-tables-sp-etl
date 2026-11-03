-- ============================================================================
-- sp_snow_step_TTF_VAL_S10_ENRICHED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TTF)
--
-- Mapping: m_Tgt_C_S_TTF_Pty_Validation, workflow wf_TTF_Stage_Load, step 10.
-- Step name (checkpoint): ENRICHED.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TTF_VAL_S1_ENRICHED. Reads base source tables, not work tables, so its default P_INPUT_TABLES is empty and the existence check below is skipped.
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
--   The CTAS below is the current step-10 SELECT verbatim. Only
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
CREATE OR REPLACE FUNCTION sp_snow_step_TTF_VAL_S10_ENRICHED (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT '') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TTF';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TTF_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TTF_Pty_Validation';
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

    -- ---- Step 10: ENRICHED (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TTF_VAL_S1_ENRICHED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TTF_VAL_S1_ENRICHED AS WITH
    lkp_junk AS (SELECT * FROM TABLE(fn_snow_helper43_common())),
    sts AS (    -- Lookup_STG_TTF_PTY_INACTIVE_STS (any row)
        SELECT * FROM (SELECT i.SRC_KEY, i.DEACTIVATION_STS
          , ROW_NUMBER() OVER (PARTITION BY i.SRC_KEY ORDER BY i.DEACTIVATION_DT DESC NULLS LAST) AS __qual_rn FROM STG_TTF_PTY_INACTIVE_STS i
         WHERE i.ROWID_SYSTEM = 'TTF') WHERE __qual_rn = 1
    ),
    xref AS (   -- Lookup_C_B_PTY_XREF (lookup filter TRIM(ROWID_SYSTEM) = 'TTF')
        SELECT * FROM (SELECT x.PKEY_SRC_OBJECT, x.HUB_STATE_IND
          , ROW_NUMBER() OVER (PARTITION BY x.PKEY_SRC_OBJECT ORDER BY x.HUB_STATE_IND DESC NULLS LAST) AS __qual_rn FROM C_B_PTY_XREF x
         WHERE TRIM(x.ROWID_SYSTEM) = 'TTF') WHERE __qual_rn = 1
    ),
    enriched AS (
        SELECT v.CLIENTS_ID, v.FIRSTNAME, v.LASTNAME, v.MIDDLENAME, v.DOB, v.CREATEDDATE, v.SUBMITDATE,
               v.CLIENT_EXISTS_FLAG,
               LPAD(TO_CHAR(v.CLIENTS_ID), 10, '0')  AS pkey_src_object,
               sts.DEACTIVATION_STS                     AS deactivation_sts,
               xref.HUB_STATE_IND                       AS hub_state_ind,
               fn_snow_helper15_common(v.FIRSTNAME, v.MIDDLENAME, v.LASTNAME,
                   TRIM(NVL(CASE WHEN v.FIRSTNAME = 1 THEN 1 ELSE 0 END, '') || CASE WHEN v.MIDDLENAME IS NOT NULL THEN ' ' || TRIM(v.MIDDLENAME) ELSE '' END
                        || ' ' || NVL(LTRIM(v.LASTNAME), '')),
                   NULL, NULL, NULL, NULL, jf.NAME IS NOT NULL, jl.NAME IS NOT NULL) AS nm
          FROM V_TTF_ETL_SRC v
          LEFT JOIN sts  ON sts.SRC_KEY = LPAD(TO_CHAR(v.CLIENTS_ID), 10, '0')
          LEFT JOIN xref ON xref.PKEY_SRC_OBJECT = LPAD(TO_CHAR(v.CLIENTS_ID), 10, '0')
          LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(v.FIRSTNAME)) AND jf.IS_FIRST_JUNK = 1
          LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(v.LASTNAME)) AND jl.IS_LAST_JUNK = 1
    )
    SELECT * FROM enriched]';
    SELECT COUNT(*) INTO l_rows FROM WRK_TTF_VAL_S1_ENRICHED;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'ENRICHED', 'COMPLETED', NULL, 'Step 10 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TTF_VAL_S10_ENRICHED;
/

