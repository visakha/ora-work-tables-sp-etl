WHENEVER SQLERROR EXIT FAILURE
--------------------------------------------------------------------------------------------------------------------
-- run_wf_TTF_Stage_Load.sql - runs the Snowflake procedures that replace IDQ workflow wf_TTF_Stage_Load, via the
-- workflow runner procedure. The runner calls the four mappings in the original run-script order
-- (Pty_Validation, Pty, Pty_Rle_Alt_Id, Pty_Rle_Phn), passing one workflow JOB_RUN_ID to all of them.
-- exit_on_error stops the run at the first failure. The IDQ command task (touch <workflow>.ind) is left to the
-- scheduler, exactly as in the original run script.
--
-- Install schema: TTF_ETL_WRK in database MDM_ETL_TTF (all names unqualified in the procedures).
--
-- SnowSQL:  snowsql -c <connection> -f run_wf_TTF_Stage_Load.sql
--------------------------------------------------------------------------------------------------------------------

SELECT sp_etl_run_wf_TTF_Stage_Load() FROM DUAL;
