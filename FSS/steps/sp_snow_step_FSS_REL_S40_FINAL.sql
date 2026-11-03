-- ============================================================================
-- sp_snow_step_FSS_REL_S40_FINAL  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (FSS)
--
-- Mapping: m_Tgt_C_S_FSS_Pty_Rle_Rel, workflow wf_FSS_Stage_Load, step 40.
-- Step name (checkpoint): FINAL.
--
-- WHAT THIS STEP PRODUCES
--   WRK_FSS_REL_S4_FINAL: Relationship key, constants, exception details, insert-only guards.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (default: 'WRK_FSS_REL_S3_TYPED').
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
CREATE OR REPLACE FUNCTION sp_snow_step_FSS_REL_S40_FINAL (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_FSS_REL_S3_TYPED') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'FSS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_FSS_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_FSS_Pty_Rle_Rel';
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

    -- ---- Step 40: FINAL (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_FSS_REL_S4_FINAL';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_FSS_REL_S4_FINAL AS WITH
    lkp_exc AS (SELECT * FROM TABLE(fn_snow_helper40_common()))
    SELECT t.*,
           t.rel_fk_1 || '|' || t.rel_fk_2 || '|' || NVL(t.mstr_ref_code, '')  AS rel_pkey,
           1 /* TIMELINE: VERSION_SEQ */                                       AS version_seq,
           1                                                                    AS hub_state_ind,
           'Member Relationship'                                                AS rel_type_code,
           'Member'                                                             AS hierarchy_code,
           'batchload'                                                          AS batch_user,
           'FSS'                                                                AS src_sys,
           :1                                                            AS run_ts,
           :2                                                           AS mapping_name,
           'Relationship|Sex'                                                   AS attr_relationship,
           ex.EXCEPTION_CODE                                                    AS exc_code,
           ex.EXCEPTION_DESC                                                    AS exc_desc,
           ex.EXCEPTION_TYPE                                                    AS exc_type,
           /* BAD DATA: unique keys Snowflake does not enforce */
           (ROW_NUMBER() OVER (PARTITION BY t.mstr_ref_code IS NULL,
                                        t.rel_fk_1 || '|' || t.rel_fk_2 || '|' || NVL(t.mstr_ref_code, '')
                               ORDER BY t.RELN_DT_LAST_UPDATE DESC, t.ID_REGISTRATION) = 1
            AND xr.PKEY_SRC_OBJECT IS NULL)                                     AS uq_rel,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY t.mstr_ref_code IS NULL, t.RELN_ID_CLIENT, t.ID_CLIENT,
                                       t.ID_REGISTRATION ORDER BY t.RELN_DT_LAST_UPDATE DESC) = 1 THEN 1 ELSE 0 END AS uq_rel_exc
      FROM WRK_FSS_REL_S3_TYPED t
      LEFT JOIN lkp_exc ex ON ex.EXCEPTION_CODE = 'Invalid_Relationship'
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_FSS_PTY_RLE_REL WHERE VERSION_SEQ = 1) xr
             ON xr.PKEY_SRC_OBJECT = t.rel_fk_1 || '|' || t.rel_fk_2 || '|' || NVL(t.mstr_ref_code, '')]' USING P_RUN_TS, c_mapping;
    SELECT COUNT(*) INTO l_rows FROM WRK_FSS_REL_S4_FINAL;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'FINAL', 'COMPLETED', NULL, 'Step 40 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_FSS_REL_S40_FINAL;
/

