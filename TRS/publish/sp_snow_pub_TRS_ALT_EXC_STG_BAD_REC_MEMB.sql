-- ============================================================================
-- sp_snow_pub_TRS_ALT_EXC_STG_BAD_REC_MEMB  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_Alt_Id, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 60, driver checkpoint STEP_NAME PUBLISH_EXC_STG_BAD_REC_MEMB.
-- Target: EXC_STG_BAD_REC_MEMB. Kind: EXCEPTION (Invalid alt ids).
--
-- INPUTS
--   Reads ONLY WRK_TRS_ALT_S4_ROUTED (P_INPUT_TABLES default). The INSERT below may use
--   :P_RUN_TS (run timestamp) and :c_mapping (local constant) where
--   the original INSERT used :l_run_ts / :c_mapping; it uses original
--   parameters: none.
--
-- BUSINESS SQL
--   The INSERT below is the current publish-branch INSERT verbatim:
--   same columns, values and WHERE guard. No business expression,
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_ALT_EXC_STG_BAD_REC_MEMB (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_ALT_S4_ROUTED') RETURN NUMBER AUTHID CURRENT_USER AS
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_C_S_TRS_Pty_Rle_Alt_Id';
BEGIN
INSERT INTO EXC_STG_BAD_REC_MEMB
           (MAPPING_NAME, SRC_SYS, RUN_DATE, ATTRIBUTE_VALUE, ATTRIBUTE_NAME, EXCEPTION_DESC, EXCEPTION_CODE,
            EXCEPTION_TYPE, SRC_SYS_ID_1)
    SELECT c_mapping, src_sys, P_RUN_TS, alt_id_val, alt_id_label, dq_excp, dq_excp_cd, exc_type,
           pkey_src_object_pty
      FROM WRK_TRS_ALT_S4_ROUTED
     WHERE is_valid = 0 AND uq_exc = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_ALT_EXC_STG_BAD_REC_MEMB;
/

