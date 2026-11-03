-- ============================================================================
-- sp_snow_step_TRS_TOA_S40_RANKED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_TOA, workflow wf_TRS_Stage_Load_1_Ongoing, step 40.
-- Step name (checkpoint): TOA_RANKED.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_TOA_S40_RANKED: EXCEPTION TEXT + UNIQUENESS FLAGS (BR-27/02)
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (pipe-delimited). Default: 'WRK_TRS_TOA_S30_KEYED'.
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
--   none.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   in the 10-argument form. P_JOB_RUN_ID is present in every new proc
--   in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_TOA_S40_RANKED (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_TOA_S30_KEYED') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TRS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_TOA';
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

    -- ---- Step 40: TOA_RANKED (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_TOA_S40_RANKED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_TOA_S40_RANKED AS WITH lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common()))
    SELECT k.*,
           'TRS' AS src_sys,
           :1 AS run_ts,
           :2 AS mapping_name,
           'Type of Assistance' AS attr_toa,
           'Effective Date' AS attr_dates,
           xt.EXCEPTION_CODE AS toa_exc_code,
           xt.EXCEPTION_DESC AS toa_exc_desc,
           xt.EXCEPTION_TYPE AS toa_exc_type,
           'Period_Start_Date_>_Period_End_Date' AS date_exc_code,
           xd.EXCEPTION_DESC AS date_exc_desc,
           xd.EXCEPTION_TYPE AS date_exc_type,
           CASE WHEN (ROW_NUMBER() OVER (PARTITION BY k.grp_bad_value = 1 OR k.grp_dates = 1, k.pkey_src_object
                                   ORDER BY k.CREATE_DT DESC) = 1
            AND xa.PKEY_SRC_OBJECT IS NULL) THEN 1 ELSE 0 END AS uq_toa,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY k.grp_bad_value, k.INDV_ID, k.EDG_NUM, k.MCI_CREATE_SEQ
                                  ORDER BY k.CREATE_DT DESC) = 1 THEN 1 ELSE 0 END AS uq_exc_toa,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY k.grp_dates, k.pkey_src_object, k.pty_rle_fk
                                  ORDER BY k.CREATE_DT DESC) = 1 THEN 1 ELSE 0 END AS uq_exc_dates
      FROM WRK_TRS_TOA_S30_KEYED k
      LEFT JOIN lkp_exc xt ON xt.EXCEPTION_CODE = 'Invalid_TOA'
      LEFT JOIN lkp_exc xd ON xd.EXCEPTION_CODE = 'Period_Start_Date_>_Period_End_Date'
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TRS_PTY_RLE_TOA WHERE VERSION_SEQ = 1) xa
             ON xa.PKEY_SRC_OBJECT = k.pkey_src_object]' USING P_RUN_TS, c_mapping;
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_TOA_S40_RANKED;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'TOA_RANKED', 'COMPLETED', NULL, 'Step 40 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_TOA_S40_RANKED;
/

