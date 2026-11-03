# TOA Manifest — m_Tgt_C_S_TRS_Pty_Rle_TOA, config-driven step-driver refactor (TRS)

Prefix: `TRS_TOA` (short: `TOA`). Workflow: `wf_TRS_Stage_Load_1_Ongoing`.
Baseline (read-only, never modified): `snowflake_multisource/TRS/mappings/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_TOA.sql`.
Driver file: `drivers/driver_sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_TOA.sql`.

## Driver

Signature (IDENTICAL to the current main, verified by normalised comparison):

```sql
sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_TOA (

    P_JOB_RUN_ID  VARCHAR DEFAULT NULL

) RETURNS VARCHAR
```

Driver behaviour: job-run-id generation exactly as now + `sp_etl_job_begin`;
one config GATHER (nested `BEGIN/EXCEPTION`, defaults stand on failure) from
`COMMON.ETL_RUN_CONFIG_TBL` (`WORKFLOW_NAME = 'wf_TRS_Stage_Load_1_Ongoing'`,
`MAPPING_NAME = 'm_Tgt_C_S_TRS_Pty_Rle_TOA'`); driver-row `STEP_NO = 0` = `'N'` skips the
whole mapping BEFORE step 5 cleanup (SKIPPED checkpoint `MAPPING_SKIPPED`,
`sp_etl_job_finish` with a skipped message, early RETURN); step 5 cleanup
unchanged (4 bare `DROP TABLE IF EXISTS`, no checkpoint); conditional step
calls in order; ONE publish transaction calling the enabled branch procs in
order; branch checkpoints ONLY after `COMMIT`; `TERMINATING` via
`sp_etl_job_finish` with the same message style and RETURN format as now;
exception block identical in shape (ROLLBACK + TERMINATING `JOB_END`
FAILED checkpoint in the 10-argument form + `sp_etl_job_fail` + RAISE).

## Steps

| STEP_NO | Proc | Kind | Checkpoint STEP_NAME | Produces | Consumes default | DEPENDENT_ON | Original params used |
|---|---|---|---|---|---|---|---|
| 10 | `sp_snow_step_TRS_TOA_S10_RAW` | TRANSFORM | `TOA_SRC_RANKED` | `WRK_TRS_TOA_S10_RAW` | (base tables only) | — | none |
| 20 | `sp_snow_step_TRS_TOA_S20_LATEST` | TRANSFORM | `TOA_LATEST` | `WRK_TRS_TOA_S20_SRC` | WRK_TRS_TOA_S10_RAW | 10 | none |
| 30 | `sp_snow_step_TRS_TOA_S30_KEYED` | TRANSFORM | `TOA_KEYED` | `WRK_TRS_TOA_S30_KEYED` | WRK_TRS_TOA_S20_SRC | 20 | none |
| 40 | `sp_snow_step_TRS_TOA_S40_RANKED` | TRANSFORM | `TOA_RANKED` | `WRK_TRS_TOA_S40_RANKED` | WRK_TRS_TOA_S30_KEYED | 30 | none |

Step proc signatures: the step's used original params (in original order) +
`P_JOB_RUN_ID VARCHAR DEFAULT NULL` + `P_RUN_TS TIMESTAMP_NTZ DEFAULT NULL`
+ `P_INPUT_TABLES VARCHAR DEFAULT '<consumes default>'`. Every step proc
returns `NUMBER` (row count), writes its own checkpoint in the 10-argument
form (`P_SOURCE, P_JOB_RUN_ID, P_WORKFLOW_NAME, P_MAPPING_NAME, P_STATE,
P_STEP_NAME, P_STEP_STATUS, P_TARGET_TABLE, P_MESSAGE, P_ERROR_MESSAGE`),
has no exception block, no transaction, no target write, and starts with
the work-table existence check (skipped when `P_INPUT_TABLES` is
NULL/empty; the probe surfaces the native missing-table error because
RAISE cannot carry a dynamic table name). `P_INPUT_TABLES` is a dependency
declaration + runtime check, NOT dynamic SQL — each CTAS still names its
source work table literally.

Step files: `steps/sp_snow_step_TRS_TOA_S<nn>_<NAME>.sql` (4 files).

## Publish branches

Original publish was one step 50 with 3 INSERTs in one transaction. Each
INSERT is now one branch proc, called by the driver inside ONE transaction
in the same order, checkpointed by the driver only after COMMIT. All
branches stay inside a SINGLE Publish subgraph in the diagram below;
spine / status / exception groups are distinguished by label prefixes
inside that subgraph, never by splitting the transaction.

| STEP_NO | Proc | Kind | Target | Consumes | DEPENDENT_ON | Original params used |
|---|---|---|---|---|---|---|
| 50 | `sp_snow_pub_TRS_TOA_EXC_STG_BAD_REC_MEMB_BAD_VALUE` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` | WRK_TRS_TOA_S40_RANKED | 40 | none |
| 60 | `sp_snow_pub_TRS_TOA_EXC_STG_BAD_REC_MEMB_DATES` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` | WRK_TRS_TOA_S40_RANKED | 40 | none |
| 70 | `sp_snow_pub_TRS_TOA_C_S_TRS_PTY_RLE_TOA` | SPINE | `C_S_TRS_PTY_RLE_TOA` | WRK_TRS_TOA_S40_RANKED | 40 | none |

