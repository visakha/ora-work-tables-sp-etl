-- ============================================================================
-- sp_snow_step_ECI_PHN_S50_READY  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI ONLY)
--
-- Mapping: m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr, workflow wf_ECI_Stage_Load.
-- Step 50: READY_TO_PUBLISH -- Publish-ready rows with insert-only guards.
-- Produces: TRANSIENT TABLE WRK_ECI_PHN_S50_READY.
-- Feeds: SPINE-FEEDING: the publish-ready table read directly by all four publish branches (spine 60/80 and non-spine 70/90).
--
-- WHAT THIS PROCEDURE IS
--   One step of the original mapping, re-housed unchanged. The CTAS below
--   is the original step's SELECT verbatim, with its FROM clause pointed
--   at the fixed work-table names exactly as in the original main
--   procedure. No business expression, filter, guard or column list was
--   changed. Allowed substitutions only: :l_run_ts -> :P_RUN_TS (step 50),
--   :l_job_run_id -> :P_JOB_RUN_ID in the checkpoint call.
--
-- P_INPUT_TABLES IS A DEPENDENCY DECLARATION + RUNTIME CHECK, NOT DYNAMIC SQL
--   Snowflake cannot parameterise table names in static SQL, so the CTAS
--   still names its input work table(s) literally. P_INPUT_TABLES is the
--   config-supplied list (pipe-delimited) of work-table inputs for this
--   step; this procedure only CHECKS that each named table exists in the
--   current schema (INFORMATION_SCHEMA.TABLES) before running the CTAS.
--   It never builds SQL from P_INPUT_TABLES, except for the single
--   missing-table error probe documented below.
--
-- INPUT EXISTENCE CHECK
--   Skipped when P_INPUT_TABLES is NULL or empty (step 10's default).
--   Otherwise the first missing name is found with a set-based query
--   (MIN over SPLIT_TO_TABLE parts not present in INFORMATION_SCHEMA).
--   On a missing table this procedure raises the native object-not-exists
--   error via EXECUTE IMMEDIATE 'SELECT 1 FROM <missing table>' -- see
--   PHN_MANIFEST.md for why the RAISE form was NOT used (documented
--   Snowflake RAISE syntax takes an exception name only, so a dynamic
--   table name cannot be embedded in a RAISE message; the native error
--   names the missing table). The error propagates to the driver, whose
--   exception handler writes the TERMINATING 999 FAILED row.
--
-- CHECKPOINT / RETURN / NO SIDE EFFECTS
--   Writes exactly its own checkpoint in the v2 10-argument form
--   (STEP_NAME 'READY_TO_PUBLISH', STEP_STATUS 'COMPLETED', TARGET_TABLE
--   'C_S_ECI_PTY_RLE_PHN, C_S_ECI_PTY_RLE_EADDR, EXC_STG_BAD_REC_MEMB',
--   MESSAGE 'Step 50 complete.', ERROR_MESSAGE NULL). STEP_NO, row count,
--   work-table name/action/purpose are no longer checkpoint arguments.
--   Returns the work-table row count (NUMBER). No exception block (errors
--   propagate to the driver), no transaction control, no target writes.
--
-- SIGNATURE
--   P_JOB_RUN_ID  VARCHAR  (no default -- the driver always passes it)
--   P_RUN_TS      TIMESTAMP_NTZ
--   P_INPUT_TABLES VARCHAR DEFAULT 'WRK_ECI_PHN_S40_ROUTED'  (work-table inputs only;
--                 base source tables and target guard tables are NOT
--                 work-table dependencies and are not listed)
--   Original parameters of this mapping: NONE (only P_JOB_RUN_ID was
--   appended by the modular rewrite, and it is carried here).
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_ECI_PHN_S50_READY (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_PHN_S40_ROUTED') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr';
    l_rows NUMBER DEFAULT 0;
    l_missing VARCHAR2(4000);
    l_probe_sql VARCHAR2(4000);
    l_probe_dummy NUMBER;
SELECT MIN(s.tbl) INTO l_missing FROM (SELECT REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL) AS raw, UPPER(TRIM(REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL))) AS tbl FROM DUAL CONNECT BY REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL) IS NOT NULL) s WHERE TRIM(s.raw) <> '' AND NOT EXISTS (SELECT 1 FROM ALL_TABLES t WHERE t.OWNER = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AND t.TABLE_NAME = s.tbl);
        IF (l_missing IS NOT NULL) THEN
            l_probe_sql := 'SELECT COUNT(*) FROM ' || l_missing;
            EXECUTE IMMEDIATE l_probe_sql INTO l_probe_dummy;
        END IF;
    END IF;

    -- ---- Step 50 CTAS (verbatim from the original main procedure) ----
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_PHN_S50_READY';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_ECI_PHN_S50_READY AS SELECT r.*,
           '1' /* TIMELINE: VERSION_SEQ */                                     AS version_seq,
           1                                                                    AS hub_state_ind,
           'ECI'                                                                AS src_sys,
           :1                                                            AS run_ts,
           :2                                                           AS mapping_name,
           'Bad Value'                                                          AS exc_type_bad_value,
           CASE WHEN r.PREF_LVL = 'Primary' THEN r.std_phone ELSE NULL END                       AS exc_primary_phone,
           CASE WHEN r.USG_TP = 'Work' THEN r.std_phone ELSE NULL END                            AS exc_work_phone,
           CASE WHEN r.PREF_LVL = 'Secondary' THEN r.std_phone ELSE NULL END                     AS exc_secondary_phone,
           DECODE(r.USG_TP, '001', 'Main Phone', '002', 'Work Phone', '003', 'Other Phone') AS exc_phone_attribute,
           'Email'                                                              AS exc_email_attribute,
           '001'                                                                AS eaddr_addr_tp,
           'Active'                                                             AS eaddr_sts_cd,
           'Y'                                                                  AS eaddr_is_vld,
           CASE WHEN (ROW_NUMBER() OVER (PARTITION BY r.grp_phone_good, r.pkey_src_object
                                   ORDER BY r.PERIOD_START_DATE DESC, r.ID_FAMILY_PHONE) = 1
            AND xph.PKEY_SRC_OBJECT IS NULL) THEN 1 ELSE 0 END AS uq_phn,
           CASE WHEN (ROW_NUMBER() OVER (PARTITION BY r.grp_email_good, r.pkey_src_object
                                   ORDER BY r.PERIOD_START_DATE DESC, r.ID_FAMILY_PHONE) = 1
            AND xea.PKEY_SRC_OBJECT IS NULL) THEN 1 ELSE 0 END AS uq_eaddr,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.grp_phone_bad, r.ID_CASE, r.USG_TP, r.phone_exception_code
                                  ORDER BY r.ID_FAMILY_PHONE) = 1 THEN 1 ELSE 0 END AS uq_phone_exc,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.grp_email_bad, r.ID_FAMILY_PHONE, r.email_exception_type,
                                           r.email_exception_code ORDER BY r.ID) = 1 THEN 1 ELSE 0 END AS uq_email_exc
      FROM WRK_ECI_PHN_S40_ROUTED r
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_ECI_PTY_RLE_PHN WHERE VERSION_SEQ = 1) xph
             ON xph.PKEY_SRC_OBJECT = r.pkey_src_object
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_ECI_PTY_RLE_EADDR WHERE VERSION_SEQ = 1) xea
             ON xea.PKEY_SRC_OBJECT = r.pkey_src_object]' USING P_RUN_TS, c_mapping;
    SELECT COUNT(*) INTO l_rows FROM WRK_ECI_PHN_S50_READY;
    sp_etl_checkpoint('ECI', P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'READY_TO_PUBLISH', 'COMPLETED', 'C_S_ECI_PTY_RLE_PHN, C_S_ECI_PTY_RLE_EADDR, EXC_STG_BAD_REC_MEMB', 'Step 50 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_ECI_PHN_S50_READY;
/

