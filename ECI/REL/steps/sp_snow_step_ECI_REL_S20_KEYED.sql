-- ============================================================================
-- sp_snow_step_ECI_REL_S20_KEYED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI ONLY)
--
-- Mapping: m_Tgt_C_S_ECI_Pty_Rle_Rel, workflow wf_ECI_Stage_Load.
-- Step 20, KEYED_BOTH_ACTIVE. Split out of
-- sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel; business SQL preserved verbatim
-- (the original keyed CTE, with its FROM pointed at step 10 as now).
--
-- WHAT THIS STEP PRODUCES
--   WRK_ECI_REL_S20_KEYED: child / family party keys, keeping only rows
--   where NEITHER party has a deactivation status.
-- FEEDS THE SPINE: yes -- via step 30 -> step 40 -> publish branch 50
--   (C_S_ECI_PTY_RLE_REL, spine) and branch 60 (EXC_STG_BAD_REC_MEMB,
--   non-spine exception rows).
--
-- P_INPUT_TABLES NOTE (read before changing this proc)
--   P_INPUT_TABLES is a dependency declaration + runtime existence check,
--   NOT dynamic SQL. Snowflake cannot parameterise table names in static
--   SQL, so the CTAS below still names its tables directly, exactly as
--   the current main does. The check below only verifies that the
--   declared work-table inputs exist before the CTAS runs. It lists
--   WORK-TABLE inputs only; base source tables and target guard tables
--   (here STG_ECI_PTY_INACTIVE_STS) are not work-table dependencies
--   and are not listed or checked.
--
-- SUBSTITUTIONS vs the current main (only these; nothing else changed)
--   * :l_run_ts -> :P_RUN_TS (accepted for a uniform step signature;
--     this step does not stamp run_ts, so P_RUN_TS is unused here).
--   * :c_mapping -> local DECLARE constant with the same value.
--   * The step's own checkpoint, previously written inline in the main,
--     is written here with the same STEP_NAME and message as the current step checkpoint (v2 10-argument form; STEP_NO, row count, and work-table arguments dropped).
--
-- STYLE
--   TRANSIENT work table only, same name as now. No exception block
--   (errors propagate to the driver handler), no transactions, no target
--   writes. No drop checkpoint, no resume-step parameter, no row-by-row processing.
--
-- SIGNATURE
--   P_JOB_RUN_ID   VARCHAR                            -- workflow-level run id
--   P_RUN_TS       TIMESTAMP_NTZ                      -- run timestamp (driver's)
--   P_INPUT_TABLES VARCHAR DEFAULT 'WRK_ECI_REL_S10_SRC'
-- RETURNS NUMBER (row count of the work table created).
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_ECI_REL_S20_KEYED (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_REL_S10_SRC') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_ECI_Pty_Rle_Rel';
    l_rows NUMBER DEFAULT 0;
    l_missing VARCHAR2(4000);
    l_probe_sql VARCHAR2(4000);
    l_probe_dummy NUMBER;
BEGIN
    -- ---- Input existence check (skipped when P_INPUT_TABLES is NULL/empty)
    IF (P_INPUT_TABLES IS NOT NULL AND TRIM(P_INPUT_TABLES) <> '') THEN
        SELECT LISTAGG(UPPER(TRIM(tbl)), ', ') WITHIN GROUP (ORDER BY UPPER(TRIM(tbl))) INTO l_missing FROM (SELECT REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL) AS tbl FROM DUAL CONNECT BY REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL) IS NOT NULL) f WHERE NOT EXISTS (SELECT 1 FROM ALL_TABLES t WHERE t.OWNER = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AND t.TABLE_NAME = UPPER(TRIM(f.tbl)));
        IF (l_missing IS NOT NULL AND l_missing <> '') THEN
            l_probe_sql := 'SELECT COUNT(*) FROM ' || TRIM(REGEXP_SUBSTR(l_missing, '[^,]+', 1, 1));
            EXECUTE IMMEDIATE l_probe_sql INTO l_probe_dummy;
        END IF;
    END IF;

    -- ---- Step 20: PARTY KEYS + BOTH PARTIES ACTIVE (verbatim from the main)
    -- Purpose: build the child and family party keys and keep only
    -- rows where NEITHER party has a deactivation status. This is the
    -- original keyed CTE.
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_REL_S20_KEYED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_ECI_REL_S20_KEYED AS SELECT s.*,
           LPAD(TO_CHAR(s.ID_CHILD), 10, '0')          AS child_pty_src_key,
           LPAD(TO_CHAR(s.ID_FAMILY), 10, '0') || 'F'  AS family_pty_src_key
      FROM WRK_ECI_REL_S10_SRC s
     WHERE NOT EXISTS (SELECT 1 FROM STG_ECI_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = LPAD(TO_CHAR(s.ID_CHILD), 10, '0') AND i.ROWID_SYSTEM = 'ECI'
                          AND i.DEACTIVATION_STS IS NOT NULL)
       AND NOT EXISTS (SELECT 1 FROM STG_ECI_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = LPAD(TO_CHAR(s.ID_FAMILY), 10, '0') || 'F'
                          AND i.ROWID_SYSTEM = 'ECI' AND i.DEACTIVATION_STS IS NOT NULL)]';
    SELECT COUNT(*) INTO l_rows FROM WRK_ECI_REL_S20_KEYED;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'KEYED_BOTH_ACTIVE', 'COMPLETED', NULL, 'Step 20 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_ECI_REL_S20_KEYED;
/

