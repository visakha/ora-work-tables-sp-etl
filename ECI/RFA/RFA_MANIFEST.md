# RFA_MANIFEST — m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr (ECI ONLY)

Config-driven step-driver refactor of the ECI reactivation family-address
mapping. Source of truth: `~/workspace/snowflake_multisource/ECI/mappings/sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr.sql`
(verified against the file before writing; the task's stated structure
matched the file exactly — steps 10/20, publish 30 with 1 INSERT,
no original parameters, 2 work tables).

Constants: `c_source = 'ECI'`, `c_workflow = 'wf_ECI_Stage_Load'`,
`c_mapping = 'm_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr'`.
Config table: `COMMON.ETL_RUN_CONFIG_TBL`
(`WORKFLOW_NAME`, `MAPPING_NAME`, `STEP_NO`, `STEP_PROC_NAME`,
`IS_DRIVER`, `IS_RUN_ENABLED`, `IS_DEPENDENT`, `DEPENDENT_ON`,
`WORK_TABLES_PRODUCED`, `WORK_TABLES_CONSUMED`).
Install schema (as in the current main): `ECI_ETL_WRK` in database
`MDM_ETL_ECI`; all table names unqualified.

## v2 migration (this copy only)

- **Driver flag / input / publish-count variables renamed** from the
  v1 `v_run_*` / `v_in_*` / `l_pub_rows` names (note: v1 never used
  `l_flag_<digits>` names in this mapping — the v1 names were
  `v_run_driver`, `v_run_s10`, `v_run_s20`, `v_run_s30`,
  `v_in_s10`, `v_in_s20`, `v_in_s30`, `l_pub_rows`) to descriptive
  names derived from the unit procedure names:
  `l_flag_ECI_RFA_DRIVER` (driver row, STEP_NO 0),
  `l_flag_ECI_RFA_S10_LATEST`, `l_flag_ECI_RFA_S20_KEEPNEW`,
  `l_flag_ECI_RFA_STG_ECI_D_FAMILY_ADDRESS` (publish branch, step 30),
  `l_in_ECI_RFA_S10_LATEST`, `l_in_ECI_RFA_S20_KEEPNEW`,
  `l_in_ECI_RFA_STG_ECI_D_FAMILY_ADDRESS`, and
  `l_pub_ECI_RFA_STG_ECI_D_FAMILY_ADDRESS` (publish row count, still
  used in the step-30 helper36 summary line). GATHER SELECT order and
  INTO order are unchanged — only the identifiers were renamed.
  Step / publish procs carry none of these variables and are untouched
  by the rename.
- **Checkpoint signature migrated to the new 10-argument form**
  everywhere in this mapping: `sp_etl_checkpoint(P_SOURCE,
  P_JOB_RUN_ID, P_WORKFLOW_NAME, P_MAPPING_NAME, P_STATE,
  P_STEP_NAME, P_STEP_STATUS, P_TARGET_TABLE, P_MESSAGE,
  P_ERROR_MESSAGE)`, always with explicit NULLs. Dropped from every
  call: `STEP_NO`, `ROW_COUNT`, `SOURCE_ROW_COUNT`,
  `WORK_TABLE_NAME`, `WORK_TABLE_ACTION`, `WORK_TABLE_PURPOSE`,
  `DROP_REASON`. Row counts no longer appear in checkpoint rows at
  all; they survive in the driver RETURN summaries and the
  `fn_snow_helper36_common` lines. `sp_etl_job_begin` /
  `sp_etl_job_finish` / `sp_etl_job_fail` calls are untouched, as are
  all checkpoint STEP_NAME strings, summary display strings, step
  numbers (config STEP_NO values and the `step NN ...` summary
  strings), and all business SQL. The publish proc contains no
  checkpoint calls (verified) and is byte-identical to v1.

## Driver signature

`sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr`
(`P_JOB_RUN_ID VARCHAR DEFAULT NULL`) `RETURNS VARCHAR` — name and
signature IDENTICAL to the current main procedure (verified by
extraction + comparison). File:
`ECI/RFA/driver_sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr.sql`

