-- ============================================================================
-- sp_snow_step_ECI_RFA_S10_LATEST  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI)
--
-- Mapping: m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr, workflow
-- wf_ECI_Stage_Load, step 10.
-- Step name (checkpoint): LATEST_HISTORY_ROWS.
--
-- WHAT THIS STEP PRODUCES
--   WRK_ECI_RFA_S10_LATEST: the latest history row per address of
--   reactivated families. This is the history-to-latest join of the
--   original INSERT (the source filter).
--
-- DOES IT FEED THE REACTIVATION STATUS WRITE?
--   Yes, indirectly: step 20 (KEEP_NEW_ONLY) reads only this table,
--   and step 30 publishes step 20 into STG_ECI_D_FAMILY_ADDRESS --
--   the reactivation delta/status write that causes the downstream
--   address mapping to re-send these addresses to the MDM. This step
--   writes no target itself.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only. Step 10 reads base
--   source tables (STG_ECI_H_FAMILY_ADDRESS and the reactivated-id
--   view V_ECI_ETL_LU_REACTIVATED_ID), not work tables, so its
--   default is empty and the existence check below is skipped.
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-10 SELECT verbatim. Only
--   substitutions: :l_run_ts -> :P_RUN_TS (not used by this step --
--   the original step has no run-timestamp column),
--   :c_mapping -> the local constant below (used by the checkpoint).
--   No business expression, filter, guard or column list was changed.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   with the same STEP_NAME and message as the current step-10 checkpoint (v2 10-argument form; STEP_NO, row count, and work-table arguments dropped).
--   P_JOB_RUN_ID is present in every new proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_ECI_RFA_S10_LATEST (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT '') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr';
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

    -- ---- Step 10: LATEST HISTORY ROWS (verbatim from current main)
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_RFA_S10_LATEST';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_ECI_RFA_S10_LATEST AS SELECT h.*
      FROM STG_ECI_H_FAMILY_ADDRESS h
     INNER JOIN (SELECT ID_FAMILY_ADDRESS, MAX(LOAD_DATE) AS MAX_LOAD_DATE
                   FROM STG_ECI_H_FAMILY_ADDRESS
                  WHERE ID_FAMILY IN (SELECT ID FROM V_ECI_ETL_LU_REACTIVATED_ID WHERE ID_TYPE = 'ID_FAMILY')
                  GROUP BY ID_FAMILY_ADDRESS) m
             ON m.ID_FAMILY_ADDRESS = h.ID_FAMILY_ADDRESS = 1 AND m.MAX_LOAD_DATE = h.LOAD_DATE]';
    SELECT COUNT(*) INTO l_rows FROM WRK_ECI_RFA_S10_LATEST;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'LATEST_HISTORY_ROWS', 'COMPLETED', NULL, 'Step 10 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_ECI_RFA_S10_LATEST;
/

