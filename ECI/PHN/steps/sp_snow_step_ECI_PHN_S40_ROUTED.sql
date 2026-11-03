-- ============================================================================
-- sp_snow_step_ECI_PHN_S40_ROUTED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI ONLY)
--
-- Mapping: m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr, workflow wf_ECI_Stage_Load.
-- Step 40: ROUTED_GROUPS -- Area-code lookup, phone exception codes and router groups.
-- Produces: TRANSIENT TABLE WRK_ECI_PHN_S40_ROUTED.
-- Feeds: SPINE-FEEDING (via step 50): good/bad phone and e-mail groups; feeds both spine and exception branches downstream.
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
--   (STEP_NAME 'ROUTED_GROUPS', STEP_STATUS 'COMPLETED', TARGET_TABLE NULL,
--   MESSAGE 'Step 40 complete.', ERROR_MESSAGE NULL). STEP_NO, row count,
--   work-table name/action/purpose are no longer checkpoint arguments.
--   Returns the work-table row count (NUMBER). No exception block (errors
--   propagate to the driver), no transaction control, no target writes.
--
-- SIGNATURE
--   P_JOB_RUN_ID  VARCHAR  (no default -- the driver always passes it)
--   P_RUN_TS      TIMESTAMP_NTZ
--   P_INPUT_TABLES VARCHAR DEFAULT 'WRK_ECI_PHN_S30_DQ'  (work-table inputs only;
--                 base source tables and target guard tables are NOT
--                 work-table dependencies and are not listed)
--   Original parameters of this mapping: NONE (only P_JOB_RUN_ID was
--   appended by the modular rewrite, and it is carried here).
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_ECI_PHN_S40_ROUTED (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_PHN_S30_DQ') RETURN NUMBER AUTHID CURRENT_USER AS
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

    -- ---- Step 40 CTAS (verbatim from the original main procedure) ----
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_PHN_S40_ROUTED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_ECI_PHN_S40_ROUTED AS WITH
    lkp_exc  AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    lkp_area AS (SELECT * FROM TABLE(fn_snow_helper44_common())),
    checked AS (
        SELECT d.*,
               CASE WHEN NOT d.is_email = 1 THEN fn_snow_helper24_common(d.std_phone, 'ECI', d.USG_TP, ar.NPA_ID, ar.SERVICE) ELSE NULL END AS phone_exception_code,
               CAST(d.em.email_address AS VARCHAR2(4000))                                        AS std_email
          FROM WRK_ECI_PHN_S30_DQ d
          LEFT JOIN lkp_area ar ON ar.NPA_ID = SUBSTR(d.std_phone, 1, 3)
    )
    SELECT c.*,
           xp.EXCEPTION_DESC                                                  AS phone_exception_desc,
           xe.EXCEPTION_CODE                                                  AS email_exception_code,
           xe.EXCEPTION_DESC                                                  AS email_exception_desc,
           xe.EXCEPTION_TYPE                                                  AS email_exception_type,
           CASE WHEN (NOT c.is_email = 1 AND (c.phone_exception_code IS NULL
                                OR c.phone_exception_code = 'Missing_AreaCode')) THEN 1 ELSE 0 END AS grp_phone_good,
           CASE WHEN (NOT c.is_email = 1 AND c.phone_exception_code IS NOT NULL) THEN 1 ELSE 0 END AS grp_phone_bad,
           CASE WHEN (c.is_email = 1 AND xe.EXCEPTION_CODE IS NULL) THEN 1 ELSE 0 END AS grp_email_good,
           CASE WHEN (c.is_email = 1 AND xe.EXCEPTION_CODE IS NOT NULL) THEN 1 ELSE 0 END AS grp_email_bad
      FROM checked c
      LEFT JOIN lkp_exc xp ON xp.EXCEPTION_CODE = c.phone_exception_code
      LEFT JOIN lkp_exc xe ON xe.EXCEPTION_CODE = CAST(c.em.exception_code AS VARCHAR2(4000))]';
    SELECT COUNT(*) INTO l_rows FROM WRK_ECI_PHN_S40_ROUTED;
    sp_etl_checkpoint('ECI', P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'ROUTED_GROUPS', 'COMPLETED', NULL, 'Step 40 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_ECI_PHN_S40_ROUTED;
/

