-- ============================================================================
-- sp_snow_pub_CRE_CARE_CRE_SRC_MRG  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (CRE)
--
-- Mapping: m_Tgt_C_S_CRE_CARE_Clients, workflow wf_CRE_Stage_Load_Ongoing.
-- Publish branch STEP_NO 60, checkpoint STEP_NAME PUBLISH_CRE_SRC_MRG.
-- Target: CRE_SRC_MRG. Kind: STATUS (merge routing output, not a C_S spine table).
-- Branch 60a of the original publish, in original order.
--
-- INPUTS
--   Reads ONLY WRK_CRE_CARE_S5_KEYED (P_INPUT_TABLES default). The
--   INSERT reads the run_ts / mapping_name columns materialised in step
--   50; it references neither original parameter nor the run timestamp
--   directly, so P_RUN_TS is carried for a uniform driver call
--   signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch-60a INSERT verbatim: same
--   columns, values and WHERE guard (grp_mrg). No business expression,
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
CREATE OR REPLACE FUNCTION sp_snow_pub_CRE_CARE_CRE_SRC_MRG (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_CRE_CARE_S5_KEYED') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    INSERT INTO CRE_SRC_MRG (SRC_ROWID_OBJECT, TGT_ROWID_OBJECT, RUN_DATE)
    SELECT src_rowid_object, tgt_rowid_object, run_ts
      FROM WRK_CRE_CARE_S5_KEYED
     WHERE grp_mrg = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_CRE_CARE_CRE_SRC_MRG;
/

