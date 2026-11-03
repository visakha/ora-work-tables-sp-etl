-- ============================================================================
-- sp_snow_step_ECI_REL_S40_READY  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI ONLY)
--
-- Mapping: m_Tgt_C_S_ECI_Pty_Rle_Rel, workflow wf_ECI_Stage_Load.
-- Step 40, READY_TO_PUBLISH. Split out of
-- sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel; business SQL preserved verbatim
-- (the original built CTE plus the final SELECT, with its FROM pointed
-- at step 30 as now, including the target-table guard join, which still
-- sees the pre-run state because nothing has been published yet).
--
-- WHAT THIS STEP PRODUCES
--   WRK_ECI_REL_S40_READY: publish-ready relationships with the two
--   role keys and the relationship record key, exception details, and
--   the insert-only guards (uq_rel, uq_rel_exc).
-- FEEDS THE SPINE: yes -- directly. This is the publish input for
--   branch 50 (C_S_ECI_PTY_RLE_REL, spine) and branch 60
--   (EXC_STG_BAD_REC_MEMB, non-spine exception rows).
--
-- P_INPUT_TABLES NOTE (read before changing this proc)
--   P_INPUT_TABLES is a dependency declaration + runtime existence check,
--   NOT dynamic SQL. Snowflake cannot parameterise table names in static
--   SQL, so the CTAS below still names its tables directly, exactly as
--   the current main does. The check below only verifies that the
--   declared work-table inputs exist before the CTAS runs. It lists
--   WORK-TABLE inputs only; the exception-catalogue helper, the target
--   guard table (C_S_ECI_PTY_RLE_REL) and other non-work tables are not
--   work-table dependencies and are not listed or checked.
--
-- SUBSTITUTIONS vs the current main (only these; nothing else changed)
--   * :l_run_ts -> :P_RUN_TS (stamps run_ts, exactly as :l_run_ts did).
--   * :c_mapping -> local DECLARE constant with the same value (stamps
--     mapping_name, exactly as :c_mapping did).
--   * The step's own checkpoint, previously written inline in the main,
--     is written here with the same STEP_NAME, TARGET_TABLE, and message as the current step checkpoint (v2 10-argument form; STEP_NO, row count, and work-table arguments dropped).
--     NOTE: the TARGET_TABLE value is preserved verbatim as the combined
--     string 'C_S_ECI_PTY_RLE_REL, EXC_STG_BAD_REC_MEMB' from the
--     current main, even though publish is now split into branches
--     50/60 with their own checkpoints.
--
-- STYLE
--   TRANSIENT work table only, same name as now. No exception block
--   (errors propagate to the driver handler), no transactions, no target
--   writes. No drop checkpoint, no resume-step parameter, no row-by-row processing.
--
-- SIGNATURE
--   P_JOB_RUN_ID   VARCHAR                              -- workflow-level run id
--   P_RUN_TS       TIMESTAMP_NTZ                        -- run timestamp (driver's)
--   P_INPUT_TABLES VARCHAR DEFAULT 'WRK_ECI_REL_S30_TYPED'
-- RETURNS NUMBER (row count of the work table created).
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_ECI_REL_S40_READY (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_REL_S30_TYPED') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_ECI_Pty_Rle_Rel';
    l_rows NUMBER DEFAULT 0;
    l_missing VARCHAR2(4000);
    l_probe_sql VARCHAR2(4000);
    l_probe_dummy NUMBER;
BEGIN
    -- ---- Input existence check (skipped when P_INPUT_TABLES is NULL/empty)
    IF (P_INPUT_TABLES IS NOT NULL AND TRIM(P_INPUT_TABLES) <> '') THEN
        SELECT LISTAGG(UPPER(TRIM(tbl)), ', ') WITHIN GROUP (ORDER BY UPPER(TRIM(tbl))) INTO l_missing FROM (SELECT REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL) AS tbl FROM DUAL CONNECT BY REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL) IS NOT NULL) f WHERE NOT EXISTS (SELECT 1 FROM ALL_TABLES t WHERE t.OWNER = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AND t.TABLE_NAME = UPPER(TRIM(f.tbl)));
        IF (l_missing IS NOT NULL AND l_missing <> '') THEN
            l_probe_sql := 'SELECT COUNT(*) FROM ' || TRIM(REGEXP_SUBSTR(l_missing, '[^,]+', 1, 1));
            EXECUTE IMMEDIATE l_probe_sql INTO l_probe_dummy;
        END IF;
    END IF;

    -- ---- Step 40: READY -- keys, exception details, guards (verbatim from the main)
    -- Purpose: build the two role keys and the relationship record key,
    -- resolve the exception details, and apply the insert-only guards.
    -- Reads ONLY step 30. This is the original built CTE plus the final
    -- SELECT (including the target-table guard join, which still sees
    -- the pre-run state because nothing has been published yet).
    BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_ECI_REL_S40_READY';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_ECI_REL_S40_READY AS WITH
    built AS (
        SELECT t.*,
               CASE WHEN t.RELATION_DIRECTION = 'To Child' THEN t.family_pty_src_key ELSE t.child_pty_src_key END || '|Member'
                                                                                          AS rel_fk_1,
               CASE WHEN t.RELATION_DIRECTION = 'To Child' THEN t.child_pty_src_key ELSE t.family_pty_src_key END || '|Member'
                                                                                          AS rel_fk_2,
               CASE WHEN t.RELATION_DIRECTION = 'To Child' THEN t.family_pty_src_key ELSE t.child_pty_src_key END || '|Member|'
               || CASE WHEN t.RELATION_DIRECTION = 'To Child' THEN t.child_pty_src_key ELSE t.family_pty_src_key END || '|Member|'
               || NVL(t.mstr_ref_code, '')                                               AS rel_src_key
          FROM WRK_ECI_REL_S30_TYPED t
    )
    SELECT b.*,
           1 /* TIMELINE: VERSION_SEQ */                  AS version_seq,
           1                                              AS hub_state_ind,
           'Member Relationship'                          AS rel_type_code,
           'Member'                                       AS hierarchy_code,
           'ECI'                                          AS src_sys,
           :1                                      AS run_ts,
           :2                                     AS mapping_name,
           'FAMILY_CD'                                    AS attr_family_cd,
           ex.EXCEPTION_CODE                              AS exc_code,
           ex.EXCEPTION_DESC                              AS exc_desc,
           ex.EXCEPTION_TYPE                              AS exc_type,
           CASE WHEN (ROW_NUMBER() OVER (PARTITION BY b.mstr_ref_code IS NULL, b.rel_src_key
                                   ORDER BY b.DATE_MODIFIED DESC, b.ID_FAMILY) = 1
            AND xr.PKEY_SRC_OBJECT IS NULL) THEN 1 ELSE 0 END AS uq_rel,
           CASE WHEN ROW_NUMBER() OVER (PARTITION BY b.mstr_ref_code IS NULL, b.ID_FAMILY, b.ID_CHILD, b.rel_src_key
                                  ORDER BY b.DATE_MODIFIED DESC) = 1 THEN 1 ELSE 0 END AS uq_rel_exc
      FROM built b
      LEFT JOIN (SELECT * FROM TABLE(fn_snow_helper40_common())) ex ON ex.EXCEPTION_CODE = 'Invalid_Relationship'
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_ECI_PTY_RLE_REL WHERE VERSION_SEQ = 1) xr
             ON xr.PKEY_SRC_OBJECT = b.rel_src_key]' USING P_RUN_TS, c_mapping;
    SELECT COUNT(*) INTO l_rows FROM WRK_ECI_REL_S40_READY;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'READY_TO_PUBLISH', 'COMPLETED', 'C_S_ECI_PTY_RLE_REL, EXC_STG_BAD_REC_MEMB', 'Step 40 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_ECI_REL_S40_READY;
/

