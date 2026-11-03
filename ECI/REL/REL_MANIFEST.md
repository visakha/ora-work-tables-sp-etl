# REL_MANIFEST — m_Tgt_C_S_ECI_Pty_Rle_Rel (ECI ONLY, config-driven step-driver refactor)

Example for user feedback. Source of truth: the current main
`~/workspace/snowflake_multisource/ECI/mappings/sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel.sql`
(verified against the file; where this manifest and that file differ, that file wins).
Business SQL is preserved — only re-housed. No business expression, filter, guard
or column list was changed.

## v2 migration (this mapping only)

Two v2 changes, verified against the v1 files in
`~/workspace/snowflake_eci_drivers/ECI/REL/` (v1 untouched):

**1. Driver flag/in/pub renames (driver file only).** Each new name strips the
`sp_snow_step_` / `sp_snow_pub_` prefix from the unit's procedure name and
prepends `l_flag_` / `l_in_` / `l_pub_`. Branch assignment was verified from
the driver code itself: step 50 calls
`sp_snow_pub_ECI_REL_C_S_ECI_PTY_RLE_REL`, step 60 calls
`sp_snow_pub_ECI_REL_EXC_STG_BAD_REC_MEMB`. Note: v1's flag variables were
named `l_run_*`, not `l_flag_<digits>`; the rename rule was applied to the
actual v1 flag variables, and no `l_flag_[0-9]+`, `l_in_[0-9]+` or
`l_pub_[0-9]+` identifier remains in the driver. 17 distinct identifiers,
53 occurrences total (DECLARE block, GATHER INTO list in unchanged order,
IF conditions, step/branch calls, skipped flags, helper36 summary lines).
Summary display strings are unchanged (string literals, not identifiers).

| v1 | v2 |
|---|---|
| `l_run_driver` | `l_flag_ECI_REL_DRIVER` |
| `l_run_s10` | `l_flag_ECI_REL_S10_SRC` |
| `l_run_s20` | `l_flag_ECI_REL_S20_KEYED` |
| `l_run_s30` | `l_flag_ECI_REL_S30_TYPED` |
| `l_run_s40` | `l_flag_ECI_REL_S40_READY` |
| `l_run_pub50` | `l_flag_ECI_REL_C_S_ECI_PTY_RLE_REL` |
| `l_run_pub60` | `l_flag_ECI_REL_EXC_STG_BAD_REC_MEMB` |
| `l_in_s10` | `l_in_ECI_REL_S10_SRC` |
| `l_in_s20` | `l_in_ECI_REL_S20_KEYED` |
| `l_in_s30` | `l_in_ECI_REL_S30_TYPED` |
| `l_in_s40` | `l_in_ECI_REL_S40_READY` |
| `l_in_pub50` | `l_in_ECI_REL_C_S_ECI_PTY_RLE_REL` |
| `l_in_pub60` | `l_in_ECI_REL_EXC_STG_BAD_REC_MEMB` |
| `l_pub50_rows` | `l_pub_ECI_REL_C_S_ECI_PTY_RLE_REL_rows` |
| `l_pub60_rows` | `l_pub_ECI_REL_EXC_STG_BAD_REC_MEMB_rows` |
| `l_pub50_skipped` | `l_pub_ECI_REL_C_S_ECI_PTY_RLE_REL_skipped` |
| `l_pub60_skipped` | `l_pub_ECI_REL_EXC_STG_BAD_REC_MEMB_skipped` |

**2. Checkpoint signature (driver + all 4 step procs; publish procs contain
no checkpoint calls — verified, unchanged).** Every `sp_etl_checkpoint`
call now passes exactly 10 arguments, in this order:
`P_SOURCE, P_JOB_RUN_ID, P_WORKFLOW_NAME, P_MAPPING_NAME, P_STATE,
P_STEP_NAME, P_STEP_STATUS, P_TARGET_TABLE, P_MESSAGE, P_ERROR_MESSAGE`,
with explicit `NULL`s (never trailing defaults). Kept from the old form:
SOURCE, JOB_RUN_ID, WORKFLOW, MAPPING, STATE, STEP_NAME, STEP_STATUS,
TARGET_TABLE, MESSAGE, ERROR_MESSAGE. Dropped: STEP_NO, ROW_COUNT,
SOURCE_ROW_COUNT, WORK_TABLE_NAME, WORK_TABLE_ACTION, WORK_TABLE_PURPOSE,
DROP_REASON. Counts migrated: driver 10 calls (v1: 17 args each) and steps
4 calls (v1: 16 args each — the step calls carried no ERROR_MESSAGE argument
and relied on the default; v2 passes explicit `NULL`). Step numbers are
unchanged as concepts (steps 10/20/30/40, branches 50/60, exception
`JOB_END`); they are simply no longer checkpoint arguments, so the
exception row is now `TERMINATING / JOB_END / FAILED`, not
`TERMINATING 999`. Row counts no longer travel in checkpoint rows; they
survive in the step `RETURN` values and the driver's helper36 summary lines.
Step 40's checkpoint `TARGET_TABLE` is still the combined string
`'C_S_ECI_PTY_RLE_REL, EXC_STG_BAD_REC_MEMB'`. `sp_etl_job_begin` /
`sp_etl_job_finish` / `sp_etl_job_fail` are untouched. The v1 step-file
header comments that describe a checkpoint as carrying STEP_NO,
WORK_TABLE_NAME, `'CREATED'` and purpose values still use v1 wording;
only the checkpoint calls themselves were rewritten, per v2 scope.

