# PHN_MANIFEST — m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr (ECI ONLY, config-driven step-driver refactor)

Example for user feedback. No other source was touched.

Source of truth read first:
`~/workspace/snowflake_multisource/ECI/mappings/sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr.sql`
(step map `~/workspace/snowflake_multisource/ECI/STEP_MAP_ECI.md` §7 agrees with it;
the task's stated structure was verified against the file and matches exactly —
5 staged steps, publish with 4 INSERTs in the stated order. No structural deviation.)

Base dir: `~/workspace/snowflake_eci_drivers/ECI/PHN/`
(`driver_*.sql`, `steps/`, `publish/`, this manifest.)

## v2 migration (2026-10-27) — flag rename + 10-argument checkpoint

Baseline for this migration is the v1 driver package in
`~/workspace/snowflake_eci_drivers/ECI/PHN/` (read-only, untouched).
Only this mapping's driver, its 5 step procs and this manifest changed;
the 4 publish-branch procs are byte-identical to v1.

### Actual v1 variable families (inspected in the DECLARE block, not assumed)

The v1 PHN driver did **not** use `l_flag_<digits>`. Its families were:

- run flags: `l_run_driver`, `l_run_10`, `l_run_20`, `l_run_30`,
  `l_run_40`, `l_run_50`, `l_run_60`, `l_run_70`, `l_run_80`, `l_run_90`
- consumed-table strings: `l_in_10` … `l_in_90`
- publish counts: `l_pub_60`, `l_pub_70`, `l_pub_80`, `l_pub_90`

(`l_run_ts` is an unrelated run-timestamp variable, not a flag, and is
unchanged.) The rename rule was applied to these actual families:
strip `sp_snow_step_` / `sp_snow_pub_` from the unit's procedure name,
prepend `l_flag_` / `l_in_` / `l_pub_`; the driver-row flag becomes
`l_flag_ECI_PHN_DRIVER`. Branch step-number assignment was verified
from the driver code itself (not file order): 60 =
`sp_snow_pub_ECI_PHN_C_S_ECI_PTY_RLE_PHN`, 70 =
`sp_snow_pub_ECI_PHN_EXC_STG_BAD_REC_MEMB_PHONE`, 80 =
`sp_snow_pub_ECI_PHN_C_S_ECI_PTY_RLE_EADDR`, 90 =
`sp_snow_pub_ECI_PHN_EXC_STG_BAD_REC_MEMB_EMAIL`.

| Unit | `l_flag_*` | `l_in_*` | `l_pub_*` |
|---|---|---|---|
| Driver row (STEP_NO 0) | `l_flag_ECI_PHN_DRIVER` | — | — |
| Step 10 `sp_snow_step_ECI_PHN_S10_SRC` | `l_flag_ECI_PHN_S10_SRC` | `l_in_ECI_PHN_S10_SRC` | — |
| Step 20 `sp_snow_step_ECI_PHN_S20_ACTIVE` | `l_flag_ECI_PHN_S20_ACTIVE` | `l_in_ECI_PHN_S20_ACTIVE` | — |
| Step 30 `sp_snow_step_ECI_PHN_S30_DQ` | `l_flag_ECI_PHN_S30_DQ` | `l_in_ECI_PHN_S30_DQ` | — |
| Step 40 `sp_snow_step_ECI_PHN_S40_ROUTED` | `l_flag_ECI_PHN_S40_ROUTED` | `l_in_ECI_PHN_S40_ROUTED` | — |
| Step 50 `sp_snow_step_ECI_PHN_S50_READY` | `l_flag_ECI_PHN_S50_READY` | `l_in_ECI_PHN_S50_READY` | — |
| Branch 60 `sp_snow_pub_ECI_PHN_C_S_ECI_PTY_RLE_PHN` | `l_flag_ECI_PHN_C_S_ECI_PTY_RLE_PHN` | `l_in_ECI_PHN_C_S_ECI_PTY_RLE_PHN` | `l_pub_ECI_PHN_C_S_ECI_PTY_RLE_PHN` |
| Branch 70 `sp_snow_pub_ECI_PHN_EXC_STG_BAD_REC_MEMB_PHONE` | `l_flag_ECI_PHN_EXC_STG_BAD_REC_MEMB_PHONE` | `l_in_ECI_PHN_EXC_STG_BAD_REC_MEMB_PHONE` | `l_pub_ECI_PHN_EXC_STG_BAD_REC_MEMB_PHONE` |
| Branch 80 `sp_snow_pub_ECI_PHN_C_S_ECI_PTY_RLE_EADDR` | `l_flag_ECI_PHN_C_S_ECI_PTY_RLE_EADDR` | `l_in_ECI_PHN_C_S_ECI_PTY_RLE_EADDR` | `l_pub_ECI_PHN_C_S_ECI_PTY_RLE_EADDR` |
| Branch 90 `sp_snow_pub_ECI_PHN_EXC_STG_BAD_REC_MEMB_EMAIL` | `l_flag_ECI_PHN_EXC_STG_BAD_REC_MEMB_EMAIL` | `l_in_ECI_PHN_EXC_STG_BAD_REC_MEMB_EMAIL` | `l_pub_ECI_PHN_EXC_STG_BAD_REC_MEMB_EMAIL` |

