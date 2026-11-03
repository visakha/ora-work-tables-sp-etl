-- ============================================================================
-- sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_GENDER  --  CONFIG-DRIVEN REFACTOR (ECI)
--
-- Mapping: m_Tgt_C_S_ECI_Pty, workflow wf_ECI_Stage_Load.
-- Publish branch STEP_NO 80, checkpoint STEP_NAME PUBLISH_EXC_GENDER.
-- Target: EXC_STG_BAD_REC_MEMB, branch: invalid gender.
-- Kind: NON-SPINE (demographic exception log; an exception never
-- rejects the party -- the party is loaded AND logged).
-- Branch 60c of the original publish, in original order (third).
--
-- INPUTS
--   Reads ONLY WRK_ECI_PTY_S50_READY (P_INPUT_TABLES default). The
--   INSERT reads the run_ts / exc_mapping columns materialised in step
--   50; it references neither original parameter nor the run timestamp
--   directly, so P_RUN_TS is carried for a uniform driver call
--   signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch-60c INSERT verbatim: same
--   columns, values and WHERE guard (grp_gender AND uq_gender). No
--   business expression, filter, guard or column list was changed.
--   Note the preserved routing quirk: gender exceptions are routed on
--   the looked-up description, so an unconfigured code writes no row.
--
-- FRAMEWORK RULE
--   NO transaction control and NO checkpoint calls in this proc. The
--   driver calls it inside ONE publish transaction (all branches
--   together), COMMITs, and only then checkpoints this branch with the
--   returned row count. Never call a checkpoint between BEGIN
--   TRANSACTION and COMMIT.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_GENDER (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_PTY_S50_READY') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, EXCEPTION_TYPE, EXCEPTION_CODE, EXCEPTION_DESC, ATTRIBUTE_NAME, ATTRIBUTE_VALUE,
            MAPPING_NAME, SRC_SYS_ID_1, SRC_SYS_ID_2, GENDER, BIRTH_DATE, RUN_DATE)
    SELECT src_system, gender_exception_type, gender_exception_code, gender_exception_description,
           attr_gender, GENDER, exc_mapping, pkey_src_object, ID, GENDER, DOB, run_ts
      FROM WRK_ECI_PTY_S50_READY
     WHERE grp_gender = 1 AND uq_gender = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_GENDER;
/

