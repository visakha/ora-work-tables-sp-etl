# Compile notes — all-sources step-driver package (v2.1 style)

## Explicit statement

**No live Snowflake compile, run, or row-count parity run was
performed for this package, per instruction.** The user waived live
vetting for this build because the error classes were already known
from the ECI v2.1 live compile (COMPILE_REPORT_v2.1.md in the ECI
example package). Everything below is mechanical application of
those findings plus static verification. A live compile and a run
against real source tables are still required before production use.

## Mechanical fixes applied (from the ECI v2.1 live compile)

The ECI v2.1 live compile (74 files, 193 statements, scratch
database, compile-only) first ran 69/74 OK with 12 errors in three
classes. The fixes for those classes were applied throughout this
package:

1. **`COMMENT ON ... IS` takes a string literal only.**
   `COMMENT ON TABLE ... IS 'a' || 'b'` fails on Snowflake
   ("unexpected `||`"). This package's rebuilt sources emit no
   `COMMENT ON` statements at all; the shared framework comments
   are the v2.1 single-literal form. Verified: no `||` inside any
   `COMMENT ON` in the package.
2. **Never a required parameter after an optional one.** Snowflake
   rejects a signature where a parameter with a default precedes a
   parameter without one (ECI v2.1 caught this in the ADR/PTY
   step-50 procedures). Wherever a step's or branch's original
   params carry defaults before `P_JOB_RUN_ID`/`P_RUN_TS`, those
   trailing params carry `DEFAULT NULL`. Parameters are **never
   reordered** — drivers pass positionally, so reordering would
   break the calls. Verified: no required-after-optional signature
   in any procedure in the package.
3. **Lookup UDFs unchanged; missing objects documented, never
   invented.** The eight lookup functions
   (`fn_snow_helper40–47_common`) validate their bodies at creation
   and therefore fail in a bare schema. Their seven reference
   objects (`V_LOOKUP_CODE_VALUE`, `REF_JUNK_NAME_LIST`,
   `REF_MATCHCODE_DESC`, `RDM.REF_PHN_AREA_CD`,
   `EXC_LOOKUP_CODE_VALUE`, `LOOKUP_CODE_VALUE`,
   `REF_DYLGHT_SVNGS_TM`) still need real definitions before a
   production install. The ECI v2.1 compile validated the functions
   against scratch-only stubs whose columns came from the functions'
   own SELECT lists; the stubs are scaffolding only and are not
   shipped here.
4. **Install hazards found by the ECI v2.1 compile, carried into the
   README:**
   - Personal databases refuse table creation (error 060119:
     "Tables cannot currently be created in a personal database").
     Install targets must be normal databases, not `USER$<name>`.
   - `CREATE SCHEMA` switches the session's `CURRENT_SCHEMA` to the
     newly created schema (verified by experiment). An install
     script that runs `USE SCHEMA` and then `CREATE SCHEMA` will
     silently place later objects in the new schema. Use fully
     qualified names or re-issue `USE SCHEMA` after any
     `CREATE SCHEMA`.

## Coordinator fix during assembly (WIC publish procedures)

Independent verification caught a real defect the WIC worker's own
checks missed: **all 19 WIC publish procedures were missing the
`INSERT INTO` keywords** — each body began with the bare target
table name followed by the column list and `SELECT`, which is not
valid SQL and would have failed at compile and at runtime. The
worker's strip-and-compare had compared bodies without the statement
keyword, so it passed its own check. The coordinator restored the
keywords mechanically: for each of the 19 files, the target token
was cross-checked against the file header's stated target, and
`INSERT INTO ` was inserted before it — no other text changed.
After the fix, the WIC INSERT-body multiset matches the mains
exactly (see below). No other source was affected: every publish
procedure in TRS, ECI, TTF, FSS, and CRE already contained exactly
one `INSERT INTO` (verified file by file). The fixed files are the
ones shipped in this package.

## Known error classes (what a live compile would still check)

- Scalar-call capture `l_rows := (CALL proc(...));` — passed
  creation in ECI v2.1; still unconfirmed for the five rebuilt
  sources except by identical construction.
- `IF` blocks inside the publish transaction region.
- Multi-variable GATHER `SELECT ... INTO`.
- The empty-transaction path (all branches of a mapping skipped) —
  needs execution, not creation.
- Driver-to-step call targets at runtime — creation does not
  resolve `CALL` targets (proven in ECI v2.1: drivers compiled while
  two step procedures were still failing). All called procedures
  exist on disk here, but only a run proves the chain end to end.

## Static verification performed instead (coordinator, independent)

184 checks, 0 failures, 0 warnings (script: comment-aware greps,
balanced-paren parsing, signature parsing, seed arithmetic,
mermaid fence/label checks, business-SQL multiset comparison):

- 40 drivers total (TRS 15, ECI 9, WIC 5, TTF 4, FSS 6, CRE 1);
  153 steps; 137 publish branches; 40 manifests; 330 seed rows
  (seed rows equal drivers + steps + branches in every source).
- Every new-source driver signature identical to its multisource
  main (whitespace-normalised, comment-aware comparison). ECI
  drivers are the v2.1 verbatim copy (content-diff verified against
  the ECI v2.1 tree, as is the shared framework; the two common
  helper files match the multisource ones exactly).
- Every runner file byte-identical to its multisource original;
  runners make no checkpoint calls.
- Business SQL: for each of the five rebuilt sources, the multiset
  of step CTAS bodies and the multiset of publish INSERT bodies
  match the multisource mains exactly after whitespace
  normalisation with only the allowed substitutions
  (`:l_run_ts` → `:P_RUN_TS`, `:c_mapping`/`:c_source`/`:c_workflow`
  → same-value local constants). TRS 65 CTAS + 38 INSERTs, WIC 17 +
  19, TTF 12 + 13, FSS 21 + 23, CRE 5 + 18 — all identical.
  (The WIC INSERT comparison initially failed, which is how the
  missing-`INSERT INTO` defect above was found and fixed.)
- Every `sp_etl_checkpoint` call in the package parses to exactly
  10 arguments in the v2.1 order.
- 0 `DROPPED` checkpoint calls, 0 `P_RESUME_STEP`, 0 cursors in
  code (comment-aware); work tables TRANSIENT only; `P_JOB_RUN_ID`
  in every driver, step, and publish procedure.
- Flag/in/pub naming uniform under the unit rule in all drivers
  (no numeric-only flags, no legacy `l_cons_`/`v_run_`/`l_cfg_`
  families; `l_run_ts` occurs only as the run-timestamp variable,
  as in the ECI template).
- Every rebuilt mapping's manifest has exactly one balanced
  ```mermaid fence with clean labels (letters, digits, spaces,
  hyphens, underscores only) and exactly one Publish phase; phase
  counts range from 6 (base scheme) to 8 (genuinely split Transform
  phases). ECI's 9 manifests are v2.1 originals and contain no
  Mermaid diagrams (they predate the diagram requirement); the
  README's generic driver-flow diagram covers their flow.
- Previous zips untouched (ECI v2.1 example zip byte count
  unchanged).

## Not validated (carried forward)

Runtime behaviour, row-count parity against IDQ, the
empty-transaction path, real reference data for the seven objects
above, and the open questions in the README all still require a
live run and user feedback before production use.