Branch proc signatures: the branch INSERT's used original params (in
original order) + `P_JOB_RUN_ID VARCHAR DEFAULT NULL` +
`P_RUN_TS TIMESTAMP_NTZ DEFAULT NULL` +
`P_INPUT_TABLES VARCHAR DEFAULT '<consumes default>'`. Each returns
`SQLROWCOUNT` as `NUMBER`. No transaction control, no checkpoint calls.
Driver checkpoint STEP_NAMEs are the `PUBLISH_*` names in the table above.

Branch files: `publish/sp_snow_pub_TRS_TOA_<TARGET>[_<BRANCH>].sql` (3 files).

## Preserved quirks (verbatim substance from the current main header)

(kept deliberately, do not "fix" silently)
  * Insert-only, as in the original Snowflake code: no TRUNCATE, no
    DELETE of the targets.  IDQ truncates C_S_TRS_PTY_RLE_TOA; the
    Snowflake version instead skips keys already present (the uq_*
    flags in step 40).  A re-run therefore inserts nothing twice,
    but it also does not remove rows that IDQ would have truncated
    away -- see the User Guide, "Parity gaps".
  * The Bad_Value exception row writes the looked-up EXCEPTION_CODE
    for 'Invalid_TOA', which is NULL when that code is not configured
    in EXC_LOOKUP_CODE_VALUE -- preserved, not defaulted.  The date
    exception row writes the computed code
    'Period_Start_Date_>_Period_End_Date'.
  * The original source carries only the MCI_EDG_INDV branch
    (SRC_TBL = 'MCI_EDG_INDV', decoded to source 'TIERS'); the
    LTSS_ELIG_PER / 'DADS' branch of the IDQ mapping is not present
    in the Snowflake original, and the DECODE that would map it is
    kept verbatim (it can never fire on this branch alone).
  * VERSION_SEQ is the source ROW_NUMBER() kept only where it equals
    1, i.e. always 1 in the published rows; PERIOD_START_DATE /
    EFF_STRT_DT = BEGIN_DT, PERIOD_END_DATE / EFF_END_DT = END_DT;
    PERIOD_REFERENCE_TIME is NULL (unfed port).
  * ROWID_OBJECT, DELETED_*, UPDATED_BY, CREATOR and HUB_STATE_IND
    are NULL (unfed ports), as in the original.

## Verification performed (no live Snowflake available)

- Step CTAS compared to the current file after whitespace normalisation
  and the allowed substitutions only (`:l_run_ts` -> `:P_RUN_TS`,
  `:c_mapping` -> the local constant of the same value): all MATCH.
- Branch INSERTs compared likewise: all MATCH.
- Driver name/signature compared to the current main (normalised): IDENTICAL.
- Counts: 1 driver + 4 step procs + 3 branch procs, covering all 4
  current steps and all 3 current publish INSERTs exactly once.
- Style greps: 0 `DROPPED` checkpoint calls, 0 `P_RESUME_STEP`,
  0 cursors in code, 0 `sp_etl_checkpoint` calls and 0 transaction
  statements in publish-branch code, 0 checkpoint calls between the
  driver's `BEGIN TRANSACTION` and `COMMIT`, `TRANSIENT` work tables
  only with unchanged names, `P_JOB_RUN_ID` in every new proc.
- No live Snowflake compile, run, or row-count parity run was possible
  in this environment; that step is required before use.

## Phase-flow diagram

```mermaid
flowchart LR
    subgraph P1["Phase 1 - Begin"]
        direction TB
        A["Generate run id"] --> B["Job begin"]
    end
    subgraph P2["Phase 2 - Configure"]
        direction TB
        C["Config gather"] --> D["Driver gate"]
    end
    subgraph P3["Phase 3 - Clean"]
        direction TB
        E["Step 5 cleanup"]
    end
    subgraph P4["Phase 4 - Transform"]
        direction TB
        F["Step 10 TOA_SRC_RANKED"] --> G["Step 20 TOA_LATEST"] --> H["Step 30 TOA_KEYED"] --> I["Step 40 TOA_RANKED"]
    end
    subgraph P5["Phase 5 - Publish"]
        direction TB
        J["Branch 50 EXCEPTION EXC_STG_BAD_REC_MEMB"] --> K["Branch 60 EXCEPTION EXC_STG_BAD_REC_MEMB"] --> L["Branch 70 SPINE C_S_TRS_PTY_RLE_TOA"]
    end
    subgraph P6["Phase 6 - Close"]
        direction TB
        M["Job end"] --> N["Work tables left standing"] --> O["RETURN summary"]
    end
    P1 --> P2
    P2 --> P3
    P3 --> P4
    P4 --> P5
    P5 --> P6
```
