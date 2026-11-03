-- ============================================================================
-- sp_snow_pub_TRS_MNGSW_C_S_TRS_PTY_MNG_ATTR  --  CONFIG-DRIVEN STEP DRIVER REFACTOR (TRS)
--
-- Mapping: m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw, workflow wf_TRS_Stage_Load_1_Ongoing.
-- Publish branch STEP_NO 50, driver checkpoint STEP_NAME PUBLISH_C_S_TRS_PTY_MNG_ATTR.
-- Target: C_S_TRS_PTY_MNG_ATTR. Kind: SPINE (Switch attributes).
--
-- INPUTS
--   Reads ONLY WRK_TRS_MNGSW_S40_ATTRS (P_INPUT_TABLES default). The INSERT below may use
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
CREATE OR REPLACE FUNCTION sp_snow_pub_TRS_MNGSW_C_S_TRS_PTY_MNG_ATTR (P_JOB_RUN_ID IN VARCHAR2 DEFAULT NULL, P_RUN_TS IN TIMESTAMP DEFAULT NULL, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_TRS_MNGSW_S40_ATTRS') RETURN NUMBER AUTHID CURRENT_USER AS
BEGIN
INSERT INTO C_S_TRS_PTY_MNG_ATTR
           (PKEY_SRC_OBJECT, ROWID_OBJECT, DELETED_IND, DELETED_DATE, DELETED_BY, PERIOD_START_DATE, PERIOD_END_DATE,
            MNG_ATTR_TP, MNG_ATTR_VAL, VERSION_SEQ, PERIOD_REFERENCE_TIME, TIMELINE_ACTION, UPDATED_BY, CREATE_DATE,
            SRC_ROWID, CREATOR, LAST_UPDATE_DATE, SRC_LAST_UPD_DT, PTY_FK, HUB_STATE_IND)
    SELECT * FROM (SELECT t.pkey_src_object, NULL, NULL, NULL, NULL, t.EFF_BEGIN_DT, NULL,
           t.ATTR_TYPE, t.ATTR_VALUE, 1, NULL, NULL, NULL, P_RUN_TS, t.pkey_src_object, NULL, P_RUN_TS, t.SRC_LAST_UPD_DT,
           t.PTY_PK, NULL
      , ROW_NUMBER() OVER (PARTITION BY t.pkey_src_object ORDER BY t.EFF_BEGIN_DT DESC NULLS LAST) AS __qual_rn FROM WRK_TRS_MNGSW_S40_ATTRS t
      LEFT JOIN (SELECT DISTINCT PKEY_SRC_OBJECT FROM C_S_TRS_PTY_MNG_ATTR WHERE VERSION_SEQ = 1) xa
             ON xa.PKEY_SRC_OBJECT = t.pkey_src_object
     WHERE xa.PKEY_SRC_OBJECT IS NULL) WHERE __qual_rn = 1;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_TRS_MNGSW_C_S_TRS_PTY_MNG_ATTR;
/

