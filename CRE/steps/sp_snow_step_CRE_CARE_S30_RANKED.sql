-- ============================================================================
-- sp_snow_step_CRE_CARE_S30_RANKED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (CRE)
--
-- Mapping: m_Tgt_C_S_CRE_CARE_Clients, workflow wf_CRE_Stage_Load_Ongoing, step 30.
-- Step name (checkpoint): RANK_ENRICH.
--
-- WHAT THIS STEP PRODUCES
--   WRK_CRE_CARE_S3_RANKED: rank + validation enrichment (ranked + dq + dq2).
--   One ranked row per CARE id (record type descending: I, D, B, A -- only the rank-1 row of a valid member loads), with the merge CARE id, the blanked SSN, the translated state code, and every validation result: gender, ethnicity, race, standardised phone, CARE / Medicaid / SSN id checks, the US-vs-abroad flag, and the US address validation result. Reads ONLY step 20 (plus the reference lookups).
--
-- DOES IT FEED THE SPINE?
--   Indirectly: the rank-1 / is_member flag computed here decides which rows the spine branches load; the validation results feed the exception branches.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only. Default: 'WRK_CRE_CARE_S2_NAMED'
--   (empty for step 10: it reads base source tables, not work tables, so
--   the existence check below is skipped). Snowflake cannot parameterise
--   table names in static SQL, so P_INPUT_TABLES is a dependency
--   declaration + runtime check, NOT dynamic SQL: the CTAS below still
--   names its sources literally, as in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-30 SELECT verbatim. Only
--   substitutions: :l_run_ts -> :P_RUN_TS, :c_mapping -> the local
--   constant below (used by the checkpoint), no original-parameter refs in this step. No business
--   expression, filter, guard or column list was changed. This step uses
--   original parameters: none (uses the run timestamp only via the step framework, not in its CTAS).
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   with the same STEP_NAME and message as the current step-30
--   checkpoint (v2 10-argument form; STEP_NO, row count, and work-table
--   arguments dropped). P_JOB_RUN_ID is present in every new proc in
--   this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_CRE_CARE_S30_RANKED (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_CRE_CARE_S2_NAMED') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'CRE';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_CRE_Stage_Load_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_CRE_CARE_Clients';
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

    -- ---- Step 30: RANK_ENRICH (verbatim from current main)
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_CRE_CARE_S3_RANKED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_CRE_CARE_S3_RANKED AS WITH
    lkp_exc  AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    lkp_any  AS (SELECT * FROM TABLE(fn_snow_helper42_common())),
    lkp_cv   AS (SELECT * FROM TABLE(fn_snow_helper41_common())),
    lkp_area AS (SELECT * FROM TABLE(fn_snow_helper44_common())),
    -- SRT_VALID_MEMBERS + EXP_VALID_MEMBERS2 + LKP_INVALID_FIRSTNM / LASTNM + LKP_STATE_CODE
    ranked AS (
        SELECT m.*,
               /* TIMELINE: VERSION_SEQ_NUM per CARE id, REC_TYPE descending */
               CASE WHEN m.valid_member = 1 THEN ROW_NUMBER() OVER (PARTITION BY m.valid_member, m.CARE_ID ORDER BY m.REC_TYPE DESC) ELSE NULL END
                                                                                       AS version_seq_num,
               xf.EXCEPTION_CODE AS fn_exception_code, xf.EXCEPTION_DESC AS fn_exception_desc,
               xf.EXCEPTION_TYPE AS fn_exception_type,
               xl.EXCEPTION_CODE AS ln_exception_code, xl.EXCEPTION_DESC AS ln_exception_desc,
               xl.EXCEPTION_TYPE AS ln_exception_type,
               CASE WHEN m.orig_rowid_object_desc = 'N' THEN m.TARGET_ID ELSE m.CARE_ID END             AS mrg_care_id,
               /* BAD DATA: SSN_OUT suppresses the default values */
               CASE WHEN m.SSN = 'U' OR m.SSN = 'N' THEN NULL ELSE m.SSN END                            AS ssn_out,
               st.MSTR_CODE_VALUE                                                      AS std_state_cd
          FROM WRK_CRE_CARE_S2_NAMED m
          LEFT JOIN lkp_exc xf ON xf.EXCEPTION_CODE = m.fn_missing_code
          LEFT JOIN lkp_exc xl ON xl.EXCEPTION_CODE = m.ln_missing_code
          LEFT JOIN lkp_any st ON st.SRC_SYS = 'CRE' AND st.SRC_CODE_VALUE = m.STATE
    ),
    -- the mapplets and rules (only the de-duplicated members are routed to a target)
    dq AS (
        SELECT r.*,
               NVL(CASE WHEN r.version_seq_num = 1 THEN 1 ELSE 0 END, 0)                                       AS is_member,
               fn_snow_helper17_common(r.SEX, 'Indv', 'CRE')                           AS gd,
               et.MSTR_CODE_VALUE                                                      AS ethnicity_mstr,
               rc.MSTR_CODE_VALUE                                                      AS race_mstr,
               fn_snow_helper23_common(r.PHONE)                                        AS phone_std,
               fn_snow_helper37_common(r.mrg_care_id)                                  AS ci,
               fn_snow_helper27_common(r.RECIP_NO)                                     AS md,
               fn_snow_helper26_common(r.ssn_out)                                      AS sn,
               /* RTR_US_ADDRESSES.US_ADDRESSES: STD_STATE_CD <> '99' OR ISNULL(STD_STATE_CD) */
               NVL(CASE WHEN r.std_state_cd <> '99' THEN 1 ELSE 0 END, 1)                                       AS addr_us,
               ss.MSTR_CODE_VALUE                                                      AS source_state_fips
          FROM ranked r
          LEFT JOIN lkp_cv et ON et.CODE_TYPE = 'ETHNICITY' AND et.SRC_SYS = 'CRE' AND et.SRC_CODE_VALUE = r.FEDETH
          LEFT JOIN lkp_cv rc ON rc.CODE_TYPE = 'RACE' AND rc.SRC_SYS = 'CRE' AND rc.SRC_CODE_VALUE = r.RACE
          LEFT JOIN lkp_cv ss ON ss.CODE_TYPE = 'STATE' AND ss.SRC_SYS = 'CRE'
                             AND ss.SRC_CODE_VALUE = UPPER(TRIM(r.STATE))
    )
    -- mplt_Global_Addr_Validation (US addresses) + rule_Phone_Std exception code
    SELECT d.*,
           CASE WHEN d.addr_us = 1 THEN fn_snow_helper34_common(d.STREET, NULL, d.CITY, d.STATE,
                                                  NVL(d.ZIP, '') || '-' || NVL(d.ZIPSUF, ''), 'US',
                                                  d.source_state_fips) ELSE NULL END AS av,
           /* VALIDATION */
           fn_snow_helper24_common(d.phone_std, NULL, NULL, ar.NPA_ID, ar.SERVICE)  AS phone_code
      FROM dq d
      LEFT JOIN lkp_area ar ON ar.NPA_ID = SUBSTR(d.phone_std, 1, 3)]';
    SELECT COUNT(*) INTO l_rows FROM WRK_CRE_CARE_S3_RANKED;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'RANK_ENRICH', 'COMPLETED', NULL, 'Step 30 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_CRE_CARE_S30_RANKED;
/

