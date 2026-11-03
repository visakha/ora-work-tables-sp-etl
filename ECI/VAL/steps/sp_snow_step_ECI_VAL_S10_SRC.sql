-- ============================================================================
-- sp_snow_step_ECI_VAL_S10_SRC  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI)
--
-- Mapping: m_Tgt_C_S_ECI_Pty_Validation, workflow wf_ECI_Stage_Load,
-- step 10. Step name (checkpoint): SRC_DELTA_PARTIES.
--
-- WHAT THIS STEP PRODUCES
--   WRK_ECI_VAL_S10_SRC: child + family delta rows, party key
--   (pkey_src_object: zero-padded id, plus 'F' for family rows) and the
--   10-character full name fed to name standardisation. This is the
--   original src + Exp_ECI_Data_Load CTEs.
--
-- DOES IT FEED THE STATUS PATH?
--   Yes, upstream: it is the first staged step; the enrichment and
--   routing steps read (transitively) from it, and the publish STATUS
--   branches (STG_ECI_PTY_INACTIVE_LOG / STG_ECI_PTY_INACTIVE_STS)
--   derive from it. It writes no target itself.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only. Step 10 reads base
--   source tables (STG_ECI_D_CHILD, STG_ECI_D_FAMILY), not work tables,
--   so its default is empty and the existence check below is skipped.
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
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
CREATE OR REPLACE FUNCTION sp_snow_step_ECI_VAL_S10_SRC (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT '') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_ECI_Pty_Validation';
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

    -- ---- Step 10: CHILD + FAMILY DELTA ROWS (verbatim from current main)
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_VAL_S10_SRC';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_ECI_VAL_S10_SRC AS WITH
    src AS (
        SELECT 'ECI_CHILD' AS SOURCE_TABLE, c.ID_CHILD AS ID, c.FIRST_NAME, c.LAST_NAME, c.MIDDLE_INITIAL,
               c.DOB, c.DATE_CREATED, c.DATE_MODIFIED, c.MODIFIED_BY, c.CREATED_BY, c.LOAD_DATE
          FROM STG_ECI_D_CHILD c
        UNION ALL
        SELECT 'ECI_FAMILY' AS SOURCE_TABLE, fam.ID_FAMILY AS ID, fam.FIRST_NAME, fam.LAST_NAME,
               fam.MIDDLE_INITIAL, fam.DOB, fam.DATE_CREATED, fam.DATE_MODIFIED, fam.MODIFIED_BY,
               fam.CREATED_BY, fam.LOAD_DATE
          FROM STG_ECI_D_FAMILY fam
    )
    SELECT s.*,
           LPAD(TO_CHAR(s.ID), 10, '0') || CASE WHEN s.SOURCE_TABLE = 'ECI_FAMILY' THEN 'F' ELSE '' END   AS pkey_src_object,
           'ECI'                                                                           AS src_system,
           SUBSTR(TRIM(NVL(CASE WHEN s.FIRST_NAME = 1 THEN 1 ELSE 0 END, '')
                       || CASE WHEN s.MIDDLE_INITIAL IS NOT NULL THEN ' ' || TRIM(s.MIDDLE_INITIAL) ELSE '' END
                       || ' ' || NVL(LTRIM(s.LAST_NAME), '')), 1, 10)                       AS full_name
      FROM src s]';
    SELECT COUNT(*) INTO l_rows FROM WRK_ECI_VAL_S10_SRC;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'SRC_DELTA_PARTIES', 'COMPLETED', NULL,
        'Step 10 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_ECI_VAL_S10_SRC;
/

