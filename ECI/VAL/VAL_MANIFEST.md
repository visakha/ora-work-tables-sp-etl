# VAL_MANIFEST — m_Tgt_C_S_ECI_Pty_Validation (ECI, config-driven step-driver refactor)

Example for user feedback. ECI ONLY. Business SQL preserved — only
re-housed. No business expression, filter, guard or column list was
changed; every step CTAS and every publish INSERT was diffed against
the current main procedure and matches (see Verification below).

## v2 migration (2026-10-27) — flag rename + 10-argument checkpoint

Branch number-to-branch assignment, verified from the driver code
itself (NOT assumed from file order): 40 =
`sp_snow_pub_ECI_VAL_EXC_STG_BAD_REC_MEMB`, 50 =
`sp_snow_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_DEACTIVATION`, 60 =
`sp_snow_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_STS`, 70 =
`sp_snow_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_REACTIVATION`.

Flag rename — ANOMALY NOTE: this driver's v1 variables were NOT
`l_flag_<digits>` / `l_in_<nn>`. Its actual v1 families were
`l_run_*` (run flags), `l_cons_*` (consumed-table strings) and
`l_pub_<nn>` (publish counts). The same rename rule was applied to
those actual families (strip the `sp_snow_step_` / `sp_snow_pub_`
prefix from the unit's procedure name, prepend `l_flag_` / `l_in_` /
`l_pub_`; driver-row flag becomes `l_flag_ECI_VAL_DRIVER`):

| v1 variable | v2 variable |
|---|---|
| `l_run_driver` | `l_flag_ECI_VAL_DRIVER` |
| `l_run_s10` / `l_cons_s10` / — | `l_flag_ECI_VAL_S10_SRC` / `l_in_ECI_VAL_S10_SRC` |
| `l_run_s20` / `l_cons_s20` | `l_flag_ECI_VAL_S20_ENRICHED` / `l_in_ECI_VAL_S20_ENRICHED` |
| `l_run_s30` / `l_cons_s30` | `l_flag_ECI_VAL_S30_ROUTED` / `l_in_ECI_VAL_S30_ROUTED` |
| `l_run_p40` / `l_cons_p40` / `l_pub_40` | `l_flag_ECI_VAL_EXC_STG_BAD_REC_MEMB` / `l_in_ECI_VAL_EXC_STG_BAD_REC_MEMB` / `l_pub_ECI_VAL_EXC_STG_BAD_REC_MEMB` |
| `l_run_p50` / `l_cons_p50` / `l_pub_50` | `l_flag_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_DEACTIVATION` / `l_in_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_DEACTIVATION` / `l_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_DEACTIVATION` |
| `l_run_p60` / `l_cons_p60` / `l_pub_60` | `l_flag_ECI_VAL_STG_ECI_PTY_INACTIVE_STS` / `l_in_ECI_VAL_STG_ECI_PTY_INACTIVE_STS` / `l_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_STS` |
| `l_run_p70` / `l_cons_p70` / `l_pub_70` | `l_flag_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_REACTIVATION` / `l_in_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_REACTIVATION` / `l_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_REACTIVATION` |

61 identifier occurrences renamed in the driver only (DECLARE block,
GATHER INTO list, IF conditions, publish-call arguments, helper36
summary lines). `l_run_ts` is NOT a flag and was left untouched.
GATHER SELECT column order and INTO order are unchanged — only the
identifiers changed, so INTO order still matches SELECT order
(verified: flags 0/10/20/30/40/50/60/70 then consumed 10/20/30/40/50/
60/70). Summary display strings (string literals such as
`'step 40 PUBLISH_...'`) are unchanged — they are not identifiers.
Step and publish procs carry none of these variables and were not
renamed.