Driver flow: job-run-id generation (copied verbatim from the current
main) + `sp_etl_job_begin` → GATHER config (nested BEGIN/EXCEPTION;
flags default `'Y'`, consumed strings default to the literals in the
table below; on exception the defaults stand) → driver-row skip
(`STEP_NO = 0` = `'N'`: SKIPPED checkpoint `MAPPING_SKIPPED`,
`sp_etl_job_finish`, RETURN — BEFORE step 5 cleanup) → step 5 cleanup
(bare `DROP TABLE IF EXISTS` for both work tables, no checkpoint) →
conditional step 10 / step 20 calls (executed: helper36 summary line;
skipped: SKIPPED checkpoint + plain-text summary line, NO helper36) →
publish transaction (`BEGIN TRANSACTION`, conditional branch CALL,
`COMMIT`, checkpoint AFTER COMMIT only) → `sp_etl_job_finish` +
`'JOB_RUN_ID=' || ...` RETURN → exception block identical in shape to
the current main (`ROLLBACK` + TERMINATING FAILED checkpoint
(`JOB_END`; v2: no STEP_NO argument is passed any more) +
`sp_etl_job_fail` + `RAISE`).

This mapping's outcome IS the STATUS / dimension write: the publish
writes `STG_ECI_D_FAMILY_ADDRESS` (the reactivation delta/status table).
There is NO EXC branch and NO non-spine branch — the single publish
branch below is the whole publish.

## Step table

| STEP_NO | Proc | Kind | Produces | Consumes default | Original params used | Checkpoint STEP_NAME |
|---|---|---|---|---|---|---|
| 10 | `sp_snow_step_ECI_RFA_S10_LATEST` | STEP | `WRK_ECI_RFA_S10_LATEST` — latest history row per address of reactivated families | `` (empty — reads base tables `STG_ECI_H_FAMILY_ADDRESS` + view `V_ECI_ETL_LU_REACTIVATED_ID`, not work tables; existence check skipped) | NONE (mapping has no original params; `P_RUN_TS` accepted but unused — the original step has no run-timestamp column) | `LATEST_HISTORY_ROWS` |
| 20 | `sp_snow_step_ECI_RFA_S20_KEEPNEW` | STEP | `WRK_ECI_RFA_S20_KEEPNEW` — latest rows not already in the delta table | `WRK_ECI_RFA_S10_LATEST` | NONE (`P_RUN_TS` accepted but unused) | `KEEP_NEW_ONLY` |

Step proc files: `ECI/RFA/steps/sp_snow_step_ECI_RFA_S10_LATEST.sql`,
`ECI/RFA/steps/sp_snow_step_ECI_RFA_S20_KEEPNEW.sql`.
Step proc signature (both): `P_JOB_RUN_ID VARCHAR, P_RUN_TS
TIMESTAMP_NTZ, P_INPUT_TABLES VARCHAR DEFAULT '<consumes default above>'`,
`RETURNS NUMBER`. Each step proc: input existence check (split
`P_INPUT_TABLES` on `|`, check `INFORMATION_SCHEMA.TABLES` for
`TABLE_SCHEMA = CURRENT_SCHEMA()`; missing table → `RAISE EXCEPTION`
naming the table(s) and step) → its CTAS VERBATIM → `SELECT COUNT(*)`
→ its own checkpoint with the SAME values as the current step
checkpoint → `RETURN :l_rows`. No exception block, no transactions,
no target writes. `P_INPUT_TABLES` is a dependency declaration +
runtime check, NOT dynamic SQL — Snowflake cannot parameterise table
names in static SQL, so each CTAS still names its sources literally.

## Branch table (publish)

