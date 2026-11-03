-- ============================================================================
-- sp_snow_step_TRS_ALT_S40_ROUTED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_Alt_Id, workflow wf_TRS_Stage_Load_1_Ongoing, step 40.
-- Step name (checkpoint): ROUTED.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_ALT_S4_ROUTED: ROUTE -- translate type, drop nulls, flag rows
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (pipe-delimited). Default: 'WRK_TRS_ALT_S3_NORM'.
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-40 SELECT verbatim. Only
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
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_ALT_S40_ROUTED (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_ALT_S3_NORM') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TRS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_Alt_Id';
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
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_ALT_S4_ROUTED';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_ALT_S4_ROUTED AS WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common())),
    lkp_lcv AS (SELECT * FROM TABLE(fn_snow_helper45_common())),
    routed AS (
        SELECT n.PKEY_SRC_OBJECT_PTY AS pkey_src_object_pty, n.PERIOD_START_DATE AS period_start_date,
               n.ALT_ID_VAL AS alt_id_val, lb.MSTR_REF_CODE AS alt_id_typ, lb.MSTR_REF_LABEL AS alt_id_label,
               n.DQ_EXCP_CD AS dq_excp_cd, xd.EXCEPTION_DESC AS dq_excp, n.SRC_SYS AS src_sys, n.CV_IND AS cv_ind,
               NVL(n.PKEY_SRC_OBJECT_PTY, '') || '|Member|' || NVL(lb.MSTR_REF_CODE, '') || '|' || n.ALT_ID_VAL
                                                                                     AS pkey_src_object_alt_id,
               NVL(n.PKEY_SRC_OBJECT_PTY, '') || '|Member'                           AS pty_rle_fk,
               /* VALIDATION */ fn_snow_helper03_common(n.DQ_EXCP_CD)                AS is_valid
          FROM WRK_TRS_ALT_S3_NORM n
          LEFT JOIN lkp_lcv lb ON lb.CODE_TYPE = 'ALT_ID_TP' AND lb.MSTR_REF_CODE = n.ALT_ID_TYP = 1 AND lb.SRC_SYS = n.SRC_SYS
          LEFT JOIN lkp_exc xd ON xd.EXCEPTION_CODE = n.DQ_EXCP_CD
         /* BAD DATA: FLTR_Remove_Null_Alt_IDs: NOT ISNULL(ALT_ID_VAL) AND RTRIM(ALT_ID_VAL) <> '' */
         WHERE n.ALT_ID_VAL IS NOT NULL AND RTRIM(n.ALT_ID_VAL) <> ''
    )
    SELECT r.*,
           1 /* TIMELINE: exp_Rank.VERSION_SEQ hard-coded */                  AS version_seq,
           'Issued'                                                            AS sts_cd,
           'Bad Value'                                                         AS exc_type,
           /* BAD DATA: unique keys Snowflake does not enforce */
           (ROW_NUMBER() OVER (PARTITION BY r.is_valid, r.pkey_src_object_alt_id
                                   ORDER BY r.alt_id_typ NULLS LAST, r.period_start_date DESC) = 1
            AND xa.PKEY_SRC_OBJECT IS NULL)                                    AS uq_alt_id,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY r.is_valid, r.pkey_src_object_pty, r.dq_excp_cd
                                  ORDER BY r.alt_id_typ NULLS LAST) = 1 THEN 1 ELSE 0 END AS uq_exc
      FROM routed r
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TRS_PTY_RLE_ALT_ID WHERE VERSION_SEQ = 1) xa
             ON xa.PKEY_SRC_OBJECT = r.pkey_src_object_alt_id]';
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_ALT_S4_ROUTED;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'ROUTED', 'COMPLETED', NULL, 'Step 40 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_ALT_S40_ROUTED;
/

