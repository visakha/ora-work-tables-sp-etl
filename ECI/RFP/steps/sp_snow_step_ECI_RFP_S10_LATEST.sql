-- ============================================================================
-- sp_snow_step_ECI_RFP_S10_LATEST
--   Step 10 of m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn
--   (ECI, workflow wf_ECI_Stage_Load; prefix ECI_RFP, short RFP).
--
-- WHAT THIS STEP PRODUCES
--   WRK_ECI_RFP_S10_LATEST (TRANSIENT): the latest history row per phone
--   record of reactivated families. It feeds step 20 (the keep-new
--   filter), which feeds the reactivation status/dimension write in
--   step 30 (STG_ECI_D_FAMILY_PHONE). This step writes no final target.
--
-- BUSINESS SQL
--   The CTAS below is VERBATIM from the current main procedure
--   sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn, step 10.
--   No business expression, filter, guard, or column list was changed.
--   The original step had no :l_run_ts reference, so there is no run-ts
--   substitution to make here; P_RUN_TS is accepted for signature
--   uniformity and is otherwise unused by this step's SQL. The mapping
--   name is a local DECLARE constant with the same value the driver
--   uses (:c_mapping in the original).
--
-- P_INPUT_TABLES — DEPENDENCY DECLARATION + RUNTIME CHECK, NOT DYNAMIC SQL
--   Snowflake cannot parameterise table names in static SQL, so the
--   CTAS below still reads its fixed table names (STG_ECI_H_FAMILY_PHONE
--   and V_ECI_ETL_LU_REACTIVATED_ID — base source tables, not work
--   tables). P_INPUT_TABLES therefore lists WORK-TABLE inputs only;
--   for this step that list is empty (default ''), so the existence
--   check is skipped. When a caller passes a non-empty list, each
--   pipe-delimited name is checked against INFORMATION_SCHEMA.TABLES
--   in CURRENT_SCHEMA() (the install schema, as for every unqualified
--   name in the original code); the first missing name surfaces a
--   native object-not-exists error via EXECUTE IMMEDIATE (see below).
--   No CURSOR is used: the missing-name lookup is a single aggregate
--   query (MAX over the split list), which always returns one row.
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
-- CHECKPOINT / RETURN / ERRORS
--   This step writes its own checkpoint with the SAME STEP_NAME and
--   message as the current main's step 10 checkpoint (STEP_NAME
--   LATEST_HISTORY_ROWS, message 'Step 10 complete.'), in the new
--   10-argument form (no STEP_NO, row-count, or work-table arguments),
--   then RETURNs the row
--   count as NUMBER. It has NO exception block (errors propagate to
--   the driver handler), NO transaction control, and NO target writes.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_ECI_RFP_S10_LATEST (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT '') RETURN NUMBER AUTHID CURRENT_USER AS
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

    -- ---- Step 10: LATEST HISTORY ROWS (CTAS verbatim from current main) --
    -- Purpose: the latest-load history row of each phone record
    -- belonging to a reactivated family. This is the history-to-latest
    -- join of the original INSERT (the source filter).
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_RFP_S10_LATEST';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_ECI_RFP_S10_LATEST AS SELECT h.*
      FROM STG_ECI_H_FAMILY_PHONE h
     INNER JOIN (SELECT ID_FAMILY_PHONE, MAX(LOAD_DATE) AS MAX_LOAD_DATE
                   FROM STG_ECI_H_FAMILY_PHONE
                  WHERE ID_FAMILY IN (SELECT ID FROM V_ECI_ETL_LU_REACTIVATED_ID WHERE ID_TYPE = 'ID_FAMILY')
                  GROUP BY ID_FAMILY_PHONE) m
             ON m.ID_FAMILY_PHONE = h.ID_FAMILY_PHONE = 1 AND m.MAX_LOAD_DATE = h.LOAD_DATE]';
    SELECT COUNT(*) INTO l_rows FROM WRK_ECI_RFP_S10_LATEST;
    sp_etl_checkpoint('ECI', P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'LATEST_HISTORY_ROWS', 'COMPLETED', NULL, 'Step 10 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_ECI_RFP_S10_LATEST;
/

