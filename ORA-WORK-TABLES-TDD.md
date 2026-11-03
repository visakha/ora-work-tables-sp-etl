# ORA-WORK-TABLES-TDD — Technical Design Document

## Oracle work-tables step-driver ETL: build the IICS mappings from this document

**Source:** the Snowflake All-Sources Modular Step Driver v2.1 (the "chapter-two"
code), translated faithfully to Oracle PL/SQL. **This document is the build guide:**
a developer who follows it step by step, with `WORKFLOW-STEPS.md` open beside it,
can build the IICS mappings without reading the Snowflake originals.

**Status: static translation only.** No database was connected. Nothing here has
been compiled on Oracle, executed, or parity-checked against IDQ. §13 lists
exactly what was verified and what still needs a live database. Do not read
"translated" as "proven".

---

## 1. Purpose

This layout exists for one reason, stated up front because every other decision
follows from it:

> **In Informatica IDQ / IICS, mappings are discrete: a CTE computed in one
> mapping cannot be passed to the next mapping. So the step-driver pattern
> materializes every handoff as a table: each step is a single stored procedure
> that writes one or more work tables, and the next step reads them.**

That is the whole point of this layout. The unit is the **STEP**, and work tables
are the handoffs between steps, across a whole workflow.

### 1.1 Contrast with the two sibling layouts

| | Single-SP layout (`ora-single-sp-layout`) | Multiple-SP layout (`ora-multiple-sp-layout`) | **This layout (work-tables step-driver)** |
|---|---|---|---|
| Unit | One big procedure per mapping | One discrete procedure per write, inside one mapping | **One procedure per STEP, across a whole workflow** |
| How data moves inside a mapping | CTEs inside the procedure | A materializer procedure writes a WRK table; writer procedures read it | **Each step writes a WRK table; the next step reads it** |
| How data moves across mappings | N/A (one procedure) | N/A (chain is inside one mapping) | **Work tables + staging tables, ordered by the runner** |
| IICS shape | One mapping task per mapping (the proc is the mapping) | One mapping per discrete proc, chained inside one mapping task | **One mapping per STEP; the driver is the taskflow; the runner is the workflow** |
| Restart | Whole mapping | Whole mapping (or from the materializer) | **Whole mapping (new run); no step-level resume — see §9** |
| Work tables | None | WRK snapshots inside one mapping | **152 WRK tables, one per step, across 7 workflows** |

Do not mix the layouts. If you are building from this document, you are building
the third row: step procedures, work tables between them, drivers as taskflows,
runners as workflows.

### 1.2 What this tree is NOT

- **Not the v3 line.** This tree predates all v3 features: no spine/non-spine
  flag columns, no `V_MDM_*` / `V_CMP_*` / `V_AUDIT_*` views, no DIAG columns,
  no flag-aware filtering. Targets are the plain `C_S_*` tables, and every
  landed row flows downstream. Do not import v3 concepts into this build.
- **Not a redesign.** Names, parameters, columns, predicates, order, and quirks
  are preserved from the Snowflake step-driver tree, including its known
  oddities (§11, §12). Where the Snowflake code has a wart, the Oracle code has
  the same wart, documented, not fixed.

---

## 2. Architecture: runner → driver → steps → publish

```
Run script (one per workflow, SELECT runner() FROM DUAL)
  └─ Runner procedure  (sp_etl_run_wf_<WORKFLOW>)
       └─ Driver procedure, one per mapping  (sp_snow_main_<MAPPING>)
            ├─ Step 0:  job begin + driver-row gate
            ├─ Step 5:  DROP all work tables this mapping's steps produce
            ├─ Steps 10, 20, 30, …: one procedure each, each writing WRK table(s)
            ├─ Publish 60, 70, 80, …: one procedure per target table, ONE transaction
            ├─ Step 50 (TRS party-deactivation only): checkpoint-only, AFTER publish — §11.3
            └─ Step 999: job end (finish or fail)
```

- **Runner** (`<SRC>/runners/sp_etl_run_wf_*.sql`): application level. It owns
  the workflow order and nothing else: it never writes a target table itself
  and never drops a work table. It calls each mapping's driver in order,
  passing every original parameter explicitly (drivers append `P_JOB_RUN_ID`
  AFTER the original parameters, so a runner cannot call a mapping with only
  the run id). It returns the job run id plus a short status line; the full
  story lives in `JOB_CONTROL_ETL` (views in §3). The IDQ command task
  (`touch <workflow>.ind`) is left to the scheduler, exactly as before.
- **Driver** (`driver_sp_snow_main_*.sql`, one per mapping): the taskflow. It
  reads the config (§6), gates, cleans, calls steps, publishes, and closes the
  job. §4 gives its exact shape.
- **Step** (`steps/sp_snow_step_*.sql`): one procedure = one IICS mapping. It
  reads staging tables and/or earlier WRK tables and writes exactly one WRK
  table (152 of 153 steps; the exception is the checkpoint-only step 50).
- **Publish branch** (`publish/sp_snow_pub_*.sql`): one procedure = one IICS
  mapping. It reads exactly one WRK table and INSERTs into exactly one target
  table (137 of 137 branches; verified — one INSERT per branch, no exceptions).
  Publish branches contain NO checkpoint calls and NO transaction control: the
  driver wraps them all in one transaction (§11.2).

Counts for the whole tree: **7 workflows, 40 drivers, 153 steps, 137 publish
branches, 330 config seed rows, 152 WRK tables, 45 common helpers** (37 scalar
+ 8 table functions). Per-workflow build sequences with mapping orders and step
counts are in §10; the row-by-row chain is in `WORKFLOW-STEPS.md`.

---

## 3. Job control: JOB_CONTROL_ETL and the four framework procedures

One shared control table serves all six sources, distinguished by SOURCE:

- **Table** `JOB_CONTROL_ETL` (framework DDL `00_framework/01_job_control_ddl.sql`):
  append-only, one row per event, never updated, never truncated or deleted as
  part of a job run (prune only by an explicit dated housekeeping decision).
  Columns: `EVENT_ID` (identity, never reused), `JOB_RUN_ID`, `SOURCE`,
  `WORKFLOW_NAME`, `MAPPING_NAME`, `STATE` (STARTING / WORKING / TERMINATING),
  `STEP_NO` (0 = job begin, 999 = job end on begin/finish/fail rows; NULL on
  v2 checkpoint rows — see below), `STEP_NAME`, `STEP_STATUS` (STARTED /
  COMPLETED / FAILED / SKIPPED), `TARGET_TABLE`, `ROW_COUNT`,
  `SOURCE_ROW_COUNT`, `WORK_TABLE_NAME`, `WORK_TABLE_ACTION` (default `'NONE'`),
  `WORK_TABLE_PURPOSE`, `DROP_REASON`, `MESSAGE`, `ERROR_MESSAGE`, `EVENT_TS`,
  `CREATED_BY`.
- **Views** (same file): `VW_ETL_JOB_CURRENT` (latest row per run),
  `VW_ETL_JOB_STEPS` (latest row per STEP_NAME — **warning: do not reuse
  STEP_NAMEs within a mapping, or the view silently merges them**),
  `VW_ETL_RUNS_NEEDING_ATTENTION` (FAILED runs, or runs with no TERMINATING row,
  with a RECOMMENDED_ACTION), `VW_ETL_JOB_STORY` (whole run in order).
  `VW_ETL_OPEN_WORK_TABLES` was REMOVED in v2: it would always return empty and
  lie, because v2 checkpoint rows carry no work-table action. The replacement
  is a catalog query for tables named `WRK_%` (see §5.4).
- **v2 lossy simplification, by design:** `sp_etl_checkpoint` takes 10
  parameters (SOURCE, JOB_RUN_ID, WORKFLOW_NAME, MAPPING_NAME, STATE,
  STEP_NAME, STEP_STATUS, TARGET_TABLE, MESSAGE, ERROR_MESSAGE) and inserts
  NULL into STEP_NO, ROW_COUNT, SOURCE_ROW_COUNT, WORK_TABLE_NAME,
  WORK_TABLE_PURPOSE, and DROP_REASON. What survives, and where: step identity
  is by STEP_NAME; run ordering is by EVENT_ID; **per-step row counts survive
  only in each procedure's RETURN summary, not in this table**; work-table
  existence is answered from the catalog, not from this table. Columns for the
  dropped values are RETAINED, not dropped, so older rows keep their values.

The four framework procedures (`00_framework/02_job_control_procs.sql`) are the
ONLY procedures that write to `JOB_CONTROL_ETL`, and every call takes SOURCE
first:

| Procedure | Purpose | Returns (Snowflake) | Oracle form |
|---|---|---|---|
| `sp_etl_job_begin` | Generates a run id if NULL (`SOURCE_YYYYMMDD_HH24MISS_<guid>`), writes the STARTING row (STEP_NO 0) | run id string | PROCEDURE (see §13 deviation 1) |
| `sp_etl_checkpoint` | Writes one WORKING event row | `'CHECKPOINT_OK'` | PROCEDURE (see §13 deviation 1) |
| `sp_etl_job_finish` | Writes the TERMINATING/COMPLETED row (STEP_NO 999) | `'JOB_COMPLETED'` | PROCEDURE (see §13 deviation 1) |
| `sp_etl_job_fail` | Writes the TERMINATING/FAILED row (STEP_NO 999) | `'JOB_FAILED'` | PROCEDURE (see §13 deviation 1) |

