# PTY Manifest -- m_Tgt_C_S_FSS_Pty, config-driven step-driver refactor (FSS ONLY)

Prefix: `FSS_PTY`, short: `PTY`. Base dir: `snowflake_all_drivers/FSS/`.
Source verified against: `snowflake_multisource/FSS/mappings/sp_snow_main_m_Tgt_C_S_FSS_Pty.sql`
(step map `snowflake_multisource/FSS/STEP_MAP_FSS.md` agrees with the file on
step numbers, work tables and publish counts; where they agreed, no
discrepancy was found -- see Deviations).

## Driver

Signature (IDENTICAL to the current main, verified by normalised comparison):

```sql
sp_snow_main_Tgt_C_S_FSS_Pty (
    
        P_PTY_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Indv',
        P_RLE_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Member',
        P_JOB_RUN_ID             VARCHAR DEFAULT NULL
) RETURNS VARCHAR
```

File: `drivers/driver_sp_snow_main_Tgt_C_S_FSS_Pty.sql`

Driver behaviour: job-run-id generation exactly as now + `sp_etl_job_begin`;
one config GATHER (nested `BEGIN/EXCEPTION`, defaults stand on failure) from
`COMMON.ETL_RUN_CONFIG_TBL` (`WORKFLOW_NAME = 'wf_FSS_Stage_Load'`,
`MAPPING_NAME = 'm_Tgt_C_S_FSS_Pty'`); driver-row `STEP_NO = 0` = `'N'` skips the
whole mapping BEFORE step 5 cleanup (SKIPPED checkpoint `MAPPING_SKIPPED`,
`sp_etl_job_finish` with a skipped message, early RETURN); step 5 cleanup
unchanged (bare `DROP TABLE IF EXISTS`, no checkpoint); conditional step
calls in order; ONE publish transaction calling the enabled branch procs in
order; branch checkpoints ONLY after `COMMIT`; `TERMINATING` via
`sp_etl_job_finish` with the same message style and RETURN format as now;
exception block identical in shape (ROLLBACK + TERMINATING `JOB_END`
FAILED checkpoint in the v2 10-argument form + `sp_etl_job_fail` + RAISE).

## Steps

| STEP_NO | Proc | Kind | Produces | Consumes default | Original params used | Checkpoint STEP_NAME | Description |
|---|---|---|---|---|---|---|---|
| 10 | `sp_snow_step_FSS_PTY_S10_SRC` | TRANSFORM | `WRK_FSS_PTY_S1_SRC` | `` | none | `SRC_ACTIVE` | Source clients, deactivated parties removed |
| 20 | `sp_snow_step_FSS_PTY_S20_DQ` | TRANSFORM | `WRK_FSS_PTY_S2_DQ` | `WRK_FSS_PTY_S1_SRC` | none | `DQ_CHECKS` | Name standardisation, gender, birth date, ethnicity, race, language, suffix checks |
| 30 | `sp_snow_step_FSS_PTY_S30_DQ2` | TRANSFORM | `WRK_FSS_PTY_S3_DQ2` | `WRK_FSS_PTY_S2_DQ` | none | `DQ2_EXCEPTIONS` | Standardised values with exception codes / descriptions / types resolved |
| 40 | `sp_snow_step_FSS_PTY_S40_ROUTED` | TRANSFORM | `WRK_FSS_PTY_S4_ROUTED` | `WRK_FSS_PTY_S3_DQ2` | P_PTY_BO_CLASS_CD_MEMBER, P_RLE_BO_CLASS_CD_MEMBER | `ROUTED` | Party / role keys, exception groups, insert-only guards |

Step proc signatures: the step's used original params (in original order) +
`P_JOB_RUN_ID` + `P_RUN_TS` + `P_INPUT_TABLES VARCHAR DEFAULT '<consumes default>'`.
Where an original param carries a default before the trailing params, the
trailing params carry DEFAULT NULL (ECI v2.1 live-compile fix -- never a
required parameter after an optional one; drivers pass everything
positionally, so behaviour is unchanged). Every step proc returns `NUMBER`
(row count), writes its own checkpoint in the v2 10-argument form
(TARGET_TABLE NULL, as in the current main's step checkpoints; row count
survives in the RETURN value and the helper36 summary line), has no
exception block, no transaction, no target write, and starts with the
work-table existence check (skipped when `P_INPUT_TABLES` is NULL/empty).
`P_INPUT_TABLES` is a dependency declaration + runtime check, NOT dynamic
SQL -- each CTAS still names its source work table literally.

Step files: `steps/sp_snow_step_FSS_PTY_S<nn>_<NAME>.sql` (4 files).

## Publish branches

Original publish was one step 50 with 8 INSERT(s) in one transaction. Each
INSERT is now one branch proc, called by the driver inside ONE transaction
in the same order, checkpointed by the driver only after COMMIT. First
branch takes step number 50, +10 per branch.

