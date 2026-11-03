-- ============================================================================
-- sp_snow_step_TRS_REL2_S20_KEYED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP, workflow wf_TRS_Stage_Load_1_Ongoing, step 20.
-- Step name (checkpoint): KEYED.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_REL2_S2_KEYED: KEYING -- resolve provider, build keys (BR-37)
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (pipe-delimited). Default: 'WRK_TRS_REL2_S1_SRC'.
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-20 SELECT verbatim. Only
--   substitution: :l_run_ts -> :P_RUN_TS (where used); :c_mapping is
--   the local constant below. No business expression, filter, guard
--   or column list was changed. This step uses original parameters:
--   P_PCP_REL_TP.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   in the 10-argument form. P_JOB_RUN_ID is present in every new proc
--   in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_REL2_S20_KEYED (P_PCP_REL_TP IN VARCHAR2 DEFAULT '100', P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_REL2_S1_SRC') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TRS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP';
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

    -- ---- Step 20: KEYED (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_REL2_S2_KEYED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'{CREATE TABLE WRK_TRS_REL2_S2_KEYED AS WITH
    tpi_src_key AS (
        SELECT * FROM (SELECT bo.alt_id_val, xr.pkey_src_object
          , ROW_NUMBER() OVER (PARTITION BY bo.alt_id_val ORDER BY xr.src_last_upd_dt DESC) AS __qual_rn FROM C_B_PTY_RLE_ALT_ID bo
         INNER JOIN C_B_PTY_RLE_ALT_ID_XREF xr ON bo.rowid_object = xr.rowid_object
         WHERE bo.alt_id_tp = '006' AND TRIM(xr.rowid_system) = 'C21' AND xr.hub_state_ind = 1) WHERE __qual_rn = 1
    ),
    keyed AS (
        SELECT s.*,
               CASE WHEN s.PTY_PK IS NULL THEN NULL ELSE TRIM(s.PTY_PK) || '|Member' END                        AS pty_rle_fk_1,
               SUBSTR(TRIM(t.pkey_src_object), 1, REGEXP_INSTR(TRIM(t.pkey_src_object), '[|]', 1, 2) - 1)
                                                                                              AS pty_rle_fk_2,
               CASE WHEN CONTAINS(TRIM(t.pkey_src_object), '|HCO') = 1 THEN 'Member PCO' ELSE 'Member PCP' END     AS rel_type_code
          FROM WRK_TRS_REL2_S1_SRC s
          LEFT JOIN tpi_src_key t ON t.alt_id_val = s.PROVIDER_NUM
    )
    SELECT k.*,
           NVL(k.pty_rle_fk_1, '') || '|' || NVL(k.pty_rle_fk_2, '') || '|' || :1 AS pkey_src_object,
           /* VALIDATION */ NVL(CASE WHEN k.BEGIN_DT > k.END_DT THEN 1 ELSE 0 END, 0)                              AS dates_reversed,
           /* VALIDATION */ (k.pty_rle_fk_1 IS NOT NULL AND k.pty_rle_fk_2 IS NOT NULL
                             AND NVL(CASE WHEN k.BEGIN_DT <= k.END_DT = 1 OR k.END_DT IS NULL THEN 1 ELSE 0 END, 0) = 1)   AS is_valid
      FROM keyed k}' USING P_PCP_REL_TP;
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_REL2_S2_KEYED;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'KEYED', 'COMPLETED', NULL, 'Step 20 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_REL2_S20_KEYED;
/

