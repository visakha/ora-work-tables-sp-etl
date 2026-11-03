-- ============================================================================
-- 02_job_control_procs.sql  (multi-source)
--
-- The only procedures that write to JOB_CONTROL_ETL (shared, MDM_ETL_COMMON.COMMON).
-- Every call takes SOURCE first, so one control table serves all six sources.  Mapping
-- procedures never INSERT into the control table directly: they CALL
-- these, so the checkpoint format, the three states and the work-table
-- registry stay identical across every mapping, and a future change to
-- the log format is a change in one file, not fifteen.
--
-- v2 CHANGE (ECI step-driver example): sp_etl_checkpoint now takes 10
-- positional parameters (see below).  Dropped versus v1: STEP_NO,
-- ROW_COUNT, SOURCE_ROW_COUNT, WORK_TABLE_NAME, WORK_TABLE_ACTION,
-- WORK_TABLE_PURPOSE, DROP_REASON.  This is a LOSSY simplification by
-- design: per-step row counts and work-table registry entries no longer
-- land in JOB_CONTROL_ETL from checkpoint rows.  Row counts survive in
-- each procedure's RETURN summary (fn_snow_helper36_common lines);
-- step identity is by STEP_NAME; run ordering is by EVENT_ID.
-- sp_etl_job_begin / _finish / _fail are UNCHANGED and still write
-- STEP_NO 0 / 999 directly.
--
-- TRANSACTION RULE (read this before changing anything):
--   These procedures contain a single INSERT and no transaction control.
--   Called from a mapping procedure that is NOT inside an explicit
--   transaction, that INSERT autocommits immediately -- which is exactly
--   what self-healing needs: the checkpoint survives a later rollback.
--   Called from inside a publish transaction, it would roll back with
--   that transaction -- which is why mapping procedures are written as:
--     steps (autocommitted) -> checkpoints -> ONE publish transaction
--     -> COMMIT -> terminating checkpoint.  Never call a checkpoint
--   between BEGIN TRANSACTION and COMMIT inside a mapping.
--
-- RETURN VALUES
--   sp_etl_job_begin returns the JOB_RUN_ID to use for the whole run.
--   The other procedures return a short 'OK' string; callers ignore it
--   except in ad-hoc use.  (Snowflake SQL procedures are called as
--   statements, so mapping code CALLs them and does not assign their
--   result -- the run id is generated locally where it is needed, see
--   the template in 02_mappings.)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- sp_etl_job_begin
--   Starts a run.  If P_JOB_RUN_ID is NULL, a new id is generated and
--   returned; if one is supplied (a workflow runner passing its run id,
--   or an operator running one mapping under a specific run id), that id
--   is used.  Writes the STARTING row (STEP_NO 0).  Every run is a new
--   run: there is no resume mode, and a restart is simply a new run id.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_etl_job_begin (P_SOURCE IN VARCHAR2, P_WORKFLOW_NAME IN VARCHAR2, P_MAPPING_NAME IN VARCHAR2, P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL) AUTHID CURRENT_USER AS
    l_job_run_id VARCHAR2(4000) DEFAULT P_JOB_RUN_ID;
BEGIN
    IF (l_job_run_id IS NULL OR l_job_run_id = '') THEN
        l_job_run_id := P_SOURCE || '_' || TO_CHAR(SYSTIMESTAMP, 'YYYYMMDD_HH24MISS')
                        || '_' || RAWTOHEX(SYS_GUID());
    END IF;

    INSERT INTO COMMON.JOB_CONTROL_ETL
           (JOB_RUN_ID, SOURCE, WORKFLOW_NAME, MAPPING_NAME, STATE, STEP_NO, STEP_NAME,
            STEP_STATUS, WORK_TABLE_ACTION, MESSAGE)
    VALUES (l_job_run_id, P_SOURCE, P_WORKFLOW_NAME, P_MAPPING_NAME, 'STARTING', 0,
            'JOB_BEGIN', 'STARTED', 'NONE',
            'Job started. Work tables for this run '
            || 'will be registered here step by step; see VW_ETL_JOB_STORY.');

    RETURN;
END sp_etl_job_begin;
/


