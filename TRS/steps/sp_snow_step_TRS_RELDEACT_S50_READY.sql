-- ============================================================================
-- sp_snow_step_TRS_RELDEACT_S50_READY  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1, workflow wf_TRS_Stage_Load_1_Ongoing, step 50.
-- Step name (checkpoint): READY_TO_PUBLISH.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_RELDEACT_S50_READY: READY -- not already logged AND present in the MDM
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (pipe-delimited). Default: 'WRK_TRS_RELDEACT_S30_KEYED|WRK_TRS_RELDEACT_S40_XREF'.
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-50 SELECT verbatim. Only
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
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_RELDEACT_S50_READY (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_RELDEACT_S30_KEYED|WRK_TRS_RELDEACT_S40_XREF') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TRS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1';
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

    -- ---- Step 50: READY_TO_PUBLISH (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_RELDEACT_S50_READY';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_RELDEACT_S50_READY AS SELECT k.INDV_ID AS INDV_ID, k.REF_INDV_ID AS REF_INDV_ID,
           k.pty_rle_fk_1 AS PTY_RLE_FK_1, k.pty_rle_fk_2 AS PTY_RLE_FK_2,
           k.RELATIONSHIP_TYPE_CD AS REL_TYPE_CODE, x.SRC_PKEY_CT AS SRC_PKEY_CT,
           :1 AS LOAD_DATE, k.pkey_src_object AS PKEY_SRC_OBJECT,
           x.ROWID_OBJECT AS ROWID_OBJECT, x.MASTER_RECORD_YN AS MASTER_RECORD_YN,
           TRIM(x.MERGE_YN) AS MERGED_YN, k.SRC_SYS AS ROWID_SYSTEM, x.MIN_ROWID_XREF AS ROWID_XREF
      FROM WRK_TRS_RELDEACT_S30_KEYED k
      LEFT JOIN WRK_TRS_RELDEACT_S40_XREF x ON x.PKEY_SRC_OBJECT = k.pkey_src_object
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM STG_TRS_DEACTIVATED_RELATIONSHIPS
                  WHERE PROCESSED_YN = 'N' AND PKEY_SRC_OBJECT IS NOT NULL) d
             ON d.PKEY_SRC_OBJECT = k.pkey_src_object
     WHERE d.PKEY_SRC_OBJECT IS NULL
       AND x.MIN_ROWID_XREF IS NOT NULL]' USING P_RUN_TS;
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_RELDEACT_S50_READY;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'READY_TO_PUBLISH', 'COMPLETED', 'STG_TRS_DEACTIVATED_RELATIONSHIPS', 'Step 50 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_RELDEACT_S50_READY;
/

