-- ============================================================================
-- sp_snow_step_CRE_CARE_S50_KEYED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (CRE)
--
-- Mapping: m_Tgt_C_S_CRE_CARE_Clients, workflow wf_CRE_Stage_Load_Ongoing, step 50.
-- Step name (checkpoint): KEYED_ROUTES_GUARDS.
--
-- WHAT THIS STEP PRODUCES
--   WRK_CRE_CARE_S5_KEYED: route flags + unique-key guards (keyed + final select).
--   The rows the publish step writes, with the county rule (non-Texas state -> 996, missing county FIPS -> 998, else the county FIPS), the address / phone / alternate-id keys, the route flag for every target and exception class (every flag NVL-ed: a NULL router condition does not route), the run constants, the SRC_ROWIDs cut to 30 characters, and the insert-only guards: keys already in a target (VERSION_SEQ = 1) are skipped, and the first row per exception key wins (record type descending). Reads ONLY step 40.
--
-- DOES IT FEED THE SPINE?
--   YES, directly: all eighteen publish branches read ONLY this table. It writes no target itself.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only. Default: 'WRK_CRE_CARE_S4_FLAT'
--   (empty for step 10: it reads base source tables, not work tables, so
--   the existence check below is skipped). Snowflake cannot parameterise
--   table names in static SQL, so P_INPUT_TABLES is a dependency
--   declaration + runtime check, NOT dynamic SQL: the CTAS below still
--   names its sources literally, as in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-50 SELECT verbatim. Only
--   substitutions: :l_run_ts -> :P_RUN_TS, :c_mapping -> the local
--   constant below (used by the checkpoint), original-parameter refs -> this proc's params of the same names. No business
--   expression, filter, guard or column list was changed. This step uses
--   original parameters: P_PHYSICAL_ADDR_TYPE_CD, P_RLE_BO_CLASS_CD_MEMBER, P_DEFAULT_TX_STATE_CD, P_COUNTY_CD_NONTX, P_COUNTYCD_DEFAULTALL.
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   with the same STEP_NAME and message as the current step-50
--   checkpoint (v2 10-argument form; STEP_NO, row count, and work-table
--   arguments dropped). P_JOB_RUN_ID is present in every new proc in
--   this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_CRE_CARE_S50_KEYED (P_PHYSICAL_ADDR_TYPE_CD IN VARCHAR2 DEFAULT '002', P_RLE_BO_CLASS_CD_MEMBER IN VARCHAR2 DEFAULT 'Member', P_DEFAULT_TX_STATE_CD IN VARCHAR2 DEFAULT '48', P_COUNTY_CD_NONTX IN VARCHAR2 DEFAULT '996', P_COUNTYCD_DEFAULTALL IN VARCHAR2 DEFAULT '998', -- Live-compile fix: Snowflake forbids a required parameter after an
    -- optional one, so P_JOB_RUN_ID / P_RUN_TS carry DEFAULT NULL here.
    -- Drivers always pass all parameters positionally, so behaviour is unchanged.
    P_JOB_RUN_ID             VARCHAR DEFAULT NULL IN , P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_CRE_CARE_S4_FLAT') RETURN NUMBER AUTHID CURRENT_USER AS
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

    -- ---- Step 50: KEYED_ROUTES_GUARDS (verbatim from current main)
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_CRE_CARE_S5_KEYED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_CRE_CARE_S5_KEYED AS WITH
    keyed AS (
        SELECT f.*,
               /* EXP_PTY_RLE_ADDR_HOLD.out_COUNTY_CD */
               CASE WHEN f.a_state <> :1 THEN :2
                    WHEN f.a_county_fips IS NULL THEN :3
                    ELSE f.a_county_fips END                                           AS a_county,
               f.rle_key || '|' || :4                            AS addr_key,
               CASE WHEN f.care_alt_id IN ('U', 'N') = 1 THEN NULL ELSE f.care_alt_id END                   AS care_alt_val,
               CASE WHEN f.medicaid_alt_id IN ('U', 'N') = 1 THEN NULL ELSE f.medicaid_alt_id END           AS medicaid_alt_val,
               f.rle_key || '|' || NVL(f.care_tp_cd, '') || '|' || NVL(f.care_alt_id, '')         AS care_alt_key,
               f.rle_key || '|' || NVL(f.medicaid_tp_cd, '') || '|' || NVL(f.medicaid_alt_id, '') AS medicaid_alt_key,
               f.rle_key || '|' || NVL(f.ssn_tp_cd, '') || '|' || NVL(CASE WHEN f.ssn_out = 1 THEN 1 ELSE 0 END, '')              AS ssn_alt_key,
               CASE WHEN /* routes (every flag NVL'd: a NULL router condition does not route) */
               NOT f.grp_deletes = 1 AND NVL(CASE WHEN f.orig_rowid_object_desc = 'N' THEN 1 ELSE 0 END, 0) = 1 THEN 1 ELSE 0 END AS grp_mrg,
               CASE WHEN f.valid_member = 0 AND (f.fn_exception_code IS NOT NULL OR f.fn_exception_desc IS NOT NULL
                                       OR f.fn_exception_type IS NOT NULL) THEN 1 ELSE 0 END AS grp_first_name,
               CASE WHEN f.valid_member = 0 AND (f.ln_exception_code IS NOT NULL OR f.ln_exception_desc IS NOT NULL
                                       OR f.ln_exception_type IS NOT NULL) THEN 1 ELSE 0 END AS grp_last_name,
               CASE WHEN f.is_member = 1 AND f.gender_exception_description IS NOT NULL THEN 1 ELSE 0 END AS grp_gender,
               CASE WHEN f.is_member = 1 AND f.suffix_exception_code IS NOT NULL THEN 1 ELSE 0 END AS grp_suffix,
               CASE WHEN f.is_member = 1 AND f.ethnicity_exception_code IS NOT NULL THEN 1 ELSE 0 END AS grp_ethnicity,
               CASE WHEN f.is_member = 1 AND f.race_exception_code IS NOT NULL THEN 1 ELSE 0 END AS grp_race,
               CASE WHEN f.is_member = 1 AND f.addr_valid = 1 THEN 1 ELSE 0 END AS grp_addr,
               CASE WHEN f.is_member = 1 AND f.addr_valid = 0 THEN 1 ELSE 0 END AS grp_addr_exc,
               CASE WHEN f.is_member = 1 AND f.PHONE IS NOT NULL AND f.phone_exception_code IS NULL THEN 1 ELSE 0 END AS grp_phone,
               CASE WHEN f.is_member = 1 AND f.PHONE IS NOT NULL AND f.phone_exception_code IS NOT NULL THEN 1 ELSE 0 END AS grp_phone_exc,
               CASE WHEN f.is_member = 1 AND f.care_alt_id IS NOT NULL THEN 1 ELSE 0 END AS grp_care_alt,
               CASE WHEN f.is_member = 1 AND f.medicaid_alt_id IS NOT NULL AND f.medicaid_exception_code IS NULL THEN 1 ELSE 0 END AS grp_medicaid_alt,
               CASE WHEN f.is_member = 1 AND f.medicaid_alt_id IS NOT NULL AND f.medicaid_exception_code IS NOT NULL THEN 1 ELSE 0 END AS grp_medicaid_exc,
               CASE WHEN f.is_member = 1 AND f.ssn_out IS NOT NULL AND f.ssn_exception_code IS NULL THEN 1 ELSE 0 END AS grp_ssn_alt,
               CASE WHEN f.is_member = 1 AND f.ssn_out IS NOT NULL AND f.ssn_exception_code IS NOT NULL THEN 1 ELSE 0 END AS grp_ssn_exc
          FROM WRK_CRE_CARE_S4_FLAT f
    )
    SELECT k.*,
           'CRE'                                             AS src_sys,
           :5                                         AS run_ts,
           :6                                        AS mapping_name,
           'Indv'                                            AS pty_bo_class_cd,
           :7                         AS rle_bo_class_cd,
           :4                          AS addr_tp,
           'Payer'                                           AS hierarchy_code,
           'Primary'                                         AS pref_lvl,
           'Member Addr'                                     AS hm_rel_tp_cd,
           'US'                                              AS src_cntry,
           'Telephone'                                       AS phn_tp,
           '001'                                             AS usg_tp_phone,
           'Issued'                                          AS sts_cd,
           'First Name'                                      AS attr_first_name,
           'Last Name'                                       AS attr_last_name,
           'Gender'                                          AS attr_gender,
           'Name Suffix'                                     AS attr_suffix,
           'FEDETH'                                          AS attr_fedeth,
           'RACE'                                            AS attr_race,
           'Address'                                         AS attr_address,
           'Telephone'                                       AS attr_phone,
           CAST(NULL AS TIMESTAMP)                       AS null_timestamp,   -- TIMELINE: not linked
           CAST(NULL AS NUMBER)                              AS null_number,      -- TIMELINE: not linked
           /* BAD DATA: SRC_ROWID is 30 characters */
           LEFT(k.addr_key, 30)                              AS addr_src_rowid,
           LEFT(k.phn_key, 30)                               AS phn_src_rowid,
           LEFT(k.care_alt_key, 30)                          AS care_alt_src_rowid,
           LEFT(k.medicaid_alt_key, 30)                      AS medicaid_alt_src_rowid,
           LEFT(k.ssn_alt_key, 30)                           AS ssn_alt_src_rowid,
           CASE WHEN /* BAD DATA: unique keys Snowflake does not enforce */
           ROW_NUMBER() OVER (PARTITION BY k.grp_first_name, k.CARE_ID, k.fn_exception_type, k.fn_exception_code
                              ORDER BY k.REC_TYPE DESC) = 1 THEN 1 ELSE 0 END AS uq_first_name,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY k.grp_last_name, k.CARE_ID, k.ln_exception_type, k.ln_exception_code
                              ORDER BY k.REC_TYPE DESC) = 1 THEN 1 ELSE 0 END AS uq_last_name,
           CASE WHEN xpty.PKEY_SRC_OBJECT IS NULL THEN 1 ELSE 0 END AS uq_pty,
           CASE WHEN xrle.PKEY_SRC_OBJECT IS NULL THEN 1 ELSE 0 END AS uq_rle,
           CASE WHEN xadr.PKEY_SRC_OBJECT IS NULL THEN 1 ELSE 0 END AS uq_addr,
           CASE WHEN xphn.PKEY_SRC_OBJECT IS NULL THEN 1 ELSE 0 END AS uq_phone,
           CASE WHEN xca.PKEY_SRC_OBJECT IS NULL THEN 1 ELSE 0 END AS uq_care_alt,
           CASE WHEN xma.PKEY_SRC_OBJECT IS NULL THEN 1 ELSE 0 END AS uq_medicaid_alt,
           CASE WHEN xsa.PKEY_SRC_OBJECT IS NULL THEN 1 ELSE 0 END AS uq_ssn_alt,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY k.grp_medicaid_exc, k.mrg_care_id, k.medicaid_exception_type,
                                           k.medicaid_exception_code ORDER BY k.REC_TYPE DESC) = 1 THEN 1 ELSE 0 END AS uq_medicaid_exc,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY k.grp_ssn_exc, k.mrg_care_id, k.ssn_exception_type,
                                           k.ssn_exception_code ORDER BY k.REC_TYPE DESC) = 1 THEN 1 ELSE 0 END AS uq_ssn_exc
      FROM keyed k
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_CRE_PTY WHERE VERSION_SEQ = 1) xpty
             ON xpty.PKEY_SRC_OBJECT = k.pty_key
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_CRE_PTY_RLE WHERE VERSION_SEQ = 1) xrle
             ON xrle.PKEY_SRC_OBJECT = k.rle_key
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_CRE_PTY_RLE_ADDR WHERE VERSION_SEQ = 1) xadr
             ON xadr.PKEY_SRC_OBJECT = k.addr_key
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_CRE_PTY_RLE_PHN WHERE VERSION_SEQ = 1) xphn
             ON xphn.PKEY_SRC_OBJECT = k.phn_key
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_CRE_PTY_RLE_ALT_ID WHERE VERSION_SEQ = 1) xca
             ON xca.PKEY_SRC_OBJECT = k.care_alt_key
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_CRE_PTY_RLE_ALT_ID WHERE VERSION_SEQ = 1) xma
             ON xma.PKEY_SRC_OBJECT = k.medicaid_alt_key
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_CRE_PTY_RLE_ALT_ID WHERE VERSION_SEQ = 1) xsa
             ON xsa.PKEY_SRC_OBJECT = k.ssn_alt_key]' USING P_DEFAULT_TX_STATE_CD, P_COUNTY_CD_NONTX, P_COUNTYCD_DEFAULTALL, P_PHYSICAL_ADDR_TYPE_CD, P_RUN_TS, c_mapping, P_RLE_BO_CLASS_CD_MEMBER;
    SELECT COUNT(*) INTO l_rows FROM WRK_CRE_CARE_S5_KEYED;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'KEYED_ROUTES_GUARDS', 'COMPLETED', 'CRE_SRC_MRG, C_S_CRE_PTY, C_S_CRE_PTY_RLE, C_S_CRE_PTY_RLE_ADDR, C_S_CRE_PTY_RLE_PHN, C_S_CRE_PTY_RLE_ALT_ID, EXC_STG_BAD_REC_MEMB', 'Step 50 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_CRE_CARE_S50_KEYED;
/