Verification (balanced-parenthesis parsing, not single-line grep): all 14
checkpoint calls have exactly 10 arguments in the new order; zero 16/17-arg
calls remain; zero dropped-parameter arguments remain; GATHER INTO order
still matches SELECT order; every step CTAS and every publish INSERT is
identical to v1 (publish files byte-identical).

## Driver

Driver file: `ECI/REL/driver_sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel.sql`

Driver signature (identical to the current main):

```sql
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel (
    P_JOB_RUN_ID VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
```

Constants: `c_source = 'ECI'`, `c_workflow = 'wf_ECI_Stage_Load'`,
`c_mapping = 'm_Tgt_C_S_ECI_Pty_Rle_Rel'`.
Config table: `COMMON.ETL_RUN_CONFIG_TBL` (`WORKFLOW_NAME`, `MAPPING_NAME`,
`STEP_NO`, `STEP_PROC_NAME`, `IS_DRIVER`, `IS_RUN_ENABLED`, `IS_DEPENDENT`,
`DEPENDENT_ON`, `WORK_TABLES_PRODUCED`, `WORK_TABLES_CONSUMED`).
The driver GATHERs only `IS_RUN_ENABLED` and `WORK_TABLES_CONSUMED` (one SELECT);
`STEP_PROC_NAME`, `IS_DRIVER`, `IS_DEPENDENT`, `DEPENDENT_ON` and
`WORK_TABLES_PRODUCED` are not read by this driver — step/branch procedure names
are hard-coded in the driver body, in original order.

Driver flow: job-run-id generation (as now) + `sp_etl_job_begin` -> config GATHER
(nested BEGIN/EXCEPTION; defaults stand on error) -> driver-row `STEP_NO = 0`
`'N'` check (MAPPING_SKIPPED checkpoint + `sp_etl_job_finish`, early RETURN,
BEFORE step 5) -> step 5 cleanup (bare drops, no checkpoint) -> conditional steps
10/20/30/40 -> publish transaction (branches 50, 60 in order) -> COMMIT -> branch
checkpoints after COMMIT -> `sp_etl_job_finish` + same RETURN format as now.
Exception block identical in shape to now (ROLLBACK + TERMINATING JOB_END
FAILED checkpoint + `sp_etl_job_fail` + RAISE; v2 carries no STEP_NO argument,
so the v1 STEP_NO value 999 no longer appears).

## Steps

| STEP_NO | proc | kind | produces | consumes default | original params used | checkpoint STEP_NAME |
|---|---|---|---|---|---|---|
| 10 | `sp_snow_step_ECI_REL_S10_SRC` | staged (spine chain) | `WRK_ECI_REL_S10_SRC` — family rows doubled, one row per direction | `` (empty — reads no work table; existence check skipped) | none | `SRC_BOTH_DIRECTIONS` |
| 20 | `sp_snow_step_ECI_REL_S20_KEYED` | staged (spine chain) | `WRK_ECI_REL_S20_KEYED` — child/family party keys, both parties active | `WRK_ECI_REL_S10_SRC` | none | `KEYED_BOTH_ACTIVE` |
| 30 | `sp_snow_step_ECI_REL_S30_TYPED` | staged (spine chain) | `WRK_ECI_REL_S30_TYPED` — relationship code built and translated (NULL when untranslated) | `WRK_ECI_REL_S20_KEYED` | none | `CODED_TRANSLATED` |
| 40 | `sp_snow_step_ECI_REL_S40_READY` | staged (spine chain, direct publish input) | `WRK_ECI_REL_S40_READY` — relationship keys, exception details, insert-only guards (`uq_rel`, `uq_rel_exc`) | `WRK_ECI_REL_S30_TYPED` | none | `READY_TO_PUBLISH` |

