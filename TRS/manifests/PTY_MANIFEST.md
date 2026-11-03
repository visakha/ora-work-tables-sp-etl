# PTY Manifest — m_Tgt_C_S_TRS_Pty_OnGoing, config-driven step-driver refactor (TRS)

Prefix: `TRS_PTY` (short: `PTY`). Workflow: `wf_TRS_Stage_Load_1_Ongoing`.
Baseline (read-only, never modified): `snowflake_multisource/TRS/mappings/sp_snow_main_m_Tgt_C_S_TRS_Pty_OnGoing.sql`.
Driver file: `drivers/driver_sp_snow_main_m_Tgt_C_S_TRS_Pty_OnGoing.sql`.

## Driver

Signature (IDENTICAL to the current main, verified by normalised comparison):

```sql
sp_snow_main_m_Tgt_C_S_TRS_Pty_OnGoing (

    P_PTY_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Indv',
    P_RLE_BO_CLASS_CD_MEMBER VARCHAR DEFAULT 'Member',
    P_DC_INDV_TBL_SRC        VARCHAR DEFAULT 'DC_INDV',
    P_MCI_TBL_SRC            VARCHAR DEFAULT 'MCI',
    P_JOB_RUN_ID             VARCHAR DEFAULT NULL

) RETURNS VARCHAR
```

Driver behaviour: job-run-id generation exactly as now + `sp_etl_job_begin`;
one config GATHER (nested `BEGIN/EXCEPTION`, defaults stand on failure) from
`COMMON.ETL_RUN_CONFIG_TBL` (`WORKFLOW_NAME = 'wf_TRS_Stage_Load_1_Ongoing'`,
`MAPPING_NAME = 'm_Tgt_C_S_TRS_Pty_OnGoing'`); driver-row `STEP_NO = 0` = `'N'` skips the
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
| 10 | `sp_snow_step_TRS_PTY_S10_SRC` | TRANSFORM | `SRC_VALID_LIST` | `WRK_TRS_PTY_S1_SRC` | (base tables only) | — | P_DC_INDV_TBL_SRC, P_MCI_TBL_SRC |
| 20 | `sp_snow_step_TRS_PTY_S20_DQ` | TRANSFORM | `DQ_STANDARDISE_VALIDATE` | `WRK_TRS_PTY_S2_DQ` | WRK_TRS_PTY_S1_SRC | 10 | P_DC_INDV_TBL_SRC |
| 30 | `sp_snow_step_TRS_PTY_S30_ROUTER` | TRANSFORM | `ROUTER_EXCEPTIONS` | `WRK_TRS_PTY_S3_ROUTER` | WRK_TRS_PTY_S2_DQ | 20 | none |
| 40 | `sp_snow_step_TRS_PTY_S40_DEDUP` | TRANSFORM | `DEDUP_VALID` | `WRK_TRS_PTY_S4_DEDUP` | WRK_TRS_PTY_S2_DQ | 20 | P_RLE_BO_CLASS_CD_MEMBER |

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

Step files: `steps/sp_snow_step_TRS_PTY_S<nn>_<NAME>.sql` (4 files).

## Publish branches

Original publish was one step 50 with 9 INSERTs in one transaction. Each
INSERT is now one branch proc, called by the driver inside ONE transaction
in the same order, checkpointed by the driver only after COMMIT. All
branches stay inside a SINGLE Publish subgraph in the diagram below;
spine / status / exception groups are distinguished by label prefixes
inside that subgraph, never by splitting the transaction.

| STEP_NO | Proc | Kind | Target | Consumes | DEPENDENT_ON | Original params used |
|---|---|---|---|---|---|---|
| 50 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_NAME` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` | WRK_TRS_PTY_S3_ROUTER | 30 | none |
| 60 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_GENDER` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` | WRK_TRS_PTY_S3_ROUTER | 30 | none |
| 70 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_DEATH` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` | WRK_TRS_PTY_S3_ROUTER | 30 | none |
| 80 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` | WRK_TRS_PTY_S3_ROUTER | 30 | none |
| 90 | `sp_snow_pub_TRS_PTY_C_S_TRS_PTY` | SPINE | `C_S_TRS_PTY` | WRK_TRS_PTY_S4_DEDUP | 40 | P_PTY_BO_CLASS_CD_MEMBER |
| 100 | `sp_snow_pub_TRS_PTY_C_S_TRS_PTY_RLE` | SPINE | `C_S_TRS_PTY_RLE` | WRK_TRS_PTY_S4_DEDUP | 40 | P_RLE_BO_CLASS_CD_MEMBER |
| 110 | `sp_snow_pub_TRS_PTY_STG_TRS_VALID_MEMBERS` | SPINE | `STG_TRS_VALID_MEMBERS` | WRK_TRS_PTY_S4_DEDUP | 40 | none |
| 120 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_RACE` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` | WRK_TRS_PTY_S4_DEDUP | 40 | none |
| 130 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` | WRK_TRS_PTY_S4_DEDUP | 40 | none |

