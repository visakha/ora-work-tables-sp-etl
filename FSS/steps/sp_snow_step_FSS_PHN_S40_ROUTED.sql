-- ============================================================================
-- sp_snow_step_FSS_PHN_S40_ROUTED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (FSS)
--
-- Mapping: m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr, workflow wf_FSS_Stage_Load, step 40.
-- Step name (checkpoint): ROUTED.
--
-- WHAT THIS STEP PRODUCES
--   WRK_FSS_PHN_S4_ROUTED: Exception details, good / bad groups for e-mail, phone and extension, insert-only guards.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (default: 'WRK_FSS_PHN_S3_CHECKED').
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
--   Original parameters used by this step: none; this step uses :P_RUN_TS (substituted from :l_run_ts).
--
-- FRAMEWORK
--   No exception block (errors propagate to the driver handler), no
--   transactions, no target writes. This proc writes its own checkpoint
--   in the v2 10-argument form (TARGET_TABLE NULL, as in the current
--   main's step checkpoints; row count survives in the RETURN value
--   and the driver's helper36 summary line).
--   P_JOB_RUN_ID is present in every new proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_FSS_PHN_S40_ROUTED (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_FSS_PHN_S3_CHECKED') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'FSS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_FSS_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr';
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

    -- ---- Step 40: ROUTED (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_FSS_PHN_S4_ROUTED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_FSS_PHN_S4_ROUTED AS WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    routed AS (
        SELECT c.*,
               xe.EXCEPTION_CODE  AS email_exception_code,
               xe.EXCEPTION_DESC  AS email_exception_desc,
               xe.EXCEPTION_TYPE  AS email_exception_type,
               xp.EXCEPTION_DESC  AS phone_exception_desc,
               xx.EXCEPTION_DESC  AS ext_exception_desc,
               CASE WHEN (c.ADDR_EMAIL IS NOT NULL AND xe.EXCEPTION_CODE IS NULL) THEN 1 ELSE 0 END AS grp_email_good,
               CASE WHEN (c.ADDR_EMAIL IS NOT NULL AND xe.EXCEPTION_CODE IS NOT NULL) THEN 1 ELSE 0 END AS grp_email_bad,
               CASE WHEN (c.NBR_PHONE IS NOT NULL AND c.phone_exception_code IS NULL) THEN 1 ELSE 0 END AS grp_phone_good,
               CASE WHEN (c.NBR_PHONE IS NOT NULL AND c.phone_exception_code IS NOT NULL) THEN 1 ELSE 0 END AS grp_phone_bad,
               CASE WHEN (c.NBR_PHONE IS NOT NULL AND c.ext_exception_code IS NOT NULL) THEN 1 ELSE 0 END AS grp_ext_bad
          FROM WRK_FSS_PHN_S3_CHECKED c
          LEFT JOIN lkp_exc xe ON xe.EXCEPTION_CODE = CAST(c.em.exception_code AS VARCHAR2(4000))
          LEFT JOIN lkp_exc xp ON xp.EXCEPTION_CODE = c.phone_exception_code
          LEFT JOIN lkp_exc xx ON xx.EXCEPTION_CODE = c.ext_exception_code
    )
    SELECT r.*,
           '1' /* TIMELINE: VERSION_SEQ */                          AS version_seq,
           1                                                         AS hub_state_ind,
           'FSS'                                                     AS src_sys,
           :1                                                 AS run_ts,
           :2                                                AS mapping_name,
           '001'                                                     AS eaddr_addr_tp,
           'Active'                                                  AS eaddr_sts_cd,
           'Y'                                                       AS eaddr_is_vld,
           'Telephone'                                               AS phn_tp,
           '001'                                                     AS usg_tp,
           'Primary'                                                 AS pref_lvl,
           /* BAD DATA: an invalid extension is blanked on the loaded phone */
           CASE WHEN r.ext_exception_code IS NULL THEN r.std_ext ELSE NULL END        AS phn_num_ext,
           'Email'                                                   AS attr_email,
           'Main Phone'                                              AS attr_phone,
           'Main Phone Ext'                                          AS attr_phone_ext,
           'Rejected Record'                                         AS exc_type_rejected,
           'Bad Value'                                               AS exc_type_bad_value,
           /* BAD DATA: unique keys Snowflake does not enforce */
           (ROW_NUMBER() OVER (PARTITION BY r.grp_email_good, r.eaddr_pkey
                                   ORDER BY r.DT_LAST_UPDATE DESC, r.ID_REGISTRATION_CLIENT) = 1
            AND xea.PKEY_SRC_OBJECT IS NULL)                         AS uq_eaddr,
           CASE WHEN (ROW_NUMBER() OVER (PARTITION BY r.grp_phone_good, r.phn_pkey
                                   ORDER BY r.DT_LAST_UPDATE DESC, r.ID_REGISTRATION_CLIENT) = 1
            AND xph.PKEY_SRC_OBJECT IS NULL) THEN 1 ELSE 0 END AS uq_phn,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.grp_email_bad, r.PTY_SRC_KEY, r.ID_REGISTRATION_CLIENT,
                                           r.email_exception_type, r.email_exception_code
                                  ORDER BY r.DT_LAST_UPDATE DESC) = 1 THEN 1 ELSE 0 END AS uq_email_exc,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.grp_phone_bad, r.PTY_SRC_KEY, r.ID_REGISTRATION_CLIENT,
                                           r.phone_exception_code ORDER BY r.DT_LAST_UPDATE DESC) = 1 THEN 1 ELSE 0 END AS uq_phone_exc,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.grp_ext_bad, r.PTY_SRC_KEY, r.ID_REGISTRATION_CLIENT,
                                           r.ext_exception_code ORDER BY r.DT_LAST_UPDATE DESC) = 1 THEN 1 ELSE 0 END AS uq_ext_exc
      FROM routed r
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_FSS_PTY_RLE_EADDR WHERE VERSION_SEQ = 1) xea
             ON xea.PKEY_SRC_OBJECT = r.eaddr_pkey
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_FSS_PTY_RLE_PHN WHERE VERSION_SEQ = 1) xph
             ON xph.PKEY_SRC_OBJECT = r.phn_pkey]' USING P_RUN_TS, c_mapping;
    SELECT COUNT(*) INTO l_rows FROM WRK_FSS_PHN_S4_ROUTED;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'ROUTED', 'COMPLETED', NULL, 'Step 40 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_FSS_PHN_S40_ROUTED;
/

