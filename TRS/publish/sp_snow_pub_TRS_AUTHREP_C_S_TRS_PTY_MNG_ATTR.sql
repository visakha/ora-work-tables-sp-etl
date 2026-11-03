-- ============================================================================
-- sp_snow_pub_TRS_AUTHREP_C_S_TRS_PTY_MNG_ATTR  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 50, driver checkpoint STEP_NAME PUBLISH_C_S_TRS_PTY_MNG_ATTR.
-- Target: C_S_TRS_PTY_MNG_ATTR. Kind: SPINE (Authorised representative flags).
--
-- INPUTS
--   Reads ONLY WRK_TRS_MNGAR_S40_AGG (P_INPUT_TABLES default). The INSERT below may use
--   :P_RUN_TS (run timestamp) and :c_mapping (local constant) where
--   the original INSERT used :l_run_ts / :c_mapping; it uses original
--   parameters: P_ATTR_TP_AUTH_REP.
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_AUTHREP_C_S_TRS_PTY_MNG_ATTR (P_ATTR_TP_AUTH_REP IN VARCHAR2 DEFAULT 'Auth_Rep_Flag', P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_MNGAR_S40_AGG') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO C_S_TRS_PTY_MNG_ATTR
           (CREATE_DATE, LAST_UPDATE_DATE, MNG_ATTR_TP, PTY_FK, PERIOD_END_DATE, PERIOD_START_DATE, VERSION_SEQ,
            SRC_ROWID, PKEY_SRC_OBJECT, SRC_LAST_UPD_DT, MNG_ATTR_VAL)
    SELECT g.CREATE_DT, P_RUN_TS, P_ATTR_TP_AUTH_REP, g.pty_pk, g.max_eff_end_dt,
           g.EFF_BEGIN_DT, 1, g.pkey_src_object,
           g.pkey_src_object, g.CREATE_DT, g.AR_FLAG
      FROM WRK_TRS_MNGAR_S40_AGG g
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TRS_PTY_MNG_ATTR WHERE VERSION_SEQ = 1) xa
             ON xa.PKEY_SRC_OBJECT = g.pkey_src_object
     WHERE g.rn = 1
       AND xa.PKEY_SRC_OBJECT IS NULL;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_AUTHREP_C_S_TRS_PTY_MNG_ATTR;
/

