-- ============================================================================
-- sp_snow_pub_ECI_REL_C_S_ECI_PTY_RLE_REL  --  CONFIG-DRIVEN STEP DRIVER
-- REFACTOR (ECI ONLY)
--
-- Mapping: m_Tgt_C_S_ECI_Pty_Rle_Rel, workflow wf_ECI_Stage_Load.
-- Publish branch STEP_NO 50 (first publish branch, in original order).
--
-- TARGET: C_S_ECI_PTY_RLE_REL
-- KIND: SPINE -- this is the relationship-spine branch. Valid (translated)
--   relationships land here.
--
-- WHAT THIS PROC DOES
--   The first INSERT of the current main's step-50 publish, verbatim:
--   same columns, values and WHERE guards (mstr_ref_code IS NOT NULL
--   AND uq_rel), reading WRK_ECI_REL_S40_READY. Insert-only, as in the
--   original: no TRUNCATE, no DELETE.
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
CREATE OR REPLACE FUNCTION sp_snow_pub_ECI_REL_C_S_ECI_PTY_RLE_REL (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_REL_S40_READY') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    -- 50a. Valid relationships -> C_S_ECI_PTY_RLE_REL (verbatim from the main)
    INSERT INTO C_S_ECI_PTY_RLE_REL
           (PTY_RLE_FK_1, PTY_RLE_FK_2, PKEY_SRC_OBJECT, VERSION_SEQ, SRC_ROWID, HUB_STATE_IND, REL_TYPE_CODE,
            HIERARCHY_CODE, REL_TP, SRC_LAST_UPD_DT, LAST_UPDATE_DATE, UPDATED_BY, CREATE_DATE, CREATOR,
            PERIOD_START_DATE)
    SELECT rel_fk_1, rel_fk_2, rel_src_key, version_seq, rel_src_key, hub_state_ind, rel_type_code,
           hierarchy_code, mstr_ref_code, DATE_MODIFIED, run_ts, mapping_name, DATE_MODIFIED, mapping_name,
           DATE_CREATED
      FROM WRK_ECI_REL_S40_READY
     WHERE mstr_ref_code IS NOT NULL AND uq_rel = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_ECI_REL_C_S_ECI_PTY_RLE_REL;
/

