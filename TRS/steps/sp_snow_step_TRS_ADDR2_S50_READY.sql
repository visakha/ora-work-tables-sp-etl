-- ============================================================================
-- sp_snow_step_TRS_ADDR2_S50_READY  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Addr_2, workflow wf_TRS_Stage_Load_1_Ongoing, step 50.
-- Step name (checkpoint): READY_TO_PUBLISH.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_ADDR2_S50_READY: READY -- audit keys, hold lines, exception data
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (pipe-delimited). Default: 'WRK_TRS_ADDR2_S40_SCORED'.
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
--   P_MEMBER_ROLE_TYPE, P_MEMBER_HIERARCHY_CODE, P_MEMBER_HM_REL_TP_CD.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   in the 10-argument form. P_JOB_RUN_ID is present in every new proc
--   in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_ADDR2_S50_READY (P_MEMBER_ROLE_TYPE IN VARCHAR2 DEFAULT 'Member', P_MEMBER_HIERARCHY_CODE IN VARCHAR2 DEFAULT 'Member', P_MEMBER_HM_REL_TP_CD IN VARCHAR2 DEFAULT 'Member Addr', P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_ADDR2_S40_SCORED') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TRS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Addr_2';
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
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_ADDR2_S50_READY';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_ADDR2_S50_READY AS WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common()))
    SELECT c.*,
           'TRS'                                                                AS src_sys,
           :1                                                            AS run_ts,
           :2                                                           AS mapping_name,
           :3                                             AS hierarchy_code,
           :4                                               AS hm_rel_tp_cd,
           'Primary'                                                            AS pref_lvl,
           CASE WHEN c.EFF_END_DT IS NOT NULL THEN :1 ELSE NULL END                        AS period_reference_time,
           c.pkey_pty_rle_addr || '|' || TO_CHAR(c.version_seq)               AS src_rowid,
           NVL(TO_CHAR(TRUNC(c.CASE_NUM)), '') || '|' || NVL(TO_CHAR(TRUNC(c.EDG_NUM)), '') AS loc_idn,
           NVL(CASE WHEN c.PTY_PK = 1 THEN 1 ELSE 0 END, '') || '|' || :5                      AS pty_rle_fk,
           fn_snow_helper07_common(c.ADDR_LN_1, c.ADDR_LN_2)                    AS hold_line1,
           fn_snow_helper08_common(c.ADDR_LN_1, c.ADDR_LN_2)                    AS hold_line2,
           NVL(c.ADDR_LN_1, '') || '|' || NVL(c.ADDR_LN_2, '') || '|' || NVL(CASE WHEN c.CITY = 1 THEN 1 ELSE 0 END, '') || '|' || c.rslt_pstl_cd
           || '|' || NVL(CASE WHEN c.STATE = 1 THEN 1 ELSE 0 END, '') || '|' || NVL(c.CNTRY_CD, '')             AS dqm_addr_src_key,
           NVL(CASE WHEN c.SRC_PSTL_CD = 1 THEN 1 ELSE 0 END, '') || CASE WHEN c.SRC_PSTL_CD_EXT IS NOT NULL THEN '-' || c.SRC_PSTL_CD_EXT ELSE '' END AS dqm_src_pstl_cd,
           CASE WHEN c.addr_issue_desc IS NOT NULL THEN 'Address' ELSE NULL END                  AS exc_attribute_name,
           CASE WHEN c.addr_issue_desc IS NOT NULL THEN NVL(c.SRC_ADDR_LN_1, '') || ' ' || NVL(c.SRC_ADDR_LN_2, '') || ' ' || NVL(c.SRC_CITY, '') || ' '
               || NVL(c.SRC_STATE, '') || ' ' || NVL(TO_CHAR(c.SRC_PSTL_CD), '') || ' '
               || NVL(TO_CHAR(c.SRC_PSTL_CD_EXT), '') || ' ' || NVL(c.SRC_CNTRY, '') ELSE NULL END AS exc_attribute_value,
           ex.EXCEPTION_CODE                                                    AS exc_code,
           ex.EXCEPTION_DESC                                                    AS exc_desc,
           ex.EXCEPTION_TYPE                                                    AS exc_type,
           CASE WHEN xa.PKEY_SRC_OBJECT IS NULL THEN 1 ELSE 0 END AS uq_addr,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY c.score, c.INDV_ID, c.CASE_NUM, c.EDG_NUM
                                  ORDER BY c.CREATE_DT DESC, c.ADDR_TYPE_CD) = 1 THEN 1 ELSE 0 END AS uq_addr_exc
      FROM WRK_TRS_ADDR2_S40_SCORED c
      LEFT JOIN lkp_exc ex ON ex.EXCEPTION_CODE = 'Invalid_Address'
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT, VERSION_SEQ FROM C_S_TRS_PTY_RLE_ADDR) xa
             ON xa.PKEY_SRC_OBJECT = c.pkey_pty_rle_addr = 1 AND xa.VERSION_SEQ = c.version_seq]' USING P_RUN_TS, c_mapping, P_MEMBER_HIERARCHY_CODE, P_MEMBER_HM_REL_TP_CD, P_MEMBER_ROLE_TYPE;
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_ADDR2_S50_READY;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'READY_TO_PUBLISH', 'COMPLETED', 'DQM_ADDRESS, C_S_TRS_PTY_RLE_ADDR, EXC_STG_BAD_REC_MEMB', 'Step 50 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_ADDR2_S50_READY;
/

