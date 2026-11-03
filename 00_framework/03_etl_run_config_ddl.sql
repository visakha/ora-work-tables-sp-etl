-- ============================================================================
-- 03_etl_run_config_ddl.sql  (ECI step-driver example)
--
-- ETL_RUN_CONFIG_TBL: the per-step run toggle table for config-driven
-- step drivers.  Install it in the COMMON schema (MDM_ETL_COMMON.COMMON
-- in the established topology), using the same unqualified-name
-- convention as JOB_CONTROL_ETL in 01_job_control_ddl.sql: run this
-- file with the COMMON schema current.
--
-- COLUMNS — the operator's 8 columns, plus 3 addressing columns the
-- driver needs (flagged as REQUIRED additions, not optional):
--   WORKFLOW_NAME, MAPPING_NAME, IS_DRIVER, IS_RUN_ENABLED,
--   IS_DEPENDENT, DEPENDENT_ON, WORK_TABLES_PRODUCED,
--   WORK_TABLES_CONSUMED                        -- the operator's 8
--   STEP_NO, STEP_PROC_NAME, STEP_KIND          -- REQUIRED additions:
--     STEP_NO is the driver's address for a unit (0 = the driver row
--     itself; transform steps keep their current numbers; publish
--     branches take the current publish number, then +10 each).
--     STEP_PROC_NAME names the procedure that implements the unit.
--     STEP_KIND is informational only (the driver never gates on it).
--
-- THE OPERATOR CONTRACT (see README.md — stated here so it travels
-- with the DDL):
--   * The operator ONLY toggles IS_RUN_ENABLED ('Y'/'N').  Every other
--     column is informational for a driver run, except IS_DRIVER (the
--     STEP_NO = 0 row gates the whole mapping) and WORK_TABLES_CONSUMED
--     (passed to each unit as P_INPUT_TABLES and runtime-checked).
--   * The driver does NOT validate flag consistency.  Disabling a step
--     while a downstream step stays enabled is the operator's
--     responsibility to avoid: step 5 drops ALL work tables regardless
--     of flags, so the downstream step WILL error on its missing input
--     table.  That is the designed behaviour, not a bug.
--   * IS_RUN_ENABLED is VARCHAR(1) holding 'Y'/'N'.  Only exact 'Y'
--     runs a step/branch; only exact 'N' on the driver row skips the
--     whole mapping.  Any other value is treated as "do not run" for
--     steps/branches (and as "run" for the driver row, which skips
--     only on exact 'N').
-- ============================================================================

BEGIN
    EXECUTE IMMEDIATE 'CREATE TABLE IF NOT EXISTS ETL_RUN_CONFIG_TBL (
    WORKFLOW_NAME        VARCHAR2(200)  NOT NULL,
    MAPPING_NAME         VARCHAR2(200)  NOT NULL,
    STEP_NO              NUMBER(4)     NOT NULL,   -- 0 = driver row; steps/branches per mapping
    STEP_PROC_NAME       VARCHAR2(200)  NOT NULL,   -- driver / step / publish-branch procedure
    IS_DRIVER            VARCHAR2(1)    DEFAULT ''N'',  -- ''Y'' only on the STEP_NO = 0 row
    IS_RUN_ENABLED       VARCHAR2(1)    DEFAULT ''Y'',  -- THE toggle: ''Y'' runs, anything else skips (steps/branches)
    IS_DEPENDENT         VARCHAR2(1),                 -- ''Y'' iff DEPENDENT_ON is non-empty (informational)
    DEPENDENT_ON         VARCHAR2(200),               -- pipe-delimited producing STEP_NOs (informational)
    WORK_TABLES_PRODUCED VARCHAR2(1000),               -- pipe-delimited work tables this unit creates ('''' for publish branches)
    WORK_TABLES_CONSUMED VARCHAR2(1000),               -- pipe-delimited work tables this unit reads ('''' for step 10)
    STEP_KIND            VARCHAR2(30),                -- DRIVER / TRANSFORM / SPINE / STATUS / EXCEPTION / VALIDATION (informational)
    PRIMARY KEY (WORKFLOW_NAME, MAPPING_NAME, STEP_NO)
)';
EXCEPTION
    WHEN OTHERS THEN
        IF SQLCODE <> -955 THEN RAISE; END IF;
END;
/

COMMENT ON TABLE ETL_RUN_CONFIG_TBL IS
    'Per-step run toggles for config-driven step drivers. The operator toggles only IS_RUN_ENABLED; IS_DRIVER (STEP_NO = 0 row) gates the whole mapping and WORK_TABLES_CONSUMED is passed to each unit as P_INPUT_TABLES and runtime-checked. The driver does NOT validate flag consistency: disabling a producer while a consumer stays enabled fails loudly on the missing input table (step 5 drops ALL work tables regardless of flags). See ECI/seed_etl_run_config_eci.sql and DEPENDENCIES.md.';
-- NOTE (live-compile fix): COMMENT ON ... IS takes a string literal only;
-- the earlier ||-concatenated form failed with "unexpected ||" on Snowflake.