All four contain a single INSERT and no transaction control. A checkpoint INSERT
autocommits and survives a later rollback — which is exactly why drivers must
never call a checkpoint between BEGIN TRANSACTION and COMMIT (§11.2).
**No caller in this tree captures any framework return value** (verified: zero
capturing call sites; the framework header itself says callers ignore them
except in ad-hoc use). That is why the Oracle form is a PROCEDURE, not a
FUNCTION — see the deviation note in §13.

---

## 4. The step pattern (read this before building any mapping)

### 4.1 One step = one procedure = one IICS mapping

A step procedure has this shape (Snowflake names; Oracle equivalents in §11.7):

```
sp_snow_step_<SRC>_<DIM>_<Snn>_<SLUG> (P_JOB_RUN_ID, P_RUN_TS, P_INPUT_TABLES DEFAULT '<WRK inputs, pipe-delimited>')
```

- **Parameters.** `P_JOB_RUN_ID` (the run, for checkpoints), `P_RUN_TS` (the
  run timestamp), `P_INPUT_TABLES` — a **dependency declaration plus a runtime
  check, NOT dynamic SQL**. It lists WORK-TABLE inputs only, pipe-delimited
  (e.g. `'WRK_TRS_PTY_S1_SRC'`). Snowflake cannot parameterize table names in
  static SQL, so the CTAS still names its sources literally; the parameter
  exists so the driver can pass the config's `WORK_TABLES_CONSUMED` and the
  step can verify its inputs exist before doing any work.
- **Input existence check.** If `P_INPUT_TABLES` is non-empty, the step builds
  the list of declared tables, probes the catalog for each, and if any is
  missing, executes a probe SELECT against the first missing table so the
  native object-not-exists error surfaces loudly. In Oracle the probe is
  `SELECT COUNT(*) FROM <missing>` (COUNT(*) form: it avoids a multi-row INTO
  failure while still raising ORA-00942 for the missing table — same surfacing
  behaviour, see §11.7). **A missing input is a hard failure, not a skip.**
  That is the no-validation rule in action (§6.3): the driver does not
  re-route around a missing table; the step fails plainly.
- **Body.** `CREATE OR REPLACE TRANSIENT TABLE <WRK> AS <verbatim step SELECT>`
  (in Oracle: DROP-if-exists + `EXECUTE IMMEDIATE 'CREATE TABLE <WRK> AS
  <select>'` — see §5.1), then `SELECT COUNT(*) INTO l_rows FROM <WRK>`,
  then a checkpoint, then `RETURN l_rows`. No exception block (errors
  propagate to the driver handler), no transactions, no target writes.
- **What a step never does.** It never writes a `C_S_*` / `EXC_*` / `DQM_*` /
  `STG_*` target, never calls another step, and never drops a table other
  than its own CTAS target (the step-5 drops belong to the driver).

### 4.2 One publish branch = one IICS mapping

```
sp_snow_pub_<SRC>_<DIM>_<TARGET> (original params…, P_JOB_RUN_ID, P_RUN_TS, P_INPUT_TABLES DEFAULT '<WRK table>')
```

- It reads ONLY its WRK table (the `P_INPUT_TABLES` default names it), uses
  the run timestamp and mapping code where the original used its locals, and
  executes the publish-branch INSERT verbatim: same columns, same values,
  same WHERE guard.
- It returns the row count. It contains NO transaction control and NO
  checkpoint calls — the driver owns both.

### 4.3 The driver, in order

Read one driver file end to end before building its mappings (example:
`TRS/drivers/driver_sp_snow_main_m_Tgt_C_S_TRS_Pty_OnGoing.sql`). Every driver
follows the same skeleton:

1. **Header** documents the business flow top-to-bottom. Read it; it is the
   mapping's design note.
2. **Config gather (unnumbered).** ONE SELECT with `MAX(CASE WHEN STEP_NO = n
   THEN IS_RUN_ENABLED / WORK_TABLES_CONSUMED END)` into `l_flag_*` /
   `l_in_*` variables, pre-initialized to defaults (`'Y'` / normal input) so
   a missing or unreadable config table leaves every step enabled with normal
   inputs. A nested BEGIN/EXCEPTION block re-asserts the defaults on
   exception. **Fallback is all-'Y', silently, by design** — a missing config
   row means "run it", not "skip it" (§6.2).
3. **Step 0 — driver-row gate.** If the config row `STEP_NO = 0,
   IS_RUN_ENABLED = 'N'` exists for this mapping, the WHOLE mapping is skipped
   BEFORE step-5 cleanup: the driver writes a MAPPING_SKIPPED checkpoint plus
   job_finish and returns a summary. Nothing is dropped, nothing runs.
4. **Step 5 — drop all work tables.** `DROP TABLE IF EXISTS <WRK>` for every
   WRK table this mapping's steps produce, regardless of flags. Verified:
   every driver's step-5 drop list equals exactly its steps' CTAS targets
   (40/40 mappings, zero mismatches). See §5.2 for why drops-all (not
   enabled-only) matters.
5. **Steps 10–40 (and further).** Each enabled step is called as
   `l_rows := step_proc(…, :l_job_run_id, :l_run_ts, :l_in_…)` under
   `IF (l_flag = 'Y')`; a disabled step gets a SKIPPED checkpoint plus a
   summary line instead. **A disabled step does NOT auto-skip its downstream
   steps**: a downstream step left enabled while its input step was skipped
   raises the missing table loudly, by design (§6.3).
6. **Publish 60–120.** `BEGIN TRANSACTION;` then all enabled branch calls,
   then `COMMIT;`, then one checkpoint per branch AFTER COMMIT (§11.2).
7. **Step 50 (TRS party-deactivation only).** After publish, a checkpoint-only
   step — see §11.3. It is NOT a mistake in this document; it is the
   preserved placement, flagged open.
8. **Step 999 — job end.** TERMINATING: `sp_etl_job_finish` on success.
   EXCEPTION: `ROLLBACK;` then a FAILED checkpoint, then `sp_etl_job_fail`,
   then `RAISE;` (re-raise, so the caller sees the original error).

**Driver signature rule:** driver = original main signature + appended
`P_JOB_RUN_ID VARCHAR DEFAULT NULL` (NULL = new run; the run id is generated
and returned in the summary). Restart = a new run, never a step-level restart.

### 4.4 Building the IICS mapping from a step

For each row of `WORKFLOW-STEPS.md`:

1. The **mapping source** is the step's CTAS SELECT: staging tables (prerequisites,
   §8) plus the WRK tables in its `P_INPUT_TABLES` default (the "work tables
   consumed" column). Build the SELECT as the mapping's transformation logic,
   in order.
2. The **mapping target** is the WRK table in the "work tables produced"
   column. The target has no pre-created DDL: in the stored-procedure form it
   is DROP + CTAS at runtime. In IICS, create the target table from the CTAS
   SELECT list (column names and order are the SELECT list; types are what
   the database infers when the CTAS runs — do not invent a different type
   list; if your IICS target needs explicit types, derive them by running the
   CTAS once on scratch and describing the result).
3. The **probe** becomes a pre-session check: verify every `P_INPUT_TABLES`
   entry exists before the mapping runs; fail the taskflow loudly if one is
   missing. Do not silently substitute an empty source.
4. The **checkpoint** becomes taskflow logging: write the step name, status,
   and row count to `JOB_CONTROL_ETL` (or your run log) after the mapping.
   Row counts live ONLY in these summaries (§3) — if you skip them, per-step
   counts are lost.
5. The **publish branch** becomes a mapping whose source is its WRK table and
   whose target is its INSERT target, with the branch's WHERE guard as the
   mapping filter. All publish mappings of one driver run inside ONE taskflow
   transaction (commit once, after the last branch — §11.2).

---

## 5. Work-table lifecycle

### 5.1 Runtime creation (the mechanism)

Work tables are **TRANSIENT in Snowflake, plain tables in Oracle** (Oracle has
no TRANSIENT keyword; the runtime DROP + CTAS gives the same lifecycle).
No work table has a CREATE definition anywhere in the source tree, and none is
invented here: `ddl/work_tables.sql` is a commented inventory (152 entries:
producing step, consuming units, dropping driver, CTAS file + line), not DDL.
The mechanism, translated:

- Snowflake step: `CREATE OR REPLACE TRANSIENT TABLE <WRK> AS <select>;`
- Oracle step: DROP-if-exists block (swallows only ORA-00942) followed by
  `EXECUTE IMMEDIATE 'CREATE TABLE <WRK> AS <select with :N binds>' USING
  <binds in first-appearance order>;` (152 step CTAS + 2 framework DDL
  wrappers = 154 CREATE EXECUTE IMMEDIATEs; 304 DROP blocks = 152 CTAS drops
  + 152 step-5 drops; 151 probe EXECUTE IMMEDIATEs — counts verified).
- The CTAS binds are the step's parameters and locals (`:P_RUN_TS`, `:l_run_ts`,
  `:c_mapping`, `:P_*`, `:l_*`) converted to positional `:N` binds in
  first-appearance order. The q-quote delimiter is chosen per file to avoid
  collision with `]'` in the text; single quotes inside are preserved,
  including `''` empty strings.

### 5.2 Step 5 drops ALL work tables, regardless of flags

