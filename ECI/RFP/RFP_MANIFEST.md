# RFP_MANIFEST — m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn (ECI, config-driven step driver)

## v2 migration (2026-10-27) — flag rename + 10-argument checkpoint form

This v2 copy differs from v1 in exactly two ways (plus this manifest):

1. **Driver flag / input variables renamed from step numbers to proc-derived names.**
   The v1 driver used `l_flag_driver`, `l_flag_s10`, `l_flag_s20`, `l_flag_s30`,
   `l_cons_s10`, `l_cons_s20`, `l_cons_s30`, `l_pub_skipped`. The v2 names strip
   the `sp_snow_step_` / `sp_snow_pub_` prefix from the unit's procedure name:

   | v1 name | v2 name | derived from |
   |---|---|---|
   | `l_flag_driver` | `l_flag_ECI_RFP_DRIVER` | driver row (STEP_NO 0) |
   | `l_flag_s10` | `l_flag_ECI_RFP_S10_LATEST` | `sp_snow_step_ECI_RFP_S10_LATEST` |
   | `l_flag_s20` | `l_flag_ECI_RFP_S20_KEEPNEW` | `sp_snow_step_ECI_RFP_S20_KEEPNEW` |
   | `l_flag_s30` | `l_flag_ECI_RFP_STG_ECI_D_FAMILY_PHONE` | `sp_snow_pub_ECI_RFP_STG_ECI_D_FAMILY_PHONE` (publish branch, step 30, verified from the driver code) |
   | `l_cons_s10` | `l_in_ECI_RFP_S10_LATEST` | `sp_snow_step_ECI_RFP_S10_LATEST` |
   | `l_cons_s20` | `l_in_ECI_RFP_S20_KEEPNEW` | `sp_snow_step_ECI_RFP_S20_KEEPNEW` |
   | `l_cons_s30` | `l_in_ECI_RFP_STG_ECI_D_FAMILY_PHONE` | `sp_snow_pub_ECI_RFP_STG_ECI_D_FAMILY_PHONE` |
   | `l_pub_skipped` | `l_pub_ECI_RFP_STG_ECI_D_FAMILY_PHONE_skipped` | publish-branch skip boolean for `sp_snow_pub_ECI_RFP_STG_ECI_D_FAMILY_PHONE` |

   Renamed everywhere in the driver: DECLARE block, GATHER INTO list, IF
   conditions, step/publish call arguments, and the publish-skip boolean's
   assignments. GATHER SELECT column order and INTO order are unchanged (only
   identifiers); step numbers, checkpoint STEP_NAME strings, and all summary
   display string literals are unchanged. Step/publish procs carry none of
   these variables and are untouched by the rename.
2. **Every `sp_etl_checkpoint` call migrated to the new 10-argument form**, in
   this order: `P_SOURCE, P_JOB_RUN_ID, P_WORKFLOW_NAME, P_MAPPING_NAME,
   P_STATE, P_STEP_NAME, P_STEP_STATUS, P_TARGET_TABLE, P_MESSAGE,
   P_ERROR_MESSAGE` — always exactly 10 arguments with explicit NULLs.
   Dropped from the old form: `STEP_NO`, `ROW_COUNT`, `SOURCE_ROW_COUNT`,
   `WORK_TABLE_NAME`, `WORK_TABLE_ACTION`, `WORK_TABLE_PURPOSE`, `DROP_REASON`.
   Kept values are unchanged (source, job run id, workflow, mapping, state,
   STEP_NAME, STEP_STATUS, target table, message text, error message). Row
   counts no longer travel in checkpoints; they survive in the driver's
   `fn_snow_helper36_common` summary lines and the step procs' RETURN values.
   `sp_etl_job_begin` / `sp_etl_job_finish` / `sp_etl_job_fail` are separate
   procedures and are untouched. The publish proc still contains NO checkpoint
   call — only a header comment mentioning `sp_etl_checkpoint`, which does not
   describe the old argument form and was left untouched (verified: 0
   `sp_etl_checkpoint(` occurrences in the publish file).
   Calls migrated: driver 6 (`MAPPING_SKIPPED`, step 10 skip, step 20 skip,
   publish skip, publish completed, exception `JOB_END`), step 10 completed,
   step 20 completed — 8 total, 0 old-form calls remain.

