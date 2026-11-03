-- ============================================================================
-- sp_snow_step_ECI_RFM_S20_KEEPNEW
--   Step 20 (KEEP_NEW_ONLY) of
--   m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid, workflow
--   wf_ECI_Stage_Load. Config-driven step-driver refactor (ECI only).
--
-- WHAT THIS STEP PRODUCES
--   WRK_ECI_RFM_S20_KEEPNEW (TRANSIENT): rows passing the keep-new
--   filter, one row per Medicaid id. It feeds the reactivation status
--   write (step 30 publish into STG_ECI_D_MEDICAID).
--
-- RE-HOUSING ONLY
--   The CTAS below is the current step-20 CTAS verbatim: same SELECT,
--   same FROM pointed at the fixed work-table names as now. No
--   business expression, filter, guard, or column list was changed --
--   including the preserved defect (see below). Snowflake cannot
--   parameterise table names in static SQL, so P_INPUT_TABLES is a
--   dependency declaration plus a runtime existence check, NOT dynamic
--   SQL: the CTAS itself still names its source table literally.
--
-- PRESERVED DEFECT (kept deliberately, do not "fix" silently)
--   With the default P_TEST_LOOKUP_RESULT = 'N' the keep-new filter
--   tests the source ID_MEDICAID, which is never NULL, so this step is
--   empty -- exactly as IDQ does. Passing 'Y' tests the lookup result
--   instead and keeps records not yet in STG_ECI_D_MEDICAID.
--
-- INPUTS / PARAMS
--   P_TEST_LOOKUP_RESULT VARCHAR            -- original parameter; this
--                                             step's SQL DOES use it
--                                             (the IFF keep-new filter)
--   P_JOB_RUN_ID         VARCHAR            -- run id, from the driver
--   P_RUN_TS             TIMESTAMP_NTZ      -- run timestamp, from the
--                                             driver; accepted for a
--                                             uniform step interface,
--                                             but this mapping's SQL
--                                             has no run-timestamp
--                                             column, so it is unused
--                                             here
--   P_INPUT_TABLES       VARCHAR DEFAULT 'WRK_ECI_RFM_S10_LATEST'
--                                             -- pipe-delimited
--                                             WORK-TABLE inputs for
--                                             this step (step 10 only;
--                                             base source tables and
--                                             target guard tables are
--                                             not work-table
--                                             dependencies)
--
-- BEHAVIOUR
--   (1) Input existence check, skipped when P_INPUT_TABLES is NULL or
--       empty: every trimmed name must exist in INFORMATION_SCHEMA.TABLES
--       under CURRENT_SCHEMA(); otherwise a probe query
--       (EXECUTE IMMEDIATE 'SELECT 1 FROM <table>') surfaces the
--       native object-not-exists error naming the table and the step.
--       (Coordinator normalisation: Snowflake RAISE accepts only a
--       declared exception name, so a dynamic message is not possible.)
--   (2) The step CTAS, verbatim. It reads ONLY step 10, so the lookup
--       sees the delta table as it was before this run's publish,
--       exactly as in the original. (3) COUNT(*) into the return
--       value. (4) Its own checkpoint, with the same STEP_NAME, TARGET_TABLE, and message as the current step-20 checkpoint (v2 10-argument form; STEP_NO, row count, and work-table arguments dropped).
--   (5) RETURN the row count (NUMBER).
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes, no cursors.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_ECI_RFM_S20_KEEPNEW (P_TEST_LOOKUP_RESULT IN VARCHAR2, P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_RFM_S10_LATEST') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid';
    l_rows NUMBER DEFAULT 0;
    l_missing VARCHAR2(4000) DEFAULT NULL;
    l_probe_sql VARCHAR2(4000);
    l_probe_dummy NUMBER;
SELECT TRIM(MIN(s.raw)) INTO l_missing FROM (SELECT REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL) AS raw, UPPER(TRIM(REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL))) AS tbl FROM DUAL CONNECT BY REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL) IS NOT NULL) s WHERE TRIM(s.raw) <> '' AND NOT EXISTS (SELECT 1 FROM ALL_TABLES t WHERE t.OWNER = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AND t.TABLE_NAME = TRIM(s.raw));
        IF (l_missing IS NOT NULL) THEN
            l_probe_sql := 'SELECT COUNT(*) FROM ' || TRIM(REGEXP_SUBSTR(l_missing, '[^,]+', 1, 1));
            EXECUTE IMMEDIATE l_probe_sql INTO l_probe_dummy;
        END IF;
    END IF;

    -- ---- Step 20: KEEP-NEW FILTER + ONE ROW PER ID (verbatim CTAS) -----
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_RFM_S20_KEEPNEW';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_ECI_RFM_S20_KEEPNEW AS SELECT * FROM (SELECT h.*
      , ROW_NUMBER() OVER (PARTITION BY h.ID_MEDICAID ORDER BY h.DATE_MODIFIED DESC NULLS LAST) AS __qual_rn FROM WRK_ECI_RFM_S10_LATEST h
     WHERE CASE WHEN :1 = 'Y' THEN h.LKP_ID_MEDICAID IS NULL ELSE h.ID_MEDICAID IS NULL END) WHERE __qual_rn = 1]' USING P_TEST_LOOKUP_RESULT;
    SELECT COUNT(*) INTO l_rows FROM WRK_ECI_RFM_S20_KEEPNEW;
    sp_etl_checkpoint('ECI', P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
            'KEEP_NEW_ONLY', 'COMPLETED', 'STG_ECI_D_MEDICAID', 'Step 20 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_ECI_RFM_S20_KEEPNEW;
/

