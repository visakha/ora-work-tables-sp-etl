WHENEVER SQLERROR EXIT FAILURE
-- ----------------------------------------------------------------------------
-- run_wf_TRS_Stage_Load_1_Ongoing.sql
--
-- SnowSQL entry point for the modular rewrite of wf_TRS_Stage_Load_1_Ongoing.
-- This REPLACES the original run script's 14 CALL lines with one runner
-- CALL.  If your scheduler / CLI parses the old script looking for one
-- "CALL sp_snow_main_<mapping>();" per line, it must be updated to this
-- single runner CALL (see the User Guide, "Migrating the scheduler").
-- The IDQ command task (touch <workflow>.ind) is still left to the
-- scheduler, exactly as before.
--
-- SnowSQL:  snowsql -c <connection> -f run_wf_TRS_Stage_Load_1_Ongoing.sql
--
-- Restarting: just run this script again. There is no step-level
-- restart and no resume call -- each mapping cleans up the previous
-- run's WRK tables at its start (step 5) and runs every step from
-- scratch. A restart is always a new JOB_RUN_ID.
-- ----------------------------------------------------------------------------

SELECT sp_etl_run_wf_TRS_Stage_Load_1_Ongoing() FROM DUAL;
