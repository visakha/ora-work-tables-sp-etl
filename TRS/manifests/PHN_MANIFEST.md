# PHN Manifest — m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr, config-driven step-driver refactor (TRS)

Prefix: `TRS_PHN` (short: `PHN`). Workflow: `wf_TRS_Stage_Load_1_Ongoing`.
Baseline (read-only, never modified): `snowflake_multisource/TRS/mappings/sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr.sql`.
Driver file: `drivers/driver_sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr.sql`.

## Driver

Signature (IDENTICAL to the current main, verified by normalised comparison):

```sql
sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr (

    P_JOB_RUN_ID             VARCHAR DEFAULT NULL

) RETURNS VARCHAR
```

Driver behaviour: job-run-id generation exactly as now + `sp_etl_job_begin`;
one config GATHER (nested `BEGIN/EXCEPTION`, defaults stand on failure) from
`COMMON.ETL_RUN_CONFIG_TBL` (`WORKFLOW_NAME = 'wf_TRS_Stage_Load_1_Ongoing'`,
`MAPPING_NAME = 'm_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr'`); driver-row `STEP_NO = 0` = `'N'` skips the
whole mapping BEFORE step 5 cleanup (SKIPPED checkpoint `MAPPING_SKIPPED`,
`sp_etl_job_finish` with a skipped message, early RETURN); step 5 cleanup
unchanged (7 bare `DROP TABLE IF EXISTS`, no checkpoint); conditional step
calls in order; ONE publish transaction calling the enabled branch procs in
order; branch checkpoints ONLY after `COMMIT`; `TERMINATING` via
`sp_etl_job_finish` with the same message style and RETURN format as now;
exception block identical in shape (ROLLBACK + TERMINATING `JOB_END`
FAILED checkpoint in the 10-argument form + `sp_etl_job_fail` + RAISE).

## Steps

| STEP_NO | Proc | Kind | Checkpoint STEP_NAME | Produces | Consumes default | DEPENDENT_ON | Original params used |
|---|---|---|---|---|---|---|---|
| 10 | `sp_snow_step_TRS_PHN_S10_SRC` | TRANSFORM | `SRC_CASE_DELTA` | `WRK_TRS_PHN_S1_SRC` | (base tables only) | — | none |
| 20 | `sp_snow_step_TRS_PHN_S20_SLOTS` | TRANSFORM | `PHONE_SLOTS` | `WRK_TRS_PHN_S2_SLOTS` | WRK_TRS_PHN_S1_SRC | 10 | none |
| 30 | `sp_snow_step_TRS_PHN_S30_CHECKED` | TRANSFORM | `PHONES_CHECKED` | `WRK_TRS_PHN_S3_CHECKED` | WRK_TRS_PHN_S2_SLOTS | 20 | none |
| 40 | `sp_snow_step_TRS_PHN_S40_PHONES` | TRANSFORM | `PHONES` | `WRK_TRS_PHN_S4_PHONES` | WRK_TRS_PHN_S3_CHECKED | 30 | none |
| 50 | `sp_snow_step_TRS_PHN_S50_VERSIONS` | TRANSFORM | `PHN_VERSIONS` | `WRK_TRS_PHN_S5_VERSIONS` | WRK_TRS_PHN_S4_PHONES | 40 | none |
| 60 | `sp_snow_step_TRS_PHN_S60_EMAILS` | TRANSFORM | `EMAILS_CHECKED` | `WRK_TRS_PHN_S6_EMAILS` | WRK_TRS_PHN_S1_SRC | 10 | none |
| 70 | `sp_snow_step_TRS_PHN_S70_EADDR` | TRANSFORM | `EADDR_VERSIONS` | `WRK_TRS_PHN_S7_VERSIONS` | WRK_TRS_PHN_S6_EMAILS | 60 | none |

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

Step files: `steps/sp_snow_step_TRS_PHN_S<nn>_<NAME>.sql` (7 files).

## Publish branches

Original publish was one step 80 with 4 INSERTs in one transaction. Each
INSERT is now one branch proc, called by the driver inside ONE transaction
in the same order, checkpointed by the driver only after COMMIT. All
branches stay inside a SINGLE Publish subgraph in the diagram below;
spine / status / exception groups are distinguished by label prefixes
inside that subgraph, never by splitting the transaction.

