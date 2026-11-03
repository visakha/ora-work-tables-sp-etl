-- ============================================================================
-- sp_snow_step_TRS_PHN_S60_EMAILS  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr, workflow wf_TRS_Stage_Load_1_Ongoing, step 60.
-- Step name (checkpoint): EMAILS_CHECKED.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_PHN_S6_EMAILS: E-MAILS -- validate (BR-28/29)
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (pipe-delimited). Default: 'WRK_TRS_PHN_S1_SRC'.
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-60 SELECT verbatim. Only
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
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_PHN_S60_EMAILS (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_PHN_S1_SRC') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TRS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr';
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

    -- ---- Step 60: EMAILS_CHECKED (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_PHN_S6_EMAILS';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_PHN_S6_EMAILS AS WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    emails AS (
        SELECT s.*,
               fn_snow_helper22_common(s.EMAIL)                                AS em
          FROM WRK_TRS_PHN_S1_SRC s
         WHERE TRIM(s.EMAIL) IS NOT NULL
    ),
    emails_checked AS (
        SELECT e.*,
               CAST(e.em.email_address AS VARCHAR2(4000))                                     AS std_email,
               xe.EXCEPTION_CODE AS em_exc_code, xe.EXCEPTION_DESC AS em_exc_desc, xe.EXCEPTION_TYPE AS em_exc_type
          FROM emails e
          LEFT JOIN lkp_exc xe ON xe.EXCEPTION_CODE = CAST(e.em.exception_code AS VARCHAR2(4000))
    )
    SELECT ec.*,
           CASE WHEN -- usg_tp is NULL for every e-mail row, so it does not change the grouping and is omitted here
           ROW_NUMBER() OVER (PARTITION BY TO_CHAR(ec.INDV_ID), TO_CHAR(ec.CASE_NUM), ec.em_exc_type, ec.em_exc_code
                                  ORDER BY ec.CREATE_DT DESC) = 1 THEN 1 ELSE 0 END AS uq_exc
      FROM emails_checked ec]';
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_PHN_S6_EMAILS;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'EMAILS_CHECKED', 'COMPLETED', NULL, 'Step 60 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_PHN_S60_EMAILS;
/

