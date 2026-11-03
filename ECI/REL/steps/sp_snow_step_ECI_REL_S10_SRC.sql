-- ============================================================================
-- sp_snow_step_ECI_REL_S10_SRC  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI ONLY)
--
-- Mapping: m_Tgt_C_S_ECI_Pty_Rle_Rel, workflow wf_ECI_Stage_Load.
-- Step 10, SRC_BOTH_DIRECTIONS. Split out of
-- sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel; business SQL preserved verbatim
-- (the original src CTE, with its FROM pointed at the source table as now).
--
-- WHAT THIS STEP PRODUCES
--   WRK_ECI_REL_S10_SRC: every family row twice -- 'To Child' and
--   'From Child', one row per relationship direction.
-- FEEDS THE SPINE: yes -- via step 20 -> step 30 -> step 40 -> publish
--   branch 50 (C_S_ECI_PTY_RLE_REL, spine) and branch 60
--   (EXC_STG_BAD_REC_MEMB, non-spine exception rows).
--
-- P_INPUT_TABLES NOTE (read before changing this proc)
--   P_INPUT_TABLES is a dependency declaration + runtime existence check,
--   NOT dynamic SQL. Snowflake cannot parameterise table names in static
--   SQL, so the CTAS below still names its tables directly, exactly as
--   the current main does. The check below only verifies that the
--   declared work-table inputs exist before the CTAS runs. It lists
--   WORK-TABLE inputs only; base source tables (here STG_ECI_D_FAMILY)
--   are not work-table dependencies and are not listed or checked.
--   For this step the default is empty: step 10 reads no work table, so
--   the existence check is skipped.
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
--   P_JOB_RUN_ID   VARCHAR                 -- workflow-level run id
--   P_RUN_TS       TIMESTAMP_NTZ           -- run timestamp (driver's)
--   P_INPUT_TABLES VARCHAR DEFAULT ''     -- pipe-delimited work-table
--                                             inputs; empty for step 10
-- RETURNS NUMBER (row count of the work table created).
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_ECI_REL_S10_SRC (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT '') RETURN NUMBER AUTHID CURRENT_USER AS
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

    -- ---- Step 10: FAMILY ROWS, BOTH DIRECTIONS (verbatim from the main)
    -- Purpose: every family row twice -- 'To Child' and 'From Child'.
    -- This is the original src CTE.
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_REL_S10_SRC';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_ECI_REL_S10_SRC AS SELECT d.RELATION_DIRECTION, f.ID_FAMILY, f.GENDER AS FAMILY_GENDER, f.ID_CHILD, f.FAMILY_CD,
           COALESCE(f.DATE_MODIFIED, f.DATE_CREATED) AS DATE_MODIFIED, f.DATE_CREATED
      FROM STG_ECI_D_FAMILY f
     CROSS JOIN (SELECT column1 AS RELATION_DIRECTION FROM VALUES ('From Child'), ('To Child')) d]';
    SELECT COUNT(*) INTO l_rows FROM WRK_ECI_REL_S10_SRC;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'SRC_BOTH_DIRECTIONS', 'COMPLETED', NULL, 'Step 10 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_ECI_REL_S10_SRC;
/

