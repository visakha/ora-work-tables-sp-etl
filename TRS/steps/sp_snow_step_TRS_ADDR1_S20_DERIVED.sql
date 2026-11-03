-- ============================================================================
-- sp_snow_step_TRS_ADDR1_S20_DERIVED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Addr_1, workflow wf_TRS_Stage_Load_1_Ongoing, step 20.
-- Step name (checkpoint): DERIVED_ADDR_LINES.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_ADDR1_S20_DERIVED: STREET-TYPE LOOKUP + DERIVED LINES
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (pipe-delimited). Default: 'WRK_TRS_ADDR1_S10_SRC'.
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-20 SELECT verbatim. Only
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
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_ADDR1_S20_DERIVED (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_ADDR1_S10_SRC') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TRS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Addr_1';
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

    -- ---- Step 20: DERIVED_ADDR_LINES (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_ADDR1_S20_DERIVED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_ADDR1_S20_DERIVED AS SELECT s.*,
           TRIM(NVL(TO_CHAR(s.ADDR_ST_NUM), '') || ' ' || NVL(s.ADDR_ST_NUM_FRAC, '') || ' '
                || NVL(CASE WHEN UPPER(s.ADDR_ST_DIR_CD) IN ('EA', 'NO', 'SO', 'WE') = 1 THEN SUBSTR(s.ADDR_ST_DIR_CD, 1, 1) ELSE s.ADDR_ST_DIR_CD END, '')
                || ' ' || NVL(s.ADDR_ST_NM, '') || ' ' || NVL(st.DESCRIPTION, ''))                AS addr_line_1,
           TRIM(NVL(s.ADDR_DWELLING_TYPE_CD, '') || ' ' || NVL(s.ADDR_APT_NUM, '') || ' '
                || NVL(s.ADDR_LINE, ''))                                                         AS addr_line_2
      FROM WRK_TRS_ADDR1_S10_SRC s
      LEFT JOIN (SELECT * FROM (SELECT r.CODE, r.DESCRIPTION , ROW_NUMBER() OVER (PARTITION BY r.CODE ORDER BY r.DESCRIPTION) AS __qual_rn FROM STG_TRS_CD_REF r) WHERE __qual_rn = 1) st
             ON st.CODE = s.ADDR_ST_TYPE_CD]';
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_ADDR1_S20_DERIVED;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'DERIVED_ADDR_LINES', 'COMPLETED', NULL, 'Step 20 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_ADDR1_S20_DERIVED;
/

