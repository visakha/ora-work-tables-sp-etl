-- ============================================================================
-- sp_snow_step_FSS_ADR_S40_SCORED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (FSS)
--
-- Mapping: m_Tgt_C_S_FSS_Pty_Addr, workflow wf_FSS_Stage_Load, step 40.
-- Step name (checkpoint): SCORED.
--
-- WHAT THIS STEP PRODUCES
--   WRK_FSS_ADDR_S4_SCORED: Good / exception score, held address lines, exception details, insert-only guards.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (default: 'WRK_FSS_ADDR_S3_FLAT').
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-40 SELECT verbatim. Only
--   substitution: :l_run_ts -> :P_RUN_TS,
--   :c_mapping -> the local constant below (used by the checkpoint).
--   No business expression, filter, guard or column list was changed.
--   Original parameters used by this step: P_MEMBER_HIERARCHY_CODE, P_MEMBER_HM_REL_TP_CD.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   in the v2 10-argument form (TARGET_TABLE NULL, as in the current
--   main's step checkpoints; row count survives in the RETURN value
--   and the driver's helper36 summary line).
--   P_JOB_RUN_ID is present in every new proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_FSS_ADR_S40_SCORED (P_MEMBER_HIERARCHY_CODE IN VARCHAR2 DEFAULT 'Member', P_MEMBER_HM_REL_TP_CD IN VARCHAR2 DEFAULT 'Member Addr', -- Live-compile fix (ECI v2.1): Snowflake forbids a required parameter after an
    -- optional one, so P_JOB_RUN_ID / P_RUN_TS carry DEFAULT NULL here.
    -- Drivers always pass all parameters positionally, so behaviour is unchanged.
    P_JOB_RUN_ID   VARCHAR DEFAULT NULL IN , P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_FSS_ADDR_S3_FLAT') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'FSS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_FSS_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_FSS_Pty_Addr';
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

    -- ---- Step 40: SCORED (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_FSS_ADDR_S4_SCORED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_FSS_ADDR_S4_SCORED AS WITH
    scored AS (
        SELECT f.*,
               /* VALIDATION */ fn_snow_helper05_common('002', f.a_mailability_score, f.a_match_code) AS score,
               fn_snow_helper06_common('002', f.a_mailability_score, f.a_match_code)   AS addr_issue_desc,
               fn_snow_helper07_common(f.a_line1, f.a_line2)                          AS hold_line1,
               fn_snow_helper08_common(f.a_line1, f.a_line2)                          AS hold_line2
          FROM WRK_FSS_ADDR_S3_FLAT f
    )
    SELECT s.*,
           '002'                                                         AS addr_tp,
           'US'                                                          AS src_cntry,
           'FSS'                                                         AS src_sys,
           :1                                                     AS run_ts,
           :2                                                    AS mapping_name,
           1 /* TIMELINE: VERSION_SEQ */                                 AS version_seq,
           1                                                             AS hub_state_ind,
           NVL(CASE WHEN s.PTY_SRC_KEY = 1 THEN 1 ELSE 0 END, '') || '|Member'                           AS pty_rle_fk,
           'Primary'                                                     AS pref_lvl,
           NVL(TO_CHAR(s.ID_CLIENT), '') || '|' || NVL(TO_CHAR(s.ID_REGISTRATION_CLIENT), '') AS loc_idn,
           :3                                      AS hierarchy_code,
           :4                                        AS hm_rel_tp_cd,
           CASE WHEN s.addr_issue_desc IS NOT NULL THEN 'Address' ELSE NULL END           AS exc_attribute_name,
           CASE WHEN s.addr_issue_desc IS NOT NULL THEN NVL(CASE WHEN s.ADDR_LINE1 = 1 THEN 1 ELSE 0 END, '') || ' ' || NVL(CASE WHEN s.ADDR_LINE2 = 1 THEN 1 ELSE 0 END, '') || ' ' || NVL(CASE WHEN s.ADDR_CITY = 1 THEN 1 ELSE 0 END, '') || ' '
               || NVL(CASE WHEN s.ADDR_STATE = 1 THEN 1 ELSE 0 END, '') || ' ' || NVL(s.ADDR_ZIP, '') || '  US' ELSE NULL END AS exc_attribute_value,
           'Invalid_Address'                                             AS exc_code,
           'Invalid Address per Address Doctor'                          AS exc_desc,
           'Bad Value'                                                   AS exc_type,
           /* BAD DATA: unique keys Snowflake does not enforce */
           (ROW_NUMBER() OVER (PARTITION BY s.score, s.pkey_src_object
                                   ORDER BY s.DT_LAST_UPDATE DESC, s.ID_REGISTRATION_CLIENT) = 1
            AND xa.PKEY_SRC_OBJECT IS NULL)                              AS uq_addr,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY s.score, s.ID_CLIENT, s.ID_REGISTRATION_CLIENT, s.SOURCE_TYPE
                                  ORDER BY s.DT_LAST_UPDATE DESC) = 1 THEN 1 ELSE 0 END AS uq_addr_exc
      FROM scored s
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_FSS_PTY_RLE_ADDR WHERE VERSION_SEQ = 1) xa
             ON xa.PKEY_SRC_OBJECT = s.pkey_src_object]' USING P_RUN_TS, c_mapping, P_MEMBER_HIERARCHY_CODE, P_MEMBER_HM_REL_TP_CD;
    SELECT COUNT(*) INTO l_rows FROM WRK_FSS_ADDR_S4_SCORED;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'SCORED', 'COMPLETED', NULL, 'Step 40 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_FSS_ADR_S40_SCORED;
/

