-- ============================================================================
-- sp_snow_pub_ECI_PTY_C_S_ECI_PTY_RLE  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI)
--
-- Mapping: m_Tgt_C_S_ECI_Pty, workflow wf_ECI_Stage_Load.
-- Publish branch STEP_NO 70, checkpoint STEP_NAME PUBLISH_C_S_ECI_PTY_RLE.
-- Target: C_S_ECI_PTY_RLE. Kind: SPINE (valid roles).
-- Branch 60b of the original publish, in original order (second).
--
-- INPUTS
--   Reads ONLY WRK_ECI_PTY_S50_READY (P_INPUT_TABLES default). The
--   INSERT reads the run_ts column materialised in step 50; it
--   references neither original parameter nor the run timestamp
--   directly, so P_RUN_TS is carried for a uniform driver call
--   signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch-60b INSERT verbatim: same
--   columns, values and WHERE guard (uq_rle). No business expression,
--   filter, guard or column list was changed.
--
-- FRAMEWORK RULE
--   NO transaction control and NO checkpoint calls in this proc. The
--   driver calls it inside ONE publish transaction (all branches
--   together), COMMITs, and only then checkpoints this branch with the
--   returned row count. Never call a checkpoint between BEGIN
--   TRANSACTION and COMMIT.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_ECI_PTY_C_S_ECI_PTY_RLE (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_PTY_S50_READY') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    INSERT INTO C_S_ECI_PTY_RLE
           (PKEY_SRC_OBJECT, LAST_UPDATE_DATE, CREATOR, CREATE_DATE, VERSION_SEQ, PTY_FK, SRC_LAST_UPD_DT,
            RLE_BO_CLASS_CD, PERIOD_START_DATE, HUB_STATE_IND, SRC_ROWID)
    SELECT rle_pkey, run_ts, CREATED_BY, DATE_CREATED, version_seq, pkey_trim, DATE_MODIFIED,
           rle_bo_class_cd, DATE_CREATED, hub_state_ind, rle_pkey
      FROM WRK_ECI_PTY_S50_READY
     WHERE uq_rle = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_ECI_PTY_C_S_ECI_PTY_RLE;
/