Mapping: `m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn` — reactivation, family phones.
Workflow: `wf_ECI_Stage_Load`. Source: `ECI`. Prefix: `ECI_RFP`, short `RFP`.
Source of truth: `~/workspace/snowflake_multisource/ECI/mappings/sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn.sql`
and `~/workspace/snowflake_multisource/ECI/STEP_MAP_ECI.md` §4. The current main's
structure matched the task description exactly (steps 10/20, publish 30, one INSERT);
no structural discrepancy was found. This mapping is ECI ONLY; no other source was
touched. Other directories already present under `~/workspace/snowflake_eci_drivers/ECI/`
belong to sibling mappings and were not modified — only read (see "Cross-check note").

Business flow (top to bottom — this mapping's outcome IS the dimension/status write):
latest history phone row per reactivated family → keep-new filter → one INSERT into
`STG_ECI_D_FAMILY_PHONE`. There is no EXC branch, no second target, no non-spine branch.

## Driver

Driver signature (identical to the current main — verified by diff of the
`CREATE OR REPLACE PROCEDURE` lines):

```sql
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn (
    P_JOB_RUN_ID VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
```

File: `ECI/RFP/driver_sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn.sql`

Driver behaviour: job-run-id generation exactly as now, then `sp_etl_job_begin`;
GATHER from `COMMON.ETL_RUN_CONFIG_TBL` (flags pre-initialised `'Y'`, consumed
strings to defaults; nested `BEGIN/EXCEPTION` leaves defaults standing on any
config-table error); driver-row flag (`l_flag_ECI_RFP_DRIVER`, config
`STEP_NO = 0`) `'N'` writes a `MAPPING_SKIPPED` checkpoint (10-argument form,
no `STEP_NO` argument), finishes with a skipped message, and RETURNs before step 5 cleanup;
step 5 drops both work tables with no checkpoint for drops (unchanged); steps and
the publish branch run conditionally with `SKIPPED` checkpoints + plain-text summary
lines on skip (helper36 is used only for executed steps/branches); publish runs
inside `BEGIN TRANSACTION ... COMMIT` with its checkpoint written only AFTER COMMIT;
TERMINATING via `sp_etl_job_finish` with the same message style and RETURN format as
now; exception block identical to now except the checkpoint form (ROLLBACK,
TERMINATING `JOB_END` FAILED checkpoint in the new 10-argument form — the old
`999` STEP_NO argument is dropped, message text unchanged — `sp_etl_job_fail`, RAISE).

## Step table

| STEP_NO | proc | kind | produces | consumes default | original params used | checkpoint STEP_NAME |
|---|---|---|---|---|---|---|
| 10 | `sp_snow_step_ECI_RFP_S10_LATEST` (`ECI/RFP/steps/sp_snow_step_ECI_RFP_S10_LATEST.sql`) | step (CTAS, TRANSIENT) | `WRK_ECI_RFP_S10_LATEST` — latest history row per phone record of reactivated families | `` (empty — no work-table inputs; base tables `STG_ECI_H_FAMILY_PHONE`, `V_ECI_ETL_LU_REACTIVATED_ID` are not work-table dependencies, so the existence check is skipped) | NONE — the original mapping has no parameters | `LATEST_HISTORY_ROWS` |
| 20 | `sp_snow_step_ECI_RFP_S20_KEEPNEW` (`ECI/RFP/steps/sp_snow_step_ECI_RFP_S20_KEEPNEW.sql`) | step (CTAS, TRANSIENT) | `WRK_ECI_RFP_S20_KEEPNEW` — latest rows not already in the delta table | `WRK_ECI_RFP_S10_LATEST` | NONE — the original mapping has no parameters | `KEEP_NEW_ONLY` |

Step proc signature (both steps):

```sql
(P_JOB_RUN_ID VARCHAR, P_RUN_TS TIMESTAMP_NTZ, P_INPUT_TABLES VARCHAR DEFAULT '<consumes default above>')
RETURNS NUMBER
```

Each step proc: (1) input existence check — skipped when `P_INPUT_TABLES` is
NULL/empty, otherwise a single aggregate query over `SPLIT_TO_TABLE(..., '|')`
against `INFORMATION_SCHEMA.TABLES` in `CURRENT_SCHEMA()`; (2) the step's CTAS
verbatim from the current main (verified identical after whitespace normalisation);
(3) `SELECT COUNT(*) INTO :l_rows`; (4) its own checkpoint with the SAME
STEP_NAME, TARGET_TABLE, and message as the current step checkpoint (verified
identical after the `:l_job_run_id` → `:P_JOB_RUN_ID` substitution and the v2
10-argument migration, which drops STEP_NO, ROW_COUNT, and the work-table
arguments); (5) `RETURN :l_rows`. No exception block, no
transactions, no target writes. `P_INPUT_TABLES` is a dependency declaration +
runtime check, NOT dynamic SQL: the CTAS still reads its fixed table names.

## Branch table

| STEP_NO | proc | kind | target | consumes |
|---|---|---|---|---|
| 30 | `sp_snow_pub_ECI_RFP_STG_ECI_D_FAMILY_PHONE` (`ECI/RFP/publish/sp_snow_pub_ECI_RFP_STG_ECI_D_FAMILY_PHONE.sql`) | publish (single INSERT, STATUS/dimension write) | `STG_ECI_D_FAMILY_PHONE` | `WRK_ECI_RFP_S20_KEEPNEW` |

Publish proc signature:

```sql
(P_JOB_RUN_ID VARCHAR, P_RUN_TS TIMESTAMP_NTZ, P_INPUT_TABLES VARCHAR DEFAULT 'WRK_ECI_RFP_S20_KEEPNEW')
RETURNS NUMBER
```

Publish proc: the step 30 INSERT verbatim from the current main (verified
identical after whitespace normalisation), then `l_rows := SQLROWCOUNT; RETURN
:l_rows`. It also runs the same input existence check as the step procs. NO
transaction control, NO checkpoint calls — the driver checkpoints the branch
only after COMMIT (framework rule). Driver publish checkpoint (v2, 10-argument
form): STATE `WORKING`, STEP_NAME `PUBLISH_STG_ECI_D_FAMILY_PHONE`, STEP_STATUS
`COMPLETED` (or `SKIPPED`), TARGET_TABLE `STG_ECI_D_FAMILY_PHONE`, MESSAGE as
before, ERROR_MESSAGE NULL. The old form's STEP_NO 30 and ROW_COUNT arguments
are dropped; the branch row count now survives only in the driver's helper36
summary line (`step 30 PUBLISH_STG_ECI_D_FAMILY_PHONE`, via `:l_rows`), not in
the checkpoint.

## Deviations and uncertainties (nothing silently shipped)

1. **Publish STEP_NAME changed, per task spec (f).** The current main's step 30
   checkpoint uses STEP_NAME `PUBLISH`; the driver uses `PUBLISH_STG_ECI_D_FAMILY_PHONE`
   (`PUBLISH_<TARGET>`), and the step 30 helper36 summary label changes the same way.
   Everything else in the publish checkpoint (target, row count, message) is identical
   to the current main. Confirm this rename is intended for downstream reporting.
2. **No `:l_run_ts` substitution was needed — because the original has none.**
   Grep of the current main finds no `l_run_ts` / `RUN_TS` reference in any step or
   the publish INSERT (no column in this mapping carries a run timestamp). The driver
   therefore adds `l_run_ts := CURRENT_TIMESTAMP()` at start and passes it as
   `P_RUN_TS` to every step/publish proc for signature uniformity; it is unused by
   this mapping's SQL. Likewise there are no mapping-name references in the step
   CTAS/publish INSERT to substitute — the mapping name lives only in the local
   `c_mapping` constants and the checkpoint/helper36 calls.
3. **Missing-table error uses the EXECUTE IMMEDIATE fallback, not RAISE EXCEPTION.**
   Snowflake Scripting's `RAISE` syntax is `RAISE <exception_name>;` only (docs:
   `docs.snowflake.com/sql-reference/snowflake-scripting/raise`) — a declared
   exception carries a static message and cannot name a dynamically found table.
   The step/publish procs therefore use `EXECUTE IMMEDIATE 'SELECT 1 FROM
   <missing table>'`, which fails with Snowflake's native object-not-exists error
   naming the table; the error propagates to the driver handler. This is the
   fallback the task itself sanctions. Verify on first live compile.
