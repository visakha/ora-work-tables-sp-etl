-- ============================================================================
-- sp_snow_pub_ECI_RFM_STG_ECI_D_MEDICAID
--   Publish branch (step 30) of
--   m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid, workflow
--   wf_ECI_Stage_Load. Config-driven step-driver refactor (ECI only).
--
-- WHAT THIS BRANCH WRITES
--   Target: STG_ECI_D_MEDICAID, STATUS kind. This mapping's outcome IS
--   the dimension/status write: the latest history Medicaid rows of
--   reactivated children are inserted into the delta table. There is
--   no second branch (no EXC / non-spine branch exists for this
--   mapping) -- this single INSERT is the whole publish.
--   Insert-only, as in the original: no TRUNCATE, no DELETE.
--
-- RE-HOUSING ONLY
--   The INSERT below is the current step-30 INSERT verbatim: same
--   columns, same values, same WHERE guards (none beyond reading step
--   20). No business expression, filter, guard, or column list was
--   changed. Snowflake cannot parameterise table names in static SQL,
--   so P_INPUT_TABLES is a dependency declaration plus a runtime
--   existence check, NOT dynamic SQL: the INSERT itself still names
--   its source table literally.
--
-- INPUTS / PARAMS
--   P_JOB_RUN_ID   VARCHAR            -- run id, from the driver
--   P_RUN_TS       TIMESTAMP_NTZ      -- run timestamp, from the
--                                       driver; accepted for a uniform
--                                       branch interface, but this
--                                       mapping's SQL has no
--                                       run-timestamp column, so it
--                                       is unused here
--   P_INPUT_TABLES VARCHAR DEFAULT 'WRK_ECI_RFM_S20_KEEPNEW'
--                                       -- pipe-delimited WORK-TABLE
--                                       inputs for this branch
--   This branch's INSERT does NOT use P_TEST_LOOKUP_RESULT, so that
--   original parameter is omitted from this proc's signature.
--   The INSERT has no mapping-name reference, so no local c_mapping
--   constant is needed here.
--
-- FRAMEWORK RULE (read before changing anything)
--   NO transaction control and NO checkpoint calls inside this proc.
--   The driver owns the transaction: it calls this proc between BEGIN
--   TRANSACTION and COMMIT, and only AFTER COMMIT writes the step-30
--   checkpoint. A checkpoint written inside the transaction would roll
--   back with it, which is exactly what the framework forbids.
--
-- BEHAVIOUR
--   (1) Input existence check, same pattern as the step procs, skipped
--       when P_INPUT_TABLES is NULL or empty. (2) The branch INSERT,
--       verbatim. (3) RETURN SQLROWCOUNT as NUMBER.
--   No exception block (errors propagate to the driver handler, which
--   rolls back), no cursors.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_ECI_RFM_STG_ECI_D_MEDICAID (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_RFM_S20_KEEPNEW') RETURN NUMBER AUTHID CURRENT_USER AS
    l_missing VARCHAR2(4000) DEFAULT NULL;
    l_probe_sql VARCHAR2(4000);
    l_probe_dummy NUMBER;
SELECT TRIM(MIN(s.raw)) INTO l_missing FROM (SELECT REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL) AS raw, UPPER(TRIM(REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL))) AS tbl FROM DUAL CONNECT BY REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL) IS NOT NULL) s WHERE TRIM(s.raw) <> '' AND NOT EXISTS (SELECT 1 FROM ALL_TABLES t WHERE t.OWNER = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AND t.TABLE_NAME = TRIM(s.raw));
        IF (l_missing IS NOT NULL) THEN
            l_probe_sql := 'SELECT COUNT(*) FROM ' || TRIM(REGEXP_SUBSTR(l_missing, '[^,]+', 1, 1));
            EXECUTE IMMEDIATE l_probe_sql INTO l_probe_dummy;
        END IF;
    END IF;

    -- ---- Step 30: PUBLISH -- the original INSERT, verbatim --------------
    INSERT INTO STG_ECI_D_MEDICAID
           (ID_MEDICAID, ID_CASE, MEDICAID_NBR, ELIG_DATE, END_DATE, CURRENT_IND, CANCEL_DATE, HMO_DESC,
            DATE_CREATED, DATE_MODIFIED, MODIFIED_BY, CREATED_BY, CONSENT_TO_BILL, LOAD_DATE)
    SELECT h.ID_MEDICAID, h.ID_CASE, h.MEDICAID_NBR, h.ELIG_DATE, h.END_DATE, h.CURRENT_IND, h.CANCEL_DATE,
           h.HMO_DESC, h.DATE_CREATED, h.DATE_MODIFIED, h.MODIFIED_BY, h.CREATED_BY, h.CONSENT_TO_BILL, h.LOAD_DATE
      FROM WRK_ECI_RFM_S20_KEEPNEW h;
    RETURN SQL%ROWCOUNT;
END sp_snow_pub_ECI_RFM_STG_ECI_D_MEDICAID;
/

