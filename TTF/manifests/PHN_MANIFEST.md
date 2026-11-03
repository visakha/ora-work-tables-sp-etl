# PHN Manifest - m_Tgt_C_S_TTF_Pty_Rle_Phn, config-driven step-driver refactor (TTF ONLY)

Prefix: `TTF_PHN`, short: `PHN`. Base dir: `snowflake_all_drivers/TTF/`
(step files in `steps/`, branch files in `publish/`, driver in `drivers/`).
Source verified against: `snowflake_multisource/TTF/mappings/sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Phn.sql`
(step map `snowflake_multisource/TTF/STEP_MAP_TTF.md` agrees; the file was
treated as authoritative throughout).

## What this mapping does

One phone per active TTF client into C_S_TTF_PTY_RLE_PHN. A good phone loads as usage '001', type 'Telephone', preference 'Primary'; a bad phone is NOT loaded, only logged as a 'Rejected Record' exception with the source phone as the attribute value.

## Driver

Signature (IDENTICAL to the current main, verified by normalised comparison):

```sql
sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Phn (
    P_JOB_RUN_ID VARCHAR DEFAULT NULL
) RETURNS VARCHAR
```

File: `drivers/driver_sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Phn.sql`

Driver behaviour: job-run-id generation exactly as now + `sp_etl_job_begin`;
one config GATHER (nested `BEGIN/EXCEPTION`, defaults stand on failure) from
`COMMON.ETL_RUN_CONFIG_TBL` (`WORKFLOW_NAME = 'wf_TTF_Stage_Load'`,
`MAPPING_NAME = 'm_Tgt_C_S_TTF_Pty_Rle_Phn'`); driver-row `STEP_NO = 0` = `'N'` skips the
whole mapping BEFORE step 5 cleanup (SKIPPED checkpoint `MAPPING_SKIPPED`,
`sp_etl_job_finish` with a skipped message, early RETURN); step 5 cleanup
unchanged (bare `DROP TABLE IF EXISTS`, no checkpoint); conditional step
calls in order; ONE publish transaction calling the enabled branch procs in
order; branch checkpoints ONLY after `COMMIT`; `TERMINATING` via
`sp_etl_job_finish` with the same message style and RETURN format as now;
exception block identical in shape (ROLLBACK + TERMINATING `JOB_END`
FAILED checkpoint in the v2 10-argument form + `sp_etl_job_fail` + RAISE).

## Steps

| STEP_NO | Proc | Kind | Produces | Consumes default | Checkpoint STEP_NAME |
|---|---|---|---|---|---|
| 10 | `sp_snow_step_TTF_PHN_S10_SRC` | TRANSFORM | `WRK_TTF_PHN_S1_SRC` | _(empty - base tables, check skipped)_ | `SRC` |
| 20 | `sp_snow_step_TTF_PHN_S20_CHECKED` | TRANSFORM | `WRK_TTF_PHN_S2_CHECKED` | `WRK_TTF_PHN_S1_SRC` | `CHECKED` |
| 30 | `sp_snow_step_TTF_PHN_S30_ROUTED` | TRANSFORM | `WRK_TTF_PHN_S3_ROUTED` | `WRK_TTF_PHN_S2_CHECKED` | `ROUTED` |

Step proc signatures: the step's used original params (in original order) +
`P_JOB_RUN_ID` + `P_RUN_TS` + `P_INPUT_TABLES` (pipe-delimited default naming
work-table inputs; existence checked via INFORMATION_SCHEMA.TABLES + an
EXECUTE IMMEDIATE probe of the first missing table -- RAISE cannot carry a
dynamic table name so the native error surfaces instead). `P_INPUT_TABLES`
is a declaration + check, NOT dynamic SQL: each CTAS still names its source
work table literally. Every step proc returns `NUMBER` (row count), writes
its own checkpoint in the v2 10-argument form, has no exception block, no
transaction, no target write.

## Publish branches

Original publish was one step 40 with 2 INSERT(s) in one transaction. Each
INSERT is now one branch proc, called by the driver inside ONE transaction
in the same order, checkpointed by the driver only after COMMIT.

