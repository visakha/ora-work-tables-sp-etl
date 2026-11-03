-- ============================================================================
-- sp_snow_step_TRS_REL1_S30_ROUTER  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem, workflow wf_TRS_Stage_Load_1_Ongoing, step 30.
-- Step name (checkpoint): ROUTER_EXCEPTIONS.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_REL1_S3_ROUTER: ROUTER -- exception flags + descriptions (BR-02)
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (pipe-delimited). Default: 'WRK_TRS_REL1_S2_KEYED'.
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-30 SELECT verbatim. Only
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
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_REL1_S30_ROUTER (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_REL1_S2_KEYED') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TRS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem';
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

    -- ---- Step 30: ROUTER_EXCEPTIONS (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_REL1_S3_ROUTER';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_REL1_S3_ROUTER AS WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    router AS (
        SELECT r.*,
               CASE WHEN /* BAD DATA: unique key of EXC_STG_BAD_REC_MEMB, first row per key in this run */
               ROW_NUMBER() OVER (PARTITION BY r.pty_rle_fk_1 IS NULL, r.INDV_ID, r.REF_INDV_ID, r.rel_type_code
                                      ORDER BY r.CREATE_DT DESC) = 1 THEN 1 ELSE 0 END AS uq_exc_member,
               CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.pty_rle_fk_2 IS NULL, r.INDV_ID, r.REF_INDV_ID, r.rel_type_code
                                      ORDER BY r.CREATE_DT DESC) = 1 THEN 1 ELSE 0 END AS uq_exc_ref,
               CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.rel_type_code IS NULL, r.INDV_ID, r.REF_INDV_ID,
                                               r.RELATIONSHIP_TYPE_CD ORDER BY r.CREATE_DT DESC) = 1 THEN 1 ELSE 0 END AS uq_exc_type,
               CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.dates_reversed, r.INDV_ID, r.REF_INDV_ID, r.RELATIONSHIP_TYPE_CD
                                      ORDER BY r.CREATE_DT DESC) = 1 THEN 1 ELSE 0 END AS uq_exc_dates
          FROM WRK_TRS_REL1_S2_KEYED r
    )
    SELECT r.*,
           'Member Relationship'                         AS rel_type_code_label,
           'Member'                                      AS hierarchy_code,
           'Relationship Type'                           AS attr_rel_type,
           'Effective Date'                              AS attr_dates,
           'Invalid_Member'                              AS exc_member_code,
           xm.EXCEPTION_DESC                             AS exc_member_desc,
           xm.EXCEPTION_TYPE                             AS exc_member_type,
           'Invalid_Ref_Member'                          AS exc_ref_code,
           xf.EXCEPTION_DESC                             AS exc_ref_desc,
           xf.EXCEPTION_TYPE                             AS exc_ref_type,
           xt.EXCEPTION_CODE                             AS exc_type_lkp_code,
           xt.EXCEPTION_DESC                             AS exc_type_desc,
           xt.EXCEPTION_TYPE                             AS exc_type_type,
           'Period_Start_Date_>_Period_End_Date'         AS exc_dates_code,
           xd.EXCEPTION_DESC                             AS exc_dates_desc,
           xd.EXCEPTION_TYPE                             AS exc_dates_type
      FROM router r
      LEFT JOIN lkp_exc xm ON xm.EXCEPTION_CODE = 'Invalid_Member'
      LEFT JOIN lkp_exc xf ON xf.EXCEPTION_CODE = 'Invalid_Ref_Member'
      LEFT JOIN lkp_exc xt ON xt.EXCEPTION_CODE = 'Invalid_Rel_Type'
      LEFT JOIN lkp_exc xd ON xd.EXCEPTION_CODE = 'Period_Start_Date_>_Period_End_Date']';
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_REL1_S3_ROUTER;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'ROUTER_EXCEPTIONS', 'COMPLETED', 'EXC_STG_BAD_REC_MEMB', 'Step 30 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_REL1_S30_ROUTER;
/

