-- ============================================================================
-- sp_snow_step_ECI_ADR_S50_READY  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI)
--
-- Mapping: m_Tgt_C_S_ECI_Pty_Addr, workflow wf_ECI_Stage_Load, step 50.
-- Step name (checkpoint): SCORED_READY.
--
-- WHAT THIS STEP PRODUCES
--   WRK_ECI_ADR_S50_READY: Scored, publish-ready addresses with held lines and insert-only guards uq_addr / uq_addr_exc (original scored CTE + final SELECT, including the target-table guard join, which still sees the pre-run state because nothing has been published yet).
--
-- DOES IT FEED THE SPINE?
--   Directly: this is the sole input to all three publish branches, including the SPINE branch (C_S_ECI_PTY_RLE_ADDR). It writes no target itself.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (default 'WRK_ECI_ADR_S40_FLAT').
--   Base source tables and target guard tables are NOT work-table
--   dependencies and are not listed. Snowflake cannot parameterise
--   table names in static SQL, so P_INPUT_TABLES is a dependency
--   declaration + runtime check, NOT dynamic SQL: the CTAS below still
--   names its sources literally, as in the current main procedure.
--   The existence check probes the first missing table with
--   EXECUTE IMMEDIATE 'SELECT 1 FROM <table>' (LISTAGG/FLATTEN form,
--   no row-by-row iteration), surfacing the native object-not-exists
--   error (coordinator normalisation: Snowflake RAISE accepts only a
--   declared exception name, so a dynamic message is not possible).
--
-- BUSINESS SQL
--   The CTAS below is the current step-50 SELECT verbatim. Only
--   substitutions: :l_run_ts -> :P_RUN_TS, :c_mapping -> the local
--   constant below (same value), original-param refs -> this proc's
--   params. No business expression, filter, guard or column list was
--   changed. Original params used by this step's SQL: P_MEMBER_HIERARCHY_CODE, P_MEMBER_HM_REL_TP_CD (hierarchy_code / hm_rel_tp_cd columns). Both are present, in original order, before P_JOB_RUN_ID.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   with the same STEP_NAME and message as the current step-50 checkpoint (v2 10-argument form; STEP_NO, row count, and work-table arguments dropped).
--   P_JOB_RUN_ID is present in every new proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_ECI_ADR_S50_READY (P_MEMBER_HIERARCHY_CODE IN VARCHAR2 DEFAULT 'Member', P_MEMBER_HM_REL_TP_CD IN VARCHAR2 DEFAULT 'Member Addr', -- Live-compile fix: Snowflake forbids a required parameter after an
    -- optional one, so P_JOB_RUN_ID / P_RUN_TS carry DEFAULT NULL here.
    -- Drivers always pass all five positionally, so behaviour is unchanged.
    P_JOB_RUN_ID   VARCHAR DEFAULT NULL IN , P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_ADR_S40_FLAT') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_ECI_Pty_Addr';
    l_rows NUMBER DEFAULT 0;
    l_missing VARCHAR2(4000) DEFAULT NULL;
    l_probe_sql VARCHAR2(4000);
    l_probe_dummy NUMBER;
BEGIN
    -- ---- Input existence check (skipped when P_INPUT_TABLES is NULL/empty)
    -- P_INPUT_TABLES is a dependency declaration + runtime check, NOT
    -- dynamic SQL (Snowflake cannot parameterise table names in static
    -- SQL); the CTAS below still names its sources literally, as now.
    IF (P_INPUT_TABLES IS NOT NULL AND TRIM(P_INPUT_TABLES) <> '') THEN
        SELECT LISTAGG(tbl, ', ') WITHIN GROUP (ORDER BY tbl) INTO l_missing FROM (SELECT UPPER(TRIM(REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL))) AS tbl FROM DUAL CONNECT BY REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL) IS NOT NULL) f WHERE NOT EXISTS (SELECT 1 FROM ALL_TABLES t WHERE t.OWNER = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AND t.TABLE_NAME = f.tbl);
        IF (l_missing IS NOT NULL) THEN
            l_probe_sql := 'SELECT COUNT(*) FROM ' || TRIM(REGEXP_SUBSTR(l_missing, '[^,]+', 1, 1));
            EXECUTE IMMEDIATE l_probe_sql INTO l_probe_dummy;
        END IF;
    END IF;

    -- ---- Step 50: SCORED_READY (verbatim from current main)
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_ADR_S50_READY';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_ECI_ADR_S50_READY AS WITH
    scored AS (
        SELECT f.*,
               fn_snow_helper05_common(f.mstr_addr_tp, f.a_mailability_score, f.a_match_code) AS score,
               fn_snow_helper06_common(f.mstr_addr_tp, f.a_mailability_score, f.a_match_code)   AS addr_issue_desc,
               fn_snow_helper07_common(f.a_line1, f.a_line2)                                   AS hold_line1,
               fn_snow_helper08_common(f.a_line1, f.a_line2)                                   AS hold_line2
          FROM WRK_ECI_ADR_S40_FLAT f
    )
    SELECT s.*,
           'US'                                                          AS src_cntry,
           'ECI'                                                         AS src_sys,
           :1                                                     AS run_ts,
           :2                                                    AS mapping_name,
           1 /* TIMELINE: VERSION_SEQ */                                 AS version_seq,
           1                                                             AS hub_state_ind,
           'Primary'                                                     AS pref_lvl,
           TO_CHAR(TRUNC(s.ID)) || '|' || TO_CHAR(TRUNC(s.ID_FAMILY_ADDRESS)) AS loc_idn,
           :3                                      AS hierarchy_code,
           :4                                        AS hm_rel_tp_cd,
           CASE WHEN s.addr_issue_desc IS NOT NULL THEN 'Address' ELSE NULL END           AS exc_attribute_name,
           CASE WHEN s.addr_issue_desc IS NOT NULL THEN NVL(CASE WHEN s.ADDRESS1 = 1 THEN 1 ELSE 0 END, '') || ' ' || NVL(CASE WHEN s.ADDRESS2 = 1 THEN 1 ELSE 0 END, '') || ' ' || NVL(CASE WHEN s.CITY_NAME = 1 THEN 1 ELSE 0 END, '') || ' '
               || NVL(CASE WHEN s.STATE_ABBREV = 1 THEN 1 ELSE 0 END, '') || ' ' || NVL(s.ZIP_CODE, '') || ' ' || NVL(s.ZIP_SFX, '') || ' US' ELSE NULL END                                                     AS exc_attribute_value,
           'Invalid_Address'                                             AS exc_code,
           'Invalid Address per Address Doctor'                          AS exc_desc,
           'Bad Value'                                                   AS exc_type,
           CASE WHEN (ROW_NUMBER() OVER (PARTITION BY s.score, s.pkey_src_object
                                   ORDER BY s.LAST_UPDATE_DATE DESC, s.ID_FAMILY_ADDRESS) = 1
            AND xa.PKEY_SRC_OBJECT IS NULL) THEN 1 ELSE 0 END AS uq_addr,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY s.score, s.ID, s.ID_FAMILY_ADDRESS, s.SOURCE_TABLE
                                  ORDER BY s.LAST_UPDATE_DATE DESC) = 1 THEN 1 ELSE 0 END AS uq_addr_exc
      FROM scored s
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_ECI_PTY_RLE_ADDR WHERE VERSION_SEQ = 1) xa
             ON xa.PKEY_SRC_OBJECT = s.pkey_src_object]' USING P_RUN_TS, c_mapping, P_MEMBER_HIERARCHY_CODE, P_MEMBER_HM_REL_TP_CD;
    SELECT COUNT(*) INTO l_rows FROM WRK_ECI_ADR_S50_READY;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'SCORED_READY', 'COMPLETED', 'DQM_ADDRESS, C_S_ECI_PTY_RLE_ADDR, EXC_STG_BAD_REC_MEMB', 'Step 50 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_ECI_ADR_S50_READY;
/

