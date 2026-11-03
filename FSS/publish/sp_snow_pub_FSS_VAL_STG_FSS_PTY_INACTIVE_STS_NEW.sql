-- ============================================================================
-- sp_snow_pub_FSS_VAL_STG_FSS_PTY_INACTIVE_STS_NEW  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (FSS)
--
-- Mapping: m_Tgt_C_S_FSS_Pty_Validation, workflow wf_FSS_Stage_Load.
-- Publish branch STEP_NO 70, checkpoint STEP_NAME PUBLISH_STS_NEW.
-- Target: STG_FSS_PTY_INACTIVE_STS. Kind: STATUS. New deactivation statuses.
-- Branch 3 of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_FSS_VAL_S3_ROUTED (P_INPUT_TABLES default). The INSERT references neither original parameter nor the run timestamp directly, so P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same
--   columns, values and WHERE guard (grp_deactivation AND deactivation_sts IS NULL). No business expression,
--   filter, guard or column list was changed.
--
-- FRAMEWORK RULE
--   NO transaction control and NO checkpoint calls in this proc. The
--   driver calls it inside ONE publish transaction (all branches
--   together, so a publish either lands completely or not at all),
--   COMMITs, and only then checkpoints this branch with the returned
--   row count. Never call a checkpoint between BEGIN TRANSACTION and
--   COMMIT.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_FSS_VAL_STG_FSS_PTY_INACTIVE_STS_NEW (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_FSS_VAL_S3_ROUTED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO STG_FSS_PTY_INACTIVE_STS (SRC_KEY, ROWID_SYSTEM, DEACTIVATION_STS, DEACTIVATION_DT)
    SELECT PTY_SRC_KEY, src_sys, new_deactivation_sts, run_ts
      FROM WRK_FSS_VAL_S3_ROUTED
     WHERE grp_deactivation = 1 AND deactivation_sts IS NULL;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_FSS_VAL_STG_FSS_PTY_INACTIVE_STS_NEW;
/

