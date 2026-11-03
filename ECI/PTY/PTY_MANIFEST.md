# PTY Manifest — m_Tgt_C_S_ECI_Pty, config-driven step-driver refactor (ECI ONLY)

Prefix: `ECI_PTY`, short: `PTY`. Base dir (this v2 copy): `snowflake_eci_drivers_v2/ECI/PTY/`.
Baseline (v1, read-only, never modified by this migration): `snowflake_eci_drivers/ECI/PTY/`.
Source verified against: `snowflake_multisource/ECI/mappings/sp_snow_main_m_Tgt_C_S_ECI_Pty.sql`
(step map §2 of `snowflake_multisource/ECI/STEP_MAP_ECI.md` agrees; where the task
brief, the step map and the file agreed, no discrepancy was found — see Deviations).

## v2 migration (2026-10-27) — flag rename + 10-argument checkpoint form

Two changes only, applied to the driver + 5 step procs in this mapping.
Publish-branch procs are byte-identical to v1 (they contain no
`sp_etl_checkpoint` calls — verified; only comment mentions of checkpoints
remain in them, left alone).

### A. Flag / input / publish-count rename (driver file only)

Rule: strip the `sp_snow_step_` / `sp_snow_pub_` prefix from the unit's
procedure name, prepend `l_flag_` / `l_in_` / `l_pub_`; the driver-row flag
becomes `l_flag_ECI_PTY_DRIVER`. Branch step-number assignment was verified
from the driver code itself (80 = GENDER, 90 = BIRTH, 100 = ETHNICITY,
110 = RACE, 120 = LANGUAGE), not assumed from the brief's listing order.

| Old | New flag | New input | New pub count |
|---|---|---|---|
| `l_flag_0` (driver row) | `l_flag_ECI_PTY_DRIVER` | — | — |
| `l_flag_10` / `sp_snow_step_ECI_PTY_S10_SRC` | `l_flag_ECI_PTY_S10_SRC` | `l_in_ECI_PTY_S10_SRC` | — |
| `l_flag_20` / `sp_snow_step_ECI_PTY_S20_ACTIVE` | `l_flag_ECI_PTY_S20_ACTIVE` | `l_in_ECI_PTY_S20_ACTIVE` | — |
| `l_flag_30` / `sp_snow_step_ECI_PTY_S30_DQ` | `l_flag_ECI_PTY_S30_DQ` | `l_in_ECI_PTY_S30_DQ` | — |
| `l_flag_40` / `sp_snow_step_ECI_PTY_S40_DQ2` | `l_flag_ECI_PTY_S40_DQ2` | `l_in_ECI_PTY_S40_DQ2` | — |
| `l_flag_50` / `sp_snow_step_ECI_PTY_S50_READY` | `l_flag_ECI_PTY_S50_READY` | `l_in_ECI_PTY_S50_READY` | — |
| `l_flag_60` / `sp_snow_pub_ECI_PTY_C_S_ECI_PTY` | `l_flag_ECI_PTY_C_S_ECI_PTY` | `l_in_ECI_PTY_C_S_ECI_PTY` | `l_pub_ECI_PTY_C_S_ECI_PTY` |
| `l_flag_70` / `sp_snow_pub_ECI_PTY_C_S_ECI_PTY_RLE` | `l_flag_ECI_PTY_C_S_ECI_PTY_RLE` | `l_in_ECI_PTY_C_S_ECI_PTY_RLE` | `l_pub_ECI_PTY_C_S_ECI_PTY_RLE` |
| `l_flag_80` / `sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_GENDER` | `l_flag_ECI_PTY_EXC_STG_BAD_REC_MEMB_GENDER` | `l_in_ECI_PTY_EXC_STG_BAD_REC_MEMB_GENDER` | `l_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_GENDER` |
| `l_flag_90` / `sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_BIRTH` | `l_flag_ECI_PTY_EXC_STG_BAD_REC_MEMB_BIRTH` | `l_in_ECI_PTY_EXC_STG_BAD_REC_MEMB_BIRTH` | `l_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_BIRTH` |
| `l_flag_100` / `sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY` | `l_flag_ECI_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY` | `l_in_ECI_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY` | `l_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY` |
| `l_flag_110` / `sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_RACE` | `l_flag_ECI_PTY_EXC_STG_BAD_REC_MEMB_RACE` | `l_in_ECI_PTY_EXC_STG_BAD_REC_MEMB_RACE` | `l_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_RACE` |
| `l_flag_120` / `sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE` | `l_flag_ECI_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE` | `l_in_ECI_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE` | `l_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE` |