This is the single most important lifecycle rule, and the easiest to get wrong
in IICS:

- Step 5 drops **every** WRK table the mapping's steps produce — not just the
  enabled steps' tables, not just the tables the current run will rebuild.
- Consequence, by design: **disabling a producer while a consumer stays
  enabled fails loudly on the missing input table.** That is not a bug to fix
  in the taskflow; it is the driver surfacing a configuration mistake plainly
  (§6.3). If you "helpfully" make step 5 drop only enabled steps' tables, you
  change the failure mode from loud to silent-stale-data: the consumer would
  read the previous run's WRK table as if it were fresh.
- The driver-row gate (step 0 = 'N') is the ONLY case where step 5 does not
  run — because the whole mapping is skipped before cleanup.

### 5.3 Publish transaction

Steps 60–120 (publish branches) run inside ONE transaction per driver: BEGIN,
all enabled branch calls, COMMIT, then one checkpoint per branch. Rules:

- No checkpoint call and no transaction control inside a publish branch.
- A branch failure rolls back ALL branches of that driver (not just the
  failed one) — the checkpoint rows written after COMMIT survive the rollback
  (they autocommit), which is why checkpoints come after COMMIT, never inside.
- Target INSERTs are insert-only with `uq_*` guards (see §11.5); there is no
  TRUNCATE or DELETE of targets anywhere in this tree.

### 5.4 Next-run rebuild, and survival for inspection

- Work tables are **NOT dropped at the end of a run**. They stay standing
  until the next run of the SAME mapping cleans them at its step 5. They
  survive a session crash for inspection — that is deliberate, and it is why
  the "open work tables" question is answered from the catalog
  (`TABLE_NAME LIKE 'WRK\_%'` in the current schema), not from
  `JOB_CONTROL_ETL`.
- A rerun is always a new `JOB_RUN_ID`, from scratch: step 5 drops, steps
  rebuild, publish re-inserts. There is no step-level resume (§9).
- **Stale-read hazard:** a WRK table left by a previous run is indistinguishable
  from a fresh one by name alone. Never let a downstream mapping read a WRK
  table unless the producing step ran in the same run — the taskflow order
  (§10) plus the probe (§4.1) are the guards, not the table name.

### 5.5 What is NOT a work table

- **Staging tables** (`STG_*`, `SN_*`, `_D_` delta, `_H_` history): pre-existing
  inputs, written by the separate staging codebase (delta detection lives
  OUTSIDE this ETL — see the constitution note in §8). Steps read them; only
  publish branches write a small set of them (§8.3).
- **Target tables** (`C_S_*`, `EXC_STG_BAD_REC_MEMB`, `DQM_ADDRESS`,
  `CRE_SRC_MRG`): publish-branch INSERT targets. They are not handoffs between
  steps (except the §8.3 staging outputs, which ARE read by later mappings).
- **Control tables** (`JOB_CONTROL_ETL`, `ETL_RUN_CONFIG_TBL`): framework, not
  data handoffs.

---

## 6. The config table ETL_RUN_CONFIG_TBL

### 6.1 Columns (all of them)

`00_framework/03_etl_run_config_ddl.sql`, in schema `COMMON` (see §7.2 for the
topology question). Primary key: (WORKFLOW_NAME, MAPPING_NAME, STEP_NO).

