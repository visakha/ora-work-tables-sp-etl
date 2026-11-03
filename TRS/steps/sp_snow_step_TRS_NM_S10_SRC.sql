-- ============================================================================
-- sp_snow_step_TRS_NM_S10_SRC  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Nm, workflow wf_TRS_Stage_Load_1_Ongoing, step 10.
-- Step name (checkpoint): ALIAS_SRC.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_NM_S10_SRC: ALIAS SOURCE ROWS (BR-21/10)
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (pipe-delimited). Default: ''.
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-10 SELECT verbatim. Only
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
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_NM_S10_SRC (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT '') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TRS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_Nm';
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

    -- ---- Step 10: ALIAS_SRC (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_NM_S10_SRC';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_NM_S10_SRC AS SELECT DISTINCT DC_ALIAS.INDV_ID AS INDV_ID, DC_ALIAS.PKEY_PTY AS PKEY_PTY,
           RTRIM(LTRIM(DC_ALIAS.FIRST_NAME)) AS FIRST_NAME, RTRIM(LTRIM(DC_ALIAS.MID_NAME)) AS MID_NAME,
           RTRIM(LTRIM(DC_ALIAS.LAST_NAME)) AS LAST_NAME, RTRIM(DC_ALIAS.SUFX_NAME) AS SUFX_NAME,
           RTRIM(DC_ALIAS.PREFIX_NAME) AS PREFIX_NAME, DC_ALIAS.CREATE_DT AS CREATE_DT,
           DC_ALIAS.SEQUENCE_NUM AS SEQUENCE_NUM
      FROM (SELECT INDV_ID, TO_CHAR(INDV_ID) AS PKEY_PTY, FIRST_NAME, MID_NAME, LAST_NAME, SUFX_NAME,
                   PREFIX_NAME, CREATE_DT, SEQUENCE_NUM
              FROM STG_TRS_D_CV_DC_MCI_ALIAS MCI_ALIAS
            UNION ALL
            SELECT INDV_ID, TO_CHAR(INDV_ID) || '|DC_INDV' AS PKEY_PTY, FIRST_NAME, MID_NAME, LAST_NAME,
                   SUFX_NAME, PREFIX_NAME, CREATE_DT, SEQ_NUM
              FROM STG_TRS_D_DC_ALIAS DC_ALIAS) DC_ALIAS
      JOIN STG_TRS_VALID_MEMBERS VM ON DC_ALIAS.PKEY_PTY = VM.PTY_PK]';
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_NM_S10_SRC;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'ALIAS_SRC', 'COMPLETED', NULL, 'Step 10 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_NM_S10_SRC;
/