Occurrences renamed in the driver: 59 `l_flag_*`, 48 `l_in_*`, 28
`l_pub_*` = 135 total (DECLARE block, GATHER INTO list, exception-block
defaults, IF conditions, step/branch CALL arguments, helper36 summary
arguments). GATHER SELECT column order and INTO order are unchanged — only
identifiers were renamed. Summary display strings are unchanged
(e.g. `'step 100 PUBLISH_EXC_ETHNICITY'` is still a literal).
Follow-up check (RFA anomaly): this driver's v1 variables really were
`l_flag_<digits>` / `l_in_<nn>` / `l_pub_<nn>` — confirmed from the v1
DECLARE block; it did NOT use RFA-style `v_run_*` / `v_in_*` /
`l_pub_rows`, and no such names occur anywhere in v1 or v2 PTY.
Zero members of the old families remain in the v2 driver (regex:
`l_flag_[0-9]+`, `l_in_[0-9]+`, `l_pub_[0-9]+`, `v_run_*`, `v_in_*`,
`l_pub_rows` — all zero matches).

### B. Checkpoint migration — new 10-argument form

Every `sp_etl_checkpoint` call now passes exactly 10 arguments, in this
order: `P_SOURCE, P_JOB_RUN_ID, P_WORKFLOW_NAME, P_MAPPING_NAME, P_STATE,
P_STEP_NAME, P_STEP_STATUS, P_TARGET_TABLE, P_MESSAGE, P_ERROR_MESSAGE`
— always with explicit NULLs, never trailing defaults. Kept from the old
form: SOURCE, JOB_RUN_ID, WORKFLOW, MAPPING, STATE, STEP_NAME, STEP_STATUS,
TARGET_TABLE, MESSAGE, ERROR_MESSAGE. Dropped: STEP_NO, ROW_COUNT,
SOURCE_ROW_COUNT, WORK_TABLE_NAME, WORK_TABLE_ACTION, WORK_TABLE_PURPOSE,
DROP_REASON. Consequences, by design of the new form (not silent losses):
step row counts no longer reach the checkpoint (they survive in the step
return values and the helper36 summary lines); step purpose strings (e.g.
the S10 delta-parties description) are no longer passed; publish-branch
counts no longer reach the checkpoint (they survive in helper36 lines);
STEP_NO is no longer an argument (step numbers survive only in summary
display strings and in the config STEP_NO values). `sp_etl_job_begin` /
`sp_etl_job_finish` / `sp_etl_job_fail` calls are untouched, as are
`fn_snow_helper36_common` lines and all business SQL. The driver exception
checkpoint message text is unchanged (it still says work tables are left
in place) and its error argument is still
`'See Snowflake query history for this JOB_RUN_ID for the underlying
error.'`.

Calls migrated: driver 21 (1 MAPPING_SKIPPED + 5 step SKIPPED + 7 publish
COMPLETED + 7 publish SKIPPED + 1 JOB_END FAILED), steps 5 (one COMPLETED
each, S10–S50), publish branches 0 (no calls) — 26 total. Old driver calls
had 17 arguments, old step calls 16 (no trailing ERROR_MESSAGE argument);
both now have exactly 10. Zero 16/17-argument calls remain, and no dropped
parameter (`'CREATED'` / `'NONE'` / `'KEPT'`, `:l_rows` / `:l_pub_*` as a
checkpoint argument, numeric STEP_NO) appears in any checkpoint call.

### C. v2 verification (replaces the old-form checkpoint notes below)

- Driver regex: zero `l_flag_[0-9]+`, `l_in_[0-9]+`, `l_pub_[0-9]+`
  (string literals such as `'step 100 ...'` remain and are untouched).
