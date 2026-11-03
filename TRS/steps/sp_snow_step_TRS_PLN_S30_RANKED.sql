-- ============================================================================
-- sp_snow_step_TRS_PLN_S30_RANKED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_Pln, workflow wf_TRS_Stage_Load_1_Ongoing, step 30.
-- Step name (checkpoint): RANKED.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_PLN_S30_RANKED: RANK + GUARD + EXCEPTION TEXT (BR-26/02)
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (pipe-delimited). Default: 'WRK_TRS_PLN_S20_PLANNED'.
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
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_PLN_S30_RANKED (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_PLN_S20_PLANNED') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TRS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_Pln';
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

    -- ---- Step 30: RANKED (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_PLN_S30_RANKED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_PLN_S30_RANKED AS WITH lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common()))
    SELECT p.*,
           ROW_NUMBER() OVER (PARTITION BY p.pkey_prty_rl_plan
                              ORDER BY p.BEGIN_DT DESC NULLS FIRST, p.END_DT DESC NULLS FIRST,
                                       p.pty_rle_fk DESC NULLS FIRST, p.CREATE_DT DESC NULLS FIRST) AS rn_key,
           ROW_NUMBER() OVER (PARTITION BY p.INDV_ID, p.pln_mstr_cd IS NULL
                              ORDER BY p.MC_PLAN, p.BEGIN_DT, p.END_DT) AS rn_invalid,
           CASE WHEN xp.PKEY_SRC_OBJECT IS NULL THEN 1 ELSE 0 END AS uq_pln,
           1 AS version_seq,
           'TRS' AS src_sys,
           :1 AS run_ts,
           :2 AS mapping_name,
           'Plan' AS attr_plan,
           'Invalid_Plan' AS exc_code,
           ex.EXCEPTION_DESC AS exc_desc,
           ex.EXCEPTION_TYPE AS exc_type,
           TO_CHAR(p.BEGIN_DT, 'YYYY-MM-DD') AS begin_dt_text
      FROM WRK_TRS_PLN_S20_PLANNED p
      LEFT JOIN lkp_exc ex ON ex.EXCEPTION_CODE = 'Invalid_Plan'
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TRS_PTY_RLE_PLN WHERE VERSION_SEQ = 1) xp
             ON xp.PKEY_SRC_OBJECT = p.pkey_prty_rl_plan]' USING P_RUN_TS, c_mapping;
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_PLN_S30_RANKED;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'RANKED', 'COMPLETED', NULL, 'Step 30 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_PLN_S30_RANKED;
/

