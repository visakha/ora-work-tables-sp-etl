WHENEVER SQLERROR EXIT FAILURE
-- ----------------------------------------------------------------------------
-- run_wf_FSS_Stage_Load.sql
--
-- SnowSQL entry point for the modular rewrite of wf_FSS_Stage_Load.
-- This REPLACES the original run script's 6 CALL lines with one runner
-- CALL.  If your scheduler / CLI parses the old script looking for one
-- "CALL sp_snow_main_<mapping>();" per line, it must be updated to this
-- single runner CALL.
-- The IDQ command task (touch <workflow>.ind) is still left to the
-- scheduler, exactly as before.
--
-- SnowSQL:  snowsql -c <connection> -f run_wf_FSS_Stage_Load.sql
--
-- Restarting: just run this script again. There is no step-level
-- restart and no resume call -- each mapping cleans up the previous
-- run's WRK tables at its start (step 5) and runs every step from
-- scratch. A restart is always a new JOB_RUN_ID.
--
-- Install schema is FSS_ETL_WRK in database MDM_ETL_FSS.
-- ----------------------------------------------------------------------------

SELECT sp_etl_run_wf_FSS_Stage_Load() FROM DUAL;