4. **Scalar-call capture is a compile-time verification item.** The driver uses
   `l_rows := (CALL proc(...));` exactly as specified. There is no live Snowflake
   here, so this form, the nested GATHER `BEGIN/EXCEPTION` block, the
   `SELECT ... INTO` with seven variables (now `l_flag_ECI_RFP_DRIVER`,
   `l_flag_ECI_RFP_S10_LATEST`, `l_flag_ECI_RFP_S20_KEEPNEW`,
   `l_flag_ECI_RFP_STG_ECI_D_FAMILY_PHONE`, `l_in_ECI_RFP_S10_LATEST`,
   `l_in_ECI_RFP_S20_KEEPNEW`, `l_in_ECI_RFP_STG_ECI_D_FAMILY_PHONE`, in
   the same order as v1), and the `SPLIT_TO_TABLE` existence
   check must all be confirmed at first live compile. Fallback for the call form
   (if it does not compile) is `CALL ... INTO :l_rows` or equivalent, with no
   other change.
5. **Skipped-step dependencies are NOT enforced.** Flags are honoured independently;
   `IS_DEPENDENT` / `DEPENDENT_ON` are not consulted. Skipping step 10 while step 20
   is enabled fails at step 20 (step 5 dropped `WRK_ECI_RFP_S10_LATEST`), and
   skipping step 20 while publish is enabled fails at publish (step 5 dropped
   `WRK_ECI_RFP_S20_KEEPNEW`). To skip downstream work, disable downstream steps
   too. Confirm this is the intended config behaviour, or ask for a dependency
   guard to be added.
