-- ============================================================================
-- sp_snow_pub_ECI_RFP_STG_ECI_D_FAMILY_PHONE
--   Publish branch (step 30) of m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn
--   (ECI, workflow wf_ECI_Stage_Load; prefix ECI_RFP, short RFP).
--
-- TARGET AND KIND
--   Target: STG_ECI_D_FAMILY_PHONE — this mapping's outcome IS the
--   dimension/status write (the reactivated families' phone rows moved
--   into the delta table). There is no second branch: no EXC branch,
--   no non-spine branch, no other target. This is the mapping's ONLY
--   publish branch and its ONLY final-target write.
--
-- BUSINESS SQL
--   The INSERT below is VERBATIM from the current main procedure
--   sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn, step 30:
--   same columns, same values, same source (WRK_ECI_RFP_S20_KEEPNEW).
--   No business expression, filter, guard, or column list was changed.
--   The original INSERT has no WHERE guard, no :l_run_ts reference,
--   and no mapping-name reference, so there is no run-ts or mapping
--   substitution to make here; P_RUN_TS is accepted for signature
--   uniformity and is otherwise unused, and c_mapping is declared for
--   uniformity with the step procedures. The source table name is
--   fixed, as in the original — see P_INPUT_TABLES below.
--
-- P_INPUT_TABLES — DEPENDENCY DECLARATION + RUNTIME CHECK, NOT DYNAMIC SQL
--   Snowflake cannot parameterise table names in static SQL, so the
--   INSERT below still reads its fixed work-table name
--   (WRK_ECI_RFP_S20_KEEPNEW). P_INPUT_TABLES is the dependency
--   declaration for that input (default 'WRK_ECI_RFP_S20_KEEPNEW')
--   plus a runtime check, in the same form as the step procedures:
--   each pipe-delimited name is checked against
--   INFORMATION_SCHEMA.TABLES in CURRENT_SCHEMA(); the first missing
--   name surfaces a native object-not-exists error via EXECUTE
--   IMMEDIATE (RAISE takes a declared exception with a static message
--   and cannot carry a dynamically found table name — see the step
--   procedure headers). No CURSOR is used.
--
-- FRAMEWORK RULE (do not move this checkpoint)
--   This procedure contains NO transaction control and NO
--   sp_etl_checkpoint calls. The driver owns the transaction: it calls
--   this procedure inside BEGIN TRANSACTION ... COMMIT, and only
--   AFTER COMMIT writes the step 30 checkpoint (PUBLISH_
--   STG_ECI_D_FAMILY_PHONE, COMPLETED, ROW_COUNT = rows inserted).
--   A checkpoint written from inside the publish transaction would
--   roll back with that transaction, which is why it must live in the
--   driver, after COMMIT. Errors propagate to the driver handler.
--
-- RETURN
--   RETURNs SQLROWCOUNT (rows inserted) as NUMBER, via l_rows.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_ECI_RFP_STG_ECI_D_FAMILY_PHONE (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_RFP_S20_KEEPNEW') RETURN NUMBER AUTHID CURRENT_USER AS
    c_source VARCHAR2(4000) DEFAULT 'ECI';
    c_workflow VARCHAR2(4000) DEFAULT 'wf_ECI_Stage_Load';
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn';
    l_rows NUMBER DEFAULT 0;
    l_missing VARCHAR2(4000);
    l_probe_sql VARCHAR2(4000);
    l_probe_dummy NUMBER;
SELECT MAX(s.tbl) INTO l_missing FROM (SELECT REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL) AS raw, UPPER(TRIM(REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL))) AS tbl FROM DUAL CONNECT BY REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL) IS NOT NULL) s WHERE TRIM(s.raw) <> '' AND NOT EXISTS (SELECT 1 FROM ALL_TABLES t WHERE t.OWNER = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AND t.TABLE_NAME = s.tbl);
        IF (l_missing IS NOT NULL) THEN
            l_probe_sql := 'SELECT COUNT(*) FROM ' || l_missing;
            EXECUTE IMMEDIATE l_probe_sql INTO l_probe_dummy;
        END IF;
    END IF;

    -- ---- Step 30: PUBLISH — INSERT verbatim from current main ---------
    -- The ONLY step that writes to a final target. No TRUNCATE, no
    -- DELETE: insert-only, as in the original Snowflake code.
    INSERT INTO STG_ECI_D_FAMILY_PHONE
           (ID_FAMILY_PHONE, ID_FAMILY, ID_CASE, HOME_AC, HOME_NBR, WORK_AC, WORK_NBR, WORK_EXT, CELL_AC, CELL_NBR,
            FAX_AC, FAX_NBR, PAGER_AC, PAGER_NBR, OTHER_AC, OTHER_NBR, EMAIL_ADDRESS, DATE_CREATED, DATE_MODIFIED,
            MODIFIED_BY, CREATED_BY, CHILD_RESIDES_IND, INACTIVE_IND, PRIMARY_CONTACT_IND, LOAD_DATE)
    SELECT h.ID_FAMILY_PHONE, h.ID_FAMILY, h.ID_CASE, h.HOME_AC, h.HOME_NBR, h.WORK_AC, h.WORK_NBR, h.WORK_EXT,
           h.CELL_AC, h.CELL_NBR, h.FAX_AC, h.FAX_NBR, h.PAGER_AC, h.PAGER_NBR, h.OTHER_AC, h.OTHER_NBR,
           h.EMAIL_ADDRESS, h.DATE_CREATED, h.DATE_MODIFIED, h.MODIFIED_BY, h.CREATED_BY, h.CHILD_RESIDES_IND,
           h.INACTIVE_IND, h.PRIMARY_CONTACT_IND, h.LOAD_DATE
      FROM WRK_ECI_RFP_S20_KEEPNEW h;
    l_rows := SQLROWCOUNT;
    RETURN l_rows;
END sp_snow_pub_ECI_RFP_STG_ECI_D_FAMILY_PHONE;
/