| STEP_NO | Proc | Kind | Target | Consumes |
|---|---|---|---|---|
| 40 | `sp_snow_pub_TTF_PHN_C_S_TTF_PTY_RLE_PHN` | SPINE | `C_S_TTF_PTY_RLE_PHN` | `WRK_TTF_PHN_S3_ROUTED` | `PUBLISH_C_S_TTF_PTY_RLE_PHN` |
| 50 | `sp_snow_pub_TTF_PHN_EXC_STG_BAD_REC_MEMB` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` | `WRK_TTF_PHN_S3_ROUTED` | `PUBLISH_EXC_STG_BAD_REC_MEMB` |

Branch proc signatures: `P_JOB_RUN_ID` + `P_RUN_TS` +
`P_INPUT_TABLES` (default the final routed table). Each returns
`SQLROWCOUNT` as `NUMBER`. No transaction control, no checkpoint calls.
The first branch takes the current publish step number (40), +10 per branch.

## Parameters

No original parameters. Driver signature is the main's signature exactly: P_JOB_RUN_ID only. Step procs take only P_JOB_RUN_ID + P_RUN_TS + P_INPUT_TABLES; step 30 materialises run_ts and mapping_name from :P_RUN_TS and the local constant.

## Flag / input / publish-count naming

Rule: strip the `sp_snow_step_` / `sp_snow_pub_` prefix from the unit's
procedure name, prepend `l_flag_` / `l_in_` / `l_pub_`; the driver-row flag
is `l_flag_TTF_PHN_DRIVER`. Dependencies live in `l_in_*` variables, in
config DEPENDENT_ON, and in TTF_DEPENDENCIES.md -- never in flag names.

| Variable family | Unit |
|---|---|
| `l_flag_TTF_PHN_DRIVER` | driver row (STEP_NO 0) |
| `l_flag_S10_SRC` / `l_in_S10_SRC` | step 10 SRC |
| `l_flag_S20_CHECKED` / `l_in_S20_CHECKED` | step 20 CHECKED |
| `l_flag_S30_ROUTED` / `l_in_S30_ROUTED` | step 30 ROUTED |
| `l_flag_TTF_PHN_C_S_TTF_PTY_RLE_PHN` / `l_in_TTF_PHN_C_S_TTF_PTY_RLE_PHN` / `l_pub_TTF_PHN_C_S_TTF_PTY_RLE_PHN` | branch 40 PUBLISH_C_S_TTF_PTY_RLE_PHN |
| `l_flag_TTF_PHN_EXC_STG_BAD_REC_MEMB` / `l_in_TTF_PHN_EXC_STG_BAD_REC_MEMB` / `l_pub_TTF_PHN_EXC_STG_BAD_REC_MEMB` | branch 50 PUBLISH_EXC_STG_BAD_REC_MEMB |

## Preserved quirks (kept deliberately, do not "fix" silently)

- Insert-only (IDQ truncate not performed); keys already present are skipped by the uq_phn guard.
- Bad_Phone_Ext records never occur (unfed extension port, no branch generated).
- Exception SRC_SYS_ID_2 is NULL (unfed ID_PHONE port).
- The source invalid SQL fragment is not applied.
- VERSION_SEQ = '1'; PERIOD_START_DATE = SUBMITDATE.
- A bad phone is logged only, never loaded.
- The phone area-code lookup is the shared helper fn_snow_helper44_common; its underlying table location is owned by the shared framework (not qualified here, as in the original).

## Phase-flow diagram

Phases follow the actual driver flow. Publish is ONE phase and ONE
transaction: spine / status / exception groups are distinguished by label
prefixes inside the single Publish subgraph, never by splitting the
transaction across subgraphs.

```mermaid
flowchart LR
    subgraph P1["Phase 1 - Begin"]
        direction TB
        A["Job begin"]
    end
    subgraph P2["Phase 2 - Configure"]
        direction TB
        B["Config gather"]
        C["Driver gate"]
        B --> C
    end
    subgraph P3["Phase 3 - Clean"]
        direction TB
        D["Step 5 cleanup"]
    end
    subgraph P4["Phase 4 - Source"]
        direction TB
        E["Step 10 SRC"]
    end
    subgraph P5["Phase 5 - Validate"]
        direction TB
        F["Step 20 CHECKED"]
    end
    subgraph P6["Phase 6 - Route"]
        direction TB
        G["Step 30 ROUTED"]
    end
    subgraph P7["Phase 7 - Publish"]
        direction TB
        H["Branch 40 SPINE phone"]
        I["Branch 50 EXCEPTION bad phone"]
        H --> I
    end
    subgraph P8["Phase 8 - Close"]
        direction TB
        J["Job end"]
        K["RETURN summary"]
        L["Work tables left standing"]
        J --> K --> L
    end
    P1 --> P2 --> P3 --> P4 --> P5 --> P6 --> P7 --> P8