Branch proc signatures: the branch INSERT's used original params (in
original order) + `P_JOB_RUN_ID VARCHAR DEFAULT NULL` +
`P_RUN_TS TIMESTAMP_NTZ DEFAULT NULL` +
`P_INPUT_TABLES VARCHAR DEFAULT '<consumes default>'`. Each returns
`SQLROWCOUNT` as `NUMBER`. No transaction control, no checkpoint calls.
Driver checkpoint STEP_NAMEs are the `PUBLISH_*` names in the table above.

Branch files: `publish/sp_snow_pub_TRS_PTY_<TARGET>[_<BRANCH>].sql` (9 files).

## Preserved quirks (verbatim substance from the current main header)

(kept deliberately, do not "fix" silently)
  * Insert-only, as in the original Snowflake code: no TRUNCATE, no
    DELETE of targets.  IDQ truncates C_S_TRS_PTY / C_S_TRS_PTY_RLE;
    the Snowflake version instead skips keys already present
    (uq_pty / uq_rle / uq_exc_* guards).  A re-run therefore inserts
    nothing twice, but it also does not remove rows that IDQ would
    have truncated away -- see the User Guide, "Parity gaps".
  * The stored source filter INDV_ID = 504937068 is NOT applied here,
    exactly as in the original Snowflake code (it was not part of the
    custom query).  Confirm in the live IDQ mapping whether it should
    be (BR notes, Verify item 1).
  * VERSION_SEQ is hard-coded to 1 (TIMELINE: the MD5 / version
    comparison is commented out in IDQ); PERIOD_END_DATE,
    PERIOD_REFERENCE_TIME and TIMELINE_ACTION are NULL (unfed ports).
  * HUB_STATE_IND, UPDATED_BY, CREATE_DATE, CREATOR, FLAG_SRC and
    ROWID_OBJECT / DELETED_* are NULL (unfed ports), as in the original.

## Verification performed (no live Snowflake available)

- Step CTAS compared to the current file after whitespace normalisation
  and the allowed substitutions only (`:l_run_ts` -> `:P_RUN_TS`,
  `:c_mapping` -> the local constant of the same value): all MATCH.
- Branch INSERTs compared likewise: all MATCH.
- Driver name/signature compared to the current main (normalised): IDENTICAL.
- Counts: 1 driver + 4 step procs + 9 branch procs, covering all 4
  current steps and all 9 current publish INSERTs exactly once.
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
    subgraph P4["Phase 4 - Transform Snapshot"]
        direction TB
        F["Step 10 SRC_VALID_LIST"]
    end
    subgraph P5["Phase 5 - Transform Validate"]
        direction TB
        G["Step 20 DQ_STANDARDISE_VALIDATE"] --> H["Step 30 ROUTER_EXCEPTIONS"] --> I["Step 40 DEDUP_VALID"]
    end
    subgraph P6["Phase 6 - Publish"]
        direction TB
        J["Branch 50 EXCEPTION EXC_STG_BAD_REC_MEMB"] --> K["Branch 60 EXCEPTION EXC_STG_BAD_REC_MEMB"] --> L["Branch 70 EXCEPTION EXC_STG_BAD_REC_MEMB"] --> M["Branch 80 EXCEPTION EXC_STG_BAD_REC_MEMB"] --> N["Branch 90 SPINE C_S_TRS_PTY"] --> O["Branch 100 SPINE C_S_TRS_PTY_RLE"] --> P["Branch 110 SPINE STG_TRS_VALID_MEMBERS"] --> Q["Branch 120 EXCEPTION EXC_STG_BAD_REC_MEMB"] --> R["Branch 130 EXCEPTION EXC_STG_BAD_REC_MEMB"]
    end
    subgraph P7["Phase 7 - Close"]
        direction TB
        S["Job end"] --> T["Work tables left standing"] --> U["RETURN summary"]
    end
    P1 --> P2
    P2 --> P3
    P3 --> P4
    P4 --> P5
    P5 --> P6
    P6 --> P7
```