- Balanced-parenthesis parsing of every `sp_etl_checkpoint` call in the
  driver + steps: all 26 have exactly 10 arguments in the new order, with
  STEP_NAME a quoted name and STEP_STATUS one of COMPLETED / SKIPPED /
  FAILED; publish procs have 0 calls.
- Driver with checkpoint calls stripped and new names reverse-mapped is
  byte-identical to v1 with checkpoint calls stripped; all 5 step CTAS
  are identical to v1 once their checkpoint calls are stripped; all 7
  publish INSERTs are byte-identical to v1.
- GATHER INTO order still matches SELECT order (25 + 25, flags 0–120
  then inputs 10–120), verified by mapping each new name back to its
  STEP_NO.
- No live Snowflake compile/run/parity yet — same caveat as v1.

## Driver

Signature (IDENTICAL to the current main, verified by normalised comparison):

```sql
sp_snow_main_m_Tgt_C_S_ECI_Pty (
    P_PTY_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Indv',
    P_RLE_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Member',
    P_JOB_RUN_ID             VARCHAR DEFAULT NULL
) RETURNS VARCHAR
```

File: `driver_sp_snow_main_m_Tgt_C_S_ECI_Pty.sql`

Driver behaviour: job-run-id generation exactly as now + `sp_etl_job_begin`;
one config GATHER (nested `BEGIN/EXCEPTION`, defaults stand on failure) from
`COMMON.ETL_RUN_CONFIG_TBL` (`WORKFLOW_NAME = 'wf_ECI_Stage_Load'`,
`MAPPING_NAME = 'm_Tgt_C_S_ECI_Pty'`); driver-row `STEP_NO = 0` = `'N'` skips the
whole mapping BEFORE step 5 cleanup (SKIPPED checkpoint `MAPPING_SKIPPED`,
`sp_etl_job_finish` with a skipped message, early RETURN); step 5 cleanup
unchanged (5 bare `DROP TABLE IF EXISTS`, no checkpoint); conditional step
calls in order; ONE publish transaction calling the enabled branch procs in
order; branch checkpoints ONLY after `COMMIT`; `TERMINATING` via
`sp_etl_job_finish` with the same message style and RETURN format as now;
exception block identical in shape (ROLLBACK + TERMINATING `JOB_END`
FAILED checkpoint — v2 10-argument form, no STEP_NO argument; v1 passed
999 — + `sp_etl_job_fail` + RAISE).

## Steps

| STEP_NO | Proc | Kind | Produces | Consumes default | Original params used | Checkpoint STEP_NAME |
|---|---|---|---|---|---|---|
| 10 | `sp_snow_step_ECI_PTY_S10_SRC` | staged (base read) | `WRK_ECI_PTY_S10_SRC` — child + family delta rows, party key, party type, source full name | _(empty — check skipped; reads base tables, not work tables)_ | none | `SRC_DELTA_PARTIES` |
| 20 | `sp_snow_step_ECI_PTY_S20_ACTIVE` | staged (filter) | `WRK_ECI_PTY_S20_ACTIVE` — active parties only | `WRK_ECI_PTY_S10_SRC` | none | `ACTIVE_PARTIES` |
| 30 | `sp_snow_step_ECI_PTY_S30_DQ` | staged (DQ rules) | `WRK_ECI_PTY_S30_DQ` — name/gender/birth/ethnicity/race/language rule results | `WRK_ECI_PTY_S20_ACTIVE` | none (uses run timestamp only) | `DQ_RULES` |
| 40 | `sp_snow_step_ECI_PTY_S40_DQ2` | staged (exception resolution) | `WRK_ECI_PTY_S40_DQ2` — standardised fields, every exception code/description/type resolved | `WRK_ECI_PTY_S30_DQ` | none | `DQ_EXCEPTIONS_RESOLVED` |
| 50 | `sp_snow_step_ECI_PTY_S50_READY` | staged (routing; feeds spine directly) | `WRK_ECI_PTY_S50_READY` — router groups, party/role keys, insert-only guards | `WRK_ECI_PTY_S40_DQ2` | `P_PTY_BO_CLASS_CD_MEMBER`, `P_RLE_BO_CLASS_CD_MEMBER` | `ROUTED_READY` |

