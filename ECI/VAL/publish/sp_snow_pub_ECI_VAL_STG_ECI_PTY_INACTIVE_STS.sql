-- ============================================================================
-- sp_snow_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_STS  --  CONFIG-DRIVEN STEP DRIVER
-- REFACTOR (ECI). Publish branch, STEP_NO 60.
--
-- Mapping: m_Tgt_C_S_ECI_Pty_Validation, workflow wf_ECI_Stage_Load.
-- Target: STG_ECI_PTY_INACTIVE_STS. Branch: new deactivation status
-- rows (parties with no status yet).
-- KIND: STATUS (spine/status path). For THIS mapping the LOG/STS
-- tables ARE the spine/status outcome: this branch writes the status
-- row that marks a party deactivated for every later ECI mapping, so
-- it is the status/state-tracking write the user cares about.
--
-- WHAT THIS BRANCH WRITES
--   One status row per deactivation candidate that has no status yet
--   (grp_deactivation AND deactivation_sts IS NULL), with the new
--   status derived from the hub state in step 30. This is branch 40c
--   of the current step-40 publish, verbatim: same columns, values
--   and WHERE guard. No business expression, filter, guard or column
--   list was changed.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES declares the work-table input, default
--   'WRK_ECI_VAL_S30_ROUTED'. The INSERT below reads that fixed
--   work-table name literally, as in the current main procedure:
--   Snowflake cannot parameterise table names in static SQL, so the
--   parameter is a dependency declaration, NOT dynamic SQL. NOTE:
--   unlike the step procs, this publish proc does NOT runtime-check
--   P_INPUT_TABLES -- a missing routed table surfaces as the native
--   object-not-exists error on the INSERT itself. That matches the
--   publish-proc spec for this refactor; adding the step-style
--   existence check here is a one-block change if the user wants it.
--   P_RUN_TS is likewise declared for a uniform driver-call shape but
--   is NOT used by the INSERT: the status timestamp is the routed
--   table's run_ts column, stamped at step 30, and must not be
--   re-stamped here. P_JOB_RUN_ID is present in every new proc in
--   this refactor.
--
-- FRAMEWORK RULE
--   NO transaction control and NO checkpoint calls in this proc. The
--   driver owns the publish transaction (BEGIN TRANSACTION ... COMMIT)
--   and checkpoints this branch only AFTER COMMIT, because a
--   checkpoint written inside the publish transaction would roll back
--   with it. This proc returns SQLROWCOUNT as NUMBER.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_STS (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_VAL_S30_ROUTED') RETURN NUMBER AUTHID CURRENT_USER AS
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_ECI_Pty_Validation';
BEGIN
    -- 40c. New deactivations (no status yet) -> STG_ECI_PTY_INACTIVE_STS (verbatim from current main)
    INSERT INTO STG_ECI_PTY_INACTIVE_STS (SRC_KEY, ROWID_SYSTEM, DEACTIVATION_STS, DEACTIVATION_DT)
    SELECT pkey_src_object, src_system, new_deactivation_sts, run_ts
      FROM WRK_ECI_VAL_S30_ROUTED
     WHERE grp_deactivation = 1 AND deactivation_sts IS NULL;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_STS;
/