Step proc files: `ECI/REL/steps/sp_snow_step_ECI_REL_S<nn>_<NAME>.sql`.
Step proc signature (all four): `P_JOB_RUN_ID VARCHAR + P_RUN_TS TIMESTAMP_NTZ
+ P_INPUT_TABLES VARCHAR DEFAULT '<consumes default above>'`, `RETURNS NUMBER`.
Each step proc: (1) input existence check (skipped when `P_INPUT_TABLES` is
NULL/empty; splits on `|`, checks `INFORMATION_SCHEMA.TABLES` where
`TABLE_SCHEMA = CURRENT_SCHEMA()`); (2) the step's CTAS verbatim (substitutions
only: `:l_run_ts` -> `:P_RUN_TS`, `:c_mapping` -> local constant of the same
value); (3) `SELECT COUNT(*) INTO :l_rows`; (4) its own checkpoint in the v2
10-argument form (SOURCE, JOB_RUN_ID, WORKFLOW, MAPPING, STATE, STEP_NAME,
STEP_STATUS, TARGET_TABLE, MESSAGE, ERROR_MESSAGE — STEP_NO, row counts,
work-table name/action/purpose and drop reason dropped; message is
`'Step <n> complete.'`, error is explicit `NULL`); (5) `RETURN :l_rows`.
No exception
block, no transactions, no target writes.

Notes on the step table:
- "Original params used" is `none` for every step: the current main takes no
  original parameters (only appended `P_JOB_RUN_ID`). `P_RUN_TS` is a new
  framework parameter carrying the driver's `l_run_ts`; only step 40 uses it
  (stamps `run_ts`); steps 10/20/30 accept it for a uniform signature and do
  not use it.
- `P_INPUT_TABLES` is a dependency declaration + runtime check, NOT dynamic SQL:
  Snowflake cannot parameterise table names in static SQL, so each CTAS still
  names its tables directly, exactly as the current main does. It lists
  WORK-TABLE inputs only; base source tables (`STG_ECI_D_FAMILY`,
  `STG_ECI_SN_CHILD`, `STG_ECI_PTY_INACTIVE_STS`), lookup tables
  (`LOOKUP_CODE_VALUE`), the exception helper and the target guard table
  (`C_S_ECI_PTY_RLE_REL` in step 40) are not listed or checked.
- Step 40's checkpoint `TARGET_TABLE` is preserved verbatim as the combined
  string `'C_S_ECI_PTY_RLE_REL, EXC_STG_BAD_REC_MEMB'` from the current main,
  even though publish is now split into branches 50/60.
- Every step feeds the spine chain (10 -> 20 -> 30 -> 40 -> publish 50/60);
  step 40 is the direct publish input for both branches.

## Publish branches

| STEP_NO | proc | kind | target | consumes |
|---|---|---|---|---|
| 50 | `sp_snow_pub_ECI_REL_C_S_ECI_PTY_RLE_REL` | SPINE | `C_S_ECI_PTY_RLE_REL` (valid relationships: `mstr_ref_code IS NOT NULL AND uq_rel`) | `WRK_ECI_REL_S40_READY` |
| 60 | `sp_snow_pub_ECI_REL_EXC_STG_BAD_REC_MEMB` | NON-SPINE | `EXC_STG_BAD_REC_MEMB` (relationship exceptions: `mstr_ref_code IS NULL AND uq_rel_exc`) | `WRK_ECI_REL_S40_READY` |

Branch proc files: `ECI/REL/publish/sp_snow_pub_ECI_REL_<TARGET>.sql`.
Branch proc signature (both): `P_JOB_RUN_ID VARCHAR + P_RUN_TS TIMESTAMP_NTZ
+ P_INPUT_TABLES VARCHAR DEFAULT 'WRK_ECI_REL_S40_READY'`, `RETURNS NUMBER`
(`SQLROWCOUNT` of the INSERT). Each branch proc: the branch's current INSERT
verbatim (same columns, values, WHERE guards); NO transaction control, NO
checkpoint calls (framework rule — the driver checkpoints after COMMIT).
Branch checkpoint STEP_NAMEs (driver, after COMMIT): `PUBLISH_C_S_ECI_PTY_RLE_REL`
(50), `PUBLISH_EXC_STG_BAD_REC_MEMB` (60).

Notes on the branch table:
- The current main numbers its whole publish step 50 with ONE checkpoint and a
  combined row total. This refactor numbers the branches 50 and 60 per the
  refactor spec, so each branch has its own checkpoint row and count; there is
  no combined-total publish checkpoint any more (per-branch helper36 summary
  lines carry the counts). Branch order is unchanged (spine first, then
  exception).
- Neither branch INSERT references `:l_run_ts` / `:c_mapping` variables: both
  carry `run_ts` / `mapping_name` via the `WRK_ECI_REL_S40_READY` columns
  stamped by step 40. So no variable substitution was needed in the branches,
  and `P_RUN_TS` is unused in both branch procs by design.
