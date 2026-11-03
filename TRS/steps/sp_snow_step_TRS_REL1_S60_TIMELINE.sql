-- ============================================================================
-- sp_snow_step_TRS_REL1_S60_TIMELINE  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem, workflow wf_TRS_Stage_Load_1_Ongoing, step 60.
-- Step name (checkpoint): TIMELINE.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_REL1_S6_TIMELINE: TIMELINE -- versions, ranking, guards (BR-38)
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (pipe-delimited). Default: 'WRK_TRS_REL1_S5_PREP'.
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-60 SELECT verbatim. Only
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
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_REL1_S60_TIMELINE (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_REL1_S5_PREP') RETURN NUMBER AUTHID CURRENT_USER AS
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

    -- ---- Step 60: TIMELINE (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_REL1_S6_TIMELINE';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_REL1_S6_TIMELINE AS WITH
    versions AS (
        SELECT p.*, p.dst_end_date AS tl_period_end_date FROM WRK_TRS_REL1_S5_PREP p
        UNION ALL
        SELECT p.*, CAST(NULL AS TIMESTAMP) FROM WRK_TRS_REL1_S5_PREP p WHERE p.dst_end_date IS NOT NULL
    ),
    ranked AS (
        SELECT v.*,
               ROW_NUMBER() OVER (PARTITION BY v.pkey_src_object
                                  ORDER BY v.EFF_BEGIN_DT ASC NULLS LAST,
                                           v.tl_period_end_date DESC NULLS FIRST)       AS tl_version_seq
          FROM versions v
    )
    SELECT k.*,
           CASE WHEN k.tl_period_end_date IS NOT NULL THEN 2 ELSE NULL END                          AS tl_timeline_action,
           CASE WHEN k.tl_period_end_date IS NULL AND k.tl_version_seq = 1 THEN 1 ELSE NULL END     AS tl_hub_state_ind,
           CASE WHEN /* BAD DATA: unique key (PKEY_SRC_OBJECT, VERSION_SEQ) not yet in the table */
           xr.PKEY_SRC_OBJECT IS NULL THEN 1 ELSE 0 END AS uq_rel
      FROM ranked k
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT, VERSION_SEQ FROM C_S_TRS_PTY_RLE_REL) xr
             ON xr.PKEY_SRC_OBJECT = k.pkey_src_object = 1 AND xr.VERSION_SEQ = k.tl_version_seq]';
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_REL1_S6_TIMELINE;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'TIMELINE', 'COMPLETED', NULL, 'Step 60 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_REL1_S60_TIMELINE;
/

