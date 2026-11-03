# ADR_MANIFEST — m_Tgt_C_S_ECI_Pty_Addr (ECI address spine), config-driven step-driver refactor

## v2 MIGRATION (applied to this package; v1 baseline `~/workspace/snowflake_eci_drivers/ECI/ADR/` untouched)

### v2 flag names (driver file only; step/publish procs never carried these variables)

Branch number-to-branch assignment verified from the driver code itself (file order):
60 = `sp_snow_pub_ECI_ADR_DQM_ADDRESS`, 70 = `sp_snow_pub_ECI_ADR_C_S_ECI_PTY_RLE_ADDR`,
80 = `sp_snow_pub_ECI_ADR_EXC_STG_BAD_REC_MEMB`.

| v1 name | v2 name | occurrences renamed (DECLARE + GATHER INTO + IF) |
|---|---|---|
| `l_flag_driver` (driver row, STEP_NO 0) | `l_flag_ECI_ADR_DRIVER` | 3 |
| `l_flag_10` | `l_flag_ECI_ADR_S10_SRC` | 3 |
| `l_flag_20` | `l_flag_ECI_ADR_S20_KEYED` | 3 |
| `l_flag_30` | `l_flag_ECI_ADR_S30_VALIDATED` | 3 |
| `l_flag_40` | `l_flag_ECI_ADR_S40_FLAT` | 3 |
| `l_flag_50` | `l_flag_ECI_ADR_S50_READY` | 3 |
| `l_flag_60` | `l_flag_ECI_ADR_DQM_ADDRESS` | 3 |
| `l_flag_70` | `l_flag_ECI_ADR_C_S_ECI_PTY_RLE_ADDR` | 3 |
| `l_flag_80` | `l_flag_ECI_ADR_EXC_STG_BAD_REC_MEMB` | 3 |

Total: 9 flag names, 27 identifier occurrences renamed. Coordinator follow-up fix (v2,
after the worker pass): the sibling families the worker had scoped out were renamed to
unit form under the same rule, so no old-family identifier remains in this driver:

| v1 name | v2 name | occurrences renamed |
|---|---|---|
| `l_cons_10` | `l_in_ECI_ADR_S10_SRC` | 3 |
| `l_cons_20` | `l_in_ECI_ADR_S20_KEYED` | 3 |
| `l_cons_30` | `l_in_ECI_ADR_S30_VALIDATED` | 3 |
| `l_cons_40` | `l_in_ECI_ADR_S40_FLAT` | 3 |
| `l_cons_50` | `l_in_ECI_ADR_S50_READY` | 3 |
| `l_cons_60` | `l_in_ECI_ADR_DQM_ADDRESS` | 3 |
| `l_cons_70` | `l_in_ECI_ADR_C_S_ECI_PTY_RLE_ADDR` | 3 |
| `l_cons_80` | `l_in_ECI_ADR_EXC_STG_BAD_REC_MEMB` | 3 |
| `l_pub_dqm` | `l_pub_ECI_ADR_DQM_ADDRESS` | 3 |
| `l_pub_spine` | `l_pub_ECI_ADR_C_S_ECI_PTY_RLE_ADDR` | 3 |
| `l_pub_exc` | `l_pub_ECI_ADR_EXC_STG_BAD_REC_MEMB` | 3 |
| `l_pub_dqm_run` | `l_pub_ECI_ADR_DQM_ADDRESS_run` | 3 |
| `l_pub_spine_run` | `l_pub_ECI_ADR_C_S_ECI_PTY_RLE_ADDR_run` | 3 |
| `l_pub_exc_run` | `l_pub_ECI_ADR_EXC_STG_BAD_REC_MEMB_run` | 3 |

ADR rename total: 27 flag + 42 sibling-family = 69 identifier occurrences. GATHER SELECT
column order and INTO order are unchanged (identifiers only). Summary display string
literals (e.g. `'step 60 ...'`) are unchanged. Step/driver header prose that described
the v1 checkpoint form (STEP_NO, WORK_TABLE_NAME, `'CREATED'`, purpose) was updated to
the v2 10-argument form by the coordinator prose scrub; exception message texts were
left unchanged (see the stale-pointer note in the README).