- Publish branch procs run NO input existence check (per the publish-branch
  spec); a missing `WRK_ECI_REL_S40_READY` surfaces as the native
  object-not-exists error on the INSERT, and the driver's exception handler
  rolls the publish back.

## Counts

- Steps: 4 (10, 20, 30, 40) — exactly the current main's staged steps.
- Publish branches: 2 (50, 60) — exactly the current main's 2 publish INSERTs,
  in the same order.
- Work tables: 4 (`WRK_ECI_REL_S10_SRC`, `WRK_ECI_REL_S20_KEYED`,
  `WRK_ECI_REL_S30_TYPED`, `WRK_ECI_REL_S40_READY`), all TRANSIENT, same names
  as now; step 5 drops exactly these 4.
- New procedures total: 7 (1 driver + 4 steps + 2 branches). The driver keeps
  the current main's name/signature, so it replaces the current main file
  (it is not an additional procedure).

## Deviations and uncertainties (nothing silently shipped)

1. **Publish checkpoint split (intentional, per spec).** Single step-50 PUBLISH
   checkpoint + combined total replaced by per-branch checkpoints 50/60.
   The step-50 summary line changes from `step 50 PUBLISH` (total) to
   `step 50 PUBLISH_C_S_ECI_PTY_RLE_REL` + `step 60 PUBLISH_EXC_STG_BAD_REC_MEMB`
   (per-branch counts). Confirm this checkpoint-shape change is acceptable.
2. **Scalar CALL capture — compile-time verification required (no live
   Snowflake here).** Step/branch return capture uses
   `l_rows := (CALL proc(...));`, the Snowflake Scripting scalar-call form
   per the refactor spec. Confirm it compiles and returns the row count on
   install.
3. **RAISE EXCEPTION form — compile-time verification required.** Step existence
   checks use `RAISE EXCEPTION '...' || :l_missing;` (concatenated message
   naming the missing table(s) and step). If that form does not compile, the
   prescribed fallback is `EXECUTE IMMEDIATE 'SELECT 1 FROM <missing table>'`
   to surface the native object-not-exists error. This refactor uses the
   RAISE form, not the fallback.
4. **SKIPPED vocabulary — user choice to confirm.** `JOB_CONTROL_ETL.STEP_STATUS`
   has NO CHECK constraint (only a DDL comment listing
   STARTED|COMPLETED|FAILED), so `'SKIPPED'` checkpoint rows are used for
   config-disabled steps/branches and for the mapping-skipped row. Flagged to
   the user as a choice to confirm.
5. **Skipping is per-step, not chain-aware.** Step 5 drops all work tables, so
   skipping step 10 while step 20 is enabled fails at step 20's existence
   check; skipping step 40 while a publish branch is enabled fails natively
   on the branch INSERT. This surfaces a broken chain rather than silently
   reusing stale tables, but it means a partial-skip config is not a valid
   partial run. Also: only the exact value `'Y'` runs a step/branch; the
   driver-row early return triggers only on exactly `'N'` (STEP_NO = 0).
6. **Empty publish transaction.** If BOTH publish branches are skipped,
   `BEGIN TRANSACTION ... COMMIT` encloses no statements; confirm an empty
   transaction is accepted on install.
7. **Config table not verified live.** `COMMON.ETL_RUN_CONFIG_TBL` column names
   and the STEP_NO convention (driver row 0, steps 10/20/30/40, branches 50/60)
   are taken from the refactor spec, not from a live table. The driver GATHER
   reads only `IS_RUN_ENABLED` and `WORK_TABLES_CONSUMED`; if the table is
   missing/unreadable, defaults stand and the run proceeds exactly as the
   current main does (all steps + both branches enabled).
8. **Unused parameters, by design.** `P_RUN_TS` is unused in steps 10/20/30 and
   in both publish branch procs (uniform signature only). `P_INPUT_TABLES` is
   accepted but not existence-checked in the publish branch procs (see above).
9. **No live compile or row-count parity run.** No Snowflake was available here;
   install-time compile of all 7 procedures and a parity run against the
   current main are still required before production use.

## ASSEMBLY NOTE (coordinator, post-worker normalisation)

The existence-check error form in this mapping's step procs was normalised from
`RAISE EXCEPTION '...' || :l_missing;` to a probe query
(`l_probe_sql := 'SELECT 1 FROM ' || TRIM(SPLIT_PART(:l_missing, ',', 1));`
`EXECUTE IMMEDIATE :l_probe_sql;`), because Snowflake Scripting RAISE accepts only a
declared exception name and cannot embed a runtime-discovered table name. Business SQL is
untouched; only the error-raising lines changed. Any statement in this manifest about the
RAISE form is superseded by this note.