Rename counts in the driver (DECLARE + GATHER INTO + IF conditions +
calls/summaries): every `l_run_*` occurrence renamed (driver row 3,
each step flag 3, each branch flag 4), every `l_in_*` 3, every
`l_pub_*` 4 in the pre-migration text (DECLARE, transaction assignment,
old publish-COMPLETED checkpoint row-count argument, helper36 summary;
the checkpoint row-count argument is dropped by the checkpoint rewrite,
so each `l_pub_*` now occurs 3 times). GATHER SELECT column order and
INTO order are unchanged (only identifiers renamed); all summary string
literals (`'step 10 …'`, etc.) are unchanged.

### New checkpoint signature (all `sp_etl_checkpoint` calls in this mapping)

```sql
CALL sp_etl_checkpoint(P_SOURCE, P_JOB_RUN_ID, P_WORKFLOW_NAME, P_MAPPING_NAME,
    P_STATE, P_STEP_NAME, P_STEP_STATUS, P_TARGET_TABLE, P_MESSAGE, P_ERROR_MESSAGE);
```

Exactly 10 arguments, always, with explicit `NULL`s. Kept from the old
form: SOURCE, JOB_RUN_ID, WORKFLOW, MAPPING, STATE, STEP_NAME,
STEP_STATUS, TARGET_TABLE, MESSAGE, ERROR_MESSAGE. Dropped:
STEP_NO, ROW_COUNT, SOURCE_ROW_COUNT, WORK_TABLE_NAME,
WORK_TABLE_ACTION, WORK_TABLE_PURPOSE, DROP_REASON. Consequences:
step checkpoints no longer carry their row count (it survives only in
the RETURN value and the helper36 summary line), publish-COMPLETED
checkpoints no longer carry the branch count (same), and the old
`'NONE'` / `'KEPT'` / `'CREATED'` work-table action values no longer
appear as checkpoint arguments anywhere in this mapping. The first
argument is still the literal `'ECI'` as in v1 (value-identical to
`c_source`); `sp_etl_job_begin` / `sp_etl_job_finish` /
`sp_etl_job_fail` calls are untouched, as are RETURN summaries and
helper36 lines. Step numbers are unchanged everywhere (config STEP_NO,
step comments, summary literals); only the checkpoint argument carrying
the number was removed. The exception-row message text is unchanged
(it still says work tables are left in place); for step checkpoints
the old 16-argument form had no trailing error argument, so the new
form appends an explicit `NULL` error argument. Calls migrated: 20
(driver 15 = 1 driver-row SKIPPED + 5 step SKIPPED + 4 publish
COMPLETED + 4 publish SKIPPED + 1 exception FAILED; steps 5 × 1
COMPLETED). Old arities: driver 17, steps 16. Publish-branch procs
contain 0 checkpoint calls (verified; their comment mentions of
checkpoints were left alone, as were the step-proc header notes except
for the checkpoint paragraph, which now states the v2 form).

### v2 verification performed (balanced-parenthesis parsing, not grep)

- Regex over all 10 SQL files: 0 matches for `l_flag_[0-9]+`,
  `l_in_[0-9]+`, `l_pub_[0-9]+`, and 0 remaining members of the old
  families (`l_run_driver`, `l_run_[0-9]+`, old `l_in_<nn>`,
  `l_pub_<nn>`). String literals such as `'step 60 …'` are untouched
  and remain.
- Every `sp_etl_checkpoint` call parsed with balanced parentheses
  (calls span lines): 20/20 have exactly 10 arguments in the new
  order; 0 calls with 16/17 arguments remain; 0 dropped-parameter
  values (`'NONE'`, `'KEPT'`, `'CREATED'`, work-table names, `:l_rows`,
  `:l_pub_*`) appear as checkpoint arguments.
