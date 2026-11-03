-- ============================================================================
-- sp_snow_step_TRS_RELDEACT_S40_XREF  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1, workflow wf_TRS_Stage_Load_1_Ongoing, step 40.
-- Step name (checkpoint): XREF_ONE.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_RELDEACT_S40_XREF: MDM CROSS-REFERENCE, ONE ROW PER SOURCE KEY
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (pipe-delimited). Default: ''.
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-40 SELECT verbatim. Only
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
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_RELDEACT_S40_XREF (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT '') RETURN NUMBER AUTHID CURRENT_USER AS
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

    -- ---- Step 40: XREF_ONE (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_RELDEACT_S40_XREF';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_RELDEACT_S40_XREF AS WITH
    xref_obj AS (
        SELECT ROWID_OBJECT, COUNT(DISTINCT PKEY_SRC_OBJECT) AS SRC_PKEY_CT, MAX(HUB_STATE_IND) AS MAX_HUB_STATE_IND
          FROM C_B_PTY_RLE_REL_XREF
         GROUP BY ROWID_OBJECT
    ),
    xref_key AS (
        SELECT PKEY_SRC_OBJECT, MIN(ROWID_XREF) AS MIN_ROWID_XREF
          FROM C_B_PTY_RLE_REL_XREF
         GROUP BY PKEY_SRC_OBJECT
    ),
    xref AS (
        SELECT DISTINCT t.ROWID_OBJECT, t.PKEY_SRC_OBJECT, t.ROWID_SYSTEM, o.SRC_PKEY_CT,
               CASE WHEN o.SRC_PKEY_CT > 1 THEN 'Y' ELSE 'N' END                          AS MERGE_YN,
               CASE WHEN t.ROWID_OBJECT = t.ORIG_ROWID_OBJECT THEN 'Y' ELSE 'N' END        AS MASTER_RECORD_YN,
               CASE WHEN o.MAX_HUB_STATE_IND = -1 THEN 'Y' ELSE 'N' END                    AS SOFT_DELETE_YN,
               k.MIN_ROWID_XREF
          FROM C_B_PTY_RLE_REL_XREF t
          JOIN xref_obj o ON o.ROWID_OBJECT = t.ROWID_OBJECT
          JOIN xref_key k ON k.PKEY_SRC_OBJECT = t.PKEY_SRC_OBJECT
    )
    SELECT * FROM (SELECT * , ROW_NUMBER() OVER (PARTITION BY PKEY_SRC_OBJECT ORDER BY ROWID_OBJECT) AS __qual_rn FROM xref) WHERE __qual_rn = 1]';
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_RELDEACT_S40_XREF;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'XREF_ONE', 'COMPLETED', NULL, 'Step 40 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_RELDEACT_S40_XREF;
/

