-- ============================================================================
-- sp_etl_run_wf_CRE_Stage_Load_Ongoing  --  WORKFLOW RUNNER (app level)
--
-- Runs the Snowflake replacement for IDQ workflow wf_CRE_Stage_Load_Ongoing,
-- in the same order as the original run script.  The workflow has a
-- single mapping, so the runner makes a single mapping CALL:
--   * m_Tgt_C_S_CRE_CARE_Clients (loads CARE clients into CRE_SRC_MRG,
--     C_S_CRE_PTY, C_S_CRE_PTY_RLE, C_S_CRE_PTY_RLE_ADDR,
--     C_S_CRE_PTY_RLE_PHN and C_S_CRE_PTY_RLE_ALT_ID, plus exceptions).
-- The IDQ command task (touch <workflow>.ind) is left to the scheduler,
-- exactly as in the original run script.
--
-- HOW TO RUN IT
--   CALL sp_etl_run_wf_CRE_Stage_Load_Ongoing();
--   (A JOB_RUN_ID is generated and returned. Pass one explicitly only if
--   you want this workflow attempt recorded under a specific id.)
--
-- RESTARTING (mapping level only -- there is no step-level restart)
--   A restart is simply a new run: call the runner again with no run id
--   (or with a new one). The mapping, at its start (step 5), drops any
--   work tables the previous run left in the database, then runs every
--   step from scratch. Work tables are never dropped at the end of a
--   run, and the mapping is never skipped because it completed in an
--   earlier run -- a new run re-runs it.
--   Because the procedure is insert-only with unique-key guards, a
--   re-run inserts nothing twice; it does not undo what an earlier run
--   already published.
--
-- WHY THE RUNNER PASSES EVERY ORIGINAL PARAMETER EXPLICITLY
--   The mapping procedure appends P_JOB_RUN_ID AFTER its original
--   parameters, so the runner cannot call the mapping with only the run
--   id -- it would land in the wrong parameter. The runner therefore
--   passes the original defaults (taken from the procedure's header)
--   in full, every time, followed by the run id.
--
-- WHY THE RUNNER DOES NOT RETURN THE MAPPING'S SUMMARY
--   In Snowflake scripting, a CALL's return value cannot be assigned to
--   a variable as an expression, so the runner cannot collect the
--   mapping's summary string. It returns the JOB_RUN_ID and a short
--   status line instead; the full per-step story is in the shared
--   job-control table (query VW_ETL_JOB_STORY for the run id).
--   Standalone mapping CALLs DO return their summary -- use those when
--   you run the mapping by hand.
--
-- This runner is APP level in the boundary model: it owns the workflow
-- order, but it never writes to a target table itself and never drops a
-- work table.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_etl_run_wf_CRE_Stage_Load_Ongoing (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL) RETURN VARCHAR2 AUTHID CURRENT_USER AS
    c_workflow VARCHAR2(4000) DEFAULT 'wf_CRE_Stage_Load_Ongoing';
    c_source VARCHAR2(4000) DEFAULT 'CRE';
    l_job_run_id VARCHAR2(4000);
    l_dummy VARCHAR2(4000);
BEGIN
    IF (P_JOB_RUN_ID IS NULL OR P_JOB_RUN_ID = '') THEN
        l_job_run_id := 'CRE_WF_' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDD_HH24MISS')
                        || '_' || RAWTOHEX(SYS_GUID());
    ELSE
        l_job_run_id := P_JOB_RUN_ID;
    END IF;

    -- Workflow-level STARTING row (MAPPING_NAME = 'WORKFLOW').
    sp_etl_job_begin(c_source, c_workflow, 'WORKFLOW', l_job_run_id);

    -- 1. CARE clients (the workflow's only mapping).
    l_dummy := sp_snow_main_m_Tgt_C_S_CRE_CARE_Clients('002', 'Member', '48', '996', '998', '99', l_job_run_id);

    sp_etl_job_finish(c_source, l_job_run_id, c_workflow, 'WORKFLOW',
        'wf_CRE_Stage_Load_Ongoing completed. JOB_RUN_ID = ' || l_job_run_id
        || '. Per-step counts: SELECT * FROM VW_ETL_JOB_STORY WHERE JOB_RUN_ID = ''' || l_job_run_id || ''' ORDER BY EVENT_ID;');
    RETURN 'JOB_RUN_ID=' || l_job_run_id || ' STATUS=COMPLETED MAPPINGS=1. '
           || 'Per-step story: SELECT * FROM VW_ETL_JOB_STORY WHERE JOB_RUN_ID = ''' || l_job_run_id || ''' ORDER BY EVENT_ID;';
WHEN OTHERS THEN
        -- The failing mapping has already checkpointed its own FAILED
        -- row and left its work tables in place. This row records that
        -- the WORKFLOW stopped, so the next run starts cleanly from
        -- step 5 of the mapping (there is no step-level restart).
        sp_etl_job_fail(c_source, l_job_run_id, c_workflow, 'WORKFLOW',
            'wf_CRE_Stage_Load_Ongoing stopped at a mapping failure. Restart the workflow with a new run.');
        RAISE;
END sp_etl_run_wf_CRE_Stage_Load_Ongoing;
/

