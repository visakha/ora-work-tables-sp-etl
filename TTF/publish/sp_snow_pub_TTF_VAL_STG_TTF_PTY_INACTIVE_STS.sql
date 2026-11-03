-- ============================================================================
-- sp_snow_pub_TTF_VAL_STG_TTF_PTY_INACTIVE_STS  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TTF)
--
-- Mapping: m_Tgt_C_S_TTF_Pty_Validation, workflow wf_TTF_Stage_Load.
-- Publish branch STEP_NO 60. Target: STG_TTF_PTY_INACTIVE_STS. Kind: STATUS (new deactivation status rows).
-- Branch 60 of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_TTF_VAL_S3_ROUTED (P_INPUT_TABLES default). It references neither original parameter nor the run timestamp directly (it reads the run_ts / mapping_name columns materialised in the final routed table), so P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same
--   columns, values and WHERE guard. No business expression, filter,
--   guard or column list was changed.
--
-- FRAMEWORK RULE
--   NO transaction control and NO checkpoint calls in this proc. The
--   driver calls it inside ONE publish transaction (all branches
--   together, so a publish either lands completely or not at all),
--   COMMITs, and only then checkpoints this branch with the returned
--   row count. Never call a checkpoint between BEGIN TRANSACTION and
--   COMMIT.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_TTF_VAL_STG_TTF_PTY_INACTIVE_STS (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TTF_VAL_S3_ROUTED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO STG_TTF_PTY_INACTIVE_STS (SRC_KEY, ROWID_SYSTEM, DEACTIVATION_STS, DEACTIVATION_DT)
    SELECT pkey_src_object, src_sys, new_deactivation_sts, run_ts
      FROM WRK_TTF_VAL_S3_ROUTED
     WHERE grp_deactivation = 1 AND deactivation_sts IS NULL;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TTF_VAL_STG_TTF_PTY_INACTIVE_STS;
/

