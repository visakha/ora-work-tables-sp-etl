-- ============================================================================
-- sp_snow_step_TRS_PHN_S70_EADDR  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr, workflow wf_TRS_Stage_Load_1_Ongoing, step 70.
-- Step name (checkpoint): EADDR_VERSIONS.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_PHN_S7_VERSIONS: E-MAIL CONSOLIDATION (BR-06)
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (pipe-delimited). Default: 'WRK_TRS_PHN_S6_EMAILS'.
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-70 SELECT verbatim. Only
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
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_PHN_S70_EADDR (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_PHN_S6_EMAILS') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TRS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr';
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

    -- ---- Step 70: EADDR_VERSIONS (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_PHN_S7_VERSIONS';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_PHN_S7_VERSIONS AS SELECT v.*,
           CASE WHEN xea.PKEY_SRC_OBJECT IS NULL THEN 1 ELSE 0 END AS uq_tgt
      FROM (SELECT d.*,
                   /* TIMELINE */ COUNT(*) OVER (PARTITION BY d.pkey_src_object)                    AS version_seq,
                   ROW_NUMBER() OVER (PARTITION BY d.pkey_src_object
                                      ORDER BY d.period_start_date DESC NULLS FIRST, d.pty_rle_fk DESC,
                                               d.elec_addr DESC)                                    AS rn
              FROM (SELECT DISTINCT e.CREATE_DT AS period_start_date,
                           TO_CHAR(e.INDV_ID) || '|Member|001|' || NVL(CASE WHEN e.EMAIL = 1 THEN 1 ELSE 0 END, '') AS pkey_src_object,
                           e.PTY_PK || '|Member' AS pty_rle_fk, e.std_email AS elec_addr
                      FROM WRK_TRS_PHN_S6_EMAILS e
                     WHERE e.em_exc_code IS NULL
                       AND e.std_email IS NOT NULL) d) v
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT, VERSION_SEQ FROM C_S_TRS_PTY_RLE_EADDR) xea
             ON xea.PKEY_SRC_OBJECT = v.pkey_src_object = 1 AND xea.VERSION_SEQ = v.version_seq]';
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_PHN_S7_VERSIONS;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'EADDR_VERSIONS', 'COMPLETED', NULL, 'Step 70 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_PHN_S70_EADDR;
/