-- ----------------------------------------------------------------------------
-- sp_etl_checkpoint  (v2: 10 parameters, all positional)
--   The one checkpoint writer.  The first seven parameters are required;
--   the last three default to NULL.  Deliberately dropped versus v1:
--   STEP_NO, ROW_COUNT, SOURCE_ROW_COUNT, WORK_TABLE_NAME,
--   WORK_TABLE_ACTION, WORK_TABLE_PURPOSE, DROP_REASON.  This is a LOSSY
--   simplification by design (see the file header): per-step row counts
--   and work-table registry entries no longer land in JOB_CONTROL_ETL
--   from checkpoint rows.  The dropped table columns are RETAINED (see
--   01_job_control_ddl.sql): this procedure inserts NULL into them,
--   except WORK_TABLE_ACTION, which is NOT NULL and therefore takes its
--   column DEFAULT 'NONE' (meaning "no work-table action recorded", not
--   a recorded action).  STEP_NO is nullable in v2, so checkpoint rows
--   carry NULL there; sp_etl_job_begin / _finish / _fail still write
--   0 / 999 directly.  STATE must be 'STARTING', 'WORKING' or
--   'TERMINATING'.  STEP_STATUS is STARTED | COMPLETED | FAILED |
--   SKIPPED (SKIPPED rows are written by drivers for steps/branches
--   disabled in ETL_RUN_CONFIG_TBL).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_etl_checkpoint (P_SOURCE IN VARCHAR2, P_JOB_RUN_ID IN VARCHAR2, P_WORKFLOW_NAME IN VARCHAR2, P_MAPPING_NAME IN VARCHAR2, P_STATE IN VARCHAR2, -- STARTING | WORKING | TERMINATING
    P_STEP_NAME     VARCHAR IN , P_STEP_STATUS IN VARCHAR2, -- STARTED | COMPLETED | FAILED | SKIPPED
    P_TARGET_TABLE  VARCHAR DEFAULT NULL IN , P_MESSAGE IN VARCHAR2 DEFAULT NULL, P_ERROR_MESSAGE IN VARCHAR2 DEFAULT NULL) AUTHID CURRENT_USER AS
BEGIN
    INSERT INTO COMMON.JOB_CONTROL_ETL
           (JOB_RUN_ID, SOURCE, WORKFLOW_NAME, MAPPING_NAME, STATE, STEP_NAME,
            STEP_STATUS, TARGET_TABLE, MESSAGE, ERROR_MESSAGE)
    VALUES (P_JOB_RUN_ID, P_SOURCE, P_WORKFLOW_NAME, P_MAPPING_NAME, P_STATE,
            P_STEP_NAME, P_STEP_STATUS, P_TARGET_TABLE,
            P_MESSAGE, P_ERROR_MESSAGE);

    RETURN;
END sp_etl_checkpoint;
/


-- ----------------------------------------------------------------------------
-- sp_etl_job_finish  (TERMINATING / COMPLETED)
--   Call AFTER the publish transaction has committed.  Work tables are
--   NOT dropped at the end of a run -- they stay in the database until
--   the next run of the mapping cleans them up at its start (step 5).
--   This row is the run's final terminating state: a reviewer can tell
--   a completed run from an interrupted one by the presence of this row.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_etl_job_finish (P_SOURCE IN VARCHAR2, P_JOB_RUN_ID IN VARCHAR2, P_WORKFLOW_NAME IN VARCHAR2, P_MAPPING_NAME IN VARCHAR2, P_MESSAGE IN VARCHAR2 DEFAULT NULL) AUTHID CURRENT_USER AS
BEGIN
    INSERT INTO COMMON.JOB_CONTROL_ETL
           (JOB_RUN_ID, SOURCE, WORKFLOW_NAME, MAPPING_NAME, STATE, STEP_NO, STEP_NAME,
            STEP_STATUS, WORK_TABLE_ACTION, MESSAGE)
    VALUES (P_JOB_RUN_ID, P_SOURCE, P_WORKFLOW_NAME, P_MAPPING_NAME, 'TERMINATING',
            999, 'JOB_END', 'COMPLETED', 'NONE',
            COALESCE(P_MESSAGE,
                     'Job completed. Final targets published; work tables left in place '
                     || 'until the next run of this mapping cleans them up at its start. '
                     || 'See VW_ETL_JOB_STORY for the step-by-step counts.'));

    RETURN;
END sp_etl_job_finish;
/


-- ----------------------------------------------------------------------------
-- sp_etl_job_fail  (TERMINATING / FAILED)
--   Call from an exception handler AFTER any rollback, so that this row
--   itself is not rolled back.  It deliberately does NOT drop work
--   tables: on failure the work tables are KEPT (that is the point --
--   inspect them, fix the cause, then restart the mapping with a new
--   run; its step-5 cleanup will drop them).  The handler in each mapping
--   also writes a FAILED row before calling this; work tables stay in
--   place (see INFORMATION_SCHEMA.TABLES for WRK_% tables).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE sp_etl_job_fail (P_SOURCE IN VARCHAR2, P_JOB_RUN_ID IN VARCHAR2, P_WORKFLOW_NAME IN VARCHAR2, P_MAPPING_NAME IN VARCHAR2, P_ERROR_MESSAGE IN VARCHAR2 DEFAULT NULL) AUTHID CURRENT_USER AS
BEGIN
    INSERT INTO COMMON.JOB_CONTROL_ETL
           (JOB_RUN_ID, SOURCE, WORKFLOW_NAME, MAPPING_NAME, STATE, STEP_NO, STEP_NAME,
            STEP_STATUS, WORK_TABLE_ACTION, ERROR_MESSAGE, MESSAGE)
    VALUES (P_JOB_RUN_ID, P_SOURCE, P_WORKFLOW_NAME, P_MAPPING_NAME, 'TERMINATING',
            999, 'JOB_END', 'FAILED', 'NONE', P_ERROR_MESSAGE,
            'Job failed. Work tables KEPT for inspection; nothing '
            || 'was dropped. Query ALL_TABLES for WRK_% tables in this schema, '
            || 'fix the cause, then restart the mapping with a new run.');

    RETURN;
END sp_etl_job_fail;
/


-- ----------------------------------------------------------------------------
