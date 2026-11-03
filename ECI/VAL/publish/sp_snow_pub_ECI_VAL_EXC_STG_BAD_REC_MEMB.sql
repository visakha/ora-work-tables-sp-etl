-- ============================================================================
-- sp_snow_pub_ECI_VAL_EXC_STG_BAD_REC_MEMB  --  CONFIG-DRIVEN STEP DRIVER
-- REFACTOR (ECI). Publish branch, STEP_NO 40 (first publish branch).
--
-- Mapping: m_Tgt_C_S_ECI_Pty_Validation, workflow wf_ECI_Stage_Load.
-- Target: EXC_STG_BAD_REC_MEMB. Branch: blank-name exceptions.
-- KIND: NON-SPINE. For THIS mapping the spine/status outcome is the
-- LOG/STS tables (branches 50/60/70); this EXC branch is the non-spine
-- branch -- it logs blank-name exceptions and does not carry party
-- deactivation state.
--
-- WHAT THIS BRANCH WRITES
--   One row per blank-name party, first row per exception key only
--   (grp_invalid_party_name AND uq_exc_name), with the exception
--   description/type resolved in step 30. This is branch 40a of the
--   current step-40 publish, verbatim: same columns, values and WHERE
--   guard. No business expression, filter, guard or column list was
--   changed.
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
--   is NOT used by the INSERT: run_ts and mapping_name are columns of
--   the routed table, stamped at step 30, and must not be re-stamped
--   here. P_JOB_RUN_ID is present in every new proc in this refactor.
--
-- FRAMEWORK RULE
--   NO transaction control and NO checkpoint calls in this proc. The
--   driver owns the publish transaction (BEGIN TRANSACTION ... COMMIT)
--   and checkpoints this branch only AFTER COMMIT, because a
--   checkpoint written inside the publish transaction would roll back
--   with it. This proc returns SQLROWCOUNT as NUMBER.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_ECI_VAL_EXC_STG_BAD_REC_MEMB (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_VAL_S30_ROUTED') RETURN NUMBER AUTHID CURRENT_USER AS
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_ECI_Pty_Validation';
BEGIN
    -- 40a. Invalid party name -> EXC_STG_BAD_REC_MEMB (verbatim from current main)
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE,
            FIRST_NAME, MIDDLE_NAME, LAST_NAME, BIRTH_DATE, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME,
            PERIOD_START_DATE)
    SELECT src_system, pkey_src_object, exc_code_name, exc_desc_name, exc_type_name, run_ts,
           std_first_name, std_mdl_name, std_lst_name, DOB, exc_attribute_name, exc_attribute_value,
           mapping_name, DATE_CREATED
      FROM WRK_ECI_VAL_S30_ROUTED
     WHERE grp_invalid_party_name = 1 AND uq_exc_name = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_ECI_VAL_EXC_STG_BAD_REC_MEMB;
/

