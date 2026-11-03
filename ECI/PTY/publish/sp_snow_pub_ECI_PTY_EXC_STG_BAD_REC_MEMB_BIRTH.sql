-- ============================================================================
-- sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_BIRTH  --  CONFIG-DRIVEN REFACTOR (ECI)
--
-- Mapping: m_Tgt_C_S_ECI_Pty, workflow wf_ECI_Stage_Load.
-- Publish branch STEP_NO 90, checkpoint STEP_NAME PUBLISH_EXC_BIRTH.
-- Target: EXC_STG_BAD_REC_MEMB, branch: invalid birth date.
-- Kind: NON-SPINE (demographic exception log; a future birth date is
-- loaded as NULL on the party AND logged here).
-- Branch 60d of the original publish, in original order (fourth).
--
-- INPUTS
--   Reads ONLY WRK_ECI_PTY_S50_READY (P_INPUT_TABLES default). The
--   INSERT reads the run_ts / exc_mapping columns materialised in step
--   50; it references neither original parameter nor the run timestamp
--   directly, so P_RUN_TS is carried for a uniform driver call
--   signature and is unused in the body (stated, not hidden).
--
-- BUSINESS SQL
--   The INSERT below is the current branch-60d INSERT verbatim: same
--   columns, values and WHERE guard (grp_birth AND uq_birth). No
--   business expression, filter, guard or column list was changed.
--
-- FRAMEWORK RULE
--   NO transaction control and NO checkpoint calls in this proc. The
--   driver calls it inside ONE publish transaction (all branches
--   together), COMMITs, and only then checkpoints this branch with the
--   returned row count. Never call a checkpoint between BEGIN
--   TRANSACTION and COMMIT.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_BIRTH (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_PTY_S50_READY') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
    INSERT INTO EXC_STG_BAD_REC_MEMB
           (SRC_SYS, SRC_SYS_ID_1, EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE, RUN_DATE, MAPPING_NAME,
            GENDER, ATTRIBUTE_NAME, SRC_SYS_ID_2, PREFIX, FIRST_NAME, LAST_NAME, MIDDLE_NAME, ATTRIBUTE_VALUE,
            BIRTH_DATE)
    SELECT src_system, pkey_src_object, birth_exception_code, birth_exception_description,
           birth_exception_type, run_ts, exc_mapping, GENDER, attr_birth, ID, std_prfx_name,
           FIRST_NAME, LAST_NAME, MIDDLE_INITIAL, dob_text, DOB
      FROM WRK_ECI_PTY_S50_READY
     WHERE grp_birth = 1 AND uq_birth = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_BIRTH;
/