| STEP_NO | Proc | Kind | Target | Consumes | DEPENDENT_ON | Original params used |
|---|---|---|---|---|---|---|
| 80 | `sp_snow_pub_TRS_PHN_C_S_TRS_PTY_RLE_PHN` | SPINE | `C_S_TRS_PTY_RLE_PHN` | WRK_TRS_PHN_S5_VERSIONS | 50 | none |
| 90 | `sp_snow_pub_TRS_PHN_EXC_STG_BAD_REC_MEMB_PHONE` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` | WRK_TRS_PHN_S4_PHONES | 40 | none |
| 100 | `sp_snow_pub_TRS_PHN_C_S_TRS_PTY_RLE_EADDR` | SPINE | `C_S_TRS_PTY_RLE_EADDR` | WRK_TRS_PHN_S7_VERSIONS | 70 | none |
| 110 | `sp_snow_pub_TRS_PHN_EXC_STG_BAD_REC_MEMB_EMAIL` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` | WRK_TRS_PHN_S6_EMAILS | 60 | none |

Branch proc signatures: the branch INSERT's used original params (in
original order) + `P_JOB_RUN_ID VARCHAR DEFAULT NULL` +
`P_RUN_TS TIMESTAMP_NTZ DEFAULT NULL` +
`P_INPUT_TABLES VARCHAR DEFAULT '<consumes default>'`. Each returns
`SQLROWCOUNT` as `NUMBER`. No transaction control, no checkpoint calls.
Driver checkpoint STEP_NAMEs are the `PUBLISH_*` names in the table above.

Branch files: `publish/sp_snow_pub_TRS_PHN_<TARGET>[_<BRANCH>].sql` (4 files).

## Preserved quirks (verbatim substance from the current main header)

(kept deliberately, do not "fix" silently)
  * Insert-only, as in the original Snowflake code: no TRUNCATE, no
    DELETE of targets.  IDQ truncates C_S_TRS_PTY_RLE_PHN and
    C_S_TRS_PTY_RLE_EADDR; the Snowflake version instead skips keys
    already present (uq_tgt).  A re-run therefore inserts nothing
    twice, but it also does not remove rows that IDQ would have
    truncated away.
  * The stored source filter rownum < 100000 is NOT applied here,
    exactly as in the original Snowflake code (it was not part of the
    custom query).  Confirm whether it should be (BR notes, Verify
    item 2).
  * Inside the phone normalizer, the three rule instances get ONLY
    the phone: their SRC_SYS and USG_TP inputs are not linked, so the
    TRS / main-number toll-free check of the rule never runs here.
  * The work phone is fed as "number extension"; the rule removes
    the space and its string(10) port keeps the first ten characters,
    so the extension is dropped and the number itself is validated
    and written.  Preserved.
  * The exception work-phone split in the original final SELECT
    compares usg_tp to 'Work', while the phone branch's usg_tp values
    are '001' / '002' / '003', so exc_work_phone is always NULL in
    the original -- preserved, not "corrected" to a pref_lvl test.
  * Unfed ports written as NULL: ROWID_OBJECT, DELETED_*, UPDATED_BY,
    CREATOR, HUB_STATE_IND, and USG_TP on the e-mail target.
  * Email consolidation: the version sequence is the COUNT of
    distinct versions of the key, and the aggregator keeps the LAST
    row of the key, so VERSION_SEQ = number of distinct versions.
    PERIOD_END_DATE is NULL (its port is not fed).

## Verification performed (no live Snowflake available)

- Step CTAS compared to the current file after whitespace normalisation
  and the allowed substitutions only (`:l_run_ts` -> `:P_RUN_TS`,
  `:c_mapping` -> the local constant of the same value): all MATCH.
- Branch INSERTs compared likewise: all MATCH.
- Driver name/signature compared to the current main (normalised): IDENTICAL.
- Counts: 1 driver + 7 step procs + 4 branch procs, covering all 7
  current steps and all 4 current publish INSERTs exactly once.
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
    subgraph P4["Phase 4 - Transform Phone"]
        direction TB
        F["Step 10 SRC_CASE_DELTA"] --> G["Step 20 PHONE_SLOTS"] --> H["Step 30 PHONES_CHECKED"] --> I["Step 40 PHONES"] --> J["Step 50 PHN_VERSIONS"]
    end
    subgraph P5["Phase 5 - Transform Email"]
        direction TB
        K["Step 60 EMAILS_CHECKED"] --> L["Step 70 EADDR_VERSIONS"]
    end
    subgraph P6["Phase 6 - Publish"]
        direction TB
        M["Branch 80 SPINE C_S_TRS_PTY_RLE_PHN"] --> N["Branch 90 EXCEPTION EXC_STG_BAD_REC_MEMB"] --> O["Branch 100 SPINE C_S_TRS_PTY_RLE_EADDR"] --> P["Branch 110 EXCEPTION EXC_STG_BAD_REC_MEMB"]
    end
    subgraph P7["Phase 7 - Close"]
        direction TB
        Q["Job end"] --> R["Work tables left standing"] --> S["RETURN summary"]
    end
    P1 --> P2
    P2 --> P3
    P3 --> P4
    P4 --> P5
    P5 --> P6
    P6 --> P7
```