Step proc signatures: the step's used original params (in original order) +
`P_JOB_RUN_ID VARCHAR` + `P_RUN_TS TIMESTAMP_NTZ` + `P_INPUT_TABLES VARCHAR
DEFAULT '<consumes default>'`. Every step proc returns `NUMBER` (row count),
writes its own checkpoint in the v2 10-argument form (kept values: source,
job, workflow, mapping, state, step name, status, target, message
`'Step <n> complete.'`, error NULL; row count, work-table name/action/
purpose dropped per the new signature — see §v2 migration), has no
exception block, no transaction, no target write, and
starts with the work-table existence check (skipped when `P_INPUT_TABLES` is
NULL/empty). `P_INPUT_TABLES` is a dependency declaration + runtime check,
NOT dynamic SQL — Snowflake cannot parameterise table names in static SQL,
so each CTAS still names its source work table literally.

Step files: `steps/sp_snow_step_ECI_PTY_S<nn>_<NAME>.sql` (5 files).

## Publish branches

Original publish was one step 60 with 7 INSERTs in one transaction. Each
INSERT is now one branch proc, called by the driver inside ONE transaction
in the same order, checkpointed by the driver only after COMMIT.

| STEP_NO | Proc | Kind | Target | Consumes |
|---|---|---|---|---|
| 60 | `sp_snow_pub_ECI_PTY_C_S_ECI_PTY` | SPINE | `C_S_ECI_PTY` | `WRK_ECI_PTY_S50_READY` |
| 70 | `sp_snow_pub_ECI_PTY_C_S_ECI_PTY_RLE` | SPINE | `C_S_ECI_PTY_RLE` | `WRK_ECI_PTY_S50_READY` |
| 80 | `sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_GENDER` | NON-SPINE | `EXC_STG_BAD_REC_MEMB` (gender) | `WRK_ECI_PTY_S50_READY` |
| 90 | `sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_BIRTH` | NON-SPINE | `EXC_STG_BAD_REC_MEMB` (birth date) | `WRK_ECI_PTY_S50_READY` |
| 100 | `sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY` | NON-SPINE | `EXC_STG_BAD_REC_MEMB` (ethnicity, child rows only) | `WRK_ECI_PTY_S50_READY` |
| 110 | `sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_RACE` | NON-SPINE | `EXC_STG_BAD_REC_MEMB` (race, child rows only) | `WRK_ECI_PTY_S50_READY` |
| 120 | `sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE` | NON-SPINE | `EXC_STG_BAD_REC_MEMB` (language, child rows only) | `WRK_ECI_PTY_S50_READY` |

Branch proc signatures: `P_JOB_RUN_ID VARCHAR` + `P_RUN_TS TIMESTAMP_NTZ` +
`P_INPUT_TABLES VARCHAR DEFAULT 'WRK_ECI_PTY_S50_READY'`, no original params
(no branch INSERT references either original param or the run timestamp
directly — each reads the `run_ts`/`exc_mapping` columns materialised in step
50, so `P_RUN_TS` is carried for a uniform driver call signature and is
unused in branch bodies; this is stated in each branch header). Each returns
`SQLROWCOUNT` as `NUMBER`. No transaction control, no checkpoint calls.
Driver checkpoint STEP_NAMEs: `PUBLISH_C_S_ECI_PTY`, `PUBLISH_C_S_ECI_PTY_RLE`,
`PUBLISH_EXC_GENDER`, `PUBLISH_EXC_BIRTH`, `PUBLISH_EXC_ETHNICITY`,
`PUBLISH_EXC_RACE`, `PUBLISH_EXC_LANGUAGE`.

Branch files: `publish/sp_snow_pub_ECI_PTY_<TARGET>[_<BRANCH>].sql` (7 files).

## Verification performed (no live Snowflake available)

- All 5 step CTAS compared to the current file after whitespace normalisation
  and the allowed substitutions only (`:l_run_ts` → `:P_RUN_TS`,
  `:c_exc_mapping` → local constant): all MATCH.