```

## Verification performed (no live Snowflake available)

- All 3 step CTAS compared to the current file after whitespace normalisation
  and the allowed substitution only (`:l_run_ts` -> `:P_RUN_TS`,
  `:c_mapping` -> the local constant of the same name): all MATCH.
- All 2 branch INSERTs compared likewise: all MATCH.
- Driver name/signature compared to the current main (normalised): IDENTICAL.
- Counts: 1 driver + 3 step procs + 2 branch procs, covering all
  current steps and all current publish INSERTs exactly once.
- Style greps (code): 0 checkpoint calls for drops, 0 `P_RESUME_STEP`,
  0 cursors, 0 `sp_etl_checkpoint` calls and 0 transaction statements in
  publish-branch code, 0 checkpoint calls between the driver's
  `BEGIN TRANSACTION` and `COMMIT`, `TRANSIENT` work tables only with
  unchanged names, `P_JOB_RUN_ID` in every new proc.
- Every `sp_etl_checkpoint` call parses (balanced-paren) to exactly 10
  arguments; no `||` in any `COMMENT ON`; no required-after-optional
  signature order (the one step with defaulted original params, where
  applicable, carries DEFAULT NULL on its trailing params).

## Deviations / uncertainties -- nothing silently shipped

1. **Combined publish checkpoint split (by design, per brief).** The current
   file writes ONE step-40 `PUBLISH` checkpoint with the summed row count.
   The refactor writes one checkpoint per branch (STEP_NOs
   40, 50) with that branch's count, plus a per-branch helper36
   summary line instead of the single `step 40 PUBLISH` line. Total published rows
   are recoverable by summing the branch counts; there is no longer a
   single combined publish row.
2. **Config columns not read.** `IS_DEPENDENT`, `DEPENDENT_ON` and
   `WORK_TABLES_PRODUCED` exist in `ETL_RUN_CONFIG_TBL` but are not read by
   this driver; gating is by `IS_RUN_ENABLED` only, per the brief.
3. **No cascade on skip.** Skipping is per step/branch only. If an upstream
   step is disabled but a downstream step stays enabled, the downstream
   step's existence check raises the missing work table rather than running
   on stale data. Operators must disable downstream steps explicitly.
4. **'SKIPPED' status is a choice to confirm.** `JOB_CONTROL_ETL.STEP_STATUS`
   has no CHECK constraint (only a DDL comment listing
   STARTED | COMPLETED | FAILED); `SKIPPED` rows are used here as specified
   and should be confirmed by the user.
5. **Compile-time verification items (no live Snowflake here).**
   - `l_rows := (CALL proc(...));` scalar-call capture form.
   - `IF` blocks inside the driver's `BEGIN TRANSACTION` / `COMMIT` region
     (branch CALLs gated by flags), and the multi-variable
     `SELECT ... INTO :a, :b, ...` in the GATHER.
   - Unused-parameter warnings, if any, for `P_RUN_TS` in steps/branches
     where it is carried for signature uniformity.
6. **Not tested.** No live Snowflake compile, run, or row-count parity run
   was possible in this environment; that step is required before use.
7. **Scope.** TTF `m_Tgt_C_S_TTF_Pty_Rle_Phn` only. No other source or mapping was touched; the
   current main file was not modified.
