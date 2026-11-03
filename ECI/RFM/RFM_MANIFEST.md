# RFM Manifest — m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid (ECI, config-driven step driver)

Mapping: `m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid` (reactivation, Medicaid),
workflow `wf_ECI_Stage_Load`, source `ECI`, short prefix `RFM`.
Source of truth: `snowflake_multisource/ECI/mappings/sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid.sql`
(verified against the file before writing; the file's structure matched the brief exactly:
steps 10/20, publish 30 with 1 INSERT, no EXC branch).

Driver signature (identical to the current main — every existing CALL still works):

```sql
sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid (
    P_TEST_LOOKUP_RESULT VARCHAR DEFAULT 'N',
    P_JOB_RUN_ID         VARCHAR DEFAULT NULL
) RETURNS VARCHAR
```

Original params are preserved in order, then `P_JOB_RUN_ID` (appended, as now).
Job-run-id generation is copied exactly as now (including that `l_job_run_id`
starts NULL, so the generation branch always runs; net effect unchanged:
a supplied run id is used, otherwise one is generated).

## Step table

| STEP_NO | Proc | Kind | Produces | Consumes default | Original params used | Checkpoint STEP_NAME |
|---|---|---|---|---|---|---|
| 10 | `sp_snow_step_ECI_RFM_S10_LATEST` | CTAS step | `WRK_ECI_RFM_S10_LATEST` (TRANSIENT) — latest history row per Medicaid record of reactivated children + `LKP_ID_MEDICAID` lookup key | `` (empty — reads only base source / target-guard tables, which are not work-table dependencies) | none (`P_TEST_LOOKUP_RESULT` is not referenced by this step's SQL, so it is omitted) | `LATEST_HISTORY_ROWS` |
| 20 | `sp_snow_step_ECI_RFM_S20_KEEPNEW` | CTAS step | `WRK_ECI_RFM_S20_KEEPNEW` (TRANSIENT) — rows passing the keep-new filter, one row per Medicaid id | `WRK_ECI_RFM_S10_LATEST` | `P_TEST_LOOKUP_RESULT` (the `IFF` keep-new filter) | `KEEP_NEW_ONLY` |

Step-proc signatures (each also takes `P_JOB_RUN_ID VARCHAR` and
`P_RUN_TS TIMESTAMP_NTZ`, plus `P_INPUT_TABLES VARCHAR` with the consumes
default above):

- `sp_snow_step_ECI_RFM_S10_LATEST(P_JOB_RUN_ID, P_RUN_TS, P_INPUT_TABLES DEFAULT '') RETURNS NUMBER`
- `sp_snow_step_ECI_RFM_S20_KEEPNEW(P_TEST_LOOKUP_RESULT, P_JOB_RUN_ID, P_RUN_TS, P_INPUT_TABLES DEFAULT 'WRK_ECI_RFM_S10_LATEST') RETURNS NUMBER`

Each step proc: (1) existence check on `P_INPUT_TABLES` (skipped when
NULL/empty), (2) its CTAS verbatim, (3) `COUNT(*)` into the return value,
(4) its own checkpoint with the SAME values as the current step checkpoint
(including step 20's `TARGET_TABLE = 'STG_ECI_D_MEDICAID'`), (5) `RETURN`
the count. No exception block, no transactions, no target writes.
`P_INPUT_TABLES` is a dependency declaration + runtime check, NOT dynamic
SQL — Snowflake cannot parameterise table names in static SQL, so the
CTAS still names its tables literally. `P_RUN_TS` is accepted for a
uniform step interface but is unused by this mapping's SQL (the original
has no run-timestamp column and no `:l_run_ts` reference anywhere).

## Branch table (publish)

| STEP_NO | Proc | Kind | Target | Consumes |
|---|---|---|---|---|
| 30 | `sp_snow_pub_ECI_RFM_STG_ECI_D_MEDICAID` | Publish branch, single INSERT | `STG_ECI_D_MEDICAID` (STATUS — this mapping's outcome IS the dimension/status write; there is no EXC branch) | `WRK_ECI_RFM_S20_KEEPNEW` |

Publish-proc signature:

```sql
sp_snow_pub_ECI_RFM_STG_ECI_D_MEDICAID(P_JOB_RUN_ID, P_RUN_TS,
    P_INPUT_TABLES DEFAULT 'WRK_ECI_RFM_S20_KEEPNEW') RETURNS NUMBER
```

The INSERT does not use `P_TEST_LOOKUP_RESULT`, so that parameter is
omitted here. Body: the current INSERT verbatim, then `RETURN SQLROWCOUNT`.
NO transaction control, NO checkpoint calls inside the proc (framework
rule — the driver checkpoints step 30 only AFTER COMMIT).
Driver publish checkpoint (v2 10-argument form — see "v2 migration"
below): `STEP_NAME 'PUBLISH_STG_ECI_D_MEDICAID'`, `STEP_STATUS
'COMPLETED'` (or `'SKIPPED'` when disabled by config), `TARGET_TABLE
'STG_ECI_D_MEDICAID'`; the branch row count survives only in the
`fn_snow_helper36_common` summary line, not in the checkpoint call
(`ROW_COUNT` is a dropped v1 checkpoint argument).

## Driver behaviour summary

1. Job-run-id generation exactly as now + `sp_etl_job_begin`.
2. Config gather in a nested `BEGIN/EXCEPTION`: flags pre-initialised to
   `'Y'`, consumed strings to the defaults in the step table above; one
   `SELECT` with `COALESCE(MAX(CASE WHEN STEP_NO=n THEN IS_RUN_ENABLED
   END),'Y')` per flag and `COALESCE(MAX(CASE WHEN STEP_NO=n THEN
   WORK_TABLES_CONSUMED END),'<default>')` per consumed string from
   `COMMON.ETL_RUN_CONFIG_TBL` where workflow + mapping match. On
   exception the defaults stand (missing/unreadable config table =
   run everything, as before).
3. Driver row (config `STEP_NO = 0`) flag `'N'` → `MAPPING_SKIPPED`
   checkpoint (`STATE 'WORKING'`, `STEP_STATUS 'SKIPPED'`; the v2
   checkpoint call carries no `STEP_NO` argument),
   `sp_etl_job_finish` with a skipped message, early `RETURN` — BEFORE
   step 5 cleanup.
4. Step 5 cleanup UNCHANGED: bare `DROP TABLE IF EXISTS` for both work
   tables, no checkpoint for drops.
5. Conditional step calls in order; enabled steps append a
   `fn_snow_helper36_common` summary line, skipped steps get a `SKIPPED`
   checkpoint row and a plain-text summary line (helper36 is not used
   for skips — it renders NULL as `'0 row(s)'`).
6. Publish: `BEGIN TRANSACTION`, conditional branch call capturing its
   return (`l_pub_ECI_RFM_STG_ECI_D_MEDICAID := (CALL ...)`), `COMMIT`,
   then AFTER COMMIT the branch checkpoint + helper36 line, or the
   `SKIPPED` row + plain line.
7. `TERMINATING` via `sp_etl_job_finish` with the same message style as
   now, same `RETURN` format. Exception block identical in shape to now
   (verified character-for-character after whitespace normalisation:
   `ROLLBACK` + `TERMINATING` `JOB_END` `FAILED` checkpoint (v2 form:
   no `STEP_NO 999` argument) + `sp_etl_job_fail`
   + `RAISE`).

## Files

- `ECI/RFM/driver_sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid.sql` (driver)
- `ECI/RFM/steps/sp_snow_step_ECI_RFM_S10_LATEST.sql`
- `ECI/RFM/steps/sp_snow_step_ECI_RFM_S20_KEEPNEW.sql`
- `ECI/RFM/publish/sp_snow_pub_ECI_RFM_STG_ECI_D_MEDICAID.sql`
- `ECI/RFM/RFM_MANIFEST.md` (this file)

## Verification results (all run against the current file)

- Step 10 CTAS: identical to the current file (whitespace-normalised diff).
- Step 20 CTAS: identical to the current file (whitespace-normalised diff).
- Publish INSERT: identical to the current file (whitespace-normalised diff).
- Step checkpoints: identical values to the current step checkpoints
  (only substitution: `:l_job_run_id` → `:P_JOB_RUN_ID`, the step proc's
  own run-id parameter) — SUPERSEDED for the checkpoint call itself by
  the v2 10-argument migration below (same `STEP_NAME` / `STEP_STATUS` /
  `TARGET_TABLE` / message, dropped `STEP_NO` / row-count / work-table
  arguments).
- Driver name/signature: identical to the current main.
- Step 5 drops: identical (both work tables, no checkpoint for drops).
- Outer exception block: identical to the current file.
- Style greps on code (comments excluded): 0 `DROPPED` checkpoint args,
  0 `P_RESUME_STEP`, 0 `CURSOR` statements, TRANSIENT work tables only
  (same two names as now), `P_JOB_RUN_ID` in every new proc (driver +
  2 steps + 1 publish), 0 checkpoint calls inside the publish proc,
  0 checkpoint calls inside the driver's transaction block
  (transaction contains only the conditional branch call).
- Every current step (10, 20) and the publish INSERT has exactly one new
  proc: 2 step procs + 1 publish proc + 1 driver = 4 files.

## Deviations and uncertainties (nothing silently shipped)

1. **Publish checkpoint/summary name changed per the brief, not per the
   original.** The original step-30 checkpoint is `STEP_NAME 'PUBLISH'`
   and its summary line is `'step 30 PUBLISH'`. Per the task spec, the
   driver now uses `'PUBLISH_STG_ECI_D_MEDICAID'` for both. This is the
   only intentional checkpoint/summary rename.
2. **`SKIPPED` vocabulary is a choice to confirm.** `JOB_CONTROL_ETL.STEP_STATUS`
   has NO CHECK constraint (only a DDL comment listing
   `STARTED|COMPLETED|FAILED`), so `'SKIPPED'` rows are written for
   config-skipped steps/mapping. Flag to the user as a choice to confirm.
3. **Existence check also added to the publish proc.** The brief specifies
   the check for step procs; the publish proc got the same pattern so its
   `P_INPUT_TABLES` default is not a dead declaration. The INSERT itself
   is untouched.
4. **RAISE EXCEPTION form used (fallback documented, not used).** The
   existence check raises with
   `RAISE EXCEPTION '<step>: missing input work table ' || :l_missing
   || ' (declared in P_INPUT_TABLES)'`. This has NOT been compiled
   against a live Snowflake here. If it fails to compile, the fallback
   is `EXECUTE IMMEDIATE 'SELECT 1 FROM <missing table>'` to surface
   the native object-not-exists error.
5. **Scalar-call capture form is a compile-time verification item.**
   `l_rows := (CALL proc(...));` / `l_pub_ECI_RFM_STG_ECI_D_MEDICAID := (CALL proc(...));`
   (v2 name; v1 name was `l_pub_rows`)
   has NOT been compiled against a live Snowflake here; verify before use.
6. **Config-chain behaviour.** Skipping an upstream step while a
   downstream step stays enabled is NOT silently absorbed: the downstream
   step's existence check raises on the missing work table and the driver
   fails the run (work tables kept, per the exception handler). Enable
   10 + 20 + 30 together, or disable the mapping at `STEP_NO = 0`.
7. **Config table not found in the workspace.** `COMMON.ETL_RUN_CONFIG_TBL`
   does not exist in `snowflake_multisource/` (no definition was found
   by search); the driver references it exactly as specified
   (`COMMON.ETL_RUN_CONFIG_TBL`, columns `WORKFLOW_NAME`,
   `MAPPING_NAME`, `STEP_NO`, `IS_RUN_ENABLED`, `WORK_TABLES_CONSUMED`).
   Until that table exists, the gather exception handler fires and the
   mapping runs every step — which is the specified safe default, but
   means config-driven skipping cannot be exercised until the table is
   installed. The driver reads only `IS_RUN_ENABLED` and
   `WORK_TABLES_CONSUMED`; `STEP_PROC_NAME`, `IS_DRIVER`,
   `IS_DEPENDENT`, `DEPENDENT_ON`, `WORK_TABLES_PRODUCED` are not
   consumed here.
8. **Parity notes preserved, not fixed.** The Medicaid reactivation
   defect is carried over verbatim: with default
   `P_TEST_LOOKUP_RESULT = 'N'`, step 20 is empty and publish inserts
   0 rows, exactly as IDQ does. Insert-only publish (no TRUNCATE /
   DELETE). No live-Snowflake compile or row-count parity run was
   possible here.

## ASSEMBLY NOTE (coordinator, post-worker normalisation)

The existence-check error form in this mapping's step procs and publish proc was normalised
from `RAISE EXCEPTION '...' || :l_missing;` to a probe query
(`l_probe_sql := 'SELECT 1 FROM ' || TRIM(SPLIT_PART(:l_missing, ',', 1));`
`EXECUTE IMMEDIATE :l_probe_sql;`), because Snowflake Scripting RAISE accepts only a
declared exception name and cannot embed a runtime-discovered table name. Business SQL is
untouched; only the error-raising lines changed. Any statement in this manifest about the
RAISE form is superseded by this note.

## v2 MIGRATION (2026-10-27) — flag rename + 10-argument checkpoint form

### A. Flag / input / publish-count rename (driver file only)

ANOMALY (confirmed against the v1 DECLARE block, not assumed): this
driver never used `l_flag_<digits>` / `l_in_<nn>` / `l_pub_<nn>`. Its
v1 families were `l_cfg_*` (run flags), `l_cons_*` (consumed-table
strings) and `l_pub_rows` (publish row count). The rename rule was
applied to those ACTUAL families, deriving every new name from the
unit's procedure name (strip `sp_snow_step_` / `sp_snow_pub_`, prepend
`l_flag_` / `l_in_` / `l_pub_`); the driver-row flag becomes
`l_flag_ECI_RFM_DRIVER`:

| Old (v1) | New (v2) | Occurrences renamed in driver |
|---|---|---|
| `l_cfg_driver` | `l_flag_ECI_RFM_DRIVER` | 5 |
| `l_cfg_s10` | `l_flag_ECI_RFM_S10_LATEST` | 5 |
| `l_cfg_s20` | `l_flag_ECI_RFM_S20_KEEPNEW` | 5 |
| `l_cfg_pub` | `l_flag_ECI_RFM_STG_ECI_D_MEDICAID` | 6 |
| `l_cons_s10` | `l_in_ECI_RFM_S10_LATEST` | 5 |
| `l_cons_s20` | `l_in_ECI_RFM_S20_KEEPNEW` | 5 |
| `l_cons_pub` | `l_in_ECI_RFM_STG_ECI_D_MEDICAID` | 5 |
| `l_pub_rows` | `l_pub_ECI_RFM_STG_ECI_D_MEDICAID` | 4 (3 remain after checkpoint migration, which drops the checkpoint's row-count argument) |

40 identifier occurrences renamed in total. Renamed everywhere:
DECLARE block, GATHER `INTO` list, `EXCEPTION` COALESCE fallbacks,
`IF` conditions, step/publish call arguments, and the helper36 summary
line. GATHER `SELECT` column order and `INTO` order are unchanged
(only identifiers); business SQL, step numbers, checkpoint `STEP_NAME`
strings and all summary display string literals are unchanged
(e.g. `'step 10 LATEST_HISTORY_ROWS'`, `'step 30
PUBLISH_STG_ECI_D_MEDICAID'` remain exactly as in v1). Step/publish
procs carry none of these variables and were not renamed.

### B. Checkpoint migration (driver + both step procs; publish proc untouched)

New 10-argument form, in exactly this order:
`P_SOURCE, P_JOB_RUN_ID, P_WORKFLOW_NAME, P_MAPPING_NAME, P_STATE,
P_STEP_NAME, P_STEP_STATUS, P_TARGET_TABLE, P_MESSAGE,
P_ERROR_MESSAGE` — always exactly 10 arguments with explicit `NULL`s.
Kept: SOURCE, JOB_RUN_ID, WORKFLOW, MAPPING, STATE, STEP_NAME,
STEP_STATUS, TARGET_TABLE, MESSAGE, ERROR_MESSAGE. Dropped:
`STEP_NO`, `ROW_COUNT`, `SOURCE_ROW_COUNT`, `WORK_TABLE_NAME`,
`WORK_TABLE_ACTION`, `WORK_TABLE_PURPOSE`, `DROP_REASON`.

Calls migrated (verified with balanced-parenthesis parsing, not
single-line grep): driver 6, step 10 proc 1, step 20 proc 1 — total 8.
Old forms were 16 arguments (17 for the driver exception row, which
carried both message and error). New messages are the old final
message argument in every case (step procs: `'Step 10 complete.'` /
`'Step 20 complete.'`; driver SKIPPED rows: the
`'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)'` text; publish
COMPLETED: the `'Published in one transaction: ...'` text; exception
row: the `'Job failed; work tables left in place...'` text, with its
original error text `'See Snowflake query history...'` retained as
`P_ERROR_MESSAGE`; all other new rows pass `NULL` as
`P_ERROR_MESSAGE`). The old step-purpose description strings
(e.g. step 10's "Latest history row per Medicaid record...") were
`WORK_TABLE_PURPOSE` arguments and were dropped, per the mapping —
they do not survive in the checkpoint call; row counts survive only in
`fn_snow_helper36_common` summary lines and step-proc `RETURN` values.
Publish proc verified: 0 `sp_etl_checkpoint` calls (only comment
mentions of the framework rule), file byte-identical to v1.
`sp_etl_job_begin` / `sp_etl_job_finish` / `sp_etl_job_fail` calls
(driver: 1 / 2 / 1) are untouched, as are step numbers everywhere
except as dropped `STEP_NO` checkpoint arguments.

### v2 self-verification (all run against the v2 files)

- Driver regex: 0 matches for `l_flag_[0-9]+`, `l_in_[0-9]+`,
  `l_pub_[0-9]+`; 0 remaining members of the OLD families
  (`l_cfg_driver`, `l_cfg_s10`, `l_cfg_s20`, `l_cfg_pub`, `l_cons_s10`,
  `l_cons_s20`, `l_cons_pub`, `l_pub_rows`).
- Every `sp_etl_checkpoint` call in driver + step procs parses to
  exactly 10 arguments in the new order; zero 16/17-argument calls
  remain; no dropped-parameter tokens (`'CREATED'`, `'NONE'`,
  `'KEPT'`, work-table names) appear as checkpoint arguments.
- Step 10 CTAS, step 20 CTAS and publish INSERT: identical to v1
  (whitespace-normalised diff).
- GATHER `INTO` order still matches `SELECT` order: flags for
  STEP_NO 0, 10, 20, 30 then consumed strings for 10, 20, 30.
- Scope kept: only the 4 RFM files above were changed; the empty
  `driver/` directory, `00_framework/`, the seed file, runners and
  top-level MD files were not touched, and the v1 baseline was not
  modified (v2 code was restored from v1 and re-migrated after a
  first-pass script bug dropped the closing `)` on rewritten calls —
  caught by the balanced-parenthesis verification, not shipped).
- Not verified here: no live Snowflake compile or row-count parity run
  (same standing caveat as v1).
