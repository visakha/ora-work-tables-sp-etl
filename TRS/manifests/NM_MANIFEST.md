# NM Manifest — m_Tgt_C_S_TRS_Pty_Nm, config-driven step-driver refactor (TRS)

Prefix: `TRS_NM` (short: `NM`). Workflow: `wf_TRS_Stage_Load_1_Ongoing`.
Baseline (read-only, never modified): `snowflake_multisource/TRS/mappings/sp_snow_main_m_Tgt_C_S_TRS_Pty_Nm.sql`.
Driver file: `drivers/driver_sp_snow_main_m_Tgt_C_S_TRS_Pty_Nm.sql`.

## Driver

Signature (IDENTICAL to the current main, verified by normalised comparison):

```sql
sp_snow_main_m_Tgt_C_S_TRS_Pty_Nm (

    P_MEMBER_NAME_TYPE_CODE VARCHAR DEFAULT '002',
    P_JOB_RUN_ID            VARCHAR DEFAULT NULL

) RETURNS VARCHAR
```

Driver behaviour: job-run-id generation exactly as now + `sp_etl_job_begin`;
one config GATHER (nested `BEGIN/EXCEPTION`, defaults stand on failure) from
`COMMON.ETL_RUN_CONFIG_TBL` (`WORKFLOW_NAME = 'wf_TRS_Stage_Load_1_Ongoing'`,
`MAPPING_NAME = 'm_Tgt_C_S_TRS_Pty_Nm'`); driver-row `STEP_NO = 0` = `'N'` skips the
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
| 10 | `sp_snow_step_TRS_NM_S10_SRC` | TRANSFORM | `ALIAS_SRC` | `WRK_TRS_NM_S10_SRC` | (base tables only) | — | none |
| 20 | `sp_snow_step_TRS_NM_S20_NAMED` | TRANSFORM | `NAMED_FILTERED` | `WRK_TRS_NM_S20_NAMED` | WRK_TRS_NM_S10_SRC | 10 | none |
| 30 | `sp_snow_step_TRS_NM_S30_STD` | TRANSFORM | `STANDARDISED` | `WRK_TRS_NM_S30_STD` | WRK_TRS_NM_S20_NAMED | 20 | none |
| 40 | `sp_snow_step_TRS_NM_S40_DEDUP` | TRANSFORM | `DEDUP_KEYED` | `WRK_TRS_NM_S40_DEDUP` | WRK_TRS_NM_S30_STD | 30 | P_MEMBER_NAME_TYPE_CODE |

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

Step files: `steps/sp_snow_step_TRS_NM_S<nn>_<NAME>.sql` (4 files).

## Publish branches

Original publish was one step 50 with 1 INSERTs in one transaction. Each
INSERT is now one branch proc, called by the driver inside ONE transaction
in the same order, checkpointed by the driver only after COMMIT. All
branches stay inside a SINGLE Publish subgraph in the diagram below;
spine / status / exception groups are distinguished by label prefixes
inside that subgraph, never by splitting the transaction.

| STEP_NO | Proc | Kind | Target | Consumes | DEPENDENT_ON | Original params used |
|---|---|---|---|---|---|---|
| 50 | `sp_snow_pub_TRS_NM_C_S_TRS_PTY_NM` | SPINE | `C_S_TRS_PTY_NM` | WRK_TRS_NM_S40_DEDUP | 40 | P_MEMBER_NAME_TYPE_CODE |

Branch proc signatures: the branch INSERT's used original params (in
original order) + `P_JOB_RUN_ID VARCHAR DEFAULT NULL` +
`P_RUN_TS TIMESTAMP_NTZ DEFAULT NULL` +
`P_INPUT_TABLES VARCHAR DEFAULT '<consumes default>'`. Each returns
`SQLROWCOUNT` as `NUMBER`. No transaction control, no checkpoint calls.
Driver checkpoint STEP_NAMEs are the `PUBLISH_*` names in the table above.

Branch files: `publish/sp_snow_pub_TRS_NM_<TARGET>[_<BRANCH>].sql` (1 files).

## Preserved quirks (verbatim substance from the current main header)

(kept deliberately, do not "fix" silently)
  * Insert-only, as in the original Snowflake code: no TRUNCATE, no
    DELETE of the target.  IDQ truncates C_S_TRS_PTY_NM; the
    Snowflake version instead skips keys already present (the
    existing-key guard in the publish step) and keeps the latest
    CREATE_DT per key in this run, whereas IDQ keeps the first that
    arrives and the database rejects the rest.  A re-run therefore
    inserts nothing twice, but it also does not remove rows that IDQ
    would have truncated away -- see the User Guide, "Parity gaps".
  * Prefix / suffix standardisation values are NULL, as in the
    original: the name mapplet's source-system input is not linked
    in this mapping, so its prefix/suffix lookups (keyed on the
    source system) never match.  Preserved, not repaired -- repairing
    it would change which names load.
  * VERSION_SEQ is hard-coded to 1 (the consolidation rank is
    commented out in IDQ); PERIOD_START_DATE = CREATE_DT (the
    PERIOD_START_DATE_OUT carry-forward, which in IDQ always equals
    the current row's CREATE_DT); PERIOD_END_DATE and
    PERIOD_REFERENCE_TIME are NULL (unfed ports).
  * ROWID_OBJECT, DELETED_*, UPDATED_BY, CREATOR and HUB_STATE_IND
    are NULL (unfed ports), as in the original.

## Verification performed (no live Snowflake available)

- Step CTAS compared to the current file after whitespace normalisation
  and the allowed substitutions only (`:l_run_ts` -> `:P_RUN_TS`,
  `:c_mapping` -> the local constant of the same value): all MATCH.
- Branch INSERTs compared likewise: all MATCH.
- Driver name/signature compared to the current main (normalised): IDENTICAL.
- Counts: 1 driver + 4 step procs + 1 branch procs, covering all 4
  current steps and all 1 current publish INSERTs exactly once.
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
        F["Step 10 ALIAS_SRC"] --> G["Step 20 NAMED_FILTERED"] --> H["Step 30 STANDARDISED"] --> I["Step 40 DEDUP_KEYED"]
    end
    subgraph P5["Phase 5 - Publish"]
        direction TB
        J["Branch 50 SPINE C_S_TRS_PTY_NM"]
    end
    subgraph P6["Phase 6 - Close"]
        direction TB
        K["Job end"] --> L["Work tables left standing"] --> M["RETURN summary"]
    end
    P1 --> P2
    P2 --> P3
    P3 --> P4
    P4 --> P5
    P5 --> P6
```