| STEP_NO | Proc | Kind | Target | Consumes |
|---|---|---|---|---|
| 30 | `sp_snow_pub_ECI_RFA_STG_ECI_D_FAMILY_ADDRESS` | PUBLISH_BRANCH (single INSERT; STATUS / dimension write — this mapping's outcome) | `STG_ECI_D_FAMILY_ADDRESS` | `WRK_ECI_RFA_S20_KEEPNEW` |

Publish proc file:
`ECI/RFA/publish/sp_snow_pub_ECI_RFA_STG_ECI_D_FAMILY_ADDRESS.sql`.
Signature: `P_JOB_RUN_ID VARCHAR, P_RUN_TS TIMESTAMP_NTZ,
P_INPUT_TABLES VARCHAR DEFAULT 'WRK_ECI_RFA_S20_KEEPNEW'`, `RETURNS
NUMBER`. Body: the current step-30 INSERT verbatim, then `RETURN
SQLROWCOUNT`. NO transaction control, NO checkpoint calls (framework
rule — the driver checkpoints the branch only AFTER COMMIT).
Checkpoint written by the driver after COMMIT (v2 10-argument form):
STATE `'WORKING'`, STEP_NAME `PUBLISH_STG_ECI_D_FAMILY_ADDRESS`,
STEP_STATUS `'COMPLETED'`, TARGET_TABLE `STG_ECI_D_FAMILY_ADDRESS`,
MESSAGE = the publish message, ERROR_MESSAGE = NULL (no ROW_COUNT
and no STEP_NO argument any more; the branch count survives only in
the step-30 helper36 summary line). A config-disabled branch writes a
SKIPPED row + plain summary line instead; the branch proc is then not
called at all.

## Verification performed in v2 (no live Snowflake here)

- Flag rename: 26 identifier occurrences renamed in the driver only
  (3 + 3 + 3 + 4 flag occurrences, 3 + 3 + 3 input occurrences, 4
  publish-count occurrences — the publish-count occurrence inside the
  old checkpoint call was then dropped by the checkpoint rewrite, so
  3 remain in the file). Regex over the driver: 0 matches for
  `l_flag_[0-9]+`, `l_in_[0-9]+`, `l_pub_[0-9]+`, and 0 remaining
  `v_run_*` / `v_in_*` / `l_pub_rows`. GATHER INTO order still
  matches SELECT order (flags 0/10/20/30, then consumed 10/20/30).
- Checkpoint migration: 8 calls migrated (driver 6, S10 1, S20 1),
  every one verified with balanced-parenthesis parsing to exactly 10
  arguments in the new order
  (SOURCE, JOB_RUN_ID, WORKFLOW, MAPPING, STATE, STEP_NAME,
  STEP_STATUS, TARGET_TABLE, MESSAGE, ERROR_MESSAGE). Zero 16/17-arg
  calls remain; zero references to the dropped parameters as call
  arguments. Message texts and error texts are unchanged (the
  exception message still says work tables are left in place).
- Business SQL: S10 CTAS, S20 CTAS and the publish INSERT each
  compared whitespace-normalised against v1: all three IDENTICAL.
  Publish proc byte-identical to v1 (0 checkpoint calls, as before).
  `sp_etl_job_begin` / `sp_etl_job_finish` / `sp_etl_job_fail` calls,
  helper36 lines, and all summary display strings are unchanged
  except for the renamed variable references.

## Verification performed in v1 (no live Snowflake here)

- S10 CTAS, S20 CTAS and the publish INSERT each extracted from the
  current main and from the new proc and compared whitespace-normalised:
  all three IDENTICAL. Allowed diffs only: none needed — no
  `:l_run_ts` or `:c_mapping` references exist in this mapping's
  step/publish SQL (no run-timestamp column, no mapping-name literal),
  so the substitutions were vacuous; the checkpoint calls use the
  local `c_mapping`/`c_source`/`c_workflow` constants with identical
  values.
- Step checkpoint calls compared the same way (after substituting the
  constant names): S10 and S20 IDENTICAL to the current main.
- Driver name + parameter list extracted and compared: IDENTICAL to
  the current main. Job-run-id generation block: preserved verbatim
  (including its original shape — an `IF` on the still-uninitialised
  `l_job_run_id`, whose `COALESCE` picks up a supplied
  `P_JOB_RUN_ID`). Driver exception block (last `EXCEPTION` block):
  IDENTICAL to the current main.
- Coverage: every current step and the publish INSERT has exactly one
  new proc — 2 step procs + 1 publish proc + 1 driver = 4 files.
- Greps over all 4 files: 0 `DROPPED`, 0 `P_RESUME_STEP`, 0 cursors
  (the single `cursor` hit is the word in a header comment: "No CURSOR
  was used"), 0 `sp_etl_checkpoint` calls in the publish proc, 0
  transaction statements in step/publish procs, 0 checkpoints between
  the driver's `BEGIN TRANSACTION` and `COMMIT`, only `TRANSIENT`
  work-table creates, `P_JOB_RUN_ID` in every new proc, step-5 drops
  for exactly the 2 work tables, 3 helper36 lines (executed paths
  only), 4 SKIPPED checkpoint sites (driver row + steps 10/20 +
  publish branch).

## Deviations and uncertainties (nothing silently shipped)

1. **Publish checkpoint STEP_NAME changed** (per the refactor spec):
   current main uses plain `'PUBLISH'`; the driver now checkpoints
   `'PUBLISH_STG_ECI_D_FAMILY_ADDRESS'` (`PUBLISH_<TARGET>`), and the
   executed-publish summary line uses the same label. TARGET_TABLE
   and message are unchanged; v2 note: STEP_NO 30 is still the config
   step number gating the branch, but it is no longer passed as a
   checkpoint argument, and the branch row count is no longer stored
   in the checkpoint row (it survives in the helper36 summary line).
   Flag to the user if downstream reporting keys on `'PUBLISH'` or on
   checkpoint STEP_NO / ROW_COUNT columns.
2. **Compile-time verification items (no live Snowflake here):**
   (a) scalar-call return capture `l_rows := (CALL proc(...));` in the
   driver (3 sites); (b) the `RAISE EXCEPTION '<msg>' || :l_missing;`
   form used by the step/publish existence checks — chosen to match
   the sibling PTY step procs already written in this refactor, but
   note the current Snowflake `RAISE` docs show only
   `RAISE <declared-exception-name>;`, so this form itself needs a
   compile check. Documented fallback if it fails to compile:
   `EXECUTE IMMEDIATE 'SELECT 1 FROM <missing table>'` to surface the
   native object-not-exists error naming the table.
3. **`P_RUN_TS` is unused by this mapping's SQL** (no run-timestamp
   column in the original CTAS/INSERT). It is accepted for a uniform
   step/publish signature and the driver passes
   `CURRENT_TIMESTAMP()` captured at driver start (`l_run_ts`, a new
   driver variable — the current main had none).
4. **Partial-skip behaviour (no cross-step guard added, per spec):**
   skipping step 20 while publish is enabled (or step 10 while step 20
   is enabled) fails, because step 5 already dropped the work table
   the later step/branch reads; the existence check (or the missing
   table error) surfaces it through the driver handler, which leaves
   work tables in place. A skipped publish branch still runs an empty
   `BEGIN TRANSACTION ... COMMIT` (no statements inside) before its
   SKIPPED checkpoint, per the spec's publish structure.
5. **SKIPPED vocabulary — user confirmation needed:**
   `JOB_CONTROL_ETL.STEP_STATUS` has NO CHECK constraint (only a DDL
   comment listing `STARTED | COMPLETED | FAILED`), so `'SKIPPED'`
   rows are used for config-disabled driver/steps/branch. Flagged in
   the driver header as a choice to confirm.
6. **Publish proc has the same input-existence check as the step
   procs.** The publish spec did not explicitly require it, but
   `P_INPUT_TABLES` would otherwise be dead; the check is the only
   code in the publish proc beyond the verbatim INSERT + `SQLROWCOUNT`
   return. No checkpoint or transaction was added to it.
7. **Driver-skip summary line:** the spec mandated checkpoint +
   finish + early RETURN for a driver-row skip; the driver also
   appends one plain-text `MAPPING_SKIPPED: ...` summary line so the
   RETURN format stays `'JOB_RUN_ID=' || ... || summary` in all paths.
8. **Non-work-table reads are not dependencies:** step 10's
   `STG_ECI_H_FAMILY_ADDRESS` and `V_ECI_ETL_LU_REACTIVATED_ID`, and
   step 20's guard read of `STG_ECI_D_FAMILY_ADDRESS`, are base/lookup
   reads, not work-table dependencies — they are not listed in any
   `P_INPUT_TABLES` default and are not existence-checked. The
   `V_ECI_ETL_LU_REACTIVATED_ID` view definition was not in scope to
   verify (preserved as referenced by the original).
9. **Parity notes carried over unchanged from the current main:**
   insert-only (no `TRUNCATE`/`DELETE`); keep-new filter evaluated in
   step 20 before any insert, so it sees the pre-publish delta table;
   no validation rule runs here; the split is the closest sensible
   split of a single INSERT with no CTE chain (flagged in the original).

## ASSEMBLY NOTE (coordinator, post-worker normalisation)

The existence-check error form in this mapping's step procs and publish proc was normalised
from `RAISE EXCEPTION '...' || :l_missing;` to a probe query
(`l_probe_sql := 'SELECT 1 FROM ' || TRIM(SPLIT_PART(:l_missing, ',', 1));`
`EXECUTE IMMEDIATE :l_probe_sql;`), because Snowflake Scripting RAISE accepts only a
declared exception name and cannot embed a runtime-discovered table name. Business SQL is
untouched; only the error-raising lines changed. Any statement in this manifest about the
RAISE form is superseded by this note.
