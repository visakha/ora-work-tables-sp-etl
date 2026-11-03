-- ============================================================================
-- sp_snow_step_WIC_PHN_S10_SRC  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (WIC)
--
-- Mapping: m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr, workflow wf_WIC_Stage_Load, step 10.
-- Step name (checkpoint): SRC.
--
-- WHAT THIS STEP PRODUCES
--   WRK_WIC_PHN_S10_SRC: Active source rows only (deactivation-status filter) plus party-role, phone and e-mail keys, standardised phone, and the e-mail validation object (NULL when e-mail is null). Only step that reads V_WIC_ETL_SRC.
--
-- DOES IT FEED THE SPINE?
--   Indirectly: it is a staged step; every later step reads (transitively) from it, and the publish branches read the final step, which derives from it. It writes no target itself.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only. Default: '' (empty: this step reads base tables, not work tables, so the existence check below is skipped). Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT dynamic SQL: the CTAS below still names its sources literally, as in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-10 SELECT verbatim. Only substitution: :l_run_ts -> :P_RUN_TS (not used by this step), :c_mapping -> the local constant below (used by the checkpoint). Original-parameter refs: none. No business expression, filter, guard or column list was changed.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no transactions, no target writes. This proc writes its own checkpoint in the v2 10-argument form (STEP_NAME, STEP_STATUS, TARGET_TABLE, MESSAGE, ERROR_MESSAGE; STEP_NO, row count and work-table arguments dropped per the new signature). P_JOB_RUN_ID is present in every new proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_WIC_PHN_S10_SRC (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT '') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'WIC';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_WIC_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr';
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

    -- ---- Step 10: SRC (verbatim from current main)
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_WIC_PHN_S10_SRC';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_WIC_PHN_S10_SRC AS SELECT v.SOURCE_TABLE, v.ID, v.PTY_SRC_KEY, v.DATEKEY, v.FID, v.PHONE, v.EMAIL,
           NVL(CASE WHEN v.PTY_SRC_KEY = 1 THEN 1 ELSE 0 END, '') || '|Member'                                            AS pty_rle_fk,
           NVL(CASE WHEN v.PTY_SRC_KEY = 1 THEN 1 ELSE 0 END, '') || '|Member|Telephone|001|' || NVL(TO_CHAR(v.FID), '') || '|'
           || NVL(TRIM(v.PHONE), '')                                                      AS phn_pkey,
           NVL(CASE WHEN v.PTY_SRC_KEY = 1 THEN 1 ELSE 0 END, '') || '|Member|001|' || NVL(TO_CHAR(v.FID), '') || '|' || NVL(CASE WHEN v.EMAIL = 1 THEN 1 ELSE 0 END, '')
                                                                                          AS eaddr_pkey,
           fn_snow_helper23_common(v.PHONE)                                               AS std_phone,
           CASE WHEN v.EMAIL IS NOT NULL THEN fn_snow_helper22_common(v.EMAIL) ELSE NULL END               AS em
      FROM V_WIC_ETL_SRC v
     WHERE NOT EXISTS (SELECT 1 FROM STG_WIC_PTY_INACTIVE_STS i
                        WHERE i.SRC_KEY = v.PTY_SRC_KEY = 1 AND i.ROWID_SYSTEM = 'WIC'
                          AND i.DEACTIVATION_STS IS NOT NULL)]';
    SELECT COUNT(*) INTO l_rows FROM WRK_WIC_PHN_S10_SRC;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'SRC', 'COMPLETED', NULL, 'Step 10 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_WIC_PHN_S10_SRC;
/

