-- ============================================================================
-- sp_snow_step_TRS_NM_S40_DEDUP  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Nm, workflow wf_TRS_Stage_Load_1_Ongoing, step 40.
-- Step name (checkpoint): DEDUP_KEYED.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_NM_S40_DEDUP: DE-DUPLICATE + KEY (BR-15)
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (pipe-delimited). Default: 'WRK_TRS_NM_S30_STD'.
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-40 SELECT verbatim. Only
--   substitution: :l_run_ts -> :P_RUN_TS (where used); :c_mapping is
--   the local constant below. No business expression, filter, guard
--   or column list was changed. This step uses original parameters:
--   P_MEMBER_NAME_TYPE_CODE.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   in the 10-argument form. P_JOB_RUN_ID is present in every new proc
--   in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_NM_S40_DEDUP (P_MEMBER_NAME_TYPE_CODE IN VARCHAR2 DEFAULT '002', P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_NM_S30_STD') RETURN NUMBER AUTHID CURRENT_USER AS
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

    -- ---- Step 40: DEDUP_KEYED (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_NM_S40_DEDUP';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_NM_S40_DEDUP AS SELECT DISTINCT s.PKEY_PTY, s.CREATE_DT, CAST(s.nm.sfx_name AS VARCHAR2(4000)) AS sfx_nm,
           CAST(s.nm.first_name AS VARCHAR2(4000)) AS frst_nm, CAST(s.nm.prfx_name AS VARCHAR2(4000)) AS prfx_nm,
           CAST(s.nm.last_name AS VARCHAR2(4000)) AS lst_nm, CAST(s.nm.middle_name AS VARCHAR2(4000)) AS mdl_nm,
           CAST(s.nm.full_name AS VARCHAR2(4000)) AS full_nm, s.src_full_name, s.SEQUENCE_NUM,
           NVL(s.PKEY_PTY, '') || '|' || :1 || '|' || NVL(TO_CHAR(s.SEQUENCE_NUM), '')
                                                                                        AS pkey_src_object
      FROM WRK_TRS_NM_S30_STD s]' USING P_MEMBER_NAME_TYPE_CODE;
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_NM_S40_DEDUP;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'DEDUP_KEYED', 'COMPLETED', NULL, 'Step 40 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_NM_S40_DEDUP;
/

