-- ============================================================================
-- sp_etl_run_wf_TRS_Stage_Load_TOA  --  WORKFLOW RUNNER (app level)
--
-- Runs the Snowflake replacement for IDQ workflow wf_TRS_Stage_Load_TOA:
-- one mapping, m_Tgt_C_S_TRS_Stg_TOA, which loads the TOA reference
-- catalogue into C_S_LU_TOA (BR-51).  No gateway, no indicator file,
-- exactly as in the original workflow.
--
--   CALL sp_etl_run_wf_TRS_Stage_Load_TOA();
--
-- Restarting is mapping level only: a restart is simply a new run, and
-- the mapping cleans up the previous run's work tables at its start
-- (step 5) before running every step from scratch. See the ongoing
-- runner's header for the full explanation.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_etl_run_wf_TRS_Stage_Load_TOA (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 AUTHID CURRENT_USER AS
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TRS_Stage_Load_TOA';
    c_source VARCHAR2(4000) DEFAULT 'TRS';
    l_job_run_id VARCHAR2(4000);
    l_dummy VARCHAR2(4000);
BEGIN
    IF (P_JOB_RUN_ID IS NULL OR P_JOB_RUN_ID = '') THEN
        l_job_run_id := 'TRS_WF_' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDD_HH24MISS')
                        || '_' || RAWTOHEX(SYS_GUID());
    ELSE
        l_job_run_id := P_JOB_RUN_ID;
    END IF;

    sp_etl_job_begin(c_source, c_workflow, 'WORKFLOW', l_job_run_id);

    l_dummy := sp_snow_main_m_Tgt_C_S_TRS_Stg_TOA(l_job_run_id);

    sp_etl_job_finish(c_source, l_job_run_id, c_workflow, 'WORKFLOW',
        'wf_TRS_Stage_Load_TOA completed. JOB_RUN_ID = ' || l_job_run_id);
    RETURN 'JOB_RUN_ID=' || l_job_run_id || ' STATUS=COMPLETED MAPPINGS=1. '
           || 'Per-step story: SELECT * FROM VW_ETL_JOB_STORY WHERE JOB_RUN_ID = ''' || l_job_run_id || ''' ORDER BY EVENT_ID;';
WHEN OTHERS THEN
        sp_etl_job_fail(c_source, l_job_run_id, c_workflow, 'WORKFLOW',
            'wf_TRS_Stage_Load_TOA stopped at a mapping failure. Restart the workflow with a new run.');
        RAISE;
END sp_etl_run_wf_TRS_Stage_Load_TOA;
/

