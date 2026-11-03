-- ============================================================================
-- sp_snow_step_TTF_PHN_S10_SRC  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TTF)
--
-- Mapping: m_Tgt_C_S_TTF_Pty_Rle_Phn, workflow wf_TTF_Stage_Load, step 10.
-- Step name (checkpoint): SRC.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TTF_PHN_S1_SRC. Reads base source tables, not work tables, so its default P_INPUT_TABLES is empty and the existence check below is skipped.
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
CREATE OR REPLACE FUNCTION sp_snow_step_TTF_PHN_S10_SRC (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT '') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TTF';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TTF_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TTF_Pty_Rle_Phn';
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

    -- ---- Step 10: SRC (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TTF_PHN_S1_SRC';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TTF_PHN_S1_SRC AS SELECT v.PHONE, v.SUBMITDATE, v.PTY_SRC_KEY,
           NVL(CASE WHEN v.PTY_SRC_KEY = 1 THEN 1 ELSE 0 END, '') || '|Member|Telephone|001|' || v.PHONE AS phn_pkey,
           fn_snow_helper23_common(v.PHONE)                             AS std_phone
      FROM V_TTF_ETL_SRC v
     WHERE v.PHONE IS NOT NULL                                           -- Filt_null_phone
       AND NOT EXISTS (SELECT 1 FROM STG_TTF_PTY_INACTIVE_STS i          -- fil_deactivated_status
                        WHERE i.SRC_KEY = v.PTY_SRC_KEY = 1 AND i.ROWID_SYSTEM = 'TTF'
                          AND i.DEACTIVATION_STS IS NOT NULL)]';
    SELECT COUNT(*) INTO l_rows FROM WRK_TTF_PHN_S1_SRC;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'SRC', 'COMPLETED', NULL, 'Step 10 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TTF_PHN_S10_SRC;
/

