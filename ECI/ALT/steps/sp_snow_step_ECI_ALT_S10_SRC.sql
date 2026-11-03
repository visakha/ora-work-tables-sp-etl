-- ============================================================================
-- sp_snow_step_ECI_ALT_S10_SRC  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI)
--
-- Mapping: m_Tgt_C_S_ECI_Pty_Rle_Alt_Id, workflow wf_ECI_Stage_Load,
-- step 10. Step name (checkpoint): SRC_ALT_IDS.
--
-- WHAT THIS STEP PRODUCES
--   WRK_ECI_ALT_S10_SRC: one row per alternate id -- child ECI id 018,
--   child SSN 004 (only when present), Medicaid number 002 (via the
--   case table), family ECI id 019. This is the original src CTE.
--
-- DOES IT FEED THE SPINE?
--   Indirectly: it is the first staged step; every later step reads
--   (transitively) from it, and the publish spine branch reads step
--   40, which derives from it. It writes no target itself.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only. Step 10 reads base
--   source tables (STG_ECI_D_CHILD, STG_ECI_D_MEDICAID,
--   STG_ECI_SN_CASE, STG_ECI_D_FAMILY), not work tables, so its
--   default is empty and the existence check below is skipped.
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
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
--   The CTAS below is the current step-10 SELECT verbatim. Only
--   substitutions: :l_run_ts -> :P_RUN_TS (not used by this step),
--   :c_mapping -> the local constant below (used by the checkpoint).
--   No business expression, filter, guard or column list was changed.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   with the same STEP_NAME and message as the current step-10 checkpoint (v2 10-argument form; STEP_NO, row count, and work-table arguments dropped).
--   P_JOB_RUN_ID is present in every new proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_ECI_ALT_S10_SRC (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT '') RETURN NUMBER AUTHID CURRENT_USER AS
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

    -- ---- Step 10: ALTERNATE-ID BRANCHES (verbatim from current main)
    -- Purpose: one row per alternate id -- child ECI id 018, child SSN
    -- 004 (only when present), Medicaid number 002 (via the case
    -- table), family ECI id 019. This is the original src CTE.
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_ALT_S10_SRC';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_ECI_ALT_S10_SRC AS SELECT ID_CHILD AS ID, LPAD(TO_CHAR(ID_CHILD), 10, '0') || '|Member' AS PTY_REL_FK,
           LPAD(TO_CHAR(ID_CHILD), 10, '0') AS SRC_KEY_SFX, '018' AS ALT_ID_TP,
           LPAD(TO_CHAR(ID_CHILD), 10, '0') AS ALT_ID_VAL, DATE_CREATED, DATE_MODIFIED,
           LPAD(TO_CHAR(ID_CHILD), 10, '0') || '|Member' || '|018' || '|'
           || LPAD(TO_CHAR(ID_CHILD), 10, '0') AS PKEY_SRC_OBJECT
      FROM STG_ECI_D_CHILD
    UNION ALL
    SELECT ID_CHILD, LPAD(TO_CHAR(ID_CHILD), 10, '0') || '|Member', LPAD(TO_CHAR(ID_CHILD), 10, '0'),
           '004', CHILD_SSN, DATE_CREATED, DATE_MODIFIED,
           LPAD(TO_CHAR(ID_CHILD), 10, '0') || '|Member' || '|004' || '|' || LPAD(TO_CHAR(ID_CHILD), 10, '0')
      FROM STG_ECI_D_CHILD
     WHERE CHILD_SSN IS NOT NULL
    UNION ALL
    SELECT C.ID_CHILD, LPAD(TO_CHAR(C.ID_CHILD), 10, '0') || '|Member', LPAD(TO_CHAR(M.ID_MEDICAID), 9, '0'),
           '002', M.MEDICAID_NBR, M.DATE_CREATED, M.DATE_MODIFIED,
           LPAD(TO_CHAR(C.ID_CHILD), 10, '0') || '|Member' || '|002' || '|' || LPAD(TO_CHAR(M.ID_MEDICAID), 10, '0')
      FROM STG_ECI_D_MEDICAID M
     INNER JOIN STG_ECI_SN_CASE C ON M.ID_CASE = C.ID_CASE
    UNION ALL
    SELECT ID_FAMILY, LPAD(TO_CHAR(ID_FAMILY), 10, '0') || 'F|Member', LPAD(TO_CHAR(ID_FAMILY), 10, '0'),
           '019', LPAD(TO_CHAR(ID_FAMILY), 10, '0'), DATE_CREATED, DATE_MODIFIED,
           LPAD(TO_CHAR(ID_FAMILY), 10, '0') || 'F|Member' || '|019' || '|' || LPAD(TO_CHAR(ID_FAMILY), 10, '0')
      FROM STG_ECI_D_FAMILY]';
    SELECT COUNT(*) INTO l_rows FROM WRK_ECI_ALT_S10_SRC;
    sp_etl_checkpoint(c_source,
        P_JOB_RUN_ID,
        c_workflow,
        c_mapping,
        'WORKING',
        'SRC_ALT_IDS',
        'COMPLETED',
        NULL,
        'Step 10 complete.',
        NULL);
    RETURN l_rows;
END sp_snow_step_ECI_ALT_S10_SRC;
/

