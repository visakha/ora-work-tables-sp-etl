WHENEVER SQLERROR EXIT FAILURE
-- ----------------------------------------------------------------------------
-- run_wf_TRS_Stage_Load_TOA.sql
--
-- SnowSQL entry point for the modular rewrite of wf_TRS_Stage_Load_TOA
-- (one mapping).  See run_wf_TRS_Stage_Load_1_Ongoing.sql for the
-- fresh-run / restart pattern: restarting is just running this script
-- again -- each mapping cleans up the previous run's WRK tables at its
-- start (step 5) and runs every step from scratch.
--
-- SnowSQL:  snowsql -c <connection> -f run_wf_TRS_Stage_Load_TOA.sql
-- ----------------------------------------------------------------------------

SELECT sp_etl_run_wf_TRS_Stage_Load_TOA() FROM DUAL;
