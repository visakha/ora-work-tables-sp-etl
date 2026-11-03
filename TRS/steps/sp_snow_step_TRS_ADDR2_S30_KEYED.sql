-- ============================================================================
-- sp_snow_step_TRS_ADDR2_S30_KEYED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Addr_2, workflow wf_TRS_Stage_Load_1_Ongoing, step 30.
-- Step name (checkpoint): KEYED_ADDR.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_ADDR2_S30_KEYED: ADDRESS-TYPE TRANSLATION + ROLE-ADDRESS KEY
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (pipe-delimited). Default: 'WRK_TRS_ADDR2_S20_SRC'.
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
--   P_MEMBER_ROLE_TYPE.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   in the 10-argument form. P_JOB_RUN_ID is present in every new proc
--   in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_ADDR2_S30_KEYED (P_MEMBER_ROLE_TYPE IN VARCHAR2 DEFAULT 'Member', P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_ADDR2_S20_SRC') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TRS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Addr_2';
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

    -- ---- Step 30: KEYED_ADDR (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_ADDR2_S30_KEYED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_ADDR2_S30_KEYED AS WITH
    lkp_cv AS (SELECT * FROM TABLE(fn_snow_helper41_common()))
    SELECT s.*,
           at.MSTR_CODE_VALUE                                                                    AS mstr_addr_tp,
           NVL(s.PSTL_CD, '') || CASE WHEN s.PSTL_CD_EXT IS NOT NULL THEN '-' || s.PSTL_CD_EXT ELSE '' END         AS rslt_pstl_cd,
           NVL(CASE WHEN s.PTY_PK = 1 THEN 1 ELSE 0 END, '') || '|' || :1 || '|' || NVL(at.MSTR_CODE_VALUE, '') || '|'
           || NVL(TO_CHAR(s.CASE_NUM), '') || '|' || NVL(TO_CHAR(s.EDG_NUM), '') || '|'
           || NVL(TO_CHAR(s.EFF_BEGIN_DT, 'YYYYMMDD'), '')                                    AS pkey_pty_rle_addr,
           fn_snow_helper21_common(s.EFF_END_DT, :2)                                       AS end_date_50y
      FROM WRK_TRS_ADDR2_S20_SRC s
      LEFT JOIN lkp_cv at ON at.CODE_TYPE = 'ADDR_TP' AND at.SRC_SYS = 'TRS' AND at.SRC_CODE_VALUE = s.ADDR_TYPE_CD]' USING P_MEMBER_ROLE_TYPE, P_RUN_TS;
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_ADDR2_S30_KEYED;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'KEYED_ADDR', 'COMPLETED', NULL, 'Step 30 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_ADDR2_S30_KEYED;
/

