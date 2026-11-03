-- ============================================================================
-- sp_snow_step_TRS_PTYDEACT_S50_NOTPERFORMED  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Deactivation_1, workflow wf_TRS_Stage_Load_1_Ongoing, step 50.
-- Step name (checkpoint): DELETE_VALID_STAGE_NOT_PERFORMED.
--
-- CHECKPOINT-ONLY STEP -- IT WRITES NO DATA.
--   This step exists so that the IDQ behaviour this mapping does NOT
--   reproduce stays visible in JOB_CONTROL_ETL instead of buried in a
--   code comment. IDQ Delete_Valid_Stage (DD_DELETE) deletes the
--   deactivated members from STG_TRS_VALID_MEMBERS (key PTY_PK).
--   Snowflake does NOT perform it: this code base never deletes,
--   truncates or drops target rows (rows are only inserted), so
--   deactivated members stay in the valid-member list. Re-adding the
--   delete is a business decision, not a silent fix. This proc writes
--   the step-50 checkpoint (10-argument form) and returns 0. It is
--   called by the driver AFTER the publish transaction has committed,
--   because the original step order is publish (40) then this record
--   (50). It consumes no work table, so its existence check is skipped.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_step_TRS_PTYDEACT_S50_NOTPERFORMED (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT '') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'TRS';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_TRS_Stage_Load_1_Ongoing';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_Deactivation_1';
BEGIN
    sp_etl_checkpoint(c_source, P_JOB_RUN_ID, c_workflow, c_mapping, 'WORKING',
        'DELETE_VALID_STAGE_NOT_PERFORMED', 'COMPLETED', 'STG_TRS_VALID_MEMBERS',
        'IDQ DD_DELETE of STG_TRS_VALID_MEMBERS deliberately NOT performed: insert-only Snowflake rule. Deactivated members remain in the valid-member list (parity gap -- see manifest).', NULL);
    RETURN 0;
END sp_snow_step_TRS_PTYDEACT_S50_NOTPERFORMED;
/