- All 7 branch INSERTs compared likewise (no substitutions needed): all MATCH.
- All 5 step checkpoints compared to the current step checkpoints (modulo the
  local-constant vs literal identity arguments): all MATCH in v1. In v2
  they carry the same kept values in the new 10-argument form (see
  §v2 migration); the v1 comparison note is otherwise unchanged.
- Driver name/signature compared to the current main (normalised): IDENTICAL.
- Counts: 1 driver + 5 step procs + 7 branch procs = 13 files, covering all
  5 current steps and all 7 current publish INSERTs exactly once.
- Style greps (code lines, comments excluded where noted): 0 `DROPPED`
  checkpoint args, 0 `P_RESUME_STEP`, 0 cursors (the only `CURSOR` hit is the
  comment "No CURSOR was used" carried from the original header), 0
  `sp_etl_checkpoint` calls and 0 transaction statements in publish-branch
  code, 0 checkpoint calls between the driver's `BEGIN TRANSACTION` and
  `COMMIT` (7 branch CALLs inside that region), `TRANSIENT` work tables only
  with unchanged names, `P_JOB_RUN_ID` in every new proc.

## Deviations / uncertainties — nothing silently shipped

1. **No deviations from the brief or the file.** The task's stated structure
   (steps 10/20/30/40/50, 7 publish INSERTs, params, work-table names) matched
   the file exactly; the file was treated as authoritative throughout.
2. **Combined publish checkpoint split (by design, per brief).** The current
   file writes ONE step-60 `PUBLISH` checkpoint with the summed row count.
   The refactor writes one checkpoint per branch (STEP_NOs 60–120) with that
   branch's count, plus a per-branch helper36 summary line instead of the
   single `step 60 PUBLISH` line. Total published rows are recoverable by
   summing the seven branch counts; there is no longer a single combined
   publish row.
3. **Config columns not read.** `IS_DEPENDENT`, `DEPENDENT_ON` and
   `WORK_TABLES_PRODUCED` exist in `ETL_RUN_CONFIG_TBL` but are not read by
   this driver; gating is by `IS_RUN_ENABLED` only, per the brief.
4. **No cascade on skip.** Skipping is per step/branch only. If an upstream
   step is disabled but a downstream step stays enabled, the downstream
   step's existence check raises the missing work table rather than running
   on stale data. Operators must disable downstream steps explicitly.
5. **'SKIPPED' status is a choice to confirm.** `JOB_CONTROL_ETL.STEP_STATUS`
   has no CHECK constraint (only a DDL comment listing
   STARTED | COMPLETED | FAILED); `SKIPPED` rows are used here as specified
   and should be confirmed by the user.
6. **Compile-time verification items (no live Snowflake here).**
   - `l_rows := (CALL proc(...));` scalar-call capture form.
   - `RAISE EXCEPTION '...' || :l_missing;` in the step existence checks
     (fallback if it fails to compile: `EXECUTE IMMEDIATE 'SELECT 1 FROM
     <missing table>'` to surface the native object-not-exists error).
   - `IF` blocks inside the driver's `BEGIN TRANSACTION` / `COMMIT` region
     (branch CALLs gated by flags), and the multi-variable
     `SELECT ... INTO :a, :b, ...` in the GATHER.
   - Unused-parameter warnings, if any, for `P_RUN_TS` in step 20/40 and in
     the branch procs, where it is carried for signature uniformity.
7. **Not tested.** No live Snowflake compile, run, or row-count parity run
   was possible in this environment; that step is required before use.
8. **Scope.** ECI `m_Tgt_C_S_ECI_Pty` only, as an example for user feedback.
   No other source or mapping was touched; the current main file was not
   modified.

## ASSEMBLY NOTE (coordinator, post-worker normalisation)

The existence-check error form in this mapping's step procs was normalised from
`RAISE EXCEPTION '...' || :l_missing;` to a probe query
(`l_probe_sql := 'SELECT 1 FROM ' || TRIM(SPLIT_PART(:l_missing, ',', 1));`
`EXECUTE IMMEDIATE :l_probe_sql;`), because Snowflake Scripting RAISE accepts only a
declared exception name and cannot embed a runtime-discovered table name. Business SQL is
untouched; only the error-raising lines changed. Any statement in this manifest about the
RAISE form is superseded by this note.
