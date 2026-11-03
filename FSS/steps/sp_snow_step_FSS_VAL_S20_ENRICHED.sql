-- ============================================================================
-- sp_snow_step_FSS_VAL_S20_ENRICHED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (FSS)
--
-- Mapping: m_Tgt_C_S_FSS_Pty_Validation, workflow wf_FSS_Stage_Load, step 20.
-- Step name (checkpoint): ENRICHED.
--
-- WHAT THIS STEP PRODUCES
--   WRK_FSS_VAL_S2_ENRICHED: Standardised names + blank-name flag, current deactivation status, cross-reference state.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (default: 'WRK_FSS_VAL_S1_SRC').
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-20 SELECT verbatim. Only
--   substitution: :l_run_ts -> :P_RUN_TS (not used by this step),
--   :c_mapping -> the local constant below (used by the checkpoint).
--   No business expression, filter, guard or column list was changed.
--   Original parameters used by this step: none.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   in the v2 10-argument form (TARGET_TABLE NULL, as in the current
--   main's step checkpoints; row count survives in the RETURN value
--   and the driver's helper36 summary line).
--   P_JOB_RUN_ID is present in every new proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_FSS_VAL_S20_ENRICHED (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_FSS_VAL_S1_SRC') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'FSS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_FSS_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_FSS_Pty_Validation';
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

    -- ---- Step 20: ENRICHED (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_FSS_VAL_S2_ENRICHED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_FSS_VAL_S2_ENRICHED AS WITH
    lkp_junk AS (SELECT * FROM TABLE(fn_snow_helper43_common())),
    sts AS (    -- Lookup_STG_FSS_PTY_INACTIVE_STS (any row)
        SELECT * FROM (SELECT i.SRC_KEY, i.DEACTIVATION_STS
          , ROW_NUMBER() OVER (PARTITION BY i.SRC_KEY ORDER BY i.DEACTIVATION_DT DESC NULLS LAST) AS __qual_rn FROM STG_FSS_PTY_INACTIVE_STS i
         WHERE i.ROWID_SYSTEM = 'FSS') WHERE __qual_rn = 1
    ),
    xref AS (   -- Lookup_C_B_PTY_XREF (lookup filter ROWID_SYSTEM = 'FSS'; blank-padded MDM column trimmed)
        SELECT * FROM (SELECT x.PKEY_SRC_OBJECT, x.HUB_STATE_IND
          , ROW_NUMBER() OVER (PARTITION BY x.PKEY_SRC_OBJECT ORDER BY x.HUB_STATE_IND DESC NULLS LAST) AS __qual_rn FROM C_B_PTY_XREF x
         WHERE TRIM(x.ROWID_SYSTEM) = 'FSS') WHERE __qual_rn = 1
    ),
    enriched AS (
        SELECT s.*,
               sts.DEACTIVATION_STS AS deactivation_sts,
               xref.HUB_STATE_IND   AS hub_state_ind,
               fn_snow_helper15_common(s.NM_FIRST, s.NM_MIDDLE, s.NM_LAST,
                   TRIM(NVL(CASE WHEN s.NM_FIRST = 1 THEN 1 ELSE 0 END, '') || CASE WHEN s.NM_MIDDLE IS NOT NULL THEN ' ' || TRIM(s.NM_MIDDLE) ELSE '' END
                        || ' ' || NVL(LTRIM(s.NM_LAST), '')),
                   NULL, NULL, NULL, NULL, jf.NAME IS NOT NULL, jl.NAME IS NOT NULL) AS nm
          FROM WRK_FSS_VAL_S1_SRC s
          LEFT JOIN sts  ON sts.SRC_KEY = s.PTY_SRC_KEY
          LEFT JOIN xref ON xref.PKEY_SRC_OBJECT = s.PTY_SRC_KEY
          LEFT JOIN lkp_junk jf ON jf.NAME = UPPER(TRIM(s.NM_FIRST)) AND jf.IS_FIRST_JUNK = 1
          LEFT JOIN lkp_junk jl ON jl.NAME = UPPER(TRIM(s.NM_LAST)) AND jl.IS_LAST_JUNK = 1
    )
    SELECT n.*,
           CAST(n.nm.first_name AS VARCHAR2(4000))    AS std_first_name,
           CAST(n.nm.middle_name AS VARCHAR2(4000))   AS std_mdl_name,
           CAST(n.nm.last_name AS VARCHAR2(4000))     AS std_lst_name,
           CAST(n.nm.src_full_name AS VARCHAR2(4000)) AS std_src_full_name,
           /* VALIDATION */ (fn_snow_helper03_common(CAST(n.nm.first_name AS VARCHAR2(4000)))
                             OR fn_snow_helper03_common(CAST(n.nm.last_name AS VARCHAR2(4000))) = 1) AS name_missing
      FROM enriched n]';
    SELECT COUNT(*) INTO l_rows FROM WRK_FSS_VAL_S2_ENRICHED;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'ENRICHED', 'COMPLETED', NULL, 'Step 20 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_FSS_VAL_S20_ENRICHED;
/

