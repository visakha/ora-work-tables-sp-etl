-- ============================================================================
-- sp_snow_pub_WIC_VAL_STG_WIC_PTY_INACTIVE_STS  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (WIC)
--
-- Mapping: m_Tgt_C_S_WIC_Pty_Validation, workflow wf_WIC_Stage_Load.
-- Publish branch STEP_NO 60, checkpoint STEP_NAME PUBLISH_STG_WIC_PTY_INACTIVE_STS.
-- Target: STG_WIC_PTY_INACTIVE_STS. Kind: STATUS (new deactivation-status rows).
-- Branch in original order; WHERE guard: name_missing AND deactivation_sts IS NULL.
--
-- INPUTS
--   Reads ONLY WRK_WIC_VAL_S30_ROUTED (P_INPUT_TABLES default). The INSERT reads the run_ts / mapping_name columns materialised in the final step; it references neither original parameter nor the run timestamp directly, so P_RUN_TS is carried for a uniform driver call signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch INSERT verbatim: same columns, values and WHERE guard. No business expression, filter, guard or column list was changed.
--
-- FRAMEWORK RULE
--   NO transaction control and NO checkpoint calls in this proc. The driver calls it inside ONE publish transaction (all branches together, so a publish either lands completely or not at all), COMMITs, and only then checkpoints this branch. Never call a checkpoint between BEGIN TRANSACTION and COMMIT.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_WIC_VAL_STG_WIC_PTY_INACTIVE_STS (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_WIC_VAL_S30_ROUTED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    INSERT INTO STG_WIC_PTY_INACTIVE_STS (SRC_KEY, ROWID_SYSTEM, DEACTIVATION_STS, DEACTIVATION_DT)
    SELECT PTY_SRC_KEY, src_sys, new_deactivation_sts, run_ts
      FROM WRK_WIC_VAL_S30_ROUTED
     WHERE name_missing = 1 AND deactivation_sts IS NULL;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_WIC_VAL_STG_WIC_PTY_INACTIVE_STS;
/

