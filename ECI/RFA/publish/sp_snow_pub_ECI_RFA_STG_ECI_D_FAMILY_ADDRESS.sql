-- ============================================================================
-- sp_snow_pub_ECI_RFA_STG_ECI_D_FAMILY_ADDRESS
--   --  CONFIG-DRIVEN STEP DRIVER REFACTOR (ECI)
--
-- Mapping: m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr, workflow
-- wf_ECI_Stage_Load, publish branch, step 30.
--
-- TARGET AND KIND
--   Target: STG_ECI_D_FAMILY_ADDRESS. Kind: STATUS / dimension write --
--   this mapping's outcome IS this write: the latest history address
--   rows of reactivated families land in the delta table so the
--   downstream address mapping re-sends them to the MDM. There is no
--   EXC branch and no non-spine branch in this mapping: this single
--   INSERT is the entire publish.
--
-- INPUTS / DEPENDENCY DECLARATION
--   P_INPUT_TABLES lists WORK-TABLE inputs only: 'WRK_ECI_RFA_S20_KEEPNEW'.
--   Snowflake cannot parameterise table names in static SQL, so
--   P_INPUT_TABLES is a dependency declaration + runtime check, NOT
--   dynamic SQL: the INSERT below still names its source literally, as
--   in the current main procedure. The check uses the same form as the
--   step procs; it is the only code here beyond the INSERT itself.
--
-- BUSINESS SQL
--   The INSERT below is the current step-30 INSERT verbatim (same
--   columns, values and source). Only substitutions: :l_run_ts ->
--   :P_RUN_TS (not used by this branch -- the original INSERT has no
--   run-timestamp column), mapping-name refs -> the local constant
--   below (none exist in this INSERT; declared for uniformity).
--   No business expression, filter, guard or column list was changed.
--
-- FRAMEWORK RULE
--   NO transaction control and NO checkpoint calls in this proc: the
--   driver wraps the CALL in the publish transaction (BEGIN
--   TRANSACTION ... COMMIT) and checkpoints the branch only AFTER
--   COMMIT, so a checkpoint can never roll back with the publish.
--   Errors propagate to the driver handler. Returns SQLROWCOUNT.
--   P_JOB_RUN_ID is present in every new proc in this refactor.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_snow_pub_ECI_RFA_STG_ECI_D_FAMILY_ADDRESS (P_JOB_RUN_ID IN VARCHAR2, P_RUN_TS IN TIMESTAMP, P_INPUT_TABLES IN VARCHAR2 DEFAULT 'WRK_ECI_RFA_S20_KEEPNEW') RETURN NUMBER AUTHID CURRENT_USER AS
    c_mapping VARCHAR2(4000) DEFAULT 'm_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr';
    l_rows NUMBER DEFAULT 0;
    l_missing VARCHAR2(4000) DEFAULT NULL;
    l_probe_sql VARCHAR2(4000);
    l_probe_dummy NUMBER;
BEGIN
    -- ---- Input existence check (skipped when P_INPUT_TABLES is empty)
    IF (P_INPUT_TABLES IS NOT NULL AND TRIM(P_INPUT_TABLES) <> '') THEN
        SELECT LISTAGG(tbl, ', ') WITHIN GROUP (ORDER BY tbl) INTO l_missing FROM (SELECT UPPER(TRIM(REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL))) AS tbl FROM DUAL CONNECT BY REGEXP_SUBSTR(P_INPUT_TABLES, '[^|]+', 1, LEVEL) IS NOT NULL) f WHERE NOT EXISTS (SELECT 1 FROM ALL_TABLES t WHERE t.OWNER = SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AND t.TABLE_NAME = f.tbl);
        IF (l_missing IS NOT NULL) THEN
            l_probe_sql := 'SELECT COUNT(*) FROM ' || TRIM(REGEXP_SUBSTR(l_missing, '[^,]+', 1, 1));
            EXECUTE IMMEDIATE l_probe_sql INTO l_probe_dummy;
        END IF;
    END IF;

    -- ---- Step 30: PUBLISH (verbatim from current main)
    INSERT INTO STG_ECI_D_FAMILY_ADDRESS
           (ID_FAMILY_ADDRESS, ID_FAMILY, ID_CASE, ADDRESS_CD, ADDRESS1, ADDRESS2, ID_ST_CITY_CNTY_ZIP, CITY_NAME,
            COUNTY_NAME, ZIP_CODE, ZIP_SFX, STATE_ABBREV, CANCEL_DATE, DATE_CREATED, DATE_MODIFIED, MODIFIED_BY,
            CREATED_BY, LOAD_DATE)
    SELECT h.ID_FAMILY_ADDRESS, h.ID_FAMILY, h.ID_CASE, h.ADDRESS_CD, h.ADDRESS1, h.ADDRESS2, h.ID_ST_CITY_CNTY_ZIP,
           h.CITY_NAME, h.COUNTY_NAME, h.ZIP_CODE, h.ZIP_SFX, h.STATE_ABBREV, h.CANCEL_DATE, h.DATE_CREATED,
           h.DATE_MODIFIED, h.MODIFIED_BY, h.CREATED_BY, h.LOAD_DATE
      FROM WRK_ECI_RFA_S20_KEEPNEW h;
    l_rows := SQLROWCOUNT;
    RETURN l_rows;
END sp_snow_pub_ECI_RFA_STG_ECI_D_FAMILY_ADDRESS;
/

