-- ============================================================================
-- sp_snow_step_ECI_RFM_S10_LATEST
--   Step 10 (LATEST_HISTORY_ROWS) of
--   m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid, workflow
--   wf_ECI_Stage_Load. Config-driven step-driver refactor (ECI only).
--
-- WHAT THIS STEP PRODUCES
--   WRK_ECI_RFM_S10_LATEST (TRANSIENT): the latest history row per
--   Medicaid record of a reactivated child, plus the delta-table
--   lookup key LKP_ID_MEDICAID (NULL when the id is not yet in
--   STG_ECI_D_MEDICAID). It feeds the step-20 keep-new filter, which
--   feeds the reactivation status write (step 30 publish into
--   STG_ECI_D_MEDICAID).
--
-- RE-HOUSING ONLY
--   The CTAS below is the current step-10 CTAS verbatim: same SELECT,
--   same FROM pointed at the fixed work-table names as now. No
--   business expression, filter, guard, or column list was changed.
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration plus a runtime
--   existence check, NOT dynamic SQL: the CTAS itself still names its
--   source tables literally.
--
-- INPUTS / PARAMS
--   P_JOB_RUN_ID   VARCHAR            -- run id, from the driver
--   P_RUN_TS       TIMESTAMP_NTZ      -- run timestamp, from the driver;
--                                        accepted for a uniform step
--                                        interface, but this mapping's
--                                        SQL has no run-timestamp
--                                        column, so it is unused here
--   P_INPUT_TABLES VARCHAR DEFAULT '' -- pipe-delimited WORK-TABLE
--                                        inputs for this step; empty
--                                        for step 10 (it reads only
--                                        base source / target-guard
--                                        tables, which are NOT
--                                        work-table dependencies)
--   This step's SQL does NOT use P_TEST_LOOKUP_RESULT, so that
--   original parameter is omitted from this proc's signature.
--
-- BEHAVIOUR
--   (1) Input existence check, skipped when P_INPUT_TABLES is NULL or
--       empty: every trimmed name must exist in INFORMATION_SCHEMA.TABLES
--       under CURRENT_SCHEMA(); otherwise a probe query
--       (EXECUTE IMMEDIATE 'SELECT 1 FROM <table>') surfaces the
--       native object-not-exists error naming the table and the step.
--       (Coordinator normalisation: Snowflake RAISE accepts only a
--       declared exception name, so a dynamic message is not possible.)
--   (2) The step CTAS, verbatim. (3) COUNT(*) into the return value.
--   (4) Its own checkpoint, with the same STEP_NAME and message as the current step-10 checkpoint (v2 10-argument form; STEP_NO, row count, and work-table arguments dropped).
--   (5) RETURN the row count (NUMBER).
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes, no cursors.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_ECI_RFM_S10_LATEST (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT '') RETURN NUMBER AUTHID CURRENT_USER AS
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

    -- ---- Step 10: LATEST HISTORY ROWS + LOOKUP (verbatim CTAS) ---------
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_RFM_S10_LATEST';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_ECI_RFM_S10_LATEST AS SELECT h.*, d.ID_MEDICAID AS LKP_ID_MEDICAID
      FROM STG_ECI_H_MEDICAID h
     INNER JOIN (SELECT m.ID_MEDICAID, MAX(m.LOAD_DATE) AS MAX_LOAD_DATE
                   FROM STG_ECI_H_MEDICAID m
                  INNER JOIN STG_ECI_SN_CASE c ON m.ID_CASE = c.ID_CASE
                  WHERE c.ID_CHILD IN (SELECT ID FROM V_ECI_ETL_LU_REACTIVATED_ID WHERE ID_TYPE = 'ID_CHILD')
                  GROUP BY m.ID_MEDICAID) mx
             ON mx.ID_MEDICAID = h.ID_MEDICAID = 1 AND mx.MAX_LOAD_DATE = h.LOAD_DATE
      LEFT JOIN (SELECT DISTINCT ID_MEDICAID FROM STG_ECI_D_MEDICAID) d ON d.ID_MEDICAID = h.ID_MEDICAID]';
    SELECT COUNT(*) INTO l_rows FROM WRK_ECI_RFM_S10_LATEST;
    sp_etl_checkpoint('ECI', P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
            'LATEST_HISTORY_ROWS', 'COMPLETED', NULL, 'Step 10 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_ECI_RFM_S10_LATEST;
/