Checkpoint migration — v2 `sp_etl_checkpoint` form, exactly 10
arguments in this order: 1 `P_SOURCE`, 2 `P_JOB_RUN_ID`,
3 `P_WORKFLOW_NAME`, 4 `P_MAPPING_NAME`, 5 `P_STATE`,
6 `P_STEP_NAME`, 7 `P_STEP_STATUS`, 8 `P_TARGET_TABLE`,
9 `P_MESSAGE`, 10 `P_ERROR_MESSAGE`, always with explicit NULLs.
Dropped from the old form: `STEP_NO`, `ROW_COUNT`,
`SOURCE_ROW_COUNT`, `WORK_TABLE_NAME`, `WORK_TABLE_ACTION`,
`WORK_TABLE_PURPOSE`, `DROP_REASON`. Kept values (SOURCE,
JOB_RUN_ID, WORKFLOW, MAPPING, STATE, STEP_NAME, STEP_STATUS,
TARGET_TABLE, MESSAGE, ERROR_MESSAGE) are unchanged, including all
message text. Consequence: row counts and work-table purposes no
longer travel in checkpoints — counts survive in the step procs'
`RETURN` values and the driver's helper36 summary lines, and step
numbers survive only as config `STEP_NO` values and in summary
strings. 16 calls migrated: 13 in the driver (1 MAPPING_SKIPPED,
3 step SKIPPED, 4 publish COMPLETED, 4 publish SKIPPED, 1 exception
JOB_END FAILED) + 1 in each of the 3 step procs. Publish procs
contain no checkpoint calls (verified) and were left untouched,
comment mentions included. `sp_etl_job_begin` /
`sp_etl_job_finish` / `sp_etl_job_fail` calls are untouched.
Anomaly found during migration: the 3 v1 step-proc checkpoint calls
were 16-argument (the trailing ERROR_MESSAGE was defaulted, not
passed), while the 13 v1 driver calls were 17-argument; both now
pass an explicit 10th argument (NULL error for the steps), so no
call relies on a trailing default. The v2 section below that still
describes v1 checkpoint values ("Step checkpoint values...") is
superseded by this section for the kept/dropped fields; the v1
purpose strings (including step 30's "Published in step 40") are
no longer passed as checkpoint arguments.

v2 verification (balanced-parenthesis parsing, not single-line
grep, since calls span lines): every `sp_etl_checkpoint` call in
all 8 files has exactly 10 arguments in the new order; zero
16/17-argument calls remain; zero references to the dropped
parameters as call arguments (no `'NONE'` / `'KEPT'` /
`'CREATED'` checkpoint arguments remain); zero remaining members
of the old variable families (`l_run_driver`, `l_run_s*`,
`l_run_p*`, `l_cons_*`, `l_pub_<digits>`) and zero
`l_flag_[0-9]+` / `l_in_[0-9]+` / `l_pub_[0-9]+` matches in the
driver; step CTAS bodies and publish INSERT bodies diffed against
v1 are identical except for the checkpoint-call rewrites (and the
driver renames, which touch no business SQL); the 4 publish files
are byte-identical to v1 (unchanged).
No live Snowflake compile was possible here, as before.

Source of truth read first:
`~/workspace/snowflake_multisource/ECI/mappings/sp_snow_main_m_Tgt_C_S_ECI_Pty_Validation.sql`
(step map: `~/workspace/snowflake_multisource/ECI/STEP_MAP_ECI.md` §1).
The current file matched the task description exactly — 3 steps
(10/20/30), publish step 40 with 4 INSERTs in the stated order, no
original parameters. No variance to report on that front.

## Driver signature

`sp_snow_main_m_Tgt_C_S_ECI_Pty_Validation (P_JOB_RUN_ID VARCHAR DEFAULT NULL)`
`RETURNS VARCHAR` — name and signature EXACTLY as the current main, so
installing the driver replaces the current main procedure. Constants:
`c_source='ECI'`, `c_workflow='wf_ECI_Stage_Load'`,
`c_mapping='m_Tgt_C_S_ECI_Pty_Validation'`. Config table (qualified):
`COMMON.ETL_RUN_CONFIG_TBL`.

Driver behaviour in one paragraph: job-run-id generation exactly as now
+ `sp_etl_job_begin`; GATHER of run flags + consumed strings from the
config table in a nested `BEGIN/EXCEPTION` block (defaults stand on any
config error); driver-row `STEP_NO=0` = 'N' writes a `MAPPING_SKIPPED`
checkpoint, finishes and returns BEFORE step-5 cleanup; step 5 drops
the 3 work tables with no checkpoint for drops; steps 10/20/30 called
conditionally with `SKIPPED` checkpoints + plain-text summary lines for
skips (helper36 never used for skips); publish runs in ONE transaction
(enabled branches only), `COMMIT`, then branch checkpoints + summary
lines AFTER COMMIT; `TERMINATING` via `sp_etl_job_finish` with the same
message style and RETURN format as now; exception block identical in
shape to now (`ROLLBACK` + `TERMINATING` 999 `FAILED` checkpoint +
`sp_etl_job_fail` + `RAISE`).

## Step table

KIND vocabulary for this mapping: the LOG/STS tables ARE the
spine/status outcome, so a step "feeds the status path" when its output
leads (directly or transitively) to a LOG/STS write. EXC is non-spine
and appears only in the branch table.

| STEP_NO | proc | kind | produces | consumes default | original params used | checkpoint STEP_NAME |
|---|---|---|---|---|---|---|
| 10 | `sp_snow_step_ECI_VAL_S10_SRC` | FEEDS-STATUS (upstream) | `WRK_ECI_VAL_S10_SRC` | `` (empty — reads base tables `STG_ECI_D_CHILD`, `STG_ECI_D_FAMILY`) | None (mapping has no original params) | `SRC_DELTA_PARTIES` |
| 20 | `sp_snow_step_ECI_VAL_S20_ENRICHED` | FEEDS-STATUS (upstream) | `WRK_ECI_VAL_S20_ENRICHED` | `WRK_ECI_VAL_S10_SRC` | None | `ENRICHED_STD_NAMES` |
| 30 | `sp_snow_step_ECI_VAL_S30_ROUTED` | FEEDS-STATUS (direct — sole source of all 4 publish branches) | `WRK_ECI_VAL_S30_ROUTED` | `WRK_ECI_VAL_S20_ENRICHED` | None (run_ts comes from driver `P_RUN_TS`, not an original param) | `ROUTED_GROUPS` |

Step proc signature (all three):
`sp_snow_step_ECI_VAL_S<nn>_<NAME> (P_JOB_RUN_ID VARCHAR, P_RUN_TS TIMESTAMP_NTZ, P_INPUT_TABLES VARCHAR DEFAULT '<consumes default above>')`
`RETURNS NUMBER`. Each step: (1) input-existence check over
`P_INPUT_TABLES` split on `|` against `INFORMATION_SCHEMA.TABLES`
(skipped when NULL/empty); (2) its CTAS verbatim (only substitutions
`:l_run_ts` -> `:P_RUN_TS`, `:c_mapping` -> local constant of the same
value — only step 30 actually uses either); (3) `COUNT(*)` into
`l_rows`; (4) its own checkpoint in the v2 10-argument form carrying
the same STEP_NAME, STEP_STATUS, TARGET_TABLE and message as the v1
step checkpoint (STEP_NO, row count, work-table name/action/purpose
and drop reason are no longer passed — see the v2 migration section
above); (5) `RETURN :l_rows`. No exception block, no
transactions, no target writes.

Driver-row (not a step): `STEP_NO 0`, checkpoint STEP_NAME
`MAPPING_SKIPPED`, `STATE 'WORKING'`, `STEP_STATUS 'SKIPPED'`, message
noting the config disable; `sp_etl_job_finish` with a skipped message;
early `RETURN` in the same `JOB_RUN_ID=...` format.

## Branch table

Publish order is the current publish order (40a–40d). The old single
step-40 `PUBLISH` checkpoint (combined count) is replaced by these four
branch checkpoints, per the refactor spec.

| STEP_NO | proc | kind | target | consumes |
|---|---|---|---|---|
| 40 | `sp_snow_pub_ECI_VAL_EXC_STG_BAD_REC_MEMB` | NON-SPINE | `EXC_STG_BAD_REC_MEMB` (blank-name exceptions, `grp_invalid_party_name AND uq_exc_name`) | `WRK_ECI_VAL_S30_ROUTED` |
| 50 | `sp_snow_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_DEACTIVATION` | STATUS (spine/status path) | `STG_ECI_PTY_INACTIVE_LOG` (deactivation log rows, `grp_deactivation`) | `WRK_ECI_VAL_S30_ROUTED` |
| 60 | `sp_snow_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_STS` | STATUS (spine/status path) | `STG_ECI_PTY_INACTIVE_STS` (new status rows only, `grp_deactivation AND deactivation_sts IS NULL`) | `WRK_ECI_VAL_S30_ROUTED` |
| 70 | `sp_snow_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_REACTIVATION` | STATUS (spine/status path) | `STG_ECI_PTY_INACTIVE_LOG` (reactivation log rows, `grp_reactivation`) | `WRK_ECI_VAL_S30_ROUTED` |

Branch proc signature (all four):
`sp_snow_pub_ECI_VAL_<TARGET>[_<BRANCH>] (P_JOB_RUN_ID VARCHAR, P_RUN_TS TIMESTAMP_NTZ, P_INPUT_TABLES VARCHAR DEFAULT 'WRK_ECI_VAL_S30_ROUTED')`
`RETURNS NUMBER`. Body: the branch's INSERT verbatim, then
`RETURN SQLROWCOUNT`. NO transaction control, NO checkpoint calls
(driver checkpoints each branch only after `COMMIT`).
Branch checkpoint STEP_NAMEs: `PUBLISH_EXC_STG_BAD_REC_MEMB`,
`PUBLISH_STG_ECI_PTY_INACTIVE_LOG_DEACTIVATION`,
`PUBLISH_STG_ECI_PTY_INACTIVE_STS`,
`PUBLISH_STG_ECI_PTY_INACTIVE_LOG_REACTIVATION`
(`STATE 'WORKING'`, `STEP_STATUS 'COMPLETED'` or `'SKIPPED'`,
`TARGET_TABLE` = branch target). In v2 the checkpoint carries NO
row count: the branch count survives only in the driver's helper36
summary line (and the branch proc's `RETURN` value).

## File list

- `driver_sp_snow_main_m_Tgt_C_S_ECI_Pty_Validation.sql` (driver, same name/signature as current main)
- `steps/sp_snow_step_ECI_VAL_S10_SRC.sql`
- `steps/sp_snow_step_ECI_VAL_S20_ENRICHED.sql`
- `steps/sp_snow_step_ECI_VAL_S30_ROUTED.sql`
- `publish/sp_snow_pub_ECI_VAL_EXC_STG_BAD_REC_MEMB.sql`
- `publish/sp_snow_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_DEACTIVATION.sql`
- `publish/sp_snow_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_STS.sql`
- `publish/sp_snow_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_REACTIVATION.sql`
- `VAL_MANIFEST.md` (this file)

## Verification performed (no live Snowflake here)

- Step CTAS diff: all 3 CTAS bodies extracted from the current main and
  from the new step procs match character-for-character after the single
  allowed substitution (`:l_run_ts` -> `:P_RUN_TS`, step 30 only).
- Branch INSERT diff: all 4 INSERT bodies match character-for-character.
- Step checkpoint values (v1 description; superseded for v2 by the
  v2 migration section above): STEP_NO / STEP_NAME / WORK_TABLE_NAME /
  `'CREATED'` / purpose / message matched the current checkpoints
  (purpose strings compared including step 30's full 3-part purpose).
  In v2 only STEP_NAME / STEP_STATUS / TARGET_TABLE / message are
  carried, with the same values; the other v1 fields are dropped.
- Driver name/signature identical to the current main (verified by
  direct comparison of the `CREATE OR REPLACE PROCEDURE` headers).
- Coverage: every current step has exactly one new proc; every current
  publish INSERT has exactly one new proc; no extra step/branch proc.
- Greps over all 8 new files: 0 `DROPPED` checkpoint args, 0
  `P_RESUME_STEP`, 0 cursors (one prose mention "No CURSOR was used" in
  the driver header only), 0 `TEMP`/`TEMPORARY` tables (all CTAS are
  `TRANSIENT`, same names as now), `P_JOB_RUN_ID` in all 8 procs,
  0 checkpoint calls and 0 transaction statements in publish procs
  (header prose mentions only), 0 transaction statements in step procs,
  no checkpoint call between the driver's `BEGIN TRANSACTION` and
  `COMMIT` (first publish checkpoint is after `COMMIT`), step-5
  cleanup is 3 bare `DROP TABLE IF EXISTS` statements with no
  checkpoint.
- Framework signatures used match
  `00_framework/02_job_control_procs.sql` (`sp_etl_job_begin`,
  `sp_etl_checkpoint`, `sp_etl_job_finish`, `sp_etl_job_fail`).
  In v2, `sp_etl_checkpoint` is called in the new 10-argument form
  (see the v2 migration section above); the framework file itself
  was not touched by this worker (out of scope).

## Deviations, assumptions and uncertainties (nothing silently shipped)

1. Publish INSERTs need NO `:l_run_ts` / mapping substitution: they
   reference the routed table's `run_ts` / `mapping_name` columns,
   stamped at step 30. `P_RUN_TS` in publish procs is therefore
   declared for a uniform driver-call shape but unused by the INSERT —
   re-stamping it there would CHANGE business SQL, so it was not done.
2. Publish procs do NOT runtime-check `P_INPUT_TABLES` (the publish
   spec lists only INSERT + RETURN). A missing routed table surfaces
   as the native object-not-exists error on the INSERT. If the user
   wants the step-style existence check in publish procs too, it is a
   one-block addition per proc — flagged for feedback.
3. Step-30 checkpoint purpose text (v1): preserved verbatim,
   including "Published in step 40" — step 40 is now the first
   publish branch. In v2 this purpose text is no longer passed at
   all (the 10-argument checkpoint form has no purpose argument);
   the step-30 proc header was updated to say so.
4. `SKIPPED` vocabulary: `JOB_CONTROL_ETL.STEP_STATUS` has NO CHECK
   constraint (verified in `00_framework/01_job_control_ddl.sql` — only
   a DDL comment listing `STARTED | COMPLETED | FAILED`), so
   `'SKIPPED'` rows are written for config-skipped steps/branches and
   for a config-skipped mapping. Confirm whether `SKIPPED` should be
   added to the DDL comment / a constraint, or kept as-is.
5. Config table DDL not found: a grep of the framework files and the
   driver tree found no `ETL_RUN_CONFIG_TBL` definition. The driver
   assumes it exists as `COMMON.ETL_RUN_CONFIG_TBL` per the refactor
   spec; the GATHER fallback (defaults stand on any error) means a
   missing table degrades to a full run rather than a failure. Its
   actual DDL still needs confirming before install.
6. Type assumptions (unverifiable without the config DDL):
   `IS_RUN_ENABLED` is VARCHAR `'Y'`/`'N'`; `WORK_TABLES_CONSUMED` is a
   pipe-delimited VARCHAR. A type mismatch fails inside the GATHER
   handler and likewise degrades to a full run, not a failure.
7. Config columns `IS_DRIVER`, `IS_DEPENDENT`, `DEPENDENT_ON`,
   `WORK_TABLES_PRODUCED` are NOT consumed by this driver — step order
   is the fixed order in the driver body. If dependency ordering is
   meant to be config-driven, that is a further change.
8. Skipping an upstream step while a downstream step stays enabled
   fails at the downstream step's input-existence check, by design
   (config cannot silently run a step over a missing input). The
   driver exception handler then rolls back and writes the FAILED
   rows; work tables are left in place.
9. Compile-time verification items (no live Snowflake in this
   environment — must be confirmed at first compile):
   - scalar-call capture form `l_rows := (CALL proc(...));` in the
     driver (steps + publish branches);
   - step procs' `RAISE EXCEPTION '...' || :l_missing;` form (same
     form as the sibling PTY step file); fallback if it fails to
     compile is `EXECUTE IMMEDIATE 'SELECT 1 FROM <missing table>'`
     to surface the native object-not-exists error;
   - nested `BEGIN ... EXCEPTION WHEN OTHER THEN ... END;` GATHER
     block in the driver;
   - `SPLIT`/`FLATTEN` existence-check query against
     `INFORMATION_SCHEMA.TABLES` with `TABLE_SCHEMA = CURRENT_SCHEMA()`.
10. Cosmetic-only differences from the original: the driver and step
    procs use the `:c_source` / `:c_workflow` / `:c_mapping` constants
    where the original used the `'ECI'` literal in checkpoint/job
    calls — values are identical. The driver exception block keeps the
    original `'ECI'` literals verbatim. Job-run-id generation is
    preserved verbatim, including the check on the uninitialised
    `l_job_run_id` (NULL at that point, so the branch always takes the
    supplied id or generates one).
11. Parity notes carried over unchanged from the current file,
    including: insert-only (no `TRUNCATE`/`DELETE`); the IDQ
    `DD_DELETE` of the inactive status table (`Upd_Delete_Inactive`)
    is NOT performed; 10-character full name; no prefix/suffix passed
    to name standardisation; exception description/type from the
    catalogue (NULL when unconfigured); `uq_exc_name` second-row
    suppression; hub xref `ROWID_SYSTEM` trimmed to `'ECI'`.
12. No live Snowflake compile, row-count parity run, or config-table
    test was possible here — required before install.

## ASSEMBLY NOTE (coordinator, post-worker normalisation)

The existence-check error form in this mapping's step procs was normalised from
`RAISE EXCEPTION '...' || :l_missing;` to a probe query
(`l_probe_sql := 'SELECT 1 FROM ' || TRIM(SPLIT_PART(:l_missing, ',', 1));`
`EXECUTE IMMEDIATE :l_probe_sql;`), because Snowflake Scripting RAISE accepts only a
declared exception name and cannot embed a runtime-discovered table name. Business SQL is
untouched; only the error-raising lines changed. Any statement in this manifest about the
RAISE form is superseded by this note.
