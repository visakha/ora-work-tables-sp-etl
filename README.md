# ORA-work-tables-SP-ETL — Oracle work-tables step-driver ETL

Oracle PL/SQL translation of the Snowflake All-Sources Modular Step Driver
v2.1 (the "chapter-two" code). Same names, parameters, columns, predicates,
order, and quirks — only the container changed from Snowflake SQL Scripting
to Oracle PL/SQL.

## Why this layout exists

In Informatica IDQ / IICS, mappings are discrete: a CTE computed in one
mapping cannot be passed to the next mapping. So the step-driver pattern
materializes every handoff as a table: **each step is a single stored
procedure that writes one or more work tables, and the next step reads them.**
The unit is the STEP, and work tables are the handoffs between steps, across
a whole workflow.

This is the opposite of the single-big-procedure layout (one procedure builds
everything internally with CTEs) and of the discrete-procedure layout (a
materializer feeds writers inside one mapping). If you are building IICS
mappings from this repo, you are building one mapping per STEP, with the
driver as the taskflow and the runner as the workflow.

## What is in here

| | Count |
|---|---|
| Workflows | 7 (TRS Ongoing, TRS TOA, ECI, FSS, WIC, TTF, CRE) |
| Drivers (one per mapping) | 40 |
| Steps (one per IICS mapping) | 153 |
| Publish branches (one per IICS mapping) | 137 |
| IICS mappings to build (steps + publish) | 290 |
| Config seed rows | 330 |
| WRK work tables (all runtime-created) | 152 |
| Common helpers (37 scalar + 8 table functions) | 45 |
| Framework procedures (job control) | 4 |
| Runners + run scripts | 7 + 7 |
| Publish targets (42 C_S_* + 15 STG + EXC + DQM + CRE_SRC_MRG) | 60 distinct |

## Start here

1. **`ORA-WORK-TABLES-TDD.md`** — the technical design document. Read it first:
   architecture, the step pattern, the work-table lifecycle, the config table,
   install order, prerequisites, recovery rules, per-workflow build sequences,
   gotchas, open decisions, and verification status. It is the build guide.
2. **`WORKFLOW-STEPS.md`** — the row-level chain matrix: one table per
   workflow, one row per unit (driver row + steps + publish branches), with
   step numbers, procedures, work tables produced/consumed, handoff
   mechanism, and the IICS mapping note. Build from this table, row by row.
3. **`ddl/work_tables.sql`** — commented inventory of all 152 WRK tables
   (producing step, consuming units, dropping driver, CTAS file + line).
   No CREATE statements are fabricated here: work tables are runtime CTAS
   outputs, and the CTAS SELECT list is their column definition.
4. **`ddl/00_reference_placeholders.sql`** — empty minimal shapes for the 7
   reference objects the lookup helpers read. Replace with real definitions
   before any real run.

## Layout map

```
├── README.md                        — this file
├── ORA-WORK-TABLES-TDD.md           — technical design document (the build guide)
├── WORKFLOW-STEPS.md                — chain matrix (330 rows)
├── ddl/
│   ├── 00_reference_placeholders.sql — 7 empty minimal reference shapes
│   └── work_tables.sql               — inventory of all 152 WRK tables
├── 00_framework/
│   ├── 01_job_control_ddl.sql        — JOB_CONTROL_ETL + views (COMMON schema)
│   ├── 02_job_control_procs.sql      — 4 framework procedures (per source schema)
│   ├── 03_etl_run_config_ddl.sql     — ETL_RUN_CONFIG_TBL (COMMON schema)
│   └── common/
│       ├── 00_common_types.sql       — generated OBJECT/nested-table types
│       ├── 01_snow_common_functions.sql — 37 scalar helpers
│       └── 02_snow_common_lookups.sql   — 8 table-function helpers
├── TRS/  ECI/  FSS/  WIC/  TTF/  CRE/  — per-source drivers, steps, publish,
│                                          runners, seeds, manifests, docs
└── COMPILE_NOTES.md  DEPENDENCIES.md  STEP_MAP_ALL_SOURCES.md
    (copied from the Snowflake tree; one known stale item — the ECI STEP_MAP
    order note disagrees with the runner file, and the runner file wins.)
```

## Install order (summary — the TDD §7 is authoritative)

1. Create schemas: COMMON, one per source (`TRS_ETL_WRK`, `ECI_ETL_WRK`,
   `FSS_ETL_WRK`, `WIC_ETL_WRK`, `TTF_ETL_WRK`, `CRE_ETL_WRK`), plus `RDM`
   (DBA pre-action).
2. `ddl/00_reference_placeholders.sql` (empty shapes; replace before a real run).
3. `00_framework/01_job_control_ddl.sql` in COMMON.
4. `00_framework/03_etl_run_config_ddl.sql` in COMMON + the six seed files
   in COMMON (verify 330 rows).
5. `00_framework/common/00_common_types.sql` in EACH source schema.
6. `00_framework/common/01_*.sql` + `02_*.sql` in EACH source schema.
7. Per-source drivers, steps, publish, runners in that source's schema.
8. Run scripts (`SELECT <runner>() FROM DUAL;`) as the scheduler entry points.
9. Verify zero INVALID objects per schema; recompile after replacing the
   reference placeholders with real definitions.

Do NOT create WRK tables at install time (steps DROP + CTAS them at runtime),
do NOT create staging inputs or `C_S_*` targets here (they are prerequisites
— see the TDD §8), and do NOT put DROP statements in install DDL (procedure
bodies rebuild their own WRK scratch tables at run time — that is runtime
behaviour, not install DDL).

## The one rule to never break

> **The driver must NOT validate flags or dependencies: the user toggles
> is_run_enabled only and owns dependency correctness — the driver surfaces a
> missing table plainly, never silently enforces or fixes flags.**

Do not add taskflow validation that refuses "inconsistent" flag combinations.
A consumer left enabled while its producer is disabled must fail loudly on
the missing WRK table (the step probe) — that loud failure IS the design.
Step 5 drops ALL work tables regardless of flags, for the same reason: a
drops-only-enabled variant would let consumers silently read stale tables
from the previous run.

## Status: static translation only

No database was connected. Nothing here has been compiled on Oracle,
executed, or parity-checked against IDQ. The static verification (file-count
match, zero Snowflake-construct leftovers, paren balance, run-script order,
matrix consistency, 330 seed rows, no secrets) is documented in the TDD §13,
along with every deviation from the translation brief and the live-database
items that still need closing (`func().attribute`, table-function form,
VARCHAR2(4000), `''` vs NULL, boolean-token coverage, real reference data).

## What this tree is NOT

Not the v3 line: no flag columns, no `V_MDM_*` / `V_CMP_*` / `V_AUDIT_*`
views, no DIAG columns. Targets are the plain `C_S_*` tables. Do not import
v3 concepts into this build. And this tree predates the step-driver's own
later corrections — known oddities (notably the TRS party-deactivation
step-50 placement after publish, and the config table's 3 extra columns) are
preserved and flagged open in the TDD §12, not fixed.
