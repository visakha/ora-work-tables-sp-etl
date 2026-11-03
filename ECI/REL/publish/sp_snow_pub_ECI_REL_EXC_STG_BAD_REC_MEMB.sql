-- ============================================================================
-- sp_snow_pub_ECI_REL_EXC_STG_BAD_REC_MEMB  --  CONFIG-DRIVEN STEP DRIVER
-- REFACTOR (ECI ONLY)
--
-- Mapping: m_Tgt_C_S_ECI_Pty_Rle_Rel, workflow wf_ECI_Stage_Load.
-- Publish branch STEP_NO 60 (second publish branch, in original order).
-- The current main numbers its whole publish step 50; this branch is
-- numbered 60 here so each publish branch has its own checkpoint
-- STEP_NO, per the driver-refactor spec (branches in original order:
-- 50 spine, then 60 non-spine).
--
-- TARGET: EXC_STG_BAD_REC_MEMB
-- KIND: NON-SPINE -- this is the exception-logging branch. A relationship
--   whose code does not translate is not loaded, only logged here.
--
-- WHAT THIS PROC DOES
--   The second INSERT of the current main's step-50 publish, verbatim:
--   same columns, values and WHERE guards (mstr_ref_code IS NULL
--   AND uq_rel_exc), reading WRK_ECI_REL_S40_READY. Insert-only, as in
--   the original: no TRUNCATE, no DELETE. Preserved quirk: the exception
--   row's key SRC_SYS_ID_3 ends in '|' (the master code is NULL; IDQ
--   concatenates NULL as ''), and the exception code is the catalogue
--   lookup result from step 40 (NULL when 'Invalid_Relationship' is
--   not configured).
--
-- FRAMEWORK RULE (read before changing this proc)
--   NO transaction control and NO checkpoint calls in this proc. The
--   driver opens the publish transaction, calls this proc, COMMITs, and
--   only THEN checkpoints the branch. A checkpoint written between
--   BEGIN TRANSACTION and COMMIT would roll back with the publish, so
--   it must live in the driver, after COMMIT.
--
-- SUBSTITUTIONS vs the current main
--   None needed in this branch: the INSERT carries run_ts and
--   mapping_name via the WRK_ECI_REL_S40_READY columns (stamped by step
--   40), not via :l_run_ts / :c_mapping variables, so there is no
--   mapping-name reference to re-house. P_RUN_TS is accepted for a
--   uniform publish signature and is unused here, by design.
--   P_INPUT_TABLES is the dependency declaration for this branch
--   ('WRK_ECI_REL_S40_READY'); this proc does not run an existence
--   check on it (per the publish-branch spec) -- a missing S40 table
--   surfaces as the native object-not-exists error on the INSERT, and
--   the driver's exception handler rolls the publish back.
--
-- SIGNATURE
--   P_JOB_RUN_ID   VARCHAR                              -- workflow-level run id
--   P_RUN_TS       TIMESTAMP_NTZ                        -- run timestamp (driver's; unused here)
--   P_INPUT_TABLES VARCHAR DEFAULT 'WRK_ECI_REL_S40_READY'
-- RETURNS NUMBER (SQLROWCOUNT of the INSERT).
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_ECI_REL_EXC_STG_BAD_REC_MEMB (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_REL_S40_READY') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    -- 50b. Relationship exceptions -> EXC_STG_BAD_REC_MEMB (verbatim from the main)
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, SRC_SYS_ID_2, SRC_SYS_ID_3, RUN_DATE, MAPPING_NAME, ATTRIBUTE_NAME,
            PERIOD_START_DATE, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, ATTRIBUTE_VALUE)
    SELECT src_sys, ID_FAMILY, ID_CHILD, rel_src_key, run_ts, mapping_name, attr_family_cd, DATE_CREATED,
           exc_type, exc_code, exc_desc, rel_family_cd
      FROM WRK_ECI_REL_S40_READY
     WHERE mstr_ref_code IS NULL AND uq_rel_exc = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_ECI_REL_EXC_STG_BAD_REC_MEMB;
/

