-- ============================================================================
-- sp_snow_step_TRS_ALT_S10_SRC  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_Alt_Id, workflow wf_TRS_Stage_Load_1_Ongoing, step 10.
-- Step name (checkpoint): SRC_DEDUP.
--
-- WHAT THIS STEP PRODUCES
--   WRK_TRS_ALT_S1_SRC: SOURCE + DE-DUP (BR-22)
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only (pipe-delimited). Default: ''.
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the CTAS below still names its sources literally, as
--   in the current main procedure.
--
-- BUSINESS SQL
--   The CTAS below is the current step-10 SELECT verbatim. Only
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
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_ALT_S10_SRC (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT '') RETURN NUMBER AUTHID CURRENT_USER AS
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

    -- ---- Step 10: SRC_DEDUP (verbatim from current main)
BEGIN
        EXECUTE IMMEDIATE 'DROP TABLE WRK_TRS_ALT_S1_SRC';
    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE <> -942 THEN RAISE; END IF;
    END;
        EXECUTE IMMEDIATE q'[CREATE TABLE WRK_TRS_ALT_S1_SRC AS WITH
    all_indv AS (
        SELECT DISTINCT TO_CHAR(mci_indv.indv_id) AS pty_pkey, mci_indv.indv_id AS member_id,
               mci_indv.create_dt, mci_indv.ssn, '1' AS cv_ind
          FROM STG_TRS_D_CV_DC_MCI_INDV mci_indv
        UNION ALL
        SELECT DISTINCT TO_CHAR(indv.indv_id) || '|DC_INDV', indv.indv_id, indv.create_dt, indv.ssn, NULL
          FROM STG_TRS_D_DC_INDV indv
        UNION ALL
        SELECT DISTINCT TO_CHAR(mrg.old_indv_id), mrg.indv_id, mrg.create_dt, NULL, NULL
          FROM STG_TRS_D_CV_DC_MRG_SPRT_INDV mrg
         WHERE mrg.type_cd = 'ME'
    ),
    de_dup_indv AS (
        SELECT a.pty_pkey, TO_CHAR(a.member_id) AS member_id, a.create_dt AS start_dt, a.ssn, a.cv_ind,
               ROW_NUMBER() OVER (PARTITION BY a.pty_pkey
                                  ORDER BY LENGTH(TO_CHAR(a.ssn)) DESC NULLS LAST, a.create_dt DESC) AS key_rn
          FROM all_indv a
          JOIN STG_TRS_VALID_MEMBERS vm ON a.pty_pkey = vm.pty_pk
    )
    SELECT pty_pkey AS PTY_PKEY, member_id AS MEMBER_ID, start_dt AS START_DT, ssn AS SSN, cv_ind AS CV_IND
      FROM de_dup_indv
     WHERE key_rn = 1]';
    SELECT COUNT(*) INTO l_rows FROM WRK_TRS_ALT_S1_SRC;
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'SRC_DEDUP', 'COMPLETED', NULL, 'Step 10 complete.', NULL);
    RETURN l_rows;
END sp_snow_step_TRS_ALT_S10_SRC;
/