6. **`SKIPPED` as a STEP_STATUS value is a user choice to confirm.**
   `JOB_CONTROL_ETL.STEP_STATUS` has NO CHECK constraint (only a DDL comment
   listing `STARTED | COMPLETED | FAILED`), so `SKIPPED` rows are used for
   config-skipped steps, the skipped mapping, and the skipped publish branch.
   Either accept `SKIPPED` or add it to the DDL comment / a constraint.
7. **Config value assumptions, unverified against a live config table.**
   `IS_RUN_ENABLED` is treated as VARCHAR `'Y'`/`'N'` and `WORK_TABLES_CONSUMED` as a
   pipe-delimited VARCHAR, per the task spec; if either column has a different type
   (e.g. BOOLEAN), the GATHER comparisons will need adjusting — but the GATHER
   exception handler means a type error degrades to defaults, not a failed run.
   The gathered consumed strings are passed as `P_INPUT_TABLES`, so a config value
   naming a table the step does not actually read will fail the existence check
   fast rather than being silently ignored.
8. **Driver-skip summary line is driver-added.** The task specifies the driver-row
   skip checkpoint and finish message but no summary line; the driver appends the
   plain line `MAPPING_SKIPPED: SKIPPED by config (IS_RUN_ENABLED = N)` so the
   RETURN value is not just a header. Step/branch skip summary lines follow the
   task's exact wording.
9. **Cross-check note (sibling mapping, not changed).** The sibling RFA driver
   already in `snowflake_eci_drivers` uses `RAISE EXCEPTION '...' || :l_missing;`
   in its step procs. Per the Snowflake `RAISE` syntax above, that form does not
   exist in Snowflake Scripting, so RFP deliberately does NOT copy it and uses
   the EXECUTE IMMEDIATE fallback instead. The parent may want to reconcile RFA
   (and any other sibling using that form) to the same fallback. No sibling file
   was modified here.

## Self-verification performed (no live Snowflake)

- Step 10 CTAS, step 20 CTAS, and publish INSERT each verified identical to the
  current main after whitespace normalisation (only allowed diffs: parameter /
  run-ts substitution — vacuous here, see item 2 — existence check, checkpoint
  placement).
- Step 10 and step 20 checkpoints verified identical to the current main's in
  STEP_NAME, TARGET_TABLE, and message, after the `:l_job_run_id` →
  `:P_JOB_RUN_ID` substitution and the v2 migration to the 10-argument form
  (STEP_NO, ROW_COUNT, work-table name/action/purpose arguments dropped);
  publish checkpoint verified identical except the STEP_NAME rename in item 1
  and the same 10-argument migration (ROW_COUNT dropped); final exception block
  verified identical to the current main's except the checkpoint form (STEP_NO
  999 dropped, message text unchanged).
- Driver name/signature verified identical to the current main by diff; step 5
  drops verified unchanged (2 tables, no checkpoint for drops); driver checkpoint
  calls: 6 (`MAPPING_SKIPPED`, step 10 skip, step 20 skip, publish skip, publish
  completed, exception), each exactly 10 arguments in the new order — none
  between `BEGIN TRANSACTION` and `COMMIT`.
- Every current step and the publish INSERT has exactly one new proc (2 steps +
  1 publish branch, no more, no fewer); `P_JOB_RUN_ID` present in all 4 new procs.
- Style greps over the RFP code bodies (after `CREATE OR REPLACE PROCEDURE`):
  0 `DROPPED` checkpoint args, 0 `P_RESUME_STEP`, 0 `CURSOR`, TRANSIENT work
  tables only with the same names as now, 0 checkpoint calls and 0 transaction
  statements in the publish proc (the single `BEGIN TRANSACTION` in the whole
  RFP set is the driver's publish transaction; `ROLLBACK` appears only in the
  driver's exception handler). The words `DROPPED`/`CURSOR` appear only in
  explanatory header comments, never as code.
- Not verified (needs live Snowflake): compilation of all 4 procs, the
  scalar-call capture form, the GATHER block, the existence check, and row-count
  parity against the current main.
