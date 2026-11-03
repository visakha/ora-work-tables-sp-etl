-- ============================================================================
-- sp_snow_step_TRS_PTYDEACT_S30_READY  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Deactivation_1, workflow wf_TRS_Stage_Load_1_Ongoing, step 30.
-- Step name (checkpoint): READY_TO_PUBLISH.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_DEACT1_S30_READY: READY -- valid members to log, new-rows-only (BR-40)
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (pipe-delimited). Default: 'WRK_TRS_DEACT1_S20_DEACTV_ID'.
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-30 SELECT verbatim. Only
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
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_PTYDEACT_S30_READY (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_DEACT1_S20_DEACTV_ID') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TRS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_Deactivation_1';
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

    -- ---- Step 30: READY_TO_PUBLISH (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_DEACT1_S30_READY';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_DEACT1_S30_READY AS SELECT * FROM (SELECT vm.INDV_ID AS INDV_ID, vm.PTY_PK AS PTY_PK, vm.SRC_TBL AS SRC_TBL,
           vm.CREATE_DATE AS CREATE_DATE, d.src_deactivation_date AS SRC_DEACTIVATION_DATE,
           :1 AS LOAD_DATE, d.inactive_ind AS INACTIVE_IND, d.delete_sw AS DELETE_SW,
           'N' AS PROCESSED_YN
      , ROW_NUMBER() OVER (PARTITION BY vm.INDV_ID ORDER BY vm.CREATE_DATE, vm.PTY_PK) AS __qual_rn FROM STG_TRS_VALID_MEMBERS vm
      JOIN WRK_TRS_DEACT1_S20_DEACTV_ID d ON d.indv_id = vm.indv_id
      LEFT JOIN (SELECT DISTINCT PTY_PK FROM STG_TRS_DEACTIVED_MEMBERS WHERE PTY_PK IS NOT NULL) dm
             ON dm.PTY_PK = vm.PTY_PK
      LEFT JOIN (SELECT DISTINCT INDV_ID FROM STG_TRS_DEACTIVED_MEMBERS) di ON di.INDV_ID = vm.INDV_ID
     WHERE dm.PTY_PK IS NULL
       AND di.INDV_ID IS NULL) WHERE __qual_rn = 1]' USING P_RUN_TS;
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_DEACT1_S30_READY;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'READY_TO_PUBLISH', 'COMPLETED', 'STG_TRS_DEACTIVED_MEMBERS', 'Step 30 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_PTYDEACT_S30_READY;
/