| Column | Type | Meaning |
|---|---|---|
| WORKFLOW_NAME | VARCHAR(200) NOT NULL | Workflow, e.g. `wf_TRS_Stage_Load_1_Ongoing` |
| MAPPING_NAME | VARCHAR(200) NOT NULL | Mapping, e.g. `m_Tgt_C_S_TRS_Pty_OnGoing` |
| STEP_NO | NUMBER(4) NOT NULL | **Extra column 1 — flagged, open (§12).** 0 = driver row; transform steps keep their numbers (10, 20, 30, …); publish branches take the current publish number, then +10 each |
| STEP_PROC_NAME | VARCHAR(200) NOT NULL | **Extra column 2 — flagged, open (§12).** Procedure implementing the unit |
| IS_DRIVER | VARCHAR(1) DEFAULT 'N' | 'Y' only on the STEP_NO = 0 row; that row gates the whole mapping |
| IS_RUN_ENABLED | VARCHAR(1) DEFAULT 'Y' | **THE toggle.** 'Y' runs; anything else skips (steps/branches). The driver row skips only on exact 'N' |
| IS_DEPENDENT | VARCHAR(1) | Informational: 'Y' iff DEPENDENT_ON is non-empty |
| DEPENDENT_ON | VARCHAR(200) | Informational: pipe-delimited producing STEP_NOs |
| WORK_TABLES_PRODUCED | VARCHAR(1000) | Pipe-delimited work tables this unit creates ('' for publish branches, by convention — the branch's INSERT target is not a work table) |
| WORK_TABLES_CONSUMED | VARCHAR(1000) | Pipe-delimited work tables this unit reads ('' for step 10); passed to each unit as P_INPUT_TABLES and runtime-checked |
| STEP_KIND | VARCHAR(30) | **Extra column 3 — flagged, open (§12).** DRIVER / TRANSFORM / SPINE / STATUS / EXCEPTION / VALIDATION. Informational only — the driver never gates on it |

Seed files (`<SRC>/seed_etl_run_config_<SRC>.sql`, translated verbatim):
CRE 24, ECI 67, FSS 50, TRS 119, TTF 29, WIC 41 = **330 rows**, all
IS_RUN_ENABLED = 'Y'. Each seed DELETEs only its own source's workflow rows
first, so re-running a seed is safe. Run seeds in the COMMON schema.

### 6.2 Config gather and its fallbacks

- The driver gathers flags with ONE SELECT (`MAX(CASE WHEN STEP_NO = n …)`),
  pre-initialized to all-'Y' with normal inputs. **If the config table is
  missing, unreadable, or a row is absent, the driver runs everything with
  normal inputs.** That fallback is deliberate (a missing row must not
  silently disable a step), but it means a typo'd WORKFLOW_NAME/MAPPING_NAME
  in a seed runs the mapping unconfigured rather than failing — verify seed
  rows against `WORKFLOW-STEPS.md` after install.
- The driver-row gate is exact: only `IS_RUN_ENABLED = 'N'` on STEP_NO = 0
  skips the mapping. Any other value (including NULL, 'y', '') runs it.
- Step/branch gating is looser: only exact `'Y'` runs; anything else skips.
  Note the asymmetry — it is in the source, preserved here.

### 6.3 The no-validation rule (verbatim)

> **The driver must NOT validate flags or dependencies: the user toggles
> is_run_enabled only and owns dependency correctness — the driver surfaces a
> missing table plainly, never silently enforces or fixes flags.**

What this means in practice, for the IICS build:

- Do NOT add a taskflow validation that refuses to run when a consumer is
  enabled but its producer is disabled. The correct behaviour is the probe
  failure (§4.1): the consumer mapping fails loudly on the missing WRK table.
- Do NOT auto-enable producers, auto-skip consumers, or re-order steps to
  "fix" a flag combination. The flag combination is the operator's
  responsibility; the taskflow's responsibility is to fail plainly.
- Do NOT treat `IS_DEPENDENT` / `DEPENDENT_ON` as gating inputs. They are
  informational documentation of the intended dependency; the driver never
  reads them for control flow.
- The ONE thing the driver does enforce is the step-0 gate (whole-mapping
  skip) and the step-5 drop-all (§5.2). Both are preserved exactly.

---

## 7. Install order

Install in this order. Steps 1–4 are framework (once); steps 5–7 repeat per
source schema; step 8 is the scheduler entry point.

1. **Schemas.** Create the COMMON schema and one schema per source
   (`TRS_ETL_WRK`, `ECI_ETL_WRK`, `FSS_ETL_WRK`, `WIC_ETL_WRK`, `TTF_ETL_WRK`,
   `CRE_ETL_WRK` — the same names as the Snowflake install convention), plus
   schema `RDM` (DBA pre-action, §8.1). The install convention matters because
   drivers call helpers and job procedures UNQUALIFIED: whatever schema a
   driver is installed in must contain (or resolve) those objects.
2. **`ddl/00_reference_placeholders.sql`.** The 7 reference tables (empty).
   Replace with real definitions before any real run (§8.1).
3. **`00_framework/01_job_control_ddl.sql`** (in COMMON). Table + views.
   `CREATE TABLE IF NOT EXISTS` becomes an EXECUTE IMMEDIATE wrapper that
   swallows only ORA-00955; identity column via `GENERATED BY DEFAULT AS
   IDENTITY (START WITH 1 INCREMENT BY 1)`.
4. **`00_framework/03_etl_run_config_ddl.sql`** (in COMMON) + the six seed
   files (in COMMON). Verify 330 rows after seeding.
5. **`00_framework/common/00_common_types.sql`** — schema-level OBJECT and
   nested-table types (11 OBJECT types for the 37 scalar helpers' OBJECT
   returns + 8 row types + 8 table types for the 8 lookup functions).
   **Deviation forced by Oracle: OBJECT types cannot be declared inside a
   package spec**, so they live at schema level even though the helpers are
   per-schema functions. Install this file before the helpers in each schema.
6. **`00_framework/common/01_snow_common_functions.sql` +
   `02_snow_common_lookups.sql`** (in EACH source schema — see §7.2).
   37 scalar functions + 8 table functions. The table functions return
   nested-table types and use `SELECT … BULK COLLECT INTO l_tab …; RETURN
   l_tab;` (BULK COLLECT inserted before the first top-level FROM;
   QUALIFY-wrapped bodies handled).
7. **Per-source drivers, steps, publish, runners** (in that source's schema),
   then the **run scripts** (`<SRC>/runners/run_wf_*.sql` → `SELECT
   <runner>() FROM DUAL;` + `WHENEVER SQLERROR EXIT FAILURE`; the SnowSQL
   `!set` lines are dropped — they are client commands, not SQL).
8. **Verify:** zero INVALID objects in each schema (recompile dependents after
   the reference tables are replaced with real definitions — bodies compiled
   against empty placeholders stay valid, but a placeholder-to-real swap that
   changes a column type needs a recompile pass).

### 7.1 What the installer must NOT do

- Do not create WRK tables at install time. They are runtime CTAS outputs
  (§5.1); pre-creating them is pointless (steps DROP + recreate) and a
  pre-created column list that disagrees with the CTAS SELECT would mask a
  real error.
- Do not create the staging inputs, the `C_S_*` targets, or the hub tables.
  They are prerequisites (§8), not part of this tree.
- Do not put DROP statements in install DDL. (Procedure bodies DO rebuild
  their own WRK scratch tables at run time with DROP + CTAS inside the proc —
  that is runtime behaviour, documented in §5.1, not install DDL. The
  distinction is the same one the multiple-SP layout documents.)

### 7.2 Open: job-control topology (carried, not resolved)

The source is ambiguous, and this translation adapts it without settling it:

- The framework header says "one shared table in MDM_ETL_COMMON.COMMON",
  and drivers qualify the config table as `COMMON.ETL_RUN_CONFIG_TBL`.
- But drivers call the job procedures and the common helpers UNQUALIFIED,
  which only resolves if those objects live in the driver's own schema.
- **Adaptation applied here:** framework DDL (JOB_CONTROL_ETL, views,
  ETL_RUN_CONFIG_TBL) is installed once in COMMON; the 4 framework procedures
  and the common helpers are repeated into each source schema (matching the
  estate's established per-schema install convention); the framework
  procedures qualify their table reference as `COMMON.JOB_CONTROL_ETL`, so
  the "one shared table" statement stays true regardless of install schema.
- **Alternative, not chosen:** synonyms in each source schema pointing at
  COMMON objects. If the DBA prefers synonyms, the per-schema copies of the
  framework procedures and helpers are unnecessary — but the driver code does
  not change either way. **Confirm the topology with the DBA before install;
  do not present this adaptation as settled.**

---

## 8. Prerequisites (nothing here is created by this tree)

### 8.1 The 7 reference objects (blocking)

The 8 lookup helpers (40–47) read these. `ddl/00_reference_placeholders.sql`
gives empty minimal shapes derived from the helpers' own SELECT lists; the
real definitions must come from the source system. **No real ETL run until
these have real data** — with empty placeholders, every lookup join returns
no rows and enrichments silently come back NULL.

| Object | Read by | If missing | If empty |
|---|---|---|---|
| EXC_LOOKUP_CODE_VALUE | helper40 | helper40 fails to compile; every EXC branch fails | Exception descriptions NULL |
| V_LOOKUP_CODE_VALUE | helpers 41, 42 | helpers 41/42 fail to compile | Every translated code NULL |
| REF_JUNK_NAME_LIST | helper43 | helper43 fails to compile | No name classified junk |
| RDM.REF_PHN_AREA_CD | helper44 | helper44 fails to compile; **RDM schema itself is a DBA pre-action (ORA-01918 if absent)** | No area code resolves |
| LOOKUP_CODE_VALUE | helper45 | helper45 fails to compile | Phone-usage / alt-id-type labels NULL |
| REF_MATCHCODE_DESC | helper46 | helper46 fails to compile | Match-code descriptions NULL |
| REF_DYLGHT_SVNGS_TM | helper47 | helper47 fails to compile | DST corrections never match |

`V_LOOKUP_CODE_VALUE` is a TABLE in the placeholder file (following the earlier
mirrors' pattern); in Oracle it is a VIEW, so replacing it later needs DROP
TABLE then CREATE VIEW.

### 8.2 Helpers inventory (translated, included)

- **37 scalar functions** (`01_snow_common_functions.sql`): helpers 01–37 (no
  38/39). Returns: 1 BOOLEAN→NUMBER(1) (helper03, already a CASE 1/0/NULL —
  no wrap needed), 1 NUMBER(1) (helper01), 1 NUMBER(38,10) (helper04),
  11 OBJECT (helpers 14, 15, 17, 19, 22, 25, 26, 27, 28, 34, 37 — returned as
  schema-level types `T_OBJ_<FUNC>`, all VARCHAR2(4000) attributes except
  helper34's `geocoding_latitude` / `geocoding_longitude`, which are NUMBER —
  the only attributes callers cast `::NUMBER`), 2 TIMESTAMP (helpers 21, 35),
  21 VARCHAR. Pure SQL UDFs, no table access. Lookup mapplets are split in
  two by design: the lookup itself is a LEFT JOIN to a 02 table function in
  the calling procedure, and the looked-up value is passed as an argument.
  No Java UDF. Helper30 takes a BOOLEAN parameter (→ NUMBER(1) in Oracle).
- **8 table functions** (`02_snow_common_lookups.sql`): helpers 40–47 (see
  §8.1 for their tables). Callers read OBJECT-typed results as
  `obj.attribute` in Oracle SQL — see the live-compile risk in §11.7.
- **Object-access note:** the Snowflake `:field` colon access
  (`obj:attribute::type`) becomes Oracle dot access (`obj.attribute`) with
  CAST. The `func().attribute` form in SQL (a function call followed by
  `.attribute`) is the biggest known live-compile risk (§13) — it is kept as
  dot notation, with scalar-subquery/CTE wrapping as the fallback if Oracle
  rejects it.

### 8.3 Staging inputs and staging outputs

**Written by publish branches (so they must exist before the workflow runs,
and later mappings read them):** 15 STG tables — `STG_TRS_VALID_MEMBERS`
(TRS PTY publish; read by 13 TRS loaders — the TRS valid-member hub),
`STG_TRS_D_UNQ_ADDR` (TRS ADDR1; read by ADDR1 + ADDR2),
`STG_TRS_DEACTIVED_MEMBERS` (TRS PTYDEACT; note the DB spelling DEACTIVED),
`STG_TRS_DEACTIVATED_RELATIONSHIPS` (TRS RELDEACT),
`STG_ECI_D_MEDICAID`, `STG_ECI_D_FAMILY_PHONE`, `STG_ECI_D_FAMILY_ADDRESS`
(ECI reactivation publishes; read by the reactivation loaders and by ALT),
and the eight `STG_<SRC>_PTY_INACTIVE_STS` / `STG_<SRC>_PTY_INACTIVE_LOG`
tables (written by each source's VAL loader; STS is read by `val_exc` and by
the source's ongoing loaders; LOG is read by nothing in this tree — a
write-only audit log).

**Read by steps, written outside this tree (the staging codebase owns them):**
46 tables, including the `_D_` delta tables (e.g. `STG_TRS_D_DC_INDV`,
`STG_TRS_D_DC_ALIAS`, `STG_TRS_D_UNQ_ADDR`, `STG_ECI_D_CHILD`,
`STG_ECI_D_FAMILY`), the `_H_` history tables (ECI reactivation reads
`STG_ECI_H_FAMILY_ADDRESS` / `PHONE` / `MEDICAID`; TRS ALT reads
`STG_TRS_H_DC_INDV` for the validated-SSN reference), the `SN_` tables
(`STG_CRE_SN_CARE_CLIENTS`, `STG_ECI_SN_CASE`, `STG_ECI_SN_CHILD`), and
`STG_UPDATE_DATE`. **Delta detection lives outside this ETL** in a separate
staging codebase (raw sources → `_D_` stage tables, all delta); this ETL does
not do delta detection. `_H_` tables are Type 2 history: the ETL only reads
them, never writes them.

**Target tables (publish INSERT targets, must exist):** 42 `C_S_*` tables
(the plain v1-era shapes — NOT the v3 shapes with flag/DIAG columns; this
tree predates those columns, and adding them would break the INSERT column
lists), plus `EXC_STG_BAD_REC_MEMB`, `DQM_ADDRESS`, and `CRE_SRC_MRG`.
60 distinct publish targets across 137 branches (several branches share a
target: EXC branches share `EXC_STG_BAD_REC_MEMB`, DQM branches share
`DQM_ADDRESS`).

**Not in this tree, needed by consumers downstream:** the MDM hub tables and
any hub-state views the batch reads; the scheduler's `.ind` file handling;
and the IDQ-side source connections. None of these are created here.

---

## 9. Recovery rules

There is **no step-level resume** in this design. Every recovery is a rerun,
and the rerun rules below are the whole recovery story:

1. **Restart = run the run script again.** A new `JOB_RUN_ID` is generated.
   There is no resume call and no "continue from step N" entry point. The
   runner and drivers take no step-number argument.
2. **Step 5 makes reruns safe for work tables, not for targets.** A rerun
   drops every WRK table of each mapping at its step 5 and rebuilds them.
   Target INSERTs are insert-only with `uq_*` guards (§11.5): re-running a
   mapping re-INSERTs its target rows unless the guard blocks them. Do NOT
   assume a rerun is idempotent for targets — check the guard per branch
   before re-running a mapping whose publish already committed.
3. **Re-running a single step** (ad-hoc, not via the driver): the step DROPs
   and CTAS-rebuilds its WRK table. That is safe for the WRK table itself,
   but every downstream unit that already consumed the old WRK table now
   holds stale results — re-run the downstream chain too, or re-run the whole
   mapping. Never re-run a step and call the mapping done.
4. **Partial rerun + step-5 drop.** If a run failed halfway (some mappings
   published, some not), re-running the workflow re-runs EVERY mapping from
   scratch, including the ones that already published. Combined with rule 2,
   that means: a partial rerun re-INSERTs already-published target rows
   unless guards block them. **Decide the target cleanup (if any) before
   re-running, not after** — this tree provides no target cleanup step.
5. **Publish-transaction failure.** A branch failure rolls back ALL branches
   of that driver (§5.3). The mapping's targets are untouched by that driver;
   its WRK tables stand as built. Re-run the mapping (rule 1); step 5 drops
   and rebuilds the WRK tables first.
6. **DQM append caveat (carried from the estate's DQM-RERUN decision).**
   `DQM_ADDRESS` is written by the 4 address-DQM publish branches with NO
   guard: every run appends. Re-running an address mapping duplicates its DQM
   rows. The estate's standing decision is that this is a known limitation
   with NO code fix — do not add a guard here without a new decision.
   (EXC branches, by contrast, carry NOT EXISTS guards on
   (SRC_SYS_ID_1, EXCEPTION_CODE, ATTRIBUTE_NAME, ATTRIBUTE_VALUE), so
   re-runs write zero duplicate EXC rows.)
7. **Checkpoint-only step 50 (TRS party-deactivation).** It writes no table
   and its "success" is only a checkpoint row. Re-running it is a no-op for
   data; it matters only for the run story in `JOB_CONTROL_ETL`.
8. **Driver-row skip ('N' on step 0) is not a failure.** A skipped mapping
   writes MAPPING_SKIPPED + job_finish and returns normally. The runner
   continues to the next mapping. Do not alert on a skipped mapping unless
   the skip itself was unintended — check the config row first.

---

## 10. Per-workflow build sequences

Build in runner order (the order the runner calls the drivers). Within a
mapping, build steps in step-number order, then publish branches in
step-number order. The "IICS mappings" column counts step mappings + publish
mappings (the driver row is taskflow control, not a mapping).

### 10.1 wf_TRS_Stage_Load_1_Ongoing (14 mappings; 64 steps + 37 publish = 101 mappings)

| # | Mapping | Steps | Publish (kinds) | IICS mappings |
|---|---|---|---|---|
| 1 | m_Tgt_C_S_TRS_Pty_OnGoing | 4 | 9 (6 EXCEPTION, 3 SPINE) | 13 |
| 2 | m_Tgt_C_S_TRS_Pty_Deactivation_1 | 4 | 1 (STATUS) | 5 |
| 3 | m_Tgt_C_S_TRS_Pty_Rle_TOA | 4 | 3 (2 EXCEPTION, 1 SPINE) | 7 |
| 4 | m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | 6 | 5 (4 EXCEPTION, 1 SPINE) | 11 |
| 5 | m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 | 5 | 1 (STATUS) | 6 |
| 6 | m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | 6 | 3 (2 EXCEPTION, 1 SPINE) | 9 |
| 7 | m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | 7 | 4 (2 SPINE, 2 EXCEPTION) | 11 |
| 8 | m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw | 4 | 1 (SPINE) | 5 |
| 9 | m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing | 4 | 1 (SPINE) | 5 |
| 10 | m_Tgt_C_S_TRS_Pty_Nm | 4 | 1 (SPINE) | 5 |
| 11 | m_Tgt_C_S_TRS_Pty_Rle_Alt_Id | 4 | 2 (1 SPINE, 1 EXCEPTION) | 6 |
| 12 | m_Tgt_C_S_TRS_Pty_Rle_Pln | 3 | 2 (1 SPINE, 1 EXCEPTION) | 5 |
| 13 | m_Tgt_C_S_TRS_Addr_1 | 4 | 1 (STATUS) | 5 |
| 14 | m_Tgt_C_S_TRS_Addr_2 | 5 | 3 (1 VALIDATION, 1 SPINE, 1 EXCEPTION) | 8 |

Notes: mapping 2's step 50 runs AFTER its publish transaction (§11.3).
Mapping 13 writes `STG_TRS_D_UNQ_ADDR`, which mapping 14 reads — that is why
Addr_1 precedes Addr_2. Mapping 1 writes `STG_TRS_VALID_MEMBERS`, read by 13
later TRS loaders. Run script: `TRS/runners/run_wf_TRS_Stage_Load_1_Ongoing.sql`.

### 10.2 wf_TRS_Stage_Load_TOA (1 mapping; 2 steps + 1 publish = 3 mappings)

| # | Mapping | Steps | Publish (kinds) | IICS mappings |
|---|---|---|---|---|
| 1 | m_Tgt_C_S_TRS_Stg_TOA | 2 | 1 (STATUS) | 3 |

Its publish writes `C_S_LU_TOA` with a literal VERSION_SEQ of '1' (preserved
quirk — the TOA lookup load never computed a version).

### 10.3 wf_ECI_Stage_Load (9 mappings; 32 steps + 26 publish = 58 mappings)

| # | Mapping | Steps | Publish (kinds) | IICS mappings |
|---|---|---|---|---|
| 1 | m_Tgt_C_S_ECI_Pty_Validation | 3 | 4 (1 EXCEPTION, 3 STATUS) | 7 |
| 2 | m_Tgt_C_S_ECI_Pty | 5 | 7 (2 SPINE, 5 EXCEPTION) | 12 |
| 3 | m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr | 2 | 1 (STATUS) | 3 |
| 4 | m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn | 2 | 1 (STATUS) | 3 |
| 5 | m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid | 2 | 1 (STATUS) | 3 |
| 6 | m_Tgt_C_S_ECI_Pty_Rle_Alt_Id | 4 | 3 (1 SPINE, 2 EXCEPTION) | 7 |
| 7 | m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr | 5 | 4 (2 SPINE, 2 EXCEPTION) | 9 |
| 8 | m_Tgt_C_S_ECI_Pty_Addr | 5 | 3 (1 VALIDATION, 1 SPINE, 1 EXCEPTION) | 8 |
| 9 | m_Tgt_C_S_ECI_Pty_Rle_Rel | 4 | 2 (1 SPINE, 1 EXCEPTION) | 6 |

**Order verified from the runner file itself** (not from the STEP_MAP note,
which lists a different order — see §12). The runner order is: Validation →
Pty → Reactivation Family_Addr → Family_Phn → Medicaid → Alt_Id →
Phn_And_EAddr → Addr → Rel. The dependency reason, per the runner header:
Validation first because it maintains INACTIVE_STS/LOG, Pty next, then the
three reactivations refill delta tables that Alt_Id/Phn/Addr/Rel then read.
ECI drivers are the v2.1 original template: they use BOOLEAN local variables
(`l_pub_*_skipped`, `l_config_ok`) where other sources use VARCHAR flags —
the Oracle translation converts them per file (§11.7).

### 10.4 wf_FSS_Stage_Load (6 mappings; 21 steps + 23 publish = 44 mappings)

| # | Mapping | Steps | Publish (kinds) | IICS mappings |
|---|---|---|---|---|
| 1 | m_Tgt_C_S_FSS_Pty_Validation | 3 | 4 (1 EXCEPTION, 3 STATUS) | 7 |
| 2 | m_Tgt_C_S_FSS_Pty | 4 | 8 (2 SPINE, 6 EXCEPTION) | 12 |
| 3 | m_Tgt_C_S_FSS_Pty_Addr | 4 | 3 (1 VALIDATION, 1 SPINE, 1 EXCEPTION) | 7 |
| 4 | m_Tgt_C_S_FSS_Pty_Rle_Alt_Id | 2 | 1 (SPINE) | 3 |
| 5 | m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr | 4 | 5 (2 SPINE, 3 EXCEPTION) | 9 |
| 6 | m_Tgt_C_S_FSS_Pty_Rle_Rel | 4 | 2 (1 SPINE, 1 EXCEPTION) | 6 |

### 10.5 wf_WIC_Stage_Load (5 mappings; 17 steps + 19 publish = 36 mappings)

| # | Mapping | Steps | Publish (kinds) | IICS mappings |
|---|---|---|---|---|
| 1 | m_Tgt_C_S_WIC_Pty_Validation | 3 | 4 (1 EXCEPTION, 3 STATUS) | 7 |
| 2 | m_Tgt_C_S_WIC_Pty | 4 | 7 (2 SPINE, 5 EXCEPTION) | 11 |
| 3 | m_Tgt_C_S_WIC_Pty_Addr | 4 | 3 (1 VALIDATION, 1 SPINE, 1 EXCEPTION) | 7 |
| 4 | m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr | 4 | 4 (2 SPINE, 2 EXCEPTION) | 8 |
| 5 | m_Tgt_C_S_WIC_Pty_Rle_Alt_Id | 2 | 1 (SPINE) | 3 |

### 10.6 wf_TTF_Stage_Load (4 mappings; 12 steps + 13 publish = 25 mappings)

| # | Mapping | Steps | Publish (kinds) | IICS mappings |
|---|---|---|---|---|
| 1 | m_Tgt_C_S_TTF_Pty_Validation | 3 | 4 (1 EXCEPTION, 3 STATUS) | 7 |
| 2 | m_Tgt_C_S_TTF_Pty | 4 | 6 (2 SPINE, 4 EXCEPTION) | 10 |
| 3 | m_Tgt_C_S_TTF_Pty_Rle_Alt_Id | 2 | 1 (SPINE) | 3 |
| 4 | m_Tgt_C_S_TTF_Pty_Rle_Phn | 3 | 2 (1 SPINE, 1 EXCEPTION) | 5 |

TTF has no Address driver, no Email-separate driver, no Relationship driver,
and no DQM — do not build them for TTF.

### 10.7 wf_CRE_Stage_Load_Ongoing (1 mapping; 5 steps + 18 publish = 23 mappings)

| # | Mapping | Steps | Publish (kinds) | IICS mappings |
|---|---|---|---|---|
| 1 | m_Tgt_C_S_CRE_CARE_Clients | 5 | 18 (1 STATUS, 10 EXCEPTION, 7 SPINE) | 23 |

CRE is a single wide mapping: 5 steps build one keyed WRK table (197 columns),
and 18 publish branches fan out from it (including `CRE_SRC_MRG` and 10 EXC
branches). The run timestamp is set once by the first step and reused
downstream — do not re-derive it per branch.

**Total IICS mappings to build: 101 + 3 + 58 + 44 + 36 + 25 + 23 = 290**
(153 steps + 137 publish branches; the 40 driver rows are taskflow control,
not mappings. Cross-check: 153 steps = 152 WRK-producing steps + 1
checkpoint-only step; per-workflow WRK counts are TRS Ongoing 63, TOA 2,
ECI 32, FSS 21, WIC 17, TTF 12, CRE 5 = 152. All counts reconcile with
`WORKFLOW-STEPS.md`, which is the row-level authority at 330 rows.)


---

## 11. Gotchas (read before you build, not after you fail)

### 11.1 Dispatch is STATIC, not dynamic (correction to the original brief)

The task brief for this translation assumed the drivers might call steps
dynamically and said Oracle `EXECUTE IMMEDIATE 'BEGIN proc; END;'` would be
the faithful equivalent. **That assumption was wrong, and the TDD corrects it:
driver dispatch in this tree is static.** Every driver calls its steps and
publish branches with plain `IF (flag = 'Y')` gates around direct calls
(Snowflake: `l_rows := (CALL proc(…))`; Oracle: `l_rows := proc(…)`).
There is no dynamic dispatch to translate and no `EXECUTE IMMEDIATE` dispatch
mechanism to document — the only code `EXECUTE IMMEDIATE`s in the Oracle tree
are the step probes (151), the runtime CTAS/DROP DDL (154 CREATE + 304 DROP
blocks), and the framework DDL wrappers (2). If you see a design doc that
describes dynamic dispatch for this tree, it is describing a different tree.
In IICS, static dispatch means: the taskflow has one branch per step with a
simple enabled-flag condition — no dynamic mapping invocation, no
parameter-driven mapping names.

### 11.2 Transaction boundaries (the rules that break silently if violated)

- **Never call a checkpoint between BEGIN TRANSACTION and COMMIT.** The
  checkpoint INSERT autocommits; a later rollback would leave a COMPLETED
  checkpoint for branches whose INSERTs were rolled back. Drivers checkpoint
  publish branches only AFTER COMMIT. In IICS: log branch completion after
  the transaction commits, never inside it.
- **Never put transaction control inside a publish branch.** Branches contain
  no COMMIT/ROLLBACK by construction; the driver owns the transaction.
- **A branch failure rolls back all branches of that driver.** Not just the
  failed branch. Plan reruns accordingly (§9 rule 5).
- **Steps have no transactions.** A step's CTAS is its own statement; a
  step failure leaves earlier steps' WRK tables standing (which is why step 5
  drops everything on the next run).
- **Framework procedures have no transaction control** and their INSERTs
  autocommit — including `sp_etl_job_fail`'s row, which must survive the
  driver's ROLLBACK to record the failure.

### 11.3 TRS party-deactivation step 50 runs AFTER publish (open, not fixed)

`sp_snow_step_TRS_PTYDEACT_S50_NOTPERFORMED` is called at driver lines
228–229, AFTER the publish transaction (lines 210–214) and the publish
checkpoints (from line 216). It writes no table — it is a checkpoint-only
step. Its step number (50) sorts after the publish branch (40) in the seeds,
so the matrix order matches the execution order, but the placement itself —
a transform step number running after publish — is unusual and was flagged
in the v2.1 step-driver delivery as needing user confirmation. **Preserved
exactly as-is. Do NOT "fix" it by moving it before publish** — that would
change the run story and possibly the semantics (the step's name says
NOTPERFORMED: it records that a deactivation was not performed). See §12.

### 11.4 Drops-all vs enabled-only (the silent-stale-data trap)

Covered in §5.2 because it deserves repetition: step 5 drops ALL WRK tables
of the mapping, not just enabled steps' tables. An IICS taskflow that drops
only the tables its enabled mappings will rebuild introduces silent stale
reads: a consumer left enabled while its producer is disabled would read the
previous run's WRK table and succeed with old data instead of failing loudly
on the missing table. Keep drops-all.

### 11.5 Publish granularity: one branch = one target = one INSERT

Verified: 137 publish branches, 137 INSERTs, exactly one per branch. So
disabling one publish branch disables exactly one target table's load — but
the publish transaction is all-or-nothing across the driver's enabled
branches. Two consequences:

- **Per-INSERT vs per-branch is not a choice here** — they coincide. If a
  future change splits a branch into two INSERTs, the transaction and the
  flag semantics must be re-examined, because a branch flag would then gate
  two targets at once.
- **Insert-only with `uq_*` guards.** Target INSERTs never TRUNCATE or
  DELETE. Publish SELECTs filter on `uq_*` flags (e.g. `WHERE rn_pty = 1 AND
  uq_pty`) that mark the dedup winner. Re-running a mapping re-INSERTs rows
  the guard passes — check the guard before assuming rerun safety (§9 rule 2).
- **Parity notes preserved deliberately:** insert-only (not truncate);
  party deactivation does not delete from the valid-member spine; Auth_Rep
  does not delete its own attribute type; the stored source filter
  (`INDV_ID = 504937068`, present in the IDQ originals) is NOT applied,
  exactly as in the Snowflake code; VERSION_SEQ is hard-coded to 1;
  PERIOD_END_DATE / PERIOD_REFERENCE_TIME / TIMELINE_ACTION are NULL.
  None of these are Oracle-translation choices — they are the source
  tree's behaviour, carried over.

### 11.6 IS_DRIVER gating (step 0) vs step gating

- Step 0 = 'N' skips the WHOLE mapping before step-5 cleanup (nothing is
  dropped). Any other step's 'N' skips only that unit, and step 5 still drops
  everything. Confusing the two — e.g. treating a step-0 'N' as "skip the
  driver but still clean" — deletes the previous run's WRK tables for a
  mapping that did not run, which is the opposite of the intended
  skip-without-side-effects.
- The driver-row gate is exact-'N'; step/branch gating is exact-'Y'. The
  asymmetry is in the source (see §6.2). Do not "normalize" it.

### 11.7 Oracle translation notes (what changed form, what to watch live)

Faithful translation rules, same as the earlier v1 Oracle mirror: same
names/params/columns/predicates/order/quirks; procedures with RETURNS become
Oracle FUNCTIONS with `AUTHID CURRENT_USER` (except the framework procedures
— §13 deviation 1); booleans become NUMBER(1) with NULL-preserving CASE;
bare VARCHAR becomes VARCHAR2 (params/returns) or VARCHAR2(4000)
(columns/vars/casts); `::` becomes CAST; IFF becomes CASE; DATEADD becomes
date arithmetic (year ×12, quarter ×3, week ×7, hour /24, minute /1440,
second /86400); QUALIFY becomes a subquery wrap (`ROW_NUMBER() … AS
__qual_rn`, filtered to 1 — no `__qual_rn` collisions in this tree);
TIMESTAMP_NTZ becomes TIMESTAMP; TRY_TO_* becomes `TO_*(x DEFAULT NULL ON
CONVERSION ERROR)`; TO_VARCHAR becomes TO_CHAR; CURRENT_TIMESTAMP() becomes
SYSTIMESTAMP; CURRENT_USER() becomes USER; CURRENT_SCHEMA() becomes
`SYS_CONTEXT('USERENV','CURRENT_SCHEMA')`; UUID_STRING() becomes
RAWTOHEX(SYS_GUID()) (**format differs from UUID_STRING — it is an
identifier only, never parsed**); SPLIT_PART becomes REGEXP_SUBSTR with a
regex-escaped delimiter; BOOLOR_AGG becomes `MAX(CASE WHEN … THEN 1 ELSE 0
END)`; `RETURN SQLROWCOUNT;` becomes `RETURN SQL%ROWCOUNT;`;
`BEGIN TRANSACTION;` is removed (comment noting Oracle implicit
transactions); `RAISE EXCEPTION 'msg' || expr;` becomes
RAISE_APPLICATION_ERROR(-20001, …); `RAISE;` is kept.

Watch list for the first live compile (all inherited from the translation
approach, none proven yet):

- **Boolean columns from upstream WRK tables.** Step CTAS SELECTs compute
  `uq_*` / `grp_*` / `is_*` / `has_*` flags as boolean expressions; publish
  procs filter on them bare (`WHERE rn_pty = 1 AND uq_pty`). Oracle SQL has
  no boolean, so the translation converts SELECT-list boolean expressions to
  `CASE WHEN <expr> THEN 1 ELSE 0 END` and bare predicate uses to `= 1`
  (or `= 0` after NOT), using a mechanically derived token set (~200 names:
  CTAS boolean aliases plus dotted predicate-position columns) plus per-file
  BOOLEAN DECLARE variables/parameters (ECI drivers use BOOLEAN locals;
  other sources use VARCHAR flags — handling is per file). **Residual risk:**
  a boolean column NOT in the derived set, used bare in a predicate, would
  remain unconverted and fail at live compile. The parent cross-check must
  grep for remaining bare-boolean predicates before the push; the live
  compile is the final proof.
- **helper03 NULL semantics diverge.** Snowflake helper03(NULL) = NULL;
  the Oracle CASE version returns 0 for NULL input. Equivalent under `= 1`
  tests and IFF conditions (the only uses found), divergent only if a
  helper03-derived COLUMN is tested under NOT. No such use was found, but
  it is a semantic note, not a proof.
- **Probe form changed** (Snowflake `SELECT 1 FROM <missing>` → Oracle
  `SELECT COUNT(*) FROM <missing>`): same surfacing (ORA-00942 on the
  missing table), no multi-row INTO failure. Six probe shapes exist in the
  source (STD, VAR, and four MIN/MAX/TRIM variants over FLATTEN /
  SPLIT_TO_TABLE); all 151 were converted, per-file counts match exactly.
- **CTAS binds are positional.** Snowflake `:bind` names become `:N` in
  first-appearance order inside the EXECUTE IMMEDIATE string. If you edit a
  CTAS SELECT, re-derive the USING list — a bind-order mistake silently
  binds the wrong value (types usually catch it, but same-typed binds do not).
- **VARCHAR2(4000) assumption.** Bare VARCHAR becomes VARCHAR2(4000) for
  columns/variables/casts. If a real value exceeds 4000 characters, the
  CTAS or INSERT fails at runtime, not at compile. The assumption is
  documented, not proven.
- **`''` vs NULL gaps.** Oracle treats `''` as NULL. Snowflake does not.
  Preserved `''` literals (including in CTAS strings and NVL defaults)
  behave as NULL in Oracle. Any predicate that distinguishes `''` from NULL
  in Snowflake collapses in Oracle — a parity item for the first live run,
  not a compile item.
- **`func().attribute` in SQL.** OBJECT-typed helper results are read as
  `obj.attribute` in Oracle SQL. If Oracle rejects the `function().attribute`
  form in a SELECT list, wrap it in a scalar subquery or CTE. This is the
  biggest known live-compile risk, carried from the earlier mirrors.
- **Table-function form.** The 8 lookup functions return nested-table types
  with BULK COLLECT. The PIPELINED + AUTHID clause order and the row-OBJECT
  + nested-table consumption in callers (`TABLE(fn_…())`) are unproven until
  a live compile.
- **ECI BOOLEAN locals.** ECI is the v2.1 template source: its drivers use
  BOOLEAN variables (`l_config_ok`, `l_pub_*_skipped`) with `:= TRUE/FALSE`
  assignments and bare conditions. The translation converts them to
  NUMBER(1) with `:= 1/0` and `= 1` conditions. Other sources' drivers use
  VARCHAR flags and needed no such conversion. If you hand-edit an ECI
  driver, keep the NUMBER(1) form — do not reintroduce BOOLEAN.

### 11.8 Config qualification (two-part vs three-part)

Drivers qualify the config table as `COMMON.ETL_RUN_CONFIG_TBL` in the
source — a two-part name (schema.table) that resolves inside the install
database. The framework DDL header says the table lives in
`MDM_ETL_COMMON.COMMON` (three-part: database.schema.table in Snowflake
terms). In Oracle there is no database qualifier in the same sense: install
COMMON as a schema and the two-part reference resolves. If the install uses
a different COMMON schema name, the driver references must change with it —
they are literal, not parameterized. See also §7.2 (topology).

### 11.9 ECI runner order: runner file wins over the STEP_MAP note

The STEP_MAP note for ECI lists: Validation → Pty → Addr → Phn_And_EAddr →
Alt_Id → Rel → Reactivation Family_Addr → Family_Phn → Medicaid, and says
"Runner order is unchanged". The runner file itself calls: Validation → Pty
→ Reactivation Family_Addr → Family_Phn → Medicaid → Alt_Id → Phn_And_EAddr
→ Addr → Rel. **These disagree, and the runner file is authoritative**
(execution order is what the runner calls, not what a note says). §10.3 and
`WORKFLOW-STEPS.md` use the runner order. The STEP_MAP note is stale; do not
"fix" the runner to match the note without a user decision — the runner
header's dependency reason (reactivations refill delta tables that later
mappings read) supports the runner order.

### 11.10 CRE run timestamp is set once

CRE's first step sets the run timestamp; all 18 publish branches reuse it.
Do not re-derive a timestamp per branch in IICS — a per-branch timestamp
would split one CRE run across two run stamps and break the run filters
(`LAST_UPDATE_DATE IN (run_ts, run_ts − 1h)`) that downstream logic relies on.

### 11.11 Scope notes per source (do not over-build)

- TTF: no Address driver, no Email-separate driver, no Relationship driver,
  no DQM. (4 mappings only.)
- CRE: no validation driver, no DQM (address-exception only among the
  non-spine kinds, plus the 10 EXC branches).
- TRS/CRE: no validation driver (valexc-style gating exists only in
  ECI/FSS/WIC/TTF validation mappings, as STATUS/EXCEPTION publish branches
  maintaining INACTIVE_STS/LOG).
- The 4 address-DQM publish branches are TRS Addr_2, ECI Pty_Addr,
  FSS Pty_Addr, WIC Pty_Addr — and only those four. (The DQM append caveat
  in §9 rule 6 applies to exactly these four.)

---

## 12. Open decisions (carried, not resolved)

None of these is decided by this document. Do not resolve one silently while
building; each needs the owner's word, and the build must carry the current
behaviour until then.

1. **TRS party-deactivation step-50 placement.** Runs after the publish
   transaction (§11.3). Confirm it stays there, or move it before publish
   deliberately (with the run-story consequences understood). Carried from
   the v2.1 step-driver delivery, still open.
2. **Config table's 3 extra columns** (STEP_NO, STEP_PROC_NAME, STEP_KIND).
   Flagged when the config table was designed, never resolved: are they
   permanent (the driver addresses units by STEP_NO, so STEP_NO at least is
   load-bearing in practice), or should the table be cut back to the 8
   operator columns? Until decided, install all 11 columns and seed all 11.
3. **Job-control topology** (§7.2): per-schema copies of framework procedures
   + helpers (adaptation applied here) vs synonyms pointing at COMMON.
   DBA decision; driver code is unchanged either way.
4. **ECI STEP_MAP note staleness** (§11.9): the note disagrees with the
   runner. Runner wins for execution; whether the note is corrected or the
   runner is changed is a documentation decision, not a build decision.
5. **DQM_ADDRESS append on re-run** (§9 rule 6): standing estate decision
   (known limitation, no code fix). Revisit only if the owner asks.
6. **INACTIVE_LOG retention:** the `_PTY_INACTIVE_LOG` tables are write-only
   audit logs (read by nothing in this tree). Whether they are dropped with
   other work tables at the next run's start or explicitly exempted as audit
   is undecided (same open item as in the clean-ETL constitution). This tree
   writes them via publish branches; it does not drop them (publish never
   drops). Decide before writing a housekeeping job that drops `STG_%`.
7. **Live-compile items** (§11.7, §13): `func().attribute`, table-function
   form, VARCHAR2(4000), `''` vs NULL, boolean-token coverage. Each needs a
   live Oracle compile + stub CALL to close.
8. **Target-table shapes:** the 42 `C_S_*` targets must be the plain v1-era
   shapes (no flag/DIAG columns). If the estate later adopts the v3 shapes,
   every publish INSERT column list in this tree must be re-derived — do not
   mix shapes.

---

## 13. Verification status and deviations from the brief

### 13.1 What was verified (static only, no database)

| # | Brief check | Result |
|---|---|---|
| 1 | Per-folder file counts; every source .sql has exactly one Oracle output | PASS — output tree mirrors source layout; 356 output .sql vs 355 source .sql; the single extra file is the generated `00_framework/common/00_common_types.sql` (see deviation 3) |
| 2 | Forbidden-leftover scan over code-only text (comments/strings blanked) | PASS — zero `$$`, `IFF(`, `DATEADD(`, `::`, `QUALIFY`, `EXECUTE AS CALLER`, `TIMESTAMP_NTZ`, `TO_VARCHAR(`, `LANGUAGE SQL`, `CALL`, `FLATTEN`, `INFORMATION_SCHEMA`, `TRY_TO_`, `SPLIT_PART(`, `BOOLEAN`, `SPLIT_TO_TABLE`, `;;`, bare `TRUE`/`FALSE` |
| 3 | Parenthesis balance, mask-aware (q-quote aware) | PASS — none unbalanced in any emitted file |
| 4 | Run-script call order matches source run order | PASS — all 7 run scripts: same runner call, `SELECT fn() FROM DUAL` form, `WHENEVER SQLERROR EXIT FAILURE` header, SnowSQL `!set` lines dropped |
| 5 | Matrix consistency (one writer per WRK; every consumed WRK produced earlier in the same workflow, or marked staging/prior-run) | PASS — zero multi-writer WRK tables; zero unresolved WRK consumed; step-5 drop lists equal produced sets in all 40 mappings; seed produced/consumed equal code (CTAS targets + P_INPUT_TABLES defaults) in all 330 rows; driver call order equals seed order |
| 6 | Config seed row count | CONFIRMED 330 (CRE 24, ECI 67, FSS 50, TRS 119, TTF 29, WIC 41); seeds copied verbatim (byte-identical on spot diff) |
| 7 | No secrets | PASS — no passwords, keys, tokens, or wallet material in any output (the OCI wallet was never copied into this tree) |
| 8 | Routine counts | 40 drivers, 153 steps, 137 publish branches, 45 helpers (37 scalar + 8 table), 4 framework procedures, 7 runners, 7 run scripts; 152 WRK tables (all runtime-created, zero pre-defined); 60 distinct publish targets (42 C_S_* + 15 STG + EXC + DQM + CRE_SRC_MRG) |

Eye-reads performed on the Oracle output: an ECI driver (header, BOOLEAN→
NUMBER(1) variables, step-5 drops, step/publish captures, checkpoints,
COMMIT); a TRS step with probe + CTAS + checkpoint; a TRS dedup step
(`uq_*` CASE wraps); a TRS driver (step/publish captures, checkpoints,
COMMIT); a TRS runner (`l_dummy` capture pattern); ALT/RFM/RFP probe outputs
(all three general probe shapes); a publish procedure (header + INSERT);
the framework procedures (COMMON.JOB_CONTROL_ETL qualification); helper03,
helper14 (OBJECT type + full-name concatenation), helper40, helper43
(BOOLOR_AGG conversion); a run script; the config DDL (columns + escaping).

### 13.2 Deviations from the brief, with reasons (parent to confirm)

1. **Framework procedures are Oracle PROCEDUREs, not FUNCTIONs.** The brief's
   blanket rule says procedures with RETURNS become FUNCTIONs. The 4
   framework procedures' Snowflake RETURNS values are never read at any call
   site (verified: zero capturing callers; the framework header itself says
   callers ignore them except in ad-hoc use; drivers generate the run id
   locally and pass it to job_begin). Converting them to FUNCTIONs would
   force a dummy capture at every call site for values nobody reads.
   Drivers, steps, publish branches, runners, and helpers remain FUNCTIONs.
   If the parent disagrees, the alternative is SELECT-INTO-dummy at every
   framework call site — a mechanical change, not a redesign.
2. **Install-topology adaptation** (§7.2): framework DDL once in COMMON;
   framework procedures + helpers repeated per source schema; framework
   procedures qualify `COMMON.JOB_CONTROL_ETL`. Reason: drivers call job
   procedures and helpers unqualified, while the framework header claims one
   shared table — the adaptation satisfies both statements. Unconfirmed
   until the DBA weighs in.
3. **Work-table DDL is an inventory, not CREATE statements**
   (`ddl/work_tables.sql`). Reason: no work-table CREATE definition exists
   anywhere in the source tree (all WRK tables are runtime CTAS); inventing
   column lists and types would be fabrication, and the brief forbids
   inventing types. The inventory gives producer, consumers, dropping
   driver, and the CTAS file + line where the column list lives.
4. **Reference placeholders are minimal shapes derived from helper SELECT
   lists** (`ddl/00_reference_placeholders.sql`), following the earlier
   mirrors' pattern — not real definitions, clearly marked as such.
5. **Dispatch is static, not dynamic** (§11.1). The brief's conditional
   dynamic-dispatch note does not apply; no dynamic mechanism exists in the
   source to translate. The TDD states this plainly instead of documenting
   a mechanism that is not there.
6. **Probe execution uses COUNT(*) instead of SELECT 1** (§11.7): avoids a
   multi-row INTO failure while preserving the ORA-00942 surfacing
   behaviour. Same failure mode, safer form.
7. **A generated types file exists** (`00_framework/common/00_common_types.sql`,
   11 OBJECT + 8 row + 8 table types). Forced by Oracle: OBJECT types cannot
   be declared inside a package spec, and the helpers are standalone
   functions, so their OBJECT/nested-table types must live at schema level.
   Install it before the helpers in each schema.
8. **Bugs fixed during translation** (all in the translator, none in the
   source semantics): an early per-code-segment implementation failed on
   constructs spanning string literals and was replaced with full-text
   masked parsing; a `fix_boolor` infinite loop (re-matched its own
   replacement) was fixed with position tracking; source `;;` empty
   statements after some CTAS were consumed; a q-quote-unaware segmenter
   misread `NVL'd` inside CTAS strings (that "paren imbalance" was a
   verifier artifact, not a real imbalance); the `:= (CALL f(args));`
   grouping-paren removal was corrected; a bare-`(` predicate rule that
   wrongly converted function-argument calls (e.g. `TRIM(NVL(…))` gained a
   spurious `= 1`) was narrowed to keyword + open-paren contexts; an early
   single-match framework conversion that left 3 Snowflake procedures
   untranslated was replaced with a loop over all CREATE PROCEDURE blocks;
   a non-greedy regex that left NOT EXISTS unclosed in one probe shape was
   replaced with depth-aware matching.

### 13.3 What was NOT verified (needs a live Oracle database)

- Compilation of any file (zero INVALID objects is a live check, not a
  static one). The static scans prove absence of Snowflake constructs, not
  presence of valid Oracle.
- Execution of any step, driver, or runner, including the publish
  transaction, the probe paths, and the CTAS bind order.
- Parity against IDQ or against the Snowflake step-driver run (row counts,
  target contents, `uq_*` guard behaviour, DQM/EXC contents).
- The §11.7 watch list: `func().attribute`, table-function form,
  VARCHAR2(4000) overflow, `''` vs NULL collapse, boolean-token coverage,
  helper03 NULL semantics, UUID format use, CTAS bind order under edit.
- The 7 reference objects' real definitions and data (§8.1) — placeholders
  compile the helpers but prove nothing about enrichment correctness.
- Schema-creation privilege, the COMMON schema name, and the §7.2 topology
  decision — all DBA confirmations, not code facts.

---

## 14. Appendix: layout map

```
ora-work-tables-sp-etl/
├── README.md                        — this repo in one page
├── ORA-WORK-TABLES-TDD.md           — this document
├── WORKFLOW-STEPS.md                — row-level chain matrix (330 rows)
├── ddl/
│   ├── 00_reference_placeholders.sql — 7 empty minimal reference shapes
│   └── work_tables.sql               — commented inventory of all 152 WRK tables
├── 00_framework/
│   ├── 01_job_control_ddl.sql        — JOB_CONTROL_ETL + views (COMMON)
│   ├── 02_job_control_procs.sql      — 4 framework procedures (per source schema)
│   ├── 03_etl_run_config_ddl.sql     — ETL_RUN_CONFIG_TBL (COMMON)
│   └── common/
│       ├── 00_common_types.sql       — generated OBJECT/nested-table types
│       ├── 01_snow_common_functions.sql — 37 scalar helpers
│       └── 02_snow_common_lookups.sql   — 8 table-function helpers
├── TRS/  (drivers/ steps/ publish/ runners/ + seed + manifests + docs)
├── ECI/  (mapping dirs with driver_*.sql, steps/, publish/ + seed + docs)
├── FSS/  (drivers/ steps/ publish/ runners/ + seed + docs)
├── WIC/  (drivers/ steps/ publish/ runners/ + seed + docs)
├── TTF/  (drivers/ steps/ publish/ runners/ + seed + docs)
├── CRE/  (drivers/ steps/ publish/ runners/ + seed + docs)
├── COMPILE_NOTES.md  DEPENDENCIES.md  README.md  STEP_MAP_ALL_SOURCES.md
└── <SRC>_DEPENDENCIES.md  <SRC>_STEP_MAP.md  (per source, copied from Snowflake)
```

Notes on the copied docs: `STEP_MAP_ALL_SOURCES.md` and the per-source
`*_STEP_MAP.md` / `*_DEPENDENCIES.md` / `*_MANIFEST.md` files are copied
verbatim from the Snowflake tree (they are markdown, not code). One known
stale item in them: the ECI STEP_MAP order note (§11.9) — the runner file
wins. Everything else in them describes the Snowflake form; read the Oracle
equivalents in §11.7 where forms differ.

Routine counts, one line: 7 workflows · 40 drivers · 153 steps · 137 publish
branches · 45 helpers · 4 framework procedures · 7 runners · 7 run scripts ·
330 config rows · 152 WRK tables · 60 publish targets · 7 reference objects.
