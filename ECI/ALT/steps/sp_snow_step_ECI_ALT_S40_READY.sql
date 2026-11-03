-- ============================================================================
-- sp_snow_step_ECI_ALT_S40_READY  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI)
--
-- Mapping: m_Tgt_C_S_ECI_Pty_Rle_Alt_Id, workflow wf_ECI_Stage_Load,
-- step 40. Step name (checkpoint): READY_TO_PUBLISH.
--
-- WHAT THIS STEP PRODUCES
--   WRK_ECI_ALT_S40_READY: the publish-ready rows with the insert-only
--   guards (key not yet in the target, first row per key in this run;
--   for SSN exceptions, key not already logged with a NULL run date).
--   Reads ONLY step 30. This is the original final SELECT (including
--   the target-table guard joins, which still see the pre-run state
--   because nothing has been published yet).
--
-- DOES IT FEED THE SPINE?
--   Directly: all three publish branches (spine step 50 and non-spine
--   steps 60, 70) read this table and nothing else. It writes no
--   target itself.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only: WRK_ECI_ALT_S30_ROUTED
--   by default. Target guard tables read in the guard joins
--   (C_S_ECI_PTY_RLE_ALT_ID, EXC_STG_BAD_REC_MEMB) are NOT work-table
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
--   The CTAS below is the current step-40 SELECT verbatim. Only
--   substitutions: :l_run_ts -> :P_RUN_TS, :c_mapping -> the local
--   constant below (same value). No business expression, filter,
--   guard or column list was changed.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   with the same STEP_NAME, TARGET_TABLE, and message ('Step 40 complete.') as the current step-40 checkpoint (v2 10-argument form; the v1 purpose text 'Published in step 50.' is dropped -- see ALT_MANIFEST.md).
--   P_JOB_RUN_ID is present in every new proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_ECI_ALT_S40_READY (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_ALT_S30_ROUTED') RETURN NUMBER AUTHID CURRENT_USER AS
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

    -- ---- Step 40: READY -- guards (verbatim from current main)
    -- Purpose: the publish-ready rows with the insert-only guards
    -- (key not yet in the target, first row per key in this run; for
    -- SSN exceptions, key not already logged with a NULL run date).
    -- Reads ONLY step 30. This is the original final SELECT (including
    -- the target-table guard joins, which still see the pre-run state
    -- because nothing has been published yet).
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_ALT_S40_READY';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_ECI_ALT_S40_READY AS SELECT r.*,
           TO_CHAR(r.ID) || '|' || r.ALT_ID_TP                    AS src_rowid,
           1 /* TIMELINE: VERSION_SEQ */                             AS version_seq,
           'Issued'                                                  AS sts_cd,
           1                                                         AS hub_state_ind,
           NVL(r.DATE_MODIFIED, r.DATE_CREATED)                      AS src_last_upd_dt,
           'ECI'                                                     AS src_sys,
           :1                                                 AS run_ts,
           :2                                                AS mapping_name,
           'ALT_ID_Type_SSN'                                         AS attr_ssn,
           'ALT_ID_TP_MedicaidId'                                    AS attr_medicaid,
           CASE WHEN (ROW_NUMBER() OVER (PARTITION BY r.grp_valid, r.PKEY_SRC_OBJECT ORDER BY r.DATE_MODIFIED DESC, r.ID) = 1
            AND xa.PKEY_SRC_OBJECT IS NULL) THEN 1 ELSE 0 END AS uq_alt_id,
           CASE WHEN (ROW_NUMBER() OVER (PARTITION BY r.grp_ssn_exc, r.PKEY_SRC_OBJECT, r.PTY_REL_FK, r.ssn_lkp_type,
                                            r.ssn_lkp_code ORDER BY r.ID) = 1
            AND xe.SRC_SYS_ID_1 IS NULL) THEN 1 ELSE 0 END AS uq_ssn_exc,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.grp_mcd_exc, r.PKEY_SRC_OBJECT, r.PTY_REL_FK,
                                           r.medicaid_exception_type, r.medicaid_exception_code
                                  ORDER BY r.ID) = 1 THEN 1 ELSE 0 END AS uq_mcd_exc
      FROM WRK_ECI_ALT_S30_ROUTED r
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_ECI_PTY_RLE_ALT_ID WHERE VERSION_SEQ = 1) xa
             ON xa.PKEY_SRC_OBJECT = r.PKEY_SRC_OBJECT
      LEFT JOIN (SELECT DISTINCT SRC_SYS_ID_1, SRC_SYS_ID_2, NVL(EXCEPTION_TYPE, '~') AS EXC_TYPE,
                        NVL(EXCEPTION_CODE, '~') AS EXC_CODE
                   FROM EXC_STG_BAD_REC_MEMB
                  WHERE SRC_SYS = 'ECI' AND RUN_DATE IS NULL AND SRC_SYS_ID_3 IS NULL) xe
             ON r.grp_ssn_exc = 1 AND xe.SRC_SYS_ID_1 = r.PKEY_SRC_OBJECT = 1 AND xe.SRC_SYS_ID_2 = r.PTY_REL_FK = 1 AND xe.EXC_TYPE = NVL(r.ssn_lkp_type, '~') AND xe.EXC_CODE = NVL(r.ssn_lkp_code, '~')]' USING P_RUN_TS, c_mapping;
    SELECT COUNT(*) INTO l_rows FROM WRK_ECI_ALT_S40_READY;
    sp_etl_checkpoint(c_source,
        P_JOB_RUN_ID,
        c_workflow,
        c_mapping,
        'WORKING',
        'READY_TO_PUBLISH',
        'COMPLETED',
        'C_S_ECI_PTY_RLE_ALT_ID, EXC_STG_BAD_REC_MEMB',
        'Step 40 complete.',
        NULL);
    RETURN l_rows;
END sp_snow_step_ECI_ALT_S40_READY;
/