- Kept-field parity vs v1, call by call: for all 20 calls, SOURCE,
  JOB_RUN_ID, WORKFLOW, MAPPING, STATE, STEP_NAME, STEP_STATUS,
  TARGET_TABLE, MESSAGE and ERROR_MESSAGE in the new call equal the
  corresponding kept fields of the v1 call (whitespace-normalised).
- Step CTAS diff vs v1 (checkpoint call excluded): 5/5 identical.
  Publish INSERT diff vs v1: 4/4 files byte-identical. Driver diff vs
  v1: only flag/input/pub renames, checkpoint rewrites, DECLARE
  re-alignment and INTO re-wrapping (same order) — no business SQL.
- GATHER INTO order still matches SELECT order: SELECT flags
  STEP_NO 0,10,20,30,40,50,60,70,80,90 then consumed
  10,20,30,40,50,60,70,80,90; INTO list in the same order with the
  new names (19 targets).

## Driver signature

```sql
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr (
    P_JOB_RUN_ID VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
```

Identical (verified by regex) to the current main procedure's name, parameter
list and return type. Original parameters: NONE — only `P_JOB_RUN_ID` was
appended by the modular rewrite, and it is carried unchanged. Constants:
`c_source='ECI'`, `c_workflow='wf_ECI_Stage_Load'`,
`c_mapping='m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr'`. Config table:
`COMMON.ETL_RUN_CONFIG_TBL` (`WORKFLOW_NAME`, `MAPPING_NAME`, `STEP_NO`,
`STEP_PROC_NAME`, `IS_DRIVER`, `IS_RUN_ENABLED`, `IS_DEPENDENT`,
`DEPENDENT_ON`, `WORK_TABLES_PRODUCED`, `WORK_TABLES_CONSUMED`).
Gating uses `IS_RUN_ENABLED` and `WORK_TABLES_CONSUMED` only;
`IS_DRIVER` / `IS_DEPENDENT` / `DEPENDENT_ON` / `WORK_TABLES_PRODUCED` /
`STEP_PROC_NAME` are not consulted by this driver (see "Deviations and
uncertainties").

## Step table

| STEP_NO | Proc | Kind | Produces | Consumes default | Original params used | Checkpoint STEP_NAME |
|---|---|---|---|---|---|---|
| 10 | `steps/sp_snow_step_ECI_PHN_S10_SRC.sql` (`sp_snow_step_ECI_PHN_S10_SRC`) | staged, SPINE-FEEDING (via step 50) | `WRK_ECI_PHN_S10_SRC` (TRANSIENT) | `` (empty — no work-table input; existence check skipped) | none | `SRC_PHN_EADDR` |
| 20 | `steps/sp_snow_step_ECI_PHN_S20_ACTIVE.sql` (`sp_snow_step_ECI_PHN_S20_ACTIVE`) | staged, SPINE-FEEDING (via step 50) | `WRK_ECI_PHN_S20_ACTIVE` (TRANSIENT) | `WRK_ECI_PHN_S10_SRC` | none | `ACTIVE_PHN_EADDR` |
| 30 | `steps/sp_snow_step_ECI_PHN_S30_DQ.sql` (`sp_snow_step_ECI_PHN_S30_DQ`) | staged, SPINE-FEEDING (via step 50) | `WRK_ECI_PHN_S30_DQ` (TRANSIENT) | `WRK_ECI_PHN_S20_ACTIVE` | none | `DQ_CLEAN_VALIDATE` |
| 40 | `steps/sp_snow_step_ECI_PHN_S40_ROUTED.sql` (`sp_snow_step_ECI_PHN_S40_ROUTED`) | staged, SPINE-FEEDING (via step 50) | `WRK_ECI_PHN_S40_ROUTED` (TRANSIENT) | `WRK_ECI_PHN_S30_DQ` | none | `ROUTED_GROUPS` |
| 50 | `steps/sp_snow_step_ECI_PHN_S50_READY.sql` (`sp_snow_step_ECI_PHN_S50_READY`) | staged, SPINE-FEEDING (direct: read by all 4 publish branches) | `WRK_ECI_PHN_S50_READY` (TRANSIENT) | `WRK_ECI_PHN_S40_ROUTED` | none | `READY_TO_PUBLISH` |

Step proc signature (all five):
`P_JOB_RUN_ID VARCHAR, P_RUN_TS TIMESTAMP_NTZ, P_INPUT_TABLES VARCHAR DEFAULT '<consumes default above>'`,
returns `NUMBER` (work-table row count). Each step writes exactly its own
checkpoint with the SAME values as the original (STEP_NO, STEP_NAME,
WORK_TABLE_NAME, action `CREATED`, purpose, message) in v1 — in v2 the
checkpoint is the 10-argument form described above, keeping STEP_NAME,
STEP_STATUS, TARGET_TABLE and MESSAGE and dropping STEP_NO,
WORK_TABLE_NAME, action, purpose and row count; no exception block,
no transaction control, no target writes. "Kind" note: no staged step writes
a spine target directly — all five feed the spine through step 50; the
SPINE / NON-SPINE split happens only at publish.

Consumes lists work-table inputs only. Base source tables
(`V_ECI_ETL_SRC_FAMILY_PHONE`, helper table functions) and target guard
tables (`C_S_ECI_PTY_RLE_PHN`, `C_S_ECI_PTY_RLE_EADDR` in step 50) are NOT
work-table dependencies and are not listed.

## Branch table (publish — one transaction, checkpoints after COMMIT)

| STEP_NO | Proc | Kind | Target | Consumes |
|---|---|---|---|---|
| 60 | `publish/sp_snow_pub_ECI_PHN_C_S_ECI_PTY_RLE_PHN.sql` | SPINE | `C_S_ECI_PTY_RLE_PHN` (good phones) | `WRK_ECI_PHN_S50_READY` |
| 70 | `publish/sp_snow_pub_ECI_PHN_EXC_STG_BAD_REC_MEMB_PHONE.sql` | NON-SPINE | `EXC_STG_BAD_REC_MEMB` (bad phones) | `WRK_ECI_PHN_S50_READY` |
| 80 | `publish/sp_snow_pub_ECI_PHN_C_S_ECI_PTY_RLE_EADDR.sql` | SPINE | `C_S_ECI_PTY_RLE_EADDR` (good e-mails) | `WRK_ECI_PHN_S50_READY` |
| 90 | `publish/sp_snow_pub_ECI_PHN_EXC_STG_BAD_REC_MEMB_EMAIL.sql` | NON-SPINE | `EXC_STG_BAD_REC_MEMB` (bad e-mails) | `WRK_ECI_PHN_S50_READY` |

Publish proc signature (all four):
`P_JOB_RUN_ID VARCHAR, P_RUN_TS TIMESTAMP_NTZ, P_INPUT_TABLES VARCHAR DEFAULT 'WRK_ECI_PHN_S50_READY'`,
returns `NUMBER` (`SQLROWCOUNT` of the branch INSERT). No transaction
control, no checkpoint calls (framework rule — the driver checkpoints
each branch only after COMMIT). Driver publish checkpoint STEP_NAMEs:
`PUBLISH_C_S_ECI_PTY_RLE_PHN` (60), `PUBLISH_EXC_STG_BAD_REC_MEMB_PHONE` (70),
`PUBLISH_C_S_ECI_PTY_RLE_EADDR` (80), `PUBLISH_EXC_STG_BAD_REC_MEMB_EMAIL` (90).
The two `EXC_STG_BAD_REC_MEMB` branches are distinguished by STEP_NAME;
their TARGET_TABLE value is the same.

Driver file: `driver_sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr.sql`
(1 driver + 5 step procs + 4 publish-branch procs = 10 procedures).

## Verification performed (all before reporting)

- Every current step CTAS and every current publish INSERT was extracted
  from the original file and diffed (whitespace-normalised) against the
  new files: 5/5 CTAS match, 5/5 step checkpoints match, 4/4 INSERTs
  match. Allowed diffs only: `:l_run_ts` -> `:P_RUN_TS` (step 50 only),
  `:l_job_run_id` -> `:P_JOB_RUN_ID` (step checkpoints), the input
  existence check, and checkpoint placement (steps checkpoint in their
  own proc; publish checkpoints moved to the driver, after COMMIT).
- Every current step (10/20/30/40/50) and every current publish INSERT
  (60a/60b/60c/60d) has exactly one new proc; no step or branch is
  duplicated or missing. Driver name/signature verified identical to
  the current main by regex.
- Style greps: 0 `DROPPED` checkpoint arguments (case-sensitive grep for
  `DROPPED` is clean; the lowercase English verb "dropped" appears only
  in driver comments), 0 `P_RESUME_STEP`, 0 cursors, TRANSIENT work
  tables only with the same 5 names, `P_JOB_RUN_ID` in every new proc,
  0 `sp_etl_checkpoint` calls inside any publish-branch proc, 0
  checkpoint calls inside the driver's code `BEGIN TRANSACTION` ...
  `COMMIT` segment (verified on the code lines, not the header comments),
  step-5 cleanup is 5 bare `DROP TABLE IF EXISTS` statements with no
  checkpoint for drops.

## Deviations and uncertainties (nothing silently shipped)

1. **Existence-check error form — fallback used, not RAISE.** The task
   allowed `RAISE EXCEPTION` naming the missing table, falling back to
   `EXECUTE IMMEDIATE 'SELECT 1 FROM <missing table>'` if RAISE failed
   to compile. Snowflake's documented RAISE syntax is
   `RAISE <exception_name>;` only (a declared exception with a fixed
   message) — a dynamic table name cannot be embedded in it. The step
   procs therefore use the fallback form directly: on a missing input
   they run `EXECUTE IMMEDIATE :l_probe_sql` where
   `l_probe_sql = 'SELECT 1 FROM ' || <missing table>`, surfacing the
   native object-not-exists error naming the table, which propagates to
   the driver handler. This is a compile-time verification item along
   with the scalar-call form below.
2. **`l_rows := (CALL proc(...));` — compile-time verification item.**
   Used exactly as specified for all step and branch calls. There is no
   live Snowflake in this environment, so this form (and the nested
   `BEGIN ... EXCEPTION ... END` GATHER block, and the `SELECT ... INTO`
   with `SPLIT_TO_TABLE` / `INFORMATION_SCHEMA` existence query) must
   be compile-checked against Snowflake before use.
3. **Publish checkpoint replaces the original single publish checkpoint.**
   The original wrote one step-60 `PUBLISH` checkpoint with the total
   rows across all branches. The refactor writes one checkpoint per
   branch (60/70/80/90) with its own count after COMMIT; the sum of the
   four equals the original total when all four branches run. This is
   per the task's branch STEP_NO specification, not a business change.
4. **Step 50 checkpoint message preserved verbatim, now slightly stale.**
   It still says "Published in step 60" although publish now spans
   branches 60–90. Preserved deliberately (verbatim rule) rather than
   silently edited; flagged here for the user to confirm.
5. **Skipped steps do NOT auto-skip dependents.** The driver gates each
   step/branch independently by its own flag. A consumer enabled while
   its producer is skipped fails loudly in the consumer's existence
   check and hits the driver exception handler. `IS_DEPENDENT` /
   `DEPENDENT_ON` / `IS_DRIVER` / `WORK_TABLES_PRODUCED` /
   `STEP_PROC_NAME` are not read for gating — if the user wants
   dependency-aware skipping, that is a further change.
6. **`SKIPPED` STEP_STATUS — choice to confirm.** `JOB_CONTROL_ETL`
   has no CHECK constraint on STEP_STATUS (only a DDL comment listing
   `STARTED|COMPLETED|FAILED`), so `SKIPPED` rows are written as-is, per
   the task. Flag to the user as a vocabulary choice to confirm.
7. **`IS_RUN_ENABLED` assumed VARCHAR 'Y'/'N'.** The driver compares
   flags to `'Y'`/`'N'`. If the column is BOOLEAN (or another encoding),
   those comparisons must be adapted at install. Also, a config row
   with a flag value other than `'Y'` is treated as "not Y" (i.e.
   skipped) — only exactly `'Y'` runs a step/branch.
8. **Publish `P_RUN_TS` is unreferenced.** The original publish branches
   contain no `:l_run_ts` reference (`run_ts`/`mapping_name` are step-50
   columns), so the publish procs carry `P_RUN_TS` for a uniform driver
   call shape but do not use it. Likewise step procs 10–40 carry
   `P_RUN_TS` but only step 50 references it. No business effect.
9. **Driver early-return summary is empty.** On a driver-row skip
   (`STEP_NO = 0` = `'N'`), the driver returns
   `'JOB_RUN_ID=' || id || CHR(10) || ''` (same RETURN format as the
   normal path, with an empty summary) after `sp_etl_job_finish` with
   a skipped message. No step summary lines exist in that path.
10. **Framework calls keep the original literal `'ECI'`.** Step
    checkpoints and driver framework calls pass `'ECI'` literally, as
    the original did (value-identical to `c_source`); `c_source` /
    `c_workflow` / `c_mapping` constants are declared in every file and
    used for the GATHER filter, helper36 calls and the step-50
    `mapping_name` column. Not a behavioural difference.
11. **No live compile or row-count parity run.** As with the rest of
    this estate's rewrites, nothing here has been compiled against a
    live Snowflake or parity-tested against IDQ output. That is a
    required pre-production step.