### v2 checkpoint signature (driver + all 5 step procs; publish procs have no checkpoint calls)

Every `sp_etl_checkpoint` call now passes exactly 10 arguments, in this order:
1 `P_SOURCE`, 2 `P_JOB_RUN_ID`, 3 `P_WORKFLOW_NAME`, 4 `P_MAPPING_NAME`, 5 `P_STATE`,
6 `P_STEP_NAME`, 7 `P_STEP_STATUS`, 8 `P_TARGET_TABLE`, 9 `P_MESSAGE`, 10 `P_ERROR_MESSAGE`
— with explicit NULLs, never trailing defaults. Dropped from the old form: `STEP_NO`,
`ROW_COUNT`, `SOURCE_ROW_COUNT`, `WORK_TABLE_NAME`, `WORK_TABLE_ACTION`,
`WORK_TABLE_PURPOSE`, `DROP_REASON`. Retained verbatim: SOURCE, JOB_RUN_ID, WORKFLOW,
MAPPING, STATE, STEP_NAME, STEP_STATUS, TARGET_TABLE, MESSAGE, ERROR_MESSAGE.
Consequences: step checkpoints no longer record the work-table name, `'CREATED'` action,
or purpose text (e.g. step 50's purpose text is gone; its TARGET_TABLE list and
`'Step 50 complete.'` message are retained); publish COMPLETED checkpoints no longer
carry the branch row count (the count survives in the `fn_snow_helper36_common` summary
line and the branch proc's RETURN value); SKIPPED rows no longer carry a work-table
name or `'NONE'` action. `sp_etl_job_begin` / `sp_etl_job_finish` / `sp_etl_job_fail`
calls are untouched, as are RETURN summaries and `fn_snow_helper36_common` lines.
Step numbers are unchanged everywhere else (config GATHER `STEP_NO` values, summary
literals, step/proc names).

### v2 verification results (all passed)

- Driver regex: 0 matches for `l_flag_[0-9]+`, `l_in_[0-9]+`, `l_pub_[0-9]+`.
- Balanced-parenthesis parse of every `sp_etl_checkpoint` call (not single-line grep):
  18 calls total (13 driver + 5 steps), all exactly 10 arguments in the new order;
  0 calls with 16/17 arguments remain; no dropped-parameter token (`'CREATED'`,
  `'NONE'`, `'KEPT'`, work-table name) appears inside any checkpoint call.
- Diff vs v1: driver diff is flag renames + checkpoint rewrites only; each step diff is
  its checkpoint block only (every step CTAS byte-identical to v1); all 3 publish procs
  byte-identical to v1 (0 checkpoint calls in publish, verified; their header comments
  mentioning checkpoints left alone).
- GATHER INTO order still matches SELECT order (flags 0/10/20/30/40/50/60/70/80, then
  consumed strings 10/20/30/40/50/60/70/80).
- Where this manifest previously described the old checkpoint form as current, it is
  superseded by this section (see the amended driver-flow, step-proc, and
  self-verification notes below).

Source of truth: `~/workspace/snowflake_multisource/ECI/mappings/sp_snow_main_m_Tgt_C_S_ECI_Pty_Addr.sql`
(verified against the file; where the refactor brief differed from the file, the file wins — see Deviations).
Framework: `~/workspace/snowflake_multisource/00_framework/02_job_control_procs.sql`.
Constants: `c_source = 'ECI'`, `c_workflow = 'wf_ECI_Stage_Load'`, `c_mapping = 'm_Tgt_C_S_ECI_Pty_Addr'`.
Config table (qualified): `COMMON.ETL_RUN_CONFIG_TBL`
(`WORKFLOW_NAME, MAPPING_NAME, STEP_NO, STEP_PROC_NAME, IS_DRIVER, IS_RUN_ENABLED, IS_DEPENDENT,
DEPENDENT_ON, WORK_TABLES_PRODUCED, WORK_TABLES_CONSUMED`).
Prefix `ECI_ADR`, short `ADR`. Base dir: `~/workspace/snowflake_eci_drivers/ECI/ADR/`.

## Driver

File: `ECI/ADR/driver_sp_snow_main_m_Tgt_C_S_ECI_Pty_Addr.sql`

Signature (identical to the current main procedure, name + params + order):

```sql
sp_snow_main_m_Tgt_C_S_ECI_Pty_Addr (
    P_MEMBER_HIERARCHY_CODE VARCHAR DEFAULT 'Member',
    P_MEMBER_HM_REL_TP_CD   VARCHAR DEFAULT 'Member Addr',
    P_JOB_RUN_ID            VARCHAR DEFAULT NULL
) RETURNS VARCHAR
```

Driver flow: job-run-id generation exactly as now + `sp_etl_job_begin` →
config GATHER (nested `BEGIN/EXCEPTION`, flags pre-initialised `'Y'`, consumed strings
pre-initialised to defaults; on exception the defaults stand) →
driver-row `STEP_NO = 0` flag `'N'` = SKIPPED checkpoint (`WORKING`, `MAPPING_SKIPPED`,
`SKIPPED`, v2 10-arg form — no `STEP_NO` argument) + `sp_etl_job_finish` + early RETURN, BEFORE step 5 →
step 5 cleanup unchanged (bare `DROP TABLE IF EXISTS` for all 5 work tables, no checkpoint
for drops) → conditional step calls 10–50 in order → publish transaction (branch calls only,
no checkpoint calls inside) → COMMIT → per-branch checkpoints/summary → `sp_etl_job_finish`
(same message style as now) + same RETURN format → EXCEPTION block identical in shape to now
(ROLLBACK + TERMINATING 999 FAILED checkpoint + `sp_etl_job_fail` + RAISE).

Skipped steps/branches: SKIPPED checkpoint row (same STEP_NAME, STATE `WORKING`,
STEP_STATUS `SKIPPED`, message `Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)`; v2 form
carries no `STEP_NO`, work-table name, or `'NONE'` action) and a
plain-text summary line (`step NN NAME: SKIPPED by config (IS_RUN_ENABLED = N)`).
`fn_snow_helper36_common` is NOT used for skips (it renders NULL as `0 row(s)`).
Skipping a step does not skip later steps: a later step needing the skipped step's work
table fails its own input-existence check naming the missing table.

## Step table

| STEP_NO | proc | kind | produces | consumes default | original params used | checkpoint STEP_NAME |
|---|---|---|---|---|---|---|
| 10 | `sp_snow_step_ECI_ADR_S10_SRC` | staged step, feeds spine chain indirectly | `WRK_ECI_ADR_S10_SRC` — address source rows, party/role keys, translated address type | `` (empty; base source view, no work-table input) | none | `SRC_ADDRESSES` |
| 20 | `sp_snow_step_ECI_ADR_S20_KEYED` | staged step, feeds spine chain indirectly | `WRK_ECI_ADR_S20_KEYED` — record keys, active addresses only | `WRK_ECI_ADR_S10_SRC` | none | `KEYED_ACTIVE` |
| 30 | `sp_snow_step_ECI_ADR_S30_VALIDATED` | staged step, feeds spine chain indirectly | `WRK_ECI_ADR_S30_VALIDATED` — validation result (pass-through stand-in) + state lookup | `WRK_ECI_ADR_S20_KEYED` | none | `ADDR_VALIDATION` |
| 40 | `sp_snow_step_ECI_ADR_S40_FLAT` | staged step, feeds spine chain indirectly | `WRK_ECI_ADR_S40_FLAT` — validation result unpacked + match-code description | `WRK_ECI_ADR_S30_VALIDATED` | none | `FLAT_VALIDATION` |
| 50 | `sp_snow_step_ECI_ADR_S50_READY` | staged step, feeds spine AND non-spine publish directly | `WRK_ECI_ADR_S50_READY` — score, issue description, held lines, insert-only guards (`uq_addr`, `uq_addr_exc`) | `WRK_ECI_ADR_S40_FLAT` | `P_MEMBER_HIERARCHY_CODE`, `P_MEMBER_HM_REL_TP_CD` (both, original order, before `P_JOB_RUN_ID`) | `SCORED_READY` |

Step-proc signature pattern: only the original params that step's SQL actually uses
(steps 10–40 use neither, so neither appears) + `P_JOB_RUN_ID VARCHAR` +
`P_RUN_TS TIMESTAMP_NTZ` + `P_INPUT_TABLES VARCHAR DEFAULT '<consumes default>'`.
Each step proc: input-existence check (skipped when `P_INPUT_TABLES` is NULL/empty;
`LISTAGG`/`FLATTEN` split on `|`, `INFORMATION_SCHEMA.TABLES` with
`TABLE_SCHEMA = CURRENT_SCHEMA()`; on a miss, `RAISE EXCEPTION` naming the missing
table(s) and the step — same form as the sibling PTY step proc) → step CTAS verbatim →
`SELECT COUNT(*) INTO :l_rows` → its own checkpoint in the v2 10-arg form with the
retained values from the current step checkpoint (STEP_NAME, STEP_STATUS, TARGET_TABLE,
`'Step NN complete.'` message; `STEP_NO`, row count, work-table name, `'CREATED'` action
and purpose text are dropped per the v2 signature — step 50's checkpoint TARGET_TABLE
list is retained verbatim, see Deviations) →
`RETURN :l_rows (NUMBER)`. No exception block, no transactions, no target writes.
Base source tables and target guard tables (e.g. step 20's `STG_ECI_PTY_INACTIVE_STS`,
step 50's `C_S_ECI_PTY_RLE_ADDR` guard join) are NOT work-table dependencies and are
not listed in `P_INPUT_TABLES`. `P_INPUT_TABLES` is a dependency declaration + runtime
check, NOT dynamic SQL: Snowflake cannot parameterise table names in static SQL, so
each CTAS still names its sources literally, as now. Only substitutions in the CTAS:
`:l_run_ts` → `:P_RUN_TS` (step 50 only), `:c_mapping` → a local DECLARE constant with
the same value, original-param refs → the proc's params.

## Branch table (publish, one proc per current publish INSERT, in file order)

| STEP_NO | proc | kind | target | consumes |
|---|---|---|---|---|
| 60 | `sp_snow_pub_ECI_ADR_DQM_ADDRESS` | NON-SPINE (address-quality) | `DQM_ADDRESS` (every active address; original branch 60a, first) | `WRK_ECI_ADR_S50_READY` |
| 70 | `sp_snow_pub_ECI_ADR_C_S_ECI_PTY_RLE_ADDR` | SPINE (party-role address spine) | `C_S_ECI_PTY_RLE_ADDR` (score `100` + `uq_addr`; original branch 60b, second) | `WRK_ECI_ADR_S50_READY` |
| 80 | `sp_snow_pub_ECI_ADR_EXC_STG_BAD_REC_MEMB` | NON-SPINE (exception log) | `EXC_STG_BAD_REC_MEMB` (score `40` + `uq_addr_exc`; original branch 60c, third) | `WRK_ECI_ADR_S50_READY` |

Publish-branch signature pattern: `P_JOB_RUN_ID VARCHAR` + `P_RUN_TS TIMESTAMP_NTZ` +
`P_INPUT_TABLES VARCHAR DEFAULT 'WRK_ECI_ADR_S50_READY'` (+ branch-specific original
params only if that INSERT actually uses them — none of the three INSERTs references an
original param directly; they read columns already materialised in step 50, so none
appears). Each branch proc: its INSERT verbatim (same columns, values, WHERE guards) →
`RETURN SQLROWCOUNT AS NUMBER`. NO transaction control, NO checkpoint calls (framework
rule — the driver checkpoints each branch only after COMMIT). `P_RUN_TS` is carried for
signature uniformity; the INSERTs use the `run_ts` column already stored in step 50, as
in the current code. Publish-branch checkpoint STEP_NAMEs (driver, after COMMIT):
`PUBLISH_DQM_ADDRESS`, `PUBLISH_C_S_ECI_PTY_RLE_ADDR`, `PUBLISH_EXC_STG_BAD_REC_MEMB`
(each with its single TARGET_TABLE and its own branch row count; the current single
step-60 `PUBLISH` checkpoint with the summed count is replaced by these three).

## Files delivered (9 procs + this manifest)

- `ECI/ADR/driver_sp_snow_main_m_Tgt_C_S_ECI_Pty_Addr.sql` — driver (1 proc)
- `ECI/ADR/steps/sp_snow_step_ECI_ADR_S10_SRC.sql`
- `ECI/ADR/steps/sp_snow_step_ECI_ADR_S20_KEYED.sql`
- `ECI/ADR/steps/sp_snow_step_ECI_ADR_S30_VALIDATED.sql`
- `ECI/ADR/steps/sp_snow_step_ECI_ADR_S40_FLAT.sql`
- `ECI/ADR/steps/sp_snow_step_ECI_ADR_S50_READY.sql`
- `ECI/ADR/publish/sp_snow_pub_ECI_ADR_DQM_ADDRESS.sql`
- `ECI/ADR/publish/sp_snow_pub_ECI_ADR_C_S_ECI_PTY_RLE_ADDR.sql`
- `ECI/ADR/publish/sp_snow_pub_ECI_ADR_EXC_STG_BAD_REC_MEMB.sql`
- `ECI/ADR/ADR_MANIFEST.md` — this file

## Self-verification results (all passed, by scripted diff, whitespace-normalised)

- Every step CTAS matches the current file exactly after the single allowed substitution
  (`:l_run_ts` → `:P_RUN_TS` in step 50; no other step uses it, and no other substitution
  was needed — `:c_mapping` is a local constant of the same value in each step proc).
- Every publish INSERT matches the current file exactly (columns, values, WHERE guards).
- Driver name/signature identical to the current main procedure (verified by normalised
  comparison of the procedure header).
- Counts: 5 current steps → 5 step procs (one each, no step missing, no extra);
  3 current publish INSERTs → 3 branch procs (one each, no branch missing, no extra).
- Style greps (code, ignoring header prose where noted): 0 `DROPPED` tokens anywhere;
  0 `P_RESUME_STEP`; 0 row-by-row iteration constructs (existence check is set-based
  `LISTAGG`/`FLATTEN`, no cursor); TRANSIENT work tables only, same 5 names as now;
  `P_JOB_RUN_ID` in all 9 new procs; no checkpoint calls and no transaction control in
  any publish-branch proc (code); no checkpoint call between the driver's
  `BEGIN TRANSACTION` (line 342) and `COMMIT` (line 355) — publish checkpoints start at
  line 359, after COMMIT; step 5 is 5 bare `DROP TABLE IF EXISTS` statements, no
  checkpoint for drops. (Header prose was scrubbed of the tokens `DROPPED`/`CURSOR`
  so a naive grep does not false-positive; the publish headers likewise avoid naming
  the checkpoint proc or transaction keywords.)
- Step checkpoint values spot-checked against the current file (v1 values; v2 form drops
  `STEP_NO`, work-table name, `'CREATED'` and purpose text): STEP_NAME, TARGET_TABLE and
  `Step NN complete.` message all match, including step 50's TARGET_TABLE list
  (see Deviations).

## Deviations and uncertainties — nothing silently shipped

1. **Publish branch count and STEP_NOs (file wins over the brief).** The brief described
   publish step 60 as 2 INSERTs (spine `C_S_ECI_PTY_RLE_ADDR`, then non-spine
   `EXC_STG_BAD_REC_MEMB`) with branch STEP_NOs 60 and 70. The current file in fact
   contains **3** INSERTs in its single step-60 transaction, in this order: (60a)
   `DQM_ADDRESS`, (60b) `C_S_ECI_PTY_RLE_ADDR`, (60c) `EXC_STG_BAD_REC_MEMB`. All 3
   are preserved as branches, in file order, with STEP_NOs **60, 70, 80** (DQM = 60,
   spine = 70, exception = 80). The config table therefore needs STEP_NO rows 60/70/80
   for this mapping, not 60/70. If the intent was to exclude `DQM_ADDRESS` from this
   refactor, that needs an explicit decision — it was NOT excluded here, because the
   brief also required one proc per current publish INSERT.
2. **Step 50 checkpoint retained verbatim, including its "step 60" wording (v1; v2
   keeps TARGET_TABLE and message, drops purpose).** Its TARGET_TABLE
   (`DQM_ADDRESS, C_S_ECI_PTY_RLE_ADDR, EXC_STG_BAD_REC_MEMB`) and message are copied
   unchanged from the current file, even though publish now spans STEP_NOs 60–80. This
   is a wording relic, not a behaviour change. In v1 its purpose text
   (`Scored, publish-ready addresses ... Published in step 60.`) was also recorded; in
   v2 the purpose argument no longer exists, so that text is gone from the checkpoint
   (the step-50 header/prose still describes it historically).
3. **SKIPPED checkpoint columns beyond the brief's minimum (v1 only; removed in v2).**
   In v1 the driver also recorded WORK_TABLE_NAME (step skips) / TARGET_TABLE (branch
   skips) with WORK_TABLE_ACTION `'NONE'`, for traceability. In v2 those extra columns
   are gone with the rest of the dropped arguments: a SKIPPED row now carries only
   STEP_NAME, STATE, STEP_STATUS, TARGET_TABLE (step skips: NULL; branch skips: the
   branch target), MESSAGE and ERROR_MESSAGE.
4. **Driver-skip summary line.** The brief did not specify a summary line for the
   driver-row skip; the driver sets one plain line (`...: SKIPPED by config
   (IS_RUN_ENABLED = N for STEP_NO 0)`) so the RETURN value still follows the current
   `JOB_RUN_ID=...` + summary format and is not empty.
5. **SKIPPED vocabulary — user choice to confirm.** `JOB_CONTROL_ETL.STEP_STATUS` has
   NO CHECK constraint (only a DDL comment listing `STARTED | COMPLETED | FAILED`), so
   `SKIPPED` rows are written as specified; flag this to the user as a choice to confirm
   (a CHECK constraint or a DDL-comment update would otherwise be needed).
6. **Compile-time verification items (no live Snowflake here — nothing was compiled
   or row-count parity-tested).** (a) Scalar-call return capture
   `l_rows := (CALL proc(...));` in the driver; (b) the nested `BEGIN/EXCEPTION`
   around the config GATHER; (c) the `RAISE EXCEPTION '...' || :l_missing;` form in
   the step procs (same form as the sibling PTY step proc, but likewise uncompiled here);
   (d) `RETURN SQLROWCOUNT;` in the branch procs. All four must be verified on first
   Snowflake compile; if `RAISE EXCEPTION` fails to compile, the brief's fallback is
   `EXECUTE IMMEDIATE 'SELECT 1 FROM <missing table>'` to surface the native
   object-not-exists error.
7. **Config-table assumptions not verified here.** The GATHER assumes
   `COMMON.ETL_RUN_CONFIG_TBL` exists with the stated columns and that `IS_RUN_ENABLED`
   holds `'Y'`/`'N'`; any other value is treated as "not Y" (step/branch skipped).
   If the table is missing/unreadable, the GATHER exception handler leaves the
   pre-initialised defaults standing and the run proceeds as the current main procedure.
   `l_config_ok` is set FALSE in that handler but is not read afterwards — the defaults
   standing is the mechanism; the flag is informational only.
8. **Preserved quirks (from the current file, unchanged).** Insert-only publish (no
   TRUNCATE/DELETE); the job-run-id generation block is verbatim, including that
   `l_job_run_id` starts NULL so the branch is always entered and `COALESCE` then picks
   a supplied `P_JOB_RUN_ID` or generates one; step 50's guard join still sees the
   pre-run target state because nothing is published before step 50. The current
   single step-60 summed publish count is replaced by per-branch counts (see branch
   table); the summed total is recoverable by adding the three branch checkpoints.

## ASSEMBLY NOTE (coordinator, post-worker normalisation)

The existence-check error form in this mapping's step procs was normalised from
`RAISE EXCEPTION '...' || :l_missing;` to a probe query
(`l_probe_sql := 'SELECT 1 FROM ' || TRIM(SPLIT_PART(:l_missing, ',', 1));`
`EXECUTE IMMEDIATE :l_probe_sql;`), because Snowflake Scripting RAISE accepts only a
declared exception name and cannot embed a runtime-discovered table name. Business SQL is
untouched; only the error-raising lines changed. Any statement in this manifest about the
RAISE form is superseded by this note.
