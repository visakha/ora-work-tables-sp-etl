-- ============================================================================
-- sp_snow_step_ECI_RFP_S20_KEEPNEW
--   Step 20 of m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn
--   (ECI, workflow wf_ECI_Stage_Load; prefix ECI_RFP, short RFP).
--
-- WHAT THIS STEP PRODUCES
--   WRK_ECI_RFP_S20_KEEPNEW (TRANSIENT): step 10 rows not already in
--   the delta table. It feeds ONLY the step 30 publish (the
--   reactivation status/dimension write to STG_ECI_D_FAMILY_PHONE).
--   This step writes no final target.
--
-- BUSINESS SQL
--   The CTAS below is VERBATIM from the current main procedure
--   sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn, step 20.
--   No business expression, filter, guard, or column list was changed.
--   The original step had no :l_run_ts reference, so there is no run-ts
--   substitution to make here; P_RUN_TS is accepted for signature
--   uniformity and is otherwise unused by this step's SQL. The mapping
--   name is a local DECLARE constant with the same value the driver
--   uses (:c_mapping in the original).
--
-- P_INPUT_TABLES — DEPENDENCY DECLARATION + RUNTIME CHECK, NOT DYNAMIC SQL
--   Snowflake cannot parameterise table names in static SQL, so the
--   CTAS below still reads its fixed work-table name
--   (WRK_ECI_RFP_S10_LATEST). P_INPUT_TABLES is the dependency
--   declaration for that input (default 'WRK_ECI_RFP_S10_LATEST') plus
--   a runtime check: each pipe-delimited name is checked against
--   INFORMATION_SCHEMA.TABLES in CURRENT_SCHEMA() (the install schema,
--   as for every unqualified name in the original code); the first
--   missing name surfaces a native object-not-exists error via
--   EXECUTE IMMEDIATE (see below). Base source tables and target guard
--   tables are NOT work-table dependencies and are not listed here:
--   the delta-table guard in this step reads STG_ECI_D_FAMILY_PHONE
--   directly, as in the original. No CURSOR is used: the missing-name
--   lookup is a single aggregate query (MAX over the split list),
--   which always returns one row.
--
-- MISSING-TABLE ERROR MECHANISM (compile-time note)
--   RAISE in Snowflake Scripting takes a DECLARED exception name with a
--   static message, so it cannot carry a dynamically found table name.
--   This step therefore uses the sanctioned fallback: EXECUTE IMMEDIATE
--   'SELECT 1 FROM <missing table>', which fails with Snowflake's
--   native object-not-exists error naming the table. That error
--   propagates to the driver, whose handler rolls back, writes the
--   TERMINATING 999 FAILED checkpoint, calls sp_etl_job_fail, and
--   re-raises. Verify on first live compile that EXECUTE IMMEDIATE
--   with a concatenated identifier is accepted in this install.
--
-- ORDERING NOTE (preserved from the original)
--   This filter reads ONLY step 10, so it sees the delta table as it
--   was before this run's publish, exactly as in the original. That
--   holds only if step 20 runs after step 10 in the same run; see the
--   driver header on what happens when a step is skipped by config.
--
-- CHECKPOINT / RETURN / ERRORS
--   This step writes its own checkpoint with the SAME STEP_NAME,
--   TARGET_TABLE, and message as the current main's step 20 checkpoint
--   (STEP_NAME KEEP_NEW_ONLY, TARGET_TABLE STG_ECI_D_FAMILY_PHONE,
--   message 'Step 20 complete.'), in the new 10-argument form (no
--   STEP_NO, row-count, or work-table arguments), then RETURNs the row
--   count as NUMBER. It has NO
--   exception block (errors propagate to the driver handler), NO
--   transaction control, and NO target writes.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_ECI_RFP_S20_KEEPNEW (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_RFP_S10_LATEST') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn';
    l_rows NUMBER DEFAULT 0;
    l_missing VARCHAR2(4000);
    l_probe_sql VARCHAR2(4000);
    l_probe_dummy NUMBER;
SELECT MAX(s.tbl) INTO l_missing FROM (SELECT REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL) AS raw, UPPER(TRIM(REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL))) AS tbl FROM DUAL CONNECT BY REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL) IS NOT NULL) s WHERE TRIM(s.raw) <> '' AND NOT EXISTS (SELECT 1 FROM ALL_TABLES t WHERE t.OWNER = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AND t.TABLE_NAME = s.tbl);
        IF (l_missing IS NOT NULL) THEN
            l_probe_sql := 'SELECT COUNT(*) FROM ' || l_missing;
            EXECUTE IMMEDIATE l_probe_sql INTO l_probe_dummy;
        END IF;
    END IF;

    -- ---- Step 20: KEEP-NEW FILTER (CTAS verbatim from current main) -----
    -- Purpose: drop rows already in the delta table. Reads ONLY step
    -- 10, so the filter sees the delta table as it was before this
    -- run's publish, exactly as in the original. This is the original
    -- lookup plus keep-new filter.
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_RFP_S20_KEEPNEW';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_ECI_RFP_S20_KEEPNEW AS SELECT h.*
      FROM WRK_ECI_RFP_S10_LATEST h
     WHERE NOT EXISTS (SELECT 1 FROM STG_ECI_D_FAMILY_PHONE d
                        WHERE d.ID_FAMILY_PHONE = h.ID_FAMILY_PHONE)]';
    SELECT COUNT(*) INTO l_rows FROM WRK_ECI_RFP_S20_KEEPNEW;
    sp_etl_checkpoint('ECI', P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'KEEP_NEW_ONLY', 'COMPLETED', 'STG_ECI_D_FAMILY_PHONE', 'Step 20 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_ECI_RFP_S20_KEEPNEW;
/