| STEP_NO | Proc | Kind | Target | Consumes | Description | Checkpoint STEP_NAME |
|---|---|---|---|---|---|---|
| 50 | `sp_snow_pub_FSS_PTY_C_S_FSS_PTY` | SPINE | `C_S_FSS_PTY` | `WRK_FSS_PTY_S4_ROUTED` | `Valid parties` | `PUBLISH_C_S_FSS_PTY` |
| 60 | `sp_snow_pub_FSS_PTY_C_S_FSS_PTY_RLE` | SPINE | `C_S_FSS_PTY_RLE` | `WRK_FSS_PTY_S4_ROUTED` | `Valid roles` | `PUBLISH_C_S_FSS_PTY_RLE` |
| 70 | `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_GENDER` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` | `WRK_FSS_PTY_S4_ROUTED` | `Invalid gender` | `PUBLISH_EXC_GENDER` |
| 80 | `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` | `WRK_FSS_PTY_S4_ROUTED` | `Invalid birth date` | `PUBLISH_EXC_BIRTH` |
| 90 | `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` | `WRK_FSS_PTY_S4_ROUTED` | `Invalid ethnicity` | `PUBLISH_EXC_ETHNICITY` |
| 100 | `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_RACE` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` | `WRK_FSS_PTY_S4_ROUTED` | `Invalid race` | `PUBLISH_EXC_RACE` |
| 110 | `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` | `WRK_FSS_PTY_S4_ROUTED` | `Invalid language` | `PUBLISH_EXC_LANGUAGE` |
| 120 | `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_SUFFIX` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` | `WRK_FSS_PTY_S4_ROUTED` | `Invalid suffix` | `PUBLISH_EXC_SUFFIX` |

Branch proc signatures: `P_JOB_RUN_ID VARCHAR` + `P_RUN_TS TIMESTAMP_NTZ` +
`P_INPUT_TABLES VARCHAR DEFAULT '<last step work table>'`. Each returns
`SQLROWCOUNT` as `NUMBER`. No transaction control, no checkpoint calls.

Branch files: `publish/sp_snow_pub_FSS_PTY_<TARGET>[_<BRANCH>].sql` (8 files).

## Preserved quirks (business logic NOT fixed)

- Insert-only: no TRUNCATE, no DELETE of targets. The IDQ truncate of the party and role tables is NOT performed; keys already present are skipped instead (uq_pty / uq_rle guards). A re-run inserts nothing twice but does not remove rows IDQ would have truncated away.
- PRESERVED: the party table's birth date is the source date of birth, so a future birth date is still loaded; the language exception row writes the checked birth date instead (blank for a future one).
- PRESERVED: ethnicity, race and language exceptions are routed on the looked-up code, so an unconfigured code produces no row; gender is routed on the looked-up description.
- PRESERVED: the suffix check uses the code-value lookup WITHOUT a code-type filter, exactly as in the original.
- PRESERVED: the commented-out testing source filter is not applied, exactly as in the original.
- Version sequence is hard-coded to 1 and the period start date is the last-update date on both targets, exactly as in the original.
- An exception never rejects the party: the party is loaded AND logged.

## Phase-flow diagram

```mermaid
flowchart LR
    subgraph B1["Phase 1 - Begin"]
        direction TB
        b1["Job begin"]
    end
    subgraph C1["Phase 2 - Configure"]
        direction TB
        c1["Config gather"] --> c2["Driver gate"]
    end
    subgraph C2["Phase 3 - Clean"]
        direction TB
        d1["Step 5 cleanup"]
    end
    subgraph T1["Phase 4 - Transform"]
        direction TB
        t10["Step 10 SRC"] --> t20["Step 20 DQ"] --> t30["Step 30 DQ2"] --> t40["Step 40 ROUTED"]
    end
    subgraph P1["Phase 5 - Publish"]
        direction TB
        p50["SPINE C_S_FSS_PTY"] --> p60["SPINE C_S_FSS_PTY_RLE"] --> p70["EXCEPTION GENDER"] --> p80["EXCEPTION BIRTH"] --> p90["EXCEPTION ETHNICITY"] --> p100["EXCEPTION RACE"] --> p110["EXCEPTION LANGUAGE"] --> p120["EXCEPTION SUFFIX"]
    end
    subgraph E1["Phase 6 - Close"]
        direction TB
        e1["Job end"] --> e2["RETURN summary"] --> e3["Work tables left standing"]
    end
    B1 --> C1
    C1 --> C2
    C2 --> T1
    T1 --> P1
    P1 --> E1
```

Publish is ONE transaction: all branches sit inside the single Publish
subgraph above (groups distinguished by the SPINE / STATUS / EXCEPTION /
VALIDATION label prefixes), never split across subgraphs.

## Verification performed (no live Snowflake available)

- All 4 step CTAS compared to the current file after whitespace normalisation
  and the allowed substitutions only (`:l_run_ts` -> `:P_RUN_TS`,
  `:c_mapping` -> the local constant of the same value): all MATCH.
- All 8 branch INSERTs compared likewise: all MATCH.
- Driver name/signature compared to the current main (normalised): IDENTICAL.
- Counts: 1 driver + 4 step procs + 8 branch procs = 13 files, covering all
  current steps and all current publish INSERTs exactly once.
- Style greps (code lines): 0 `DROPPED` checkpoint calls, 0 `P_RESUME_STEP`,
  0 cursors, 0 `sp_etl_checkpoint` calls and 0 transaction statements in
  publish-branch code, 0 checkpoint calls between the driver's
  `BEGIN TRANSACTION` and `COMMIT`, `TRANSIENT` work tables only with
  unchanged names, `P_JOB_RUN_ID` in every new proc.
- No live Snowflake compile, run, or row-count parity run was possible in
  this environment; that step is required before use.

## Deviations / uncertainties -- nothing silently shipped

1. **Combined publish checkpoint split (by design, per brief).** The current
   file writes ONE step-50 `PUBLISH` checkpoint with the summed row count.
   The refactor writes one checkpoint per branch (STEP_NOs 50, 60, ... in
   order) with that branch's count, plus a per-branch helper36 summary line
   instead of the single `step 50 PUBLISH` line. Total published rows are
   recoverable by summing the branch counts; there is no longer a single
   combined publish row.
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
6. **Scope.** FSS `m_Tgt_C_S_FSS_Pty` only, as part of the all-sources
   step-driver package. No other source or mapping was touched; the
   current main file was not modified.
