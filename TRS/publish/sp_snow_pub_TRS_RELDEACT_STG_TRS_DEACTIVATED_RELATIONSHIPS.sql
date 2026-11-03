-- ============================================================================
-- sp_snow_pub_TRS_RELDEACT_STG_TRS_DEACTIVATED_RELATIONSHIPS  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 60, driver checkpoint STEP_NAME PUBLISH_STG_TRS_DEACTIVATED_RELATIONSHIPS.
-- Target: STG_TRS_DEACTIVATED_RELATIONSHIPS. Kind: STATUS (Deactivated relationships).
--
-- INPUTS
--   Reads ONLY WRK_TRS_RELDEACT_S50_READY (P_INPUT_TABLES default). The INSERT below may use
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_RELDEACT_STG_TRS_DEACTIVATED_RELATIONSHIPS (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_RELDEACT_S50_READY') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO STG_TRS_DEACTIVATED_RELATIONSHIPS
           (INDV_ID, REF_INDV_ID, PTY_RLE_FK_1, PTY_RLE_FK_2, REL_TYPE_CODE, SRC_PKEY_CT, LOAD_DATE, PKEY_SRC_OBJECT,
            ROWID_OBJECT, MASTER_RECORD_YN, MERGED_YN, ROWID_SYSTEM, ROWID_XREF)
    SELECT INDV_ID, REF_INDV_ID, PTY_RLE_FK_1, PTY_RLE_FK_2, REL_TYPE_CODE, SRC_PKEY_CT, LOAD_DATE, PKEY_SRC_OBJECT,
           ROWID_OBJECT, MASTER_RECORD_YN, MERGED_YN, ROWID_SYSTEM, ROWID_XREF
      FROM WRK_TRS_RELDEACT_S50_READY;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_RELDEACT_STG_TRS_DEACTIVATED_RELATIONSHIPS;
/

