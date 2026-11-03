-- ============================================================================
-- sp_snow_step_ECI_ALT_S30_ROUTED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI)
--
-- Mapping: m_Tgt_C_S_ECI_Pty_Rle_Alt_Id, workflow wf_ECI_Stage_Load,
-- step 30. Step name (checkpoint): VALIDATED_ROUTED.
--
-- WHAT THIS STEP PRODUCES
--   WRK_ECI_ALT_S30_ROUTED: alternate ids with SSN / Medicaid
--   validation applied and sorted into the valid group, the
--   SSN-exception group and the Medicaid-exception group, with
--   exception descriptions resolved. Reads ONLY step 20. This is the
--   original dq + routed CTEs.
--
-- DOES IT FEED THE SPINE?
--   Indirectly: it is the third staged step; the ready step and the
--   publish spine branch both read (transitively) from it. It writes
--   no target itself.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only: WRK_ECI_ALT_S20_ACTIVE
--   by default. Helper-function catalogue reads are NOT work-table
--   dependencies and are not listed. Snowflake cannot parameterise
--   table names in static SQL, so P_INPUT_TABLES is a dependency
--   declaration + runtime check, NOT dynamic SQL: the CTAS below still
--   names its sources literally, as in the current main procedure.
--
-- INPUT EXISTENCE CHECK
--   Skipped when P_INPUT_TABLES is NULL/empty. Otherwise the value is
--   split on '|', each name is trimmed and upper-cased (Snowflake
--   stores unquoted identifiers uppercase), and checked against
--   INFORMATION_SCHEMA.TABLES in the current schema. The first missing
--   table (alphabetically) surfaces via EXECUTE IMMEDIATE
--   'SELECT 1 FROM <missing table>', which raises the native
--   object-not-exists error naming that table; the step is identified
--   by this procedure's name. RAISE is NOT used for this: Snowflake's
--   RAISE takes only a declared exception name, whose message is fixed
--   at declaration and so cannot name a runtime-discovered table.
--   No CURSOR is used: the check is a single set-based query.
--
-- BUSINESS SQL
--   The CTAS below is the current step-30 SELECT verbatim. Only
--   substitutions: :l_run_ts -> :P_RUN_TS (not used by this step),
--   :c_mapping -> the local constant below (used by the checkpoint).
--   No business expression, filter, guard or column list was changed.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   with the same STEP_NAME and message as the current step-30 checkpoint (v2 10-argument form; STEP_NO, row count, and work-table arguments dropped).
--   P_JOB_RUN_ID is present in every new proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_ECI_ALT_S30_ROUTED (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_ALT_S20_ACTIVE') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_ECI_Pty_Rle_Alt_Id';
    l_rows NUMBER DEFAULT 0;
    l_missing VARCHAR2(4000) DEFAULT NULL;
    l_sql VARCHAR2(4000) DEFAULT NULL;
    l_probe_dummy NUMBER;
SELECT MIN(s.tbl) INTO l_missing FROM (SELECT REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL) AS raw, UPPER(TRIM(REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL))) AS tbl FROM DUAL CONNECT BY REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL) IS NOT NULL) s WHERE s.tbl <> '' AND NOT EXISTS (SELECT 1 FROM ALL_TABLES t WHERE t.OWNER = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AND t.TABLE_NAME = s.tbl);
        IF (l_missing IS NOT NULL) THEN
            l_sql := 'SELECT COUNT(*) FROM ' || l_missing;
            EXECUTE IMMEDIATE l_sql INTO l_probe_dummy;
        END IF;
    END IF;

    -- ---- Step 30: VALIDATION + ROUTING (verbatim from current main)
    -- Purpose: validate SSNs and Medicaid ids and sort rows into the
    -- valid group, the SSN-exception group and the Medicaid-exception
    -- group, with exception descriptions resolved. Reads ONLY step 20.
    -- This is the original dq + routed CTEs.
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_ALT_S30_ROUTED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_ECI_ALT_S30_ROUTED AS WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    dq AS (
        SELECT a.*,
               CASE WHEN a.ALT_ID_TP = '004' AND fn_snow_helper26_common(a.ALT_ID_VAL)CAST(.ssn_status AS VARCHAR2(4000)) = 'Invalid' THEN 'Invalid_SSN' ELSE NULL END                                                    AS ssn_exception_code,
               CASE WHEN a.ALT_ID_TP = '002' THEN fn_snow_helper27_common(a.ALT_ID_VAL)CAST(.exception_code AS VARCHAR2(4000)) ELSE NULL END
                                                                                           AS medicaid_exception_code
          FROM WRK_ECI_ALT_S20_ACTIVE a
    )
    SELECT d.*,
           xs.EXCEPTION_CODE AS ssn_lkp_code, xs.EXCEPTION_DESC AS ssn_lkp_desc, xs.EXCEPTION_TYPE AS ssn_lkp_type,
           xm.EXCEPTION_TYPE AS medicaid_exception_type, xm.EXCEPTION_DESC AS medicaid_exception_desc,
           CASE WHEN ((d.ALT_ID_TP = '004' AND d.ssn_exception_code IS NULL)
            OR d.ALT_ID_TP IN ('018', '019')
            OR (d.ALT_ID_TP = '002' AND d.medicaid_exception_code IS NULL)) THEN 1 ELSE 0 END AS grp_valid,
           CASE WHEN (d.ALT_ID_TP = '004' AND d.ssn_exception_code IS NOT NULL) THEN 1 ELSE 0 END AS grp_ssn_exc,
           CASE WHEN (d.ALT_ID_TP = '002' AND d.medicaid_exception_code IS NOT NULL) THEN 1 ELSE 0 END AS grp_mcd_exc
      FROM dq d
      LEFT JOIN lkp_exc xs ON xs.EXCEPTION_CODE = d.ssn_exception_code
      LEFT JOIN lkp_exc xm ON xm.EXCEPTION_CODE = d.medicaid_exception_code]';
    SELECT COUNT(*) INTO l_rows FROM WRK_ECI_ALT_S30_ROUTED;
    sp_etl_checkpoint(c_source,
        P_JOB_RUN_ID,
        c_workflow,
        c_mapping,
        'WORKING',
        'VALIDATED_ROUTED',
        'COMPLETED',
        NULL,
        'Step 30 complete.',
        NULL);
    RETURN l_rows;
END sp_snow_step_ECI_ALT_S30_ROUTED;
/

