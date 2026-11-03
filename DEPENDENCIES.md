# Dependencies — all sources (modular step drivers, v2.1 style)

One section per source. Produces / Consumes are the pipe-delimited work-table strings from the config seeds and each proc's P_INPUT_TABLES default. Dependencies live here, in the seeds, and in l_in_* variables — never in flag names. The toggle contract from the README applies throughout: the driver does NOT validate flag consistency; step 5 drops ALL work tables regardless of flags.

## ECI

# ECI step-driver dependencies — `wf_ECI_Stage_Load`

> **v2 note:** driver flag variables were renamed from numbers to unit names
> (`l_flag_30` → `l_flag_ECI_PTY_S30_DQ`, `l_flag_100` →
> `l_flag_ECI_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY`; same rule for `l_in_*`
> and `l_pub_*`). The `STEP_NO` column below is unchanged — it is still the
> config-table address for each unit and the seed key. Checkpoint
> `STEP_NAME` strings are also unchanged. What changed in v2 is the
> checkpoint *call*: 10 positional parameters (SOURCE, JOB_RUN_ID,
> WORKFLOW_NAME, MAPPING_NAME, STATE, STEP_NAME, STEP_STATUS,
> TARGET_TABLE, MESSAGE, ERROR_MESSAGE) — checkpoint rows no longer carry
> step numbers, row counts, or work-table actions (see the package README
> for the lossy-simplification statement).

One section per mapping. `Produces` / `Consumes` are the pipe-delimited work-table strings verbatim from the config seed and from each proc's `P_INPUT_TABLES` default. `Depends on` is the producing STEP_NO for each consumed work table. Publish branches produce nothing (`WORK_TABLES_PRODUCED = ''`) and consume the ready table.

## The toggle contract (the user's own rules, verbatim in effect)

- The driver does **NOT** validate flag consistency — if you disable a step, disabling its downstream dependents is **your** job.
- Step 5 drops **ALL** work tables regardless of flags, so a downstream step enabled while its producer is disabled **WILL error on the missing input table** — that is the designed behaviour, not a bug.
- As a user of this table, you only play with the toggle of `IS_RUN_ENABLED`. All other columns are informational for the driver run, except `IS_DRIVER` (gates the whole mapping) and `WORK_TABLES_CONSUMED` (passed as `P_INPUT_TABLES`).
- Only exact `'Y'` runs a step/branch; only exact `'N'` on the driver row (STEP_NO 0) skips the whole mapping. A missing config table, or a missing row, defaults to `'Y'` (everything runs) — the safe default.
- `P_INPUT_TABLES` is a dependency declaration + runtime check, **not** dynamic SQL: Snowflake cannot parameterise table names in static SQL, so each step's CTAS and each branch's INSERT still name their tables literally. The check only proves the declared inputs exist before the SQL runs.

## How to disable a branch (example)

To stop ADR's exception branch only, leaving the spine and DQM branches running:
```sql
UPDATE COMMON.ETL_RUN_CONFIG_TBL SET IS_RUN_ENABLED = 'N'
 WHERE WORKFLOW_NAME = 'wf_ECI_Stage_Load'
   AND MAPPING_NAME = 'm_Tgt_C_S_ECI_Pty_Addr' AND STEP_NO = 80;
```
To stop a whole mapping, set its driver row to `'N'` (STEP_NO = 0). To stop a step, you must also set every downstream step/branch that consumes its output to `'N'` — otherwise the downstream existence check fails the run loudly instead of running on stale data.

## PTY — m_Tgt_C_S_ECI_Pty

Driver: `sp_snow_main_m_Tgt_C_S_ECI_Pty` (STEP_NO 0). Workflow: `wf_ECI_Stage_Load`.

| STEP_NO | Proc | Kind | Produces | Consumes | Depends on | Target / notes |
|---|---|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_ECI_Pty` | DRIVER | _(none)_ | _(none)_ | _(none)_ | Whole mapping; `IS_DRIVER = 'Y'`; `'N'` here skips everything before step 5 |
| 10 | `sp_snow_step_ECI_PTY_S10_SRC` | TRANSFORM | `WRK_ECI_PTY_S10_SRC` | `_(none)_` | _(none — base tables only)_ | Checkpoint `SRC_DELTA_PARTIES` |
| 20 | `sp_snow_step_ECI_PTY_S20_ACTIVE` | TRANSFORM | `WRK_ECI_PTY_S20_ACTIVE` | `WRK_ECI_PTY_S10_SRC` | 10 | Checkpoint `ACTIVE_PARTIES` |
| 30 | `sp_snow_step_ECI_PTY_S30_DQ` | TRANSFORM | `WRK_ECI_PTY_S30_DQ` | `WRK_ECI_PTY_S20_ACTIVE` | 20 | Checkpoint `DQ_RULES` |
| 40 | `sp_snow_step_ECI_PTY_S40_DQ2` | TRANSFORM | `WRK_ECI_PTY_S40_DQ2` | `WRK_ECI_PTY_S30_DQ` | 30 | Checkpoint `DQ_EXCEPTIONS_RESOLVED` |
| 50 | `sp_snow_step_ECI_PTY_S50_READY` | TRANSFORM | `WRK_ECI_PTY_S50_READY` | `WRK_ECI_PTY_S40_DQ2` | 40 | Checkpoint `ROUTED_READY` |
| 60 | `sp_snow_pub_ECI_PTY_C_S_ECI_PTY` | SPINE | _(none)_ | `WRK_ECI_PTY_S50_READY` | 50 | Target `C_S_ECI_PTY`; checkpoint `PUBLISH_C_S_ECI_PTY` |
| 70 | `sp_snow_pub_ECI_PTY_C_S_ECI_PTY_RLE` | SPINE | _(none)_ | `WRK_ECI_PTY_S50_READY` | 50 | Target `C_S_ECI_PTY_RLE`; checkpoint `PUBLISH_C_S_ECI_PTY_RLE` |
| 80 | `sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_GENDER` | EXCEPTION | _(none)_ | `WRK_ECI_PTY_S50_READY` | 50 | Target `EXC_STG_BAD_REC_MEMB`; checkpoint `PUBLISH_EXC_GENDER` |
| 90 | `sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_BIRTH` | EXCEPTION | _(none)_ | `WRK_ECI_PTY_S50_READY` | 50 | Target `EXC_STG_BAD_REC_MEMB`; checkpoint `PUBLISH_EXC_BIRTH` |
| 100 | `sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY` | EXCEPTION | _(none)_ | `WRK_ECI_PTY_S50_READY` | 50 | Target `EXC_STG_BAD_REC_MEMB`; checkpoint `PUBLISH_EXC_ETHNICITY` |
| 110 | `sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_RACE` | EXCEPTION | _(none)_ | `WRK_ECI_PTY_S50_READY` | 50 | Target `EXC_STG_BAD_REC_MEMB`; checkpoint `PUBLISH_EXC_RACE` |
| 120 | `sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE` | EXCEPTION | _(none)_ | `WRK_ECI_PTY_S50_READY` | 50 | Target `EXC_STG_BAD_REC_MEMB`; checkpoint `PUBLISH_EXC_LANGUAGE` |

**Spine / status path (the outcome the user cares about):** step 60 → `C_S_ECI_PTY` (SPINE), step 70 → `C_S_ECI_PTY_RLE` (SPINE).
**Non-spine branches (validation / enrichment / exception writes):** step 80 → `EXC_STG_BAD_REC_MEMB` (EXCEPTION), step 90 → `EXC_STG_BAD_REC_MEMB` (EXCEPTION), step 100 → `EXC_STG_BAD_REC_MEMB` (EXCEPTION), step 110 → `EXC_STG_BAD_REC_MEMB` (EXCEPTION), step 120 → `EXC_STG_BAD_REC_MEMB` (EXCEPTION).

## ADR — m_Tgt_C_S_ECI_Pty_Addr

Driver: `sp_snow_main_m_Tgt_C_S_ECI_Pty_Addr` (STEP_NO 0). Workflow: `wf_ECI_Stage_Load`.

| STEP_NO | Proc | Kind | Produces | Consumes | Depends on | Target / notes |
|---|---|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_ECI_Pty_Addr` | DRIVER | _(none)_ | _(none)_ | _(none)_ | Whole mapping; `IS_DRIVER = 'Y'`; `'N'` here skips everything before step 5 |
| 10 | `sp_snow_step_ECI_ADR_S10_SRC` | TRANSFORM | `WRK_ECI_ADR_S10_SRC` | `_(none)_` | _(none — base tables only)_ | Checkpoint `SRC_ADDRESSES` |
| 20 | `sp_snow_step_ECI_ADR_S20_KEYED` | TRANSFORM | `WRK_ECI_ADR_S20_KEYED` | `WRK_ECI_ADR_S10_SRC` | 10 | Checkpoint `KEYED_ACTIVE` |
| 30 | `sp_snow_step_ECI_ADR_S30_VALIDATED` | TRANSFORM | `WRK_ECI_ADR_S30_VALIDATED` | `WRK_ECI_ADR_S20_KEYED` | 20 | Checkpoint `ADDR_VALIDATION` |
| 40 | `sp_snow_step_ECI_ADR_S40_FLAT` | TRANSFORM | `WRK_ECI_ADR_S40_FLAT` | `WRK_ECI_ADR_S30_VALIDATED` | 30 | Checkpoint `FLAT_VALIDATION` |
| 50 | `sp_snow_step_ECI_ADR_S50_READY` | TRANSFORM | `WRK_ECI_ADR_S50_READY` | `WRK_ECI_ADR_S40_FLAT` | 40 | Checkpoint `SCORED_READY` |
| 60 | `sp_snow_pub_ECI_ADR_DQM_ADDRESS` | VALIDATION | _(none)_ | `WRK_ECI_ADR_S50_READY` | 50 | Target `DQM_ADDRESS`; checkpoint `PUBLISH_DQM_ADDRESS` |
| 70 | `sp_snow_pub_ECI_ADR_C_S_ECI_PTY_RLE_ADDR` | SPINE | _(none)_ | `WRK_ECI_ADR_S50_READY` | 50 | Target `C_S_ECI_PTY_RLE_ADDR`; checkpoint `PUBLISH_C_S_ECI_PTY_RLE_ADDR` |
| 80 | `sp_snow_pub_ECI_ADR_EXC_STG_BAD_REC_MEMB` | EXCEPTION | _(none)_ | `WRK_ECI_ADR_S50_READY` | 50 | Target `EXC_STG_BAD_REC_MEMB`; checkpoint `PUBLISH_EXC_STG_BAD_REC_MEMB` |

**Spine / status path (the outcome the user cares about):** step 70 → `C_S_ECI_PTY_RLE_ADDR` (SPINE).
**Non-spine branches (validation / enrichment / exception writes):** step 60 → `DQM_ADDRESS` (VALIDATION), step 80 → `EXC_STG_BAD_REC_MEMB` (EXCEPTION).

> **ADR note:** step 60 writes `DQM_ADDRESS`, a data-quality-mart output, not a `C_S_*` spine table and not an `EXC_*` table. It is grouped under kind `VALIDATION` for kind purposes only (see README feedback items). It was preserved because the current file contains 3 publish INSERTs, not the 2 the task brief assumed — file wins over brief.

## ALT — m_Tgt_C_S_ECI_Pty_Rle_Alt_Id

Driver: `sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id` (STEP_NO 0). Workflow: `wf_ECI_Stage_Load`.

| STEP_NO | Proc | Kind | Produces | Consumes | Depends on | Target / notes |
|---|---|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id` | DRIVER | _(none)_ | _(none)_ | _(none)_ | Whole mapping; `IS_DRIVER = 'Y'`; `'N'` here skips everything before step 5 |
| 10 | `sp_snow_step_ECI_ALT_S10_SRC` | TRANSFORM | `WRK_ECI_ALT_S10_SRC` | `_(none)_` | _(none — base tables only)_ | Checkpoint `SRC_ALT_IDS` |
| 20 | `sp_snow_step_ECI_ALT_S20_ACTIVE` | TRANSFORM | `WRK_ECI_ALT_S20_ACTIVE` | `WRK_ECI_ALT_S10_SRC` | 10 | Checkpoint `ACTIVE_ALT_IDS` |
| 30 | `sp_snow_step_ECI_ALT_S30_ROUTED` | TRANSFORM | `WRK_ECI_ALT_S30_ROUTED` | `WRK_ECI_ALT_S20_ACTIVE` | 20 | Checkpoint `VALIDATED_ROUTED` |
| 40 | `sp_snow_step_ECI_ALT_S40_READY` | TRANSFORM | `WRK_ECI_ALT_S40_READY` | `WRK_ECI_ALT_S30_ROUTED` | 30 | Checkpoint `READY_TO_PUBLISH` |
| 50 | `sp_snow_pub_ECI_ALT_C_S_ECI_PTY_RLE_ALT_ID` | SPINE | _(none)_ | `WRK_ECI_ALT_S40_READY` | 40 | Target `C_S_ECI_PTY_RLE_ALT_ID`; checkpoint `PUBLISH_C_S_ECI_PTY_RLE_ALT_ID` |
| 60 | `sp_snow_pub_ECI_ALT_EXC_STG_BAD_REC_MEMB_SSN` | EXCEPTION | _(none)_ | `WRK_ECI_ALT_S40_READY` | 40 | Target `EXC_STG_BAD_REC_MEMB`; checkpoint `PUBLISH_EXC_STG_BAD_REC_MEMB_SSN` |
| 70 | `sp_snow_pub_ECI_ALT_EXC_STG_BAD_REC_MEMB_MEDICAID` | EXCEPTION | _(none)_ | `WRK_ECI_ALT_S40_READY` | 40 | Target `EXC_STG_BAD_REC_MEMB`; checkpoint `PUBLISH_EXC_STG_BAD_REC_MEMB_MEDICAID` |

**Spine / status path (the outcome the user cares about):** step 50 → `C_S_ECI_PTY_RLE_ALT_ID` (SPINE).
**Non-spine branches (validation / enrichment / exception writes):** step 60 → `EXC_STG_BAD_REC_MEMB` (EXCEPTION), step 70 → `EXC_STG_BAD_REC_MEMB` (EXCEPTION).

## PHN — m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr

Driver: `sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr` (STEP_NO 0). Workflow: `wf_ECI_Stage_Load`.

| STEP_NO | Proc | Kind | Produces | Consumes | Depends on | Target / notes |
|---|---|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr` | DRIVER | _(none)_ | _(none)_ | _(none)_ | Whole mapping; `IS_DRIVER = 'Y'`; `'N'` here skips everything before step 5 |
| 10 | `sp_snow_step_ECI_PHN_S10_SRC` | TRANSFORM | `WRK_ECI_PHN_S10_SRC` | `_(none)_` | _(none — base tables only)_ | Checkpoint `SRC_PHN_EADDR` |
| 20 | `sp_snow_step_ECI_PHN_S20_ACTIVE` | TRANSFORM | `WRK_ECI_PHN_S20_ACTIVE` | `WRK_ECI_PHN_S10_SRC` | 10 | Checkpoint `ACTIVE_PHN_EADDR` |
| 30 | `sp_snow_step_ECI_PHN_S30_DQ` | TRANSFORM | `WRK_ECI_PHN_S30_DQ` | `WRK_ECI_PHN_S20_ACTIVE` | 20 | Checkpoint `DQ_CLEAN_VALIDATE` |
| 40 | `sp_snow_step_ECI_PHN_S40_ROUTED` | TRANSFORM | `WRK_ECI_PHN_S40_ROUTED` | `WRK_ECI_PHN_S30_DQ` | 30 | Checkpoint `ROUTED_GROUPS` |
| 50 | `sp_snow_step_ECI_PHN_S50_READY` | TRANSFORM | `WRK_ECI_PHN_S50_READY` | `WRK_ECI_PHN_S40_ROUTED` | 40 | Checkpoint `READY_TO_PUBLISH` |
| 60 | `sp_snow_pub_ECI_PHN_C_S_ECI_PTY_RLE_PHN` | SPINE | _(none)_ | `WRK_ECI_PHN_S50_READY` | 50 | Target `C_S_ECI_PTY_RLE_PHN`; checkpoint `PUBLISH_C_S_ECI_PTY_RLE_PHN` |
| 70 | `sp_snow_pub_ECI_PHN_EXC_STG_BAD_REC_MEMB_PHONE` | EXCEPTION | _(none)_ | `WRK_ECI_PHN_S50_READY` | 50 | Target `EXC_STG_BAD_REC_MEMB`; checkpoint `PUBLISH_EXC_STG_BAD_REC_MEMB_PHONE` |
| 80 | `sp_snow_pub_ECI_PHN_C_S_ECI_PTY_RLE_EADDR` | SPINE | _(none)_ | `WRK_ECI_PHN_S50_READY` | 50 | Target `C_S_ECI_PTY_RLE_EADDR`; checkpoint `PUBLISH_C_S_ECI_PTY_RLE_EADDR` |
| 90 | `sp_snow_pub_ECI_PHN_EXC_STG_BAD_REC_MEMB_EMAIL` | EXCEPTION | _(none)_ | `WRK_ECI_PHN_S50_READY` | 50 | Target `EXC_STG_BAD_REC_MEMB`; checkpoint `PUBLISH_EXC_STG_BAD_REC_MEMB_EMAIL` |

**Spine / status path (the outcome the user cares about):** step 60 → `C_S_ECI_PTY_RLE_PHN` (SPINE), step 80 → `C_S_ECI_PTY_RLE_EADDR` (SPINE).
**Non-spine branches (validation / enrichment / exception writes):** step 70 → `EXC_STG_BAD_REC_MEMB` (EXCEPTION), step 90 → `EXC_STG_BAD_REC_MEMB` (EXCEPTION).

## REL — m_Tgt_C_S_ECI_Pty_Rle_Rel

Driver: `sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel` (STEP_NO 0). Workflow: `wf_ECI_Stage_Load`.

| STEP_NO | Proc | Kind | Produces | Consumes | Depends on | Target / notes |
|---|---|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel` | DRIVER | _(none)_ | _(none)_ | _(none)_ | Whole mapping; `IS_DRIVER = 'Y'`; `'N'` here skips everything before step 5 |
| 10 | `sp_snow_step_ECI_REL_S10_SRC` | TRANSFORM | `WRK_ECI_REL_S10_SRC` | `_(none)_` | _(none — base tables only)_ | Checkpoint `SRC_BOTH_DIRECTIONS` |
| 20 | `sp_snow_step_ECI_REL_S20_KEYED` | TRANSFORM | `WRK_ECI_REL_S20_KEYED` | `WRK_ECI_REL_S10_SRC` | 10 | Checkpoint `KEYED_BOTH_ACTIVE` |
| 30 | `sp_snow_step_ECI_REL_S30_TYPED` | TRANSFORM | `WRK_ECI_REL_S30_TYPED` | `WRK_ECI_REL_S20_KEYED` | 20 | Checkpoint `CODED_TRANSLATED` |
| 40 | `sp_snow_step_ECI_REL_S40_READY` | TRANSFORM | `WRK_ECI_REL_S40_READY` | `WRK_ECI_REL_S30_TYPED` | 30 | Checkpoint `READY_TO_PUBLISH` |
| 50 | `sp_snow_pub_ECI_REL_C_S_ECI_PTY_RLE_REL` | SPINE | _(none)_ | `WRK_ECI_REL_S40_READY` | 40 | Target `C_S_ECI_PTY_RLE_REL`; checkpoint `PUBLISH_C_S_ECI_PTY_RLE_REL` |
| 60 | `sp_snow_pub_ECI_REL_EXC_STG_BAD_REC_MEMB` | EXCEPTION | _(none)_ | `WRK_ECI_REL_S40_READY` | 40 | Target `EXC_STG_BAD_REC_MEMB`; checkpoint `PUBLISH_EXC_STG_BAD_REC_MEMB` |

**Spine / status path (the outcome the user cares about):** step 50 → `C_S_ECI_PTY_RLE_REL` (SPINE).
**Non-spine branches (validation / enrichment / exception writes):** step 60 → `EXC_STG_BAD_REC_MEMB` (EXCEPTION).

## VAL — m_Tgt_C_S_ECI_Pty_Validation

Driver: `sp_snow_main_m_Tgt_C_S_ECI_Pty_Validation` (STEP_NO 0). Workflow: `wf_ECI_Stage_Load`.

| STEP_NO | Proc | Kind | Produces | Consumes | Depends on | Target / notes |
|---|---|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_ECI_Pty_Validation` | DRIVER | _(none)_ | _(none)_ | _(none)_ | Whole mapping; `IS_DRIVER = 'Y'`; `'N'` here skips everything before step 5 |
| 10 | `sp_snow_step_ECI_VAL_S10_SRC` | TRANSFORM | `WRK_ECI_VAL_S10_SRC` | `_(none)_` | _(none — base tables only)_ | Checkpoint `SRC_DELTA_PARTIES` |
| 20 | `sp_snow_step_ECI_VAL_S20_ENRICHED` | TRANSFORM | `WRK_ECI_VAL_S20_ENRICHED` | `WRK_ECI_VAL_S10_SRC` | 10 | Checkpoint `ENRICHED_STD_NAMES` |
| 30 | `sp_snow_step_ECI_VAL_S30_ROUTED` | TRANSFORM | `WRK_ECI_VAL_S30_ROUTED` | `WRK_ECI_VAL_S20_ENRICHED` | 20 | Checkpoint `ROUTED_GROUPS` |
| 40 | `sp_snow_pub_ECI_VAL_EXC_STG_BAD_REC_MEMB` | EXCEPTION | _(none)_ | `WRK_ECI_VAL_S30_ROUTED` | 30 | Target `EXC_STG_BAD_REC_MEMB`; checkpoint `PUBLISH_EXC_STG_BAD_REC_MEMB` |
| 50 | `sp_snow_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_DEACTIVATION` | STATUS | _(none)_ | `WRK_ECI_VAL_S30_ROUTED` | 30 | Target `STG_ECI_PTY_INACTIVE_LOG`; checkpoint `PUBLISH_STG_ECI_PTY_INACTIVE_LOG_DEACTIVATION` |
| 60 | `sp_snow_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_STS` | STATUS | _(none)_ | `WRK_ECI_VAL_S30_ROUTED` | 30 | Target `STG_ECI_PTY_INACTIVE_STS`; checkpoint `PUBLISH_STG_ECI_PTY_INACTIVE_STS` |
| 70 | `sp_snow_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_REACTIVATION` | STATUS | _(none)_ | `WRK_ECI_VAL_S30_ROUTED` | 30 | Target `STG_ECI_PTY_INACTIVE_LOG`; checkpoint `PUBLISH_STG_ECI_PTY_INACTIVE_LOG_REACTIVATION` |

**Spine / status path (the outcome the user cares about):** step 50 → `STG_ECI_PTY_INACTIVE_LOG` (STATUS), step 60 → `STG_ECI_PTY_INACTIVE_STS` (STATUS), step 70 → `STG_ECI_PTY_INACTIVE_LOG` (STATUS).
**Non-spine branches (validation / enrichment / exception writes):** step 40 → `EXC_STG_BAD_REC_MEMB` (EXCEPTION).

## RFA — m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr

Driver: `sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr` (STEP_NO 0). Workflow: `wf_ECI_Stage_Load`.

| STEP_NO | Proc | Kind | Produces | Consumes | Depends on | Target / notes |
|---|---|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr` | DRIVER | _(none)_ | _(none)_ | _(none)_ | Whole mapping; `IS_DRIVER = 'Y'`; `'N'` here skips everything before step 5 |
| 10 | `sp_snow_step_ECI_RFA_S10_LATEST` | TRANSFORM | `WRK_ECI_RFA_S10_LATEST` | `_(none)_` | _(none — base tables only)_ | Checkpoint `LATEST_HISTORY_ROWS` |
| 20 | `sp_snow_step_ECI_RFA_S20_KEEPNEW` | TRANSFORM | `WRK_ECI_RFA_S20_KEEPNEW` | `WRK_ECI_RFA_S10_LATEST` | 10 | Checkpoint `KEEP_NEW_ONLY` |
| 30 | `sp_snow_pub_ECI_RFA_STG_ECI_D_FAMILY_ADDRESS` | STATUS | _(none)_ | `WRK_ECI_RFA_S20_KEEPNEW` | 20 | Target `STG_ECI_D_FAMILY_ADDRESS`; checkpoint `PUBLISH_STG_ECI_D_FAMILY_ADDRESS` |

**Spine / status path (the outcome the user cares about):** step 30 → `STG_ECI_D_FAMILY_ADDRESS` (STATUS).

## RFP — m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn

Driver: `sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn` (STEP_NO 0). Workflow: `wf_ECI_Stage_Load`.

| STEP_NO | Proc | Kind | Produces | Consumes | Depends on | Target / notes |
|---|---|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn` | DRIVER | _(none)_ | _(none)_ | _(none)_ | Whole mapping; `IS_DRIVER = 'Y'`; `'N'` here skips everything before step 5 |
| 10 | `sp_snow_step_ECI_RFP_S10_LATEST` | TRANSFORM | `WRK_ECI_RFP_S10_LATEST` | `_(none)_` | _(none — base tables only)_ | Checkpoint `LATEST_HISTORY_ROWS` |
| 20 | `sp_snow_step_ECI_RFP_S20_KEEPNEW` | TRANSFORM | `WRK_ECI_RFP_S20_KEEPNEW` | `WRK_ECI_RFP_S10_LATEST` | 10 | Checkpoint `KEEP_NEW_ONLY` |
| 30 | `sp_snow_pub_ECI_RFP_STG_ECI_D_FAMILY_PHONE` | STATUS | _(none)_ | `WRK_ECI_RFP_S20_KEEPNEW` | 20 | Target `STG_ECI_D_FAMILY_PHONE`; checkpoint `PUBLISH_STG_ECI_D_FAMILY_PHONE` |

**Spine / status path (the outcome the user cares about):** step 30 → `STG_ECI_D_FAMILY_PHONE` (STATUS).

## RFM — m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid

Driver: `sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid` (STEP_NO 0). Workflow: `wf_ECI_Stage_Load`.

| STEP_NO | Proc | Kind | Produces | Consumes | Depends on | Target / notes |
|---|---|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid` | DRIVER | _(none)_ | _(none)_ | _(none)_ | Whole mapping; `IS_DRIVER = 'Y'`; `'N'` here skips everything before step 5 |
| 10 | `sp_snow_step_ECI_RFM_S10_LATEST` | TRANSFORM | `WRK_ECI_RFM_S10_LATEST` | `_(none)_` | _(none — base tables only)_ | Checkpoint `LATEST_HISTORY_ROWS` |
| 20 | `sp_snow_step_ECI_RFM_S20_KEEPNEW` | TRANSFORM | `WRK_ECI_RFM_S20_KEEPNEW` | `WRK_ECI_RFM_S10_LATEST` | 10 | Checkpoint `KEEP_NEW_ONLY` |
| 30 | `sp_snow_pub_ECI_RFM_STG_ECI_D_MEDICAID` | STATUS | _(none)_ | `WRK_ECI_RFM_S20_KEEPNEW` | 20 | Target `STG_ECI_D_MEDICAID`; checkpoint `PUBLISH_STG_ECI_D_MEDICAID` |

**Spine / status path (the outcome the user cares about):** step 30 → `STG_ECI_D_MEDICAID` (STATUS).

## TRS

# TRS_DEPENDENCIES — TRS step-driver refactor

Every unit, its produced and consumed work tables (pipe-delimited), and
its DEPENDENT_ON (producing STEP_NOs, informational — the driver gates
on IS_RUN_ENABLED only, never on these columns).

## Rules

- Work-table dependencies are INTRA-mapping only: verified by scanning
  every step CTAS and publish INSERT — no step or branch reads a work
  table produced by a different mapping. Cross-mapping coupling happens
  only through final/staging tables and through runner order (below),
  never through WRK_TRS_* tables.
- DEPENDENT_ON lists the STEP_NOs that produce the unit's consumed work
  tables. A branch that reads a router table depends on the router step,
  not on the last transform step (for example, PTY exception branches
  depend on step 30, spine branches on step 40; PHN phone-exception
  depends on step 40, email-exception on step 60).
- A step whose consumed list is empty reads base/staging tables only
  (step 10 of every mapping, and RELDEACT step 40, which reads the MDM
  cross-reference from base tables).

## Dependency chains in words

- **Runner order, wf_TRS_Stage_Load_1_Ongoing** (see
  `runners/sp_etl_run_wf_TRS_Stage_Load_1_Ongoing.sql`, copied verbatim):
  PTY first (it builds STG_TRS_VALID_MEMBERS, which every later mapping
  joins to), then PTYDEACT, TOA, REL1, RELDEACT, REL2, PHN, MNGSW,
  AUTHREP (after MNGSW: it appends to the table MNGSW loads), NM, ALT,
  PLN, ADDR1, ADDR2 (after ADDR1: it reads the unique addresses of part
  1, STG_TRS_D_UNQ_ADDR).
- **Runner order, wf_TRS_Stage_Load_TOA**: STGTOA alone (TOA reference
  catalogue into C_S_LU_TOA).
- **Within each mapping**, the chain is the step order in its manifest,
  with two branch exceptions documented in the manifests: PTY step 40
  reads step 20, NOT step 30 (exceptions and valid rows are two branches
  of the same DQ output); REL1/REL2 step 40 reads step 20, NOT step 30
  (valid relationships only, router exceptions are a side branch);
  PHN step 60 reads step 10, NOT step 50 (emails branch off the source,
  not off phone versions); RELDEACT step 50 reads steps 30 AND 40.
- **PTYDEACT step 50** depends on the publish step (40) only in
  sequence: it records a decision after publish and consumes no table.

## All units

| Mapping | STEP_NO | Proc | Produced work table | Consumed work tables | DEPENDENT_ON |
|---|---|---|---|---|---|
| m_Tgt_C_S_TRS_Pty_OnGoing | 10 | `sp_snow_step_TRS_PTY_S10_SRC` | WRK_TRS_PTY_S1_SRC |  | — |
| m_Tgt_C_S_TRS_Pty_OnGoing | 20 | `sp_snow_step_TRS_PTY_S20_DQ` | WRK_TRS_PTY_S2_DQ | WRK_TRS_PTY_S1_SRC | 10 |
| m_Tgt_C_S_TRS_Pty_OnGoing | 30 | `sp_snow_step_TRS_PTY_S30_ROUTER` | WRK_TRS_PTY_S3_ROUTER | WRK_TRS_PTY_S2_DQ | 20 |
| m_Tgt_C_S_TRS_Pty_OnGoing | 40 | `sp_snow_step_TRS_PTY_S40_DEDUP` | WRK_TRS_PTY_S4_DEDUP | WRK_TRS_PTY_S2_DQ | 20 |
| m_Tgt_C_S_TRS_Pty_OnGoing | 50 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_NAME` |  | WRK_TRS_PTY_S3_ROUTER | 30 |
| m_Tgt_C_S_TRS_Pty_OnGoing | 60 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_GENDER` |  | WRK_TRS_PTY_S3_ROUTER | 30 |
| m_Tgt_C_S_TRS_Pty_OnGoing | 70 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_DEATH` |  | WRK_TRS_PTY_S3_ROUTER | 30 |
| m_Tgt_C_S_TRS_Pty_OnGoing | 80 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH` |  | WRK_TRS_PTY_S3_ROUTER | 30 |
| m_Tgt_C_S_TRS_Pty_OnGoing | 90 | `sp_snow_pub_TRS_PTY_C_S_TRS_PTY` |  | WRK_TRS_PTY_S4_DEDUP | 40 |
| m_Tgt_C_S_TRS_Pty_OnGoing | 100 | `sp_snow_pub_TRS_PTY_C_S_TRS_PTY_RLE` |  | WRK_TRS_PTY_S4_DEDUP | 40 |
| m_Tgt_C_S_TRS_Pty_OnGoing | 110 | `sp_snow_pub_TRS_PTY_STG_TRS_VALID_MEMBERS` |  | WRK_TRS_PTY_S4_DEDUP | 40 |
| m_Tgt_C_S_TRS_Pty_OnGoing | 120 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_RACE` |  | WRK_TRS_PTY_S4_DEDUP | 40 |
| m_Tgt_C_S_TRS_Pty_OnGoing | 130 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY` |  | WRK_TRS_PTY_S4_DEDUP | 40 |
| m_Tgt_C_S_TRS_Pty_Deactivation_1 | 10 | `sp_snow_step_TRS_PTYDEACT_S10_DEACTV` | WRK_TRS_DEACT1_S10_DEACTV |  | — |
| m_Tgt_C_S_TRS_Pty_Deactivation_1 | 20 | `sp_snow_step_TRS_PTYDEACT_S20_DEACTV_ID` | WRK_TRS_DEACT1_S20_DEACTV_ID | WRK_TRS_DEACT1_S10_DEACTV | 10 |
| m_Tgt_C_S_TRS_Pty_Deactivation_1 | 30 | `sp_snow_step_TRS_PTYDEACT_S30_READY` | WRK_TRS_DEACT1_S30_READY | WRK_TRS_DEACT1_S20_DEACTV_ID | 20 |
| m_Tgt_C_S_TRS_Pty_Deactivation_1 | 40 | `sp_snow_pub_TRS_PTYDEACT_STG_TRS_DEACTIVED_MEMBERS` |  | WRK_TRS_DEACT1_S30_READY | 30 |
| m_Tgt_C_S_TRS_Pty_Deactivation_1 | 50 | `sp_snow_step_TRS_PTYDEACT_S50_NOTPERFORMED` |  |  | 40 |
| m_Tgt_C_S_TRS_Pty_Rle_TOA | 10 | `sp_snow_step_TRS_TOA_S10_RAW` | WRK_TRS_TOA_S10_RAW |  | — |
| m_Tgt_C_S_TRS_Pty_Rle_TOA | 20 | `sp_snow_step_TRS_TOA_S20_LATEST` | WRK_TRS_TOA_S20_SRC | WRK_TRS_TOA_S10_RAW | 10 |
| m_Tgt_C_S_TRS_Pty_Rle_TOA | 30 | `sp_snow_step_TRS_TOA_S30_KEYED` | WRK_TRS_TOA_S30_KEYED | WRK_TRS_TOA_S20_SRC | 20 |
| m_Tgt_C_S_TRS_Pty_Rle_TOA | 40 | `sp_snow_step_TRS_TOA_S40_RANKED` | WRK_TRS_TOA_S40_RANKED | WRK_TRS_TOA_S30_KEYED | 30 |
| m_Tgt_C_S_TRS_Pty_Rle_TOA | 50 | `sp_snow_pub_TRS_TOA_EXC_STG_BAD_REC_MEMB_BAD_VALUE` |  | WRK_TRS_TOA_S40_RANKED | 40 |
| m_Tgt_C_S_TRS_Pty_Rle_TOA | 60 | `sp_snow_pub_TRS_TOA_EXC_STG_BAD_REC_MEMB_DATES` |  | WRK_TRS_TOA_S40_RANKED | 40 |
| m_Tgt_C_S_TRS_Pty_Rle_TOA | 70 | `sp_snow_pub_TRS_TOA_C_S_TRS_PTY_RLE_TOA` |  | WRK_TRS_TOA_S40_RANKED | 40 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | 10 | `sp_snow_step_TRS_REL1_S10_SRC` | WRK_TRS_REL1_S1_SRC |  | — |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | 20 | `sp_snow_step_TRS_REL1_S20_KEYED` | WRK_TRS_REL1_S2_KEYED | WRK_TRS_REL1_S1_SRC | 10 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | 30 | `sp_snow_step_TRS_REL1_S30_ROUTER` | WRK_TRS_REL1_S3_ROUTER | WRK_TRS_REL1_S2_KEYED | 20 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | 40 | `sp_snow_step_TRS_REL1_S40_CONSOL` | WRK_TRS_REL1_S4_CONSOL | WRK_TRS_REL1_S2_KEYED | 20 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | 50 | `sp_snow_step_TRS_REL1_S50_PREP` | WRK_TRS_REL1_S5_PREP | WRK_TRS_REL1_S4_CONSOL | 40 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | 60 | `sp_snow_step_TRS_REL1_S60_TIMELINE` | WRK_TRS_REL1_S6_TIMELINE | WRK_TRS_REL1_S5_PREP | 50 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | 70 | `sp_snow_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_MAIN_ALT_ID` |  | WRK_TRS_REL1_S3_ROUTER | 30 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | 80 | `sp_snow_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_REF_ALT_ID` |  | WRK_TRS_REL1_S3_ROUTER | 30 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | 90 | `sp_snow_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_LOOKUP` |  | WRK_TRS_REL1_S3_ROUTER | 30 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | 100 | `sp_snow_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_DATES` |  | WRK_TRS_REL1_S3_ROUTER | 30 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | 110 | `sp_snow_pub_TRS_REL1_C_S_TRS_PTY_RLE_REL` |  | WRK_TRS_REL1_S6_TIMELINE | 60 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 | 10 | `sp_snow_step_TRS_RELDEACT_S10_MINPK` | WRK_TRS_RELDEACT_S10_MINPK |  | — |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 | 20 | `sp_snow_step_TRS_RELDEACT_S20_SRC` | WRK_TRS_RELDEACT_S20_SRC | WRK_TRS_RELDEACT_S10_MINPK | 10 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 | 30 | `sp_snow_step_TRS_RELDEACT_S30_KEYED` | WRK_TRS_RELDEACT_S30_KEYED | WRK_TRS_RELDEACT_S20_SRC | 20 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 | 40 | `sp_snow_step_TRS_RELDEACT_S40_XREF` | WRK_TRS_RELDEACT_S40_XREF |  | — |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 | 50 | `sp_snow_step_TRS_RELDEACT_S50_READY` | WRK_TRS_RELDEACT_S50_READY | WRK_TRS_RELDEACT_S30_KEYED|WRK_TRS_RELDEACT_S40_XREF | 30|40 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 | 60 | `sp_snow_pub_TRS_RELDEACT_STG_TRS_DEACTIVATED_RELATIONSHIPS` |  | WRK_TRS_RELDEACT_S50_READY | 50 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | 10 | `sp_snow_step_TRS_REL2_S10_SRC` | WRK_TRS_REL2_S1_SRC |  | — |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | 20 | `sp_snow_step_TRS_REL2_S20_KEYED` | WRK_TRS_REL2_S2_KEYED | WRK_TRS_REL2_S1_SRC | 10 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | 30 | `sp_snow_step_TRS_REL2_S30_ROUTER` | WRK_TRS_REL2_S3_ROUTER | WRK_TRS_REL2_S2_KEYED | 20 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | 40 | `sp_snow_step_TRS_REL2_S40_CONSOL` | WRK_TRS_REL2_S4_CONSOL | WRK_TRS_REL2_S2_KEYED | 20 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | 50 | `sp_snow_step_TRS_REL2_S50_PREP` | WRK_TRS_REL2_S5_PREP | WRK_TRS_REL2_S4_CONSOL | 40 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | 60 | `sp_snow_step_TRS_REL2_S60_TIMELINE` | WRK_TRS_REL2_S6_TIMELINE | WRK_TRS_REL2_S5_PREP | 50 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | 70 | `sp_snow_pub_TRS_REL2_EXC_STG_BAD_REC_MEMB_DATES` |  | WRK_TRS_REL2_S3_ROUTER | 30 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | 80 | `sp_snow_pub_TRS_REL2_EXC_STG_BAD_REC_MEMB_DEFAULT` |  | WRK_TRS_REL2_S3_ROUTER | 30 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | 90 | `sp_snow_pub_TRS_REL2_C_S_TRS_PTY_RLE_REL_PROV` |  | WRK_TRS_REL2_S6_TIMELINE | 60 |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | 10 | `sp_snow_step_TRS_PHN_S10_SRC` | WRK_TRS_PHN_S1_SRC |  | — |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | 20 | `sp_snow_step_TRS_PHN_S20_SLOTS` | WRK_TRS_PHN_S2_SLOTS | WRK_TRS_PHN_S1_SRC | 10 |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | 30 | `sp_snow_step_TRS_PHN_S30_CHECKED` | WRK_TRS_PHN_S3_CHECKED | WRK_TRS_PHN_S2_SLOTS | 20 |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | 40 | `sp_snow_step_TRS_PHN_S40_PHONES` | WRK_TRS_PHN_S4_PHONES | WRK_TRS_PHN_S3_CHECKED | 30 |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | 50 | `sp_snow_step_TRS_PHN_S50_VERSIONS` | WRK_TRS_PHN_S5_VERSIONS | WRK_TRS_PHN_S4_PHONES | 40 |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | 60 | `sp_snow_step_TRS_PHN_S60_EMAILS` | WRK_TRS_PHN_S6_EMAILS | WRK_TRS_PHN_S1_SRC | 10 |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | 70 | `sp_snow_step_TRS_PHN_S70_EADDR` | WRK_TRS_PHN_S7_VERSIONS | WRK_TRS_PHN_S6_EMAILS | 60 |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | 80 | `sp_snow_pub_TRS_PHN_C_S_TRS_PTY_RLE_PHN` |  | WRK_TRS_PHN_S5_VERSIONS | 50 |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | 90 | `sp_snow_pub_TRS_PHN_EXC_STG_BAD_REC_MEMB_PHONE` |  | WRK_TRS_PHN_S4_PHONES | 40 |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | 100 | `sp_snow_pub_TRS_PHN_C_S_TRS_PTY_RLE_EADDR` |  | WRK_TRS_PHN_S7_VERSIONS | 70 |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | 110 | `sp_snow_pub_TRS_PHN_EXC_STG_BAD_REC_MEMB_EMAIL` |  | WRK_TRS_PHN_S6_EMAILS | 60 |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw | 10 | `sp_snow_step_TRS_MNGSW_S10_DAILY` | WRK_TRS_MNGSW_S10_DAILY |  | — |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw | 20 | `sp_snow_step_TRS_MNGSW_S20_SRC` | WRK_TRS_MNGSW_S20_SRC | WRK_TRS_MNGSW_S10_DAILY | 10 |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw | 30 | `sp_snow_step_TRS_MNGSW_S30_NORM` | WRK_TRS_MNGSW_S30_NORM | WRK_TRS_MNGSW_S20_SRC | 20 |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw | 40 | `sp_snow_step_TRS_MNGSW_S40_ATTRS` | WRK_TRS_MNGSW_S40_ATTRS | WRK_TRS_MNGSW_S30_NORM | 30 |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw | 50 | `sp_snow_pub_TRS_MNGSW_C_S_TRS_PTY_MNG_ATTR` |  | WRK_TRS_MNGSW_S40_ATTRS | 40 |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing | 10 | `sp_snow_step_TRS_AUTHREP_S10_PAYEE` | WRK_TRS_MNGAR_S10_PAYEE |  | — |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing | 20 | `sp_snow_step_TRS_AUTHREP_S20_SRC` | WRK_TRS_MNGAR_S20_SRC | WRK_TRS_MNGAR_S10_PAYEE | 10 |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing | 30 | `sp_snow_step_TRS_AUTHREP_S30_KEYED` | WRK_TRS_MNGAR_S30_KEYED | WRK_TRS_MNGAR_S20_SRC | 20 |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing | 40 | `sp_snow_step_TRS_AUTHREP_S40_AGG` | WRK_TRS_MNGAR_S40_AGG | WRK_TRS_MNGAR_S30_KEYED | 30 |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing | 50 | `sp_snow_pub_TRS_AUTHREP_C_S_TRS_PTY_MNG_ATTR` |  | WRK_TRS_MNGAR_S40_AGG | 40 |
| m_Tgt_C_S_TRS_Pty_Nm | 10 | `sp_snow_step_TRS_NM_S10_SRC` | WRK_TRS_NM_S10_SRC |  | — |
| m_Tgt_C_S_TRS_Pty_Nm | 20 | `sp_snow_step_TRS_NM_S20_NAMED` | WRK_TRS_NM_S20_NAMED | WRK_TRS_NM_S10_SRC | 10 |
| m_Tgt_C_S_TRS_Pty_Nm | 30 | `sp_snow_step_TRS_NM_S30_STD` | WRK_TRS_NM_S30_STD | WRK_TRS_NM_S20_NAMED | 20 |
| m_Tgt_C_S_TRS_Pty_Nm | 40 | `sp_snow_step_TRS_NM_S40_DEDUP` | WRK_TRS_NM_S40_DEDUP | WRK_TRS_NM_S30_STD | 30 |
| m_Tgt_C_S_TRS_Pty_Nm | 50 | `sp_snow_pub_TRS_NM_C_S_TRS_PTY_NM` |  | WRK_TRS_NM_S40_DEDUP | 40 |
| m_Tgt_C_S_TRS_Pty_Rle_Alt_Id | 10 | `sp_snow_step_TRS_ALT_S10_SRC` | WRK_TRS_ALT_S1_SRC |  | — |
| m_Tgt_C_S_TRS_Pty_Rle_Alt_Id | 20 | `sp_snow_step_TRS_ALT_S20_SSN` | WRK_TRS_ALT_S2_SSN | WRK_TRS_ALT_S1_SRC | 10 |
| m_Tgt_C_S_TRS_Pty_Rle_Alt_Id | 30 | `sp_snow_step_TRS_ALT_S30_NORM` | WRK_TRS_ALT_S3_NORM | WRK_TRS_ALT_S2_SSN | 20 |
| m_Tgt_C_S_TRS_Pty_Rle_Alt_Id | 40 | `sp_snow_step_TRS_ALT_S40_ROUTED` | WRK_TRS_ALT_S4_ROUTED | WRK_TRS_ALT_S3_NORM | 30 |
| m_Tgt_C_S_TRS_Pty_Rle_Alt_Id | 50 | `sp_snow_pub_TRS_ALT_C_S_TRS_PTY_RLE_ALT_ID` |  | WRK_TRS_ALT_S4_ROUTED | 40 |
| m_Tgt_C_S_TRS_Pty_Rle_Alt_Id | 60 | `sp_snow_pub_TRS_ALT_EXC_STG_BAD_REC_MEMB` |  | WRK_TRS_ALT_S4_ROUTED | 40 |
| m_Tgt_C_S_TRS_Pty_Rle_Pln | 10 | `sp_snow_step_TRS_PLN_S10_SRC` | WRK_TRS_PLN_S10_SRC |  | — |
| m_Tgt_C_S_TRS_Pty_Rle_Pln | 20 | `sp_snow_step_TRS_PLN_S20_PLANNED` | WRK_TRS_PLN_S20_PLANNED | WRK_TRS_PLN_S10_SRC | 10 |
| m_Tgt_C_S_TRS_Pty_Rle_Pln | 30 | `sp_snow_step_TRS_PLN_S30_RANKED` | WRK_TRS_PLN_S30_RANKED | WRK_TRS_PLN_S20_PLANNED | 20 |
| m_Tgt_C_S_TRS_Pty_Rle_Pln | 40 | `sp_snow_pub_TRS_PLN_C_S_TRS_PTY_RLE_PLN` |  | WRK_TRS_PLN_S30_RANKED | 30 |
| m_Tgt_C_S_TRS_Pty_Rle_Pln | 50 | `sp_snow_pub_TRS_PLN_EXC_STG_BAD_REC_MEMB` |  | WRK_TRS_PLN_S30_RANKED | 30 |
| m_Tgt_C_S_TRS_Addr_1 | 10 | `sp_snow_step_TRS_ADDR1_S10_SRC` | WRK_TRS_ADDR1_S10_SRC |  | — |
| m_Tgt_C_S_TRS_Addr_1 | 20 | `sp_snow_step_TRS_ADDR1_S20_DERIVED` | WRK_TRS_ADDR1_S20_DERIVED | WRK_TRS_ADDR1_S10_SRC | 10 |
| m_Tgt_C_S_TRS_Addr_1 | 30 | `sp_snow_step_TRS_ADDR1_S30_VALIDATED` | WRK_TRS_ADDR1_S30_VALIDATED | WRK_TRS_ADDR1_S20_DERIVED | 20 |
| m_Tgt_C_S_TRS_Addr_1 | 40 | `sp_snow_step_TRS_ADDR1_S40_READY` | WRK_TRS_ADDR1_S40_READY | WRK_TRS_ADDR1_S30_VALIDATED | 30 |
| m_Tgt_C_S_TRS_Addr_1 | 50 | `sp_snow_pub_TRS_ADDR1_STG_TRS_D_UNQ_ADDR` |  | WRK_TRS_ADDR1_S40_READY | 40 |
| m_Tgt_C_S_TRS_Addr_2 | 10 | `sp_snow_step_TRS_ADDR2_S10_DEDUP` | WRK_TRS_ADDR2_S10_DEDUP |  | — |
| m_Tgt_C_S_TRS_Addr_2 | 20 | `sp_snow_step_TRS_ADDR2_S20_SRC` | WRK_TRS_ADDR2_S20_SRC | WRK_TRS_ADDR2_S10_DEDUP | 10 |
| m_Tgt_C_S_TRS_Addr_2 | 30 | `sp_snow_step_TRS_ADDR2_S30_KEYED` | WRK_TRS_ADDR2_S30_KEYED | WRK_TRS_ADDR2_S20_SRC | 20 |
| m_Tgt_C_S_TRS_Addr_2 | 40 | `sp_snow_step_TRS_ADDR2_S40_SCORED` | WRK_TRS_ADDR2_S40_SCORED | WRK_TRS_ADDR2_S30_KEYED | 30 |
| m_Tgt_C_S_TRS_Addr_2 | 50 | `sp_snow_step_TRS_ADDR2_S50_READY` | WRK_TRS_ADDR2_S50_READY | WRK_TRS_ADDR2_S40_SCORED | 40 |
| m_Tgt_C_S_TRS_Addr_2 | 60 | `sp_snow_pub_TRS_ADDR2_DQM_ADDRESS` |  | WRK_TRS_ADDR2_S50_READY | 50 |
| m_Tgt_C_S_TRS_Addr_2 | 70 | `sp_snow_pub_TRS_ADDR2_C_S_TRS_PTY_RLE_ADDR` |  | WRK_TRS_ADDR2_S50_READY | 50 |
| m_Tgt_C_S_TRS_Addr_2 | 80 | `sp_snow_pub_TRS_ADDR2_EXC_STG_BAD_REC_MEMB` |  | WRK_TRS_ADDR2_S50_READY | 50 |
| m_Tgt_C_S_TRS_Stg_TOA | 10 | `sp_snow_step_TRS_STGTOA_S10_KEYED` | WRK_TRS_LUTOA_S10_KEYED |  | — |
| m_Tgt_C_S_TRS_Stg_TOA | 20 | `sp_snow_step_TRS_STGTOA_S20_FINAL` | WRK_TRS_LUTOA_S20_FINAL | WRK_TRS_LUTOA_S10_KEYED | 10 |
| m_Tgt_C_S_TRS_Stg_TOA | 30 | `sp_snow_pub_TRS_STGTOA_C_S_LU_TOA` |  | WRK_TRS_LUTOA_S20_FINAL | 20 |

## WIC

# WIC Dependencies — wf_WIC_Stage_Load (config-driven refactor)
Gating is by `IS_RUN_ENABLED` only; drivers do NOT validate flag consistency. `DEPENDENT_ON` below is informational (the operator's responsibility), and `WORK_TABLES_CONSUMED` is what each unit actually runtime-checks via `P_INPUT_TABLES`. No work table is shared between mappings; each mapping's step 5 drops only its own tables.
## Per-unit dependencies

| Mapping | STEP_NO | Proc | Produced | Consumed | DEPENDENT_ON | Kind |
|---|---|---|---|---|---|---|
| `m_Tgt_C_S_WIC_Pty_Validation` | 0 | `sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation` | `` | `` | `` | DRIVER |
| `m_Tgt_C_S_WIC_Pty_Validation` | 10 | `sp_snow_step_WIC_VAL_S10_ENRICHED` | `WRK_WIC_VAL_S10_ENRICHED` | `` | `` | TRANSFORM |
| `m_Tgt_C_S_WIC_Pty_Validation` | 20 | `sp_snow_step_WIC_VAL_S20_NAMED` | `WRK_WIC_VAL_S20_NAMED` | `WRK_WIC_VAL_S10_ENRICHED` | `10` | TRANSFORM |
| `m_Tgt_C_S_WIC_Pty_Validation` | 30 | `sp_snow_step_WIC_VAL_S30_ROUTED` | `WRK_WIC_VAL_S30_ROUTED` | `WRK_WIC_VAL_S20_NAMED` | `20` | TRANSFORM |
| `m_Tgt_C_S_WIC_Pty_Validation` | 40 | `sp_snow_pub_WIC_VAL_EXC_STG_BAD_REC_MEMB` | `` | `WRK_WIC_VAL_S30_ROUTED` | `30` | EXCEPTION |
| `m_Tgt_C_S_WIC_Pty_Validation` | 50 | `sp_snow_pub_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_DEACTIVATION` | `` | `WRK_WIC_VAL_S30_ROUTED` | `30` | STATUS |
| `m_Tgt_C_S_WIC_Pty_Validation` | 60 | `sp_snow_pub_WIC_VAL_STG_WIC_PTY_INACTIVE_STS` | `` | `WRK_WIC_VAL_S30_ROUTED` | `30` | STATUS |
| `m_Tgt_C_S_WIC_Pty_Validation` | 70 | `sp_snow_pub_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_REACTIVATION` | `` | `WRK_WIC_VAL_S30_ROUTED` | `30` | STATUS |
| `m_Tgt_C_S_WIC_Pty` | 0 | `sp_snow_main_m_Tgt_C_S_WIC_Pty` | `` | `` | `` | DRIVER |
| `m_Tgt_C_S_WIC_Pty` | 10 | `sp_snow_step_WIC_PTY_S10_ACTIVE` | `WRK_WIC_PTY_S10_ACTIVE` | `` | `` | TRANSFORM |
| `m_Tgt_C_S_WIC_Pty` | 20 | `sp_snow_step_WIC_PTY_S20_DQ` | `WRK_WIC_PTY_S20_DQ` | `WRK_WIC_PTY_S10_ACTIVE` | `10` | TRANSFORM |
| `m_Tgt_C_S_WIC_Pty` | 30 | `sp_snow_step_WIC_PTY_S30_DQ2` | `WRK_WIC_PTY_S30_DQ2` | `WRK_WIC_PTY_S20_DQ` | `20` | TRANSFORM |
| `m_Tgt_C_S_WIC_Pty` | 40 | `sp_snow_step_WIC_PTY_S40_ROUTED` | `WRK_WIC_PTY_S40_ROUTED` | `WRK_WIC_PTY_S30_DQ2` | `30` | TRANSFORM |
| `m_Tgt_C_S_WIC_Pty` | 50 | `sp_snow_pub_WIC_PTY_C_S_WIC_PTY` | `` | `WRK_WIC_PTY_S40_ROUTED` | `40` | SPINE |
| `m_Tgt_C_S_WIC_Pty` | 60 | `sp_snow_pub_WIC_PTY_C_S_WIC_PTY_RLE` | `` | `WRK_WIC_PTY_S40_ROUTED` | `40` | SPINE |
| `m_Tgt_C_S_WIC_Pty` | 70 | `sp_snow_pub_WIC_PTY_EXC_STG_BAD_REC_MEMB_GENDER` | `` | `WRK_WIC_PTY_S40_ROUTED` | `40` | EXCEPTION |
| `m_Tgt_C_S_WIC_Pty` | 80 | `sp_snow_pub_WIC_PTY_EXC_STG_BAD_REC_MEMB_BIRTH` | `` | `WRK_WIC_PTY_S40_ROUTED` | `40` | EXCEPTION |
| `m_Tgt_C_S_WIC_Pty` | 90 | `sp_snow_pub_WIC_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY` | `` | `WRK_WIC_PTY_S40_ROUTED` | `40` | EXCEPTION |
| `m_Tgt_C_S_WIC_Pty` | 100 | `sp_snow_pub_WIC_PTY_EXC_STG_BAD_REC_MEMB_RACE` | `` | `WRK_WIC_PTY_S40_ROUTED` | `40` | EXCEPTION |
| `m_Tgt_C_S_WIC_Pty` | 110 | `sp_snow_pub_WIC_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE` | `` | `WRK_WIC_PTY_S40_ROUTED` | `40` | EXCEPTION |
| `m_Tgt_C_S_WIC_Pty_Addr` | 0 | `sp_snow_main_m_Tgt_C_S_WIC_Pty_Addr` | `` | `` | `` | DRIVER |
| `m_Tgt_C_S_WIC_Pty_Addr` | 10 | `sp_snow_step_WIC_ADR_S10_ACTIVE` | `WRK_WIC_ADDR_S10_ACTIVE` | `` | `` | TRANSFORM |
| `m_Tgt_C_S_WIC_Pty_Addr` | 20 | `sp_snow_step_WIC_ADR_S20_VALIDATED` | `WRK_WIC_ADDR_S20_VALIDATED` | `WRK_WIC_ADDR_S10_ACTIVE` | `10` | TRANSFORM |
| `m_Tgt_C_S_WIC_Pty_Addr` | 30 | `sp_snow_step_WIC_ADR_S30_FLAT` | `WRK_WIC_ADDR_S30_FLAT` | `WRK_WIC_ADDR_S20_VALIDATED` | `20` | TRANSFORM |
| `m_Tgt_C_S_WIC_Pty_Addr` | 40 | `sp_snow_step_WIC_ADR_S40_SCORED` | `WRK_WIC_ADDR_S40_SCORED` | `WRK_WIC_ADDR_S30_FLAT` | `30` | TRANSFORM |
| `m_Tgt_C_S_WIC_Pty_Addr` | 50 | `sp_snow_pub_WIC_ADR_DQM_ADDRESS` | `` | `WRK_WIC_ADDR_S40_SCORED` | `40` | VALIDATION |
| `m_Tgt_C_S_WIC_Pty_Addr` | 60 | `sp_snow_pub_WIC_ADR_C_S_WIC_PTY_RLE_ADDR` | `` | `WRK_WIC_ADDR_S40_SCORED` | `40` | SPINE |
| `m_Tgt_C_S_WIC_Pty_Addr` | 70 | `sp_snow_pub_WIC_ADR_EXC_STG_BAD_REC_MEMB` | `` | `WRK_WIC_ADDR_S40_SCORED` | `40` | EXCEPTION |
| `m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr` | 0 | `sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr` | `` | `` | `` | DRIVER |
| `m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr` | 10 | `sp_snow_step_WIC_PHN_S10_SRC` | `WRK_WIC_PHN_S10_SRC` | `` | `` | TRANSFORM |
| `m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr` | 20 | `sp_snow_step_WIC_PHN_S20_CHECKED` | `WRK_WIC_PHN_S20_CHECKED` | `WRK_WIC_PHN_S10_SRC` | `10` | TRANSFORM |
| `m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr` | 30 | `sp_snow_step_WIC_PHN_S30_ROUTED` | `WRK_WIC_PHN_S30_ROUTED` | `WRK_WIC_PHN_S20_CHECKED` | `20` | TRANSFORM |
| `m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr` | 40 | `sp_snow_step_WIC_PHN_S40_READY` | `WRK_WIC_PHN_S40_READY` | `WRK_WIC_PHN_S30_ROUTED` | `30` | TRANSFORM |
| `m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr` | 50 | `sp_snow_pub_WIC_PHN_C_S_WIC_PTY_RLE_PHN` | `` | `WRK_WIC_PHN_S40_READY` | `40` | SPINE |
| `m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr` | 60 | `sp_snow_pub_WIC_PHN_EXC_STG_BAD_REC_MEMB_PHONE` | `` | `WRK_WIC_PHN_S40_READY` | `40` | EXCEPTION |
| `m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr` | 70 | `sp_snow_pub_WIC_PHN_C_S_WIC_PTY_RLE_EADDR` | `` | `WRK_WIC_PHN_S40_READY` | `40` | SPINE |
| `m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr` | 80 | `sp_snow_pub_WIC_PHN_EXC_STG_BAD_REC_MEMB_EMAIL` | `` | `WRK_WIC_PHN_S40_READY` | `40` | EXCEPTION |
| `m_Tgt_C_S_WIC_Pty_Rle_Alt_Id` | 0 | `sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id` | `` | `` | `` | DRIVER |
| `m_Tgt_C_S_WIC_Pty_Rle_Alt_Id` | 10 | `sp_snow_step_WIC_ALT_S10_KEYS` | `WRK_WIC_ALT_S10_KEYS` | `` | `` | TRANSFORM |
| `m_Tgt_C_S_WIC_Pty_Rle_Alt_Id` | 20 | `sp_snow_step_WIC_ALT_S20_READY` | `WRK_WIC_ALT_S20_READY` | `WRK_WIC_ALT_S10_KEYS` | `10` | TRANSFORM |
| `m_Tgt_C_S_WIC_Pty_Rle_Alt_Id` | 30 | `sp_snow_pub_WIC_ALT_C_S_WIC_PTY_RLE_ALT_ID` | `` | `WRK_WIC_ALT_S20_READY` | `20` | SPINE |

## Dependency chains in words

- **m_Tgt_C_S_WIC_Pty_Validation**: step 10 (WRK_WIC_VAL_S10_ENRICHED) -> step 20 (WRK_WIC_VAL_S20_NAMED) -> step 30 (WRK_WIC_VAL_S30_ROUTED) -> publish branches step 40 (EXC_STG_BAD_REC_MEMB), step 50 (STG_WIC_PTY_INACTIVE_LOG), step 60 (STG_WIC_PTY_INACTIVE_STS), step 70 (STG_WIC_PTY_INACTIVE_LOG). Every step consumes exactly the previous step's work table (step 10 consumes no work table; it reads base tables); every publish branch consumes the final step's work table.
- **m_Tgt_C_S_WIC_Pty**: step 10 (WRK_WIC_PTY_S10_ACTIVE) -> step 20 (WRK_WIC_PTY_S20_DQ) -> step 30 (WRK_WIC_PTY_S30_DQ2) -> step 40 (WRK_WIC_PTY_S40_ROUTED) -> publish branches step 50 (C_S_WIC_PTY), step 60 (C_S_WIC_PTY_RLE), step 70 (EXC_STG_BAD_REC_MEMB), step 80 (EXC_STG_BAD_REC_MEMB), step 90 (EXC_STG_BAD_REC_MEMB), step 100 (EXC_STG_BAD_REC_MEMB), step 110 (EXC_STG_BAD_REC_MEMB). Every step consumes exactly the previous step's work table (step 10 consumes no work table; it reads base tables); every publish branch consumes the final step's work table.
- **m_Tgt_C_S_WIC_Pty_Addr**: step 10 (WRK_WIC_ADDR_S10_ACTIVE) -> step 20 (WRK_WIC_ADDR_S20_VALIDATED) -> step 30 (WRK_WIC_ADDR_S30_FLAT) -> step 40 (WRK_WIC_ADDR_S40_SCORED) -> publish branches step 50 (DQM_ADDRESS), step 60 (C_S_WIC_PTY_RLE_ADDR), step 70 (EXC_STG_BAD_REC_MEMB). Every step consumes exactly the previous step's work table (step 10 consumes no work table; it reads base tables); every publish branch consumes the final step's work table.
- **m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr**: step 10 (WRK_WIC_PHN_S10_SRC) -> step 20 (WRK_WIC_PHN_S20_CHECKED) -> step 30 (WRK_WIC_PHN_S30_ROUTED) -> step 40 (WRK_WIC_PHN_S40_READY) -> publish branches step 50 (C_S_WIC_PTY_RLE_PHN), step 60 (EXC_STG_BAD_REC_MEMB), step 70 (C_S_WIC_PTY_RLE_EADDR), step 80 (EXC_STG_BAD_REC_MEMB). Every step consumes exactly the previous step's work table (step 10 consumes no work table; it reads base tables); every publish branch consumes the final step's work table.
- **m_Tgt_C_S_WIC_Pty_Rle_Alt_Id**: step 10 (WRK_WIC_ALT_S10_KEYS) -> step 20 (WRK_WIC_ALT_S20_READY) -> publish branches step 30 (C_S_WIC_PTY_RLE_ALT_ID). Every step consumes exactly the previous step's work table (step 10 consumes no work table; it reads base tables); every publish branch consumes the final step's work table.

## Cross-mapping dependencies (target tables, not work tables)

- `m_Tgt_C_S_WIC_Pty_Validation` runs FIRST in the workflow runner because it maintains `STG_WIC_PTY_INACTIVE_STS`, which every later WIC mapping filters on with a `NOT EXISTS (DEACTIVATION_STS IS NOT NULL)` test. This is a target-table dependency through the shared schema, not a work-table dependency: no driver reads another mapping's work tables, and disabling Validation does not auto-skip the later mappings (their filters would then read the previous run's status rows).
- `m_Tgt_C_S_WIC_Pty` loads `C_S_WIC_PTY` / `C_S_WIC_PTY_RLE`; the Address, Phone/E-mail and Alt Id mappings' final steps guard against those targets (insert-only guards), so they must run after Party in the same run order as the original runner.
- The workflow runner order is therefore: Validation -> Party -> Address -> Phone/E-mail -> Alt Id. Changing that order changes results; it is not a config toggle.

## TTF

# TTF Dependencies - workflow wf_TTF_Stage_Load

Every unit, the work tables it produces and consumes (pipe-delimited, as in
the seed), and its DEPENDENT_ON (producing STEP_NOs, informational only --
drivers gate on IS_RUN_ENABLED alone and never validate these values).
Work-table dependencies are WITHIN one mapping only: no step consumes a work
table produced by another mapping. Cross-mapping dependencies travel through
target / staging tables and through runner order (see below).

## m_Tgt_C_S_TTF_Pty_Validation (PREFIX VAL)

| STEP_NO | Unit | Produced | Consumed | DEPENDENT_ON |
|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_TTF_Pty_Validation` |  |  |  |
| 10 | `sp_snow_step_TTF_VAL_S10_ENRICHED` | `WRK_TTF_VAL_S1_ENRICHED` | -- |  |
| 20 | `sp_snow_step_TTF_VAL_S20_NAMED` | `WRK_TTF_VAL_S2_NAMED` | WRK_TTF_VAL_S1_ENRICHED | 10 |
| 30 | `sp_snow_step_TTF_VAL_S30_ROUTED` | `WRK_TTF_VAL_S3_ROUTED` | WRK_TTF_VAL_S2_NAMED | 20 |
| 40 | `sp_snow_pub_TTF_VAL_EXC_STG_BAD_REC_MEMB` | -- (writes target `EXC_STG_BAD_REC_MEMB`) | `WRK_TTF_VAL_S3_ROUTED` | 30 |
| 50 | `sp_snow_pub_TTF_VAL_STG_TTF_PTY_INACTIVE_LOG_DEACTIVATION` | -- (writes target `STG_TTF_PTY_INACTIVE_LOG`) | `WRK_TTF_VAL_S3_ROUTED` | 30 |
| 60 | `sp_snow_pub_TTF_VAL_STG_TTF_PTY_INACTIVE_STS` | -- (writes target `STG_TTF_PTY_INACTIVE_STS`) | `WRK_TTF_VAL_S3_ROUTED` | 30 |
| 70 | `sp_snow_pub_TTF_VAL_STG_TTF_PTY_INACTIVE_LOG_REACTIVATION` | -- (writes target `STG_TTF_PTY_INACTIVE_LOG`) | `WRK_TTF_VAL_S3_ROUTED` | 30 |

Dependency chain in words: step 0 driver -> step 10 (ENRICHED) -> step 20 (NAMED) -> step 30 (ROUTED) -> branch 40 (EXC_STG_BAD_REC_MEMB) -> branch 50 (STG_TTF_PTY_INACTIVE_LOG) -> branch 60 (STG_TTF_PTY_INACTIVE_STS) -> branch 70 (STG_TTF_PTY_INACTIVE_LOG). Each transform step depends on the
step before it; each publish branch depends on the final routed step;
the driver row depends on nothing and gates the whole mapping.

## m_Tgt_C_S_TTF_Pty (PREFIX PTY)

| STEP_NO | Unit | Produced | Consumed | DEPENDENT_ON |
|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_TTF_Pty` |  |  |  |
| 10 | `sp_snow_step_TTF_PTY_S10_ACTIVE` | `WRK_TTF_PTY_S1_ACTIVE` | -- |  |
| 20 | `sp_snow_step_TTF_PTY_S20_DQ` | `WRK_TTF_PTY_S2_DQ` | WRK_TTF_PTY_S1_ACTIVE | 10 |
| 30 | `sp_snow_step_TTF_PTY_S30_DQ2` | `WRK_TTF_PTY_S3_DQ2` | WRK_TTF_PTY_S2_DQ | 20 |
| 40 | `sp_snow_step_TTF_PTY_S40_ROUTED` | `WRK_TTF_PTY_S4_ROUTED` | WRK_TTF_PTY_S3_DQ2 | 30 |
| 50 | `sp_snow_pub_TTF_PTY_C_S_TTF_PTY` | -- (writes target `C_S_TTF_PTY`) | `WRK_TTF_PTY_S4_ROUTED` | 40 |
| 60 | `sp_snow_pub_TTF_PTY_C_S_TTF_PTY_RLE` | -- (writes target `C_S_TTF_PTY_RLE`) | `WRK_TTF_PTY_S4_ROUTED` | 40 |
| 70 | `sp_snow_pub_TTF_PTY_EXC_STG_BAD_REC_MEMB_GENDER` | -- (writes target `EXC_STG_BAD_REC_MEMB`) | `WRK_TTF_PTY_S4_ROUTED` | 40 |
| 80 | `sp_snow_pub_TTF_PTY_EXC_STG_BAD_REC_MEMB_BIRTH` | -- (writes target `EXC_STG_BAD_REC_MEMB`) | `WRK_TTF_PTY_S4_ROUTED` | 40 |
| 90 | `sp_snow_pub_TTF_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY` | -- (writes target `EXC_STG_BAD_REC_MEMB`) | `WRK_TTF_PTY_S4_ROUTED` | 40 |
| 100 | `sp_snow_pub_TTF_PTY_EXC_STG_BAD_REC_MEMB_RACE` | -- (writes target `EXC_STG_BAD_REC_MEMB`) | `WRK_TTF_PTY_S4_ROUTED` | 40 |

Dependency chain in words: step 0 driver -> step 10 (ACTIVE) -> step 20 (DQ) -> step 30 (DQ2) -> step 40 (ROUTED) -> branch 50 (C_S_TTF_PTY) -> branch 60 (C_S_TTF_PTY_RLE) -> branch 70 (EXC_STG_BAD_REC_MEMB) -> branch 80 (EXC_STG_BAD_REC_MEMB) -> branch 90 (EXC_STG_BAD_REC_MEMB) -> branch 100 (EXC_STG_BAD_REC_MEMB). Each transform step depends on the
step before it; each publish branch depends on the final routed step;
the driver row depends on nothing and gates the whole mapping.

## m_Tgt_C_S_TTF_Pty_Rle_Alt_Id (PREFIX ALT)

| STEP_NO | Unit | Produced | Consumed | DEPENDENT_ON |
|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id` |  |  |  |
| 10 | `sp_snow_step_TTF_ALT_S10_KEYS` | `WRK_TTF_ALT_S1_KEYS` | -- |  |
| 20 | `sp_snow_step_TTF_ALT_S20_DEDUP` | `WRK_TTF_ALT_S2_DEDUP` | WRK_TTF_ALT_S1_KEYS | 10 |
| 30 | `sp_snow_pub_TTF_ALT_C_S_TTF_PTY_RLE_ALT_ID` | -- (writes target `C_S_TTF_PTY_RLE_ALT_ID`) | `WRK_TTF_ALT_S2_DEDUP` | 20 |

Dependency chain in words: step 0 driver -> step 10 (KEYS) -> step 20 (DEDUP) -> branch 30 (C_S_TTF_PTY_RLE_ALT_ID). Each transform step depends on the
step before it; each publish branch depends on the final routed step;
the driver row depends on nothing and gates the whole mapping.

## m_Tgt_C_S_TTF_Pty_Rle_Phn (PREFIX PHN)

| STEP_NO | Unit | Produced | Consumed | DEPENDENT_ON |
|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Phn` |  |  |  |
| 10 | `sp_snow_step_TTF_PHN_S10_SRC` | `WRK_TTF_PHN_S1_SRC` | -- |  |
| 20 | `sp_snow_step_TTF_PHN_S20_CHECKED` | `WRK_TTF_PHN_S2_CHECKED` | WRK_TTF_PHN_S1_SRC | 10 |
| 30 | `sp_snow_step_TTF_PHN_S30_ROUTED` | `WRK_TTF_PHN_S3_ROUTED` | WRK_TTF_PHN_S2_CHECKED | 20 |
| 40 | `sp_snow_pub_TTF_PHN_C_S_TTF_PTY_RLE_PHN` | -- (writes target `C_S_TTF_PTY_RLE_PHN`) | `WRK_TTF_PHN_S3_ROUTED` | 30 |
| 50 | `sp_snow_pub_TTF_PHN_EXC_STG_BAD_REC_MEMB` | -- (writes target `EXC_STG_BAD_REC_MEMB`) | `WRK_TTF_PHN_S3_ROUTED` | 30 |

Dependency chain in words: step 0 driver -> step 10 (SRC) -> step 20 (CHECKED) -> step 30 (ROUTED) -> branch 40 (C_S_TTF_PTY_RLE_PHN) -> branch 50 (EXC_STG_BAD_REC_MEMB). Each transform step depends on the
step before it; each publish branch depends on the final routed step;
the driver row depends on nothing and gates the whole mapping.

## Cross-mapping dependencies (via tables and runner order, NOT work tables)

- `m_Tgt_C_S_TTF_Pty_Validation` (run 1) maintains `STG_TTF_PTY_INACTIVE_STS` and `STG_TTF_PTY_INACTIVE_LOG`. Every later mapping reads the status table to filter out inactive parties: PTY step 10, ALT step 10, and PHN step 10 each carry a `NOT EXISTS (DEACTIVATION_STS IS NOT NULL)` filter against it. Validation itself also reads the status table (latest status per party) from the previous run.
- `m_Tgt_C_S_TTF_Pty` (run 2) step 40 reads target guard tables `C_S_TTF_PTY` and `C_S_TTF_PTY_RLE` (keys already loaded); its publish writes them. No later TTF mapping reads those tables as work inputs.
- `m_Tgt_C_S_TTF_Pty_Rle_Alt_Id` (run 3) step 20 reads target guard table `C_S_TTF_PTY_RLE_ALT_ID` (keys already loaded).
- `m_Tgt_C_S_TTF_Pty_Rle_Phn` (run 4) step 30 reads target guard table `C_S_TTF_PTY_RLE_PHN` (keys already loaded).
- Runner order enforces the chain: Validation before Pty before Alt_Id before Phn. Reordering the runner would break the inactive-status filter (later mappings would read a stale status table) even though no driver validates it -- that ordering is the operator's / runner's responsibility, as with flag consistency.

## Reference / lookup dependencies (not work tables, not gated)

- Validation steps read `V_TTF_ETL_SRC`, `STG_TTF_PTY_INACTIVE_STS`, `C_B_PTY_XREF`, and helpers 43 (junk names), 15 (name standardisation), 03 (blank check), 40 (exception lookup), 02 (deactivation status).
- Pty steps read `V_TTF_ETL_SRC`, `STG_TTF_PTY_INACTIVE_STS`, and helpers 43, 15, 17 (gender), 16 (birth date), 41 (code values), 40, 18 (exception code).
- Alt_Id steps read `V_TTF_ETL_SRC`, `STG_TTF_PTY_INACTIVE_STS`, and target `C_S_TTF_PTY_RLE_ALT_ID`.
- Phn steps read `V_TTF_ETL_SRC`, `STG_TTF_PTY_INACTIVE_STS`, target `C_S_TTF_PTY_RLE_PHN`, and helpers 23 (phone standardisation), 44 (area codes), 24 (phone validation), 40.
- Missing reference objects are documented, never invented: the same seven objects flagged by the ECI v2.1 live compile (V_LOOKUP_CODE_VALUE, REF_JUNK_NAME_LIST, REF_MATCHCODE_DESC, RDM.REF_PHN_AREA_CD, EXC_LOOKUP_CODE_VALUE, LOOKUP_CODE_VALUE, REF_DYLGHT_SVNGS_TM) underlie the shared helpers used here; no live compile was run for TTF.

## FSS

# FSS dependencies -- config-driven step-driver refactor (wf_FSS_Stage_Load)

Every unit, the work tables it produces and consumes (pipe-delimited;
here each unit consumes at most one work table), its DEPENDENT_ON
(producing STEP_NO within the same mapping), and the dependency chain in
words. Dependencies live in `l_in_*` variables, in the config
`DEPENDENT_ON` column, and here -- never in flag names.

Cross-mapping dependencies (target tables, not work tables -- the driver
does NOT gate on these; the workflow runner order enforces them):
- `m_Tgt_C_S_FSS_Pty_Validation` first: it maintains
  `STG_FSS_PTY_INACTIVE_STS`, which every later mapping reads via a
  NOT EXISTS (DEACTIVATION_STS IS NOT NULL) filter.
- `m_Tgt_C_S_FSS_Pty` second: it loads `C_S_FSS_PTY` / `C_S_FSS_PTY_RLE`,
  which later mappings' keys build on.
- Addresses, alternate IDs, phones / e-mails, relationships after that,
  in the original run-script order.

Within a mapping, every step consumes exactly the previous step's work
table; every publish branch consumes the last step's work table. Step 5
cleanup drops ALL of the mapping's work tables regardless of flags, so
disabling a producer while a consumer stays enabled fails loudly on the
missing input table (by design -- the operator must disable downstream
steps explicitly).

### m_Tgt_C_S_FSS_Pty_Validation (PREFIX FSS_VAL)

| Unit | STEP_NO | Produced | Consumed | DEPENDENT_ON |
|---|---|---|---|---|
| driver `sp_snow_main_m_Tgt_C_S_FSS_Pty_Validation` | 0 |  |  |  |
| step `sp_snow_step_FSS_VAL_S10_SRC` | 10 | WRK_FSS_VAL_S1_SRC |  |  |
| step `sp_snow_step_FSS_VAL_S20_ENRICHED` | 20 | WRK_FSS_VAL_S2_ENRICHED | WRK_FSS_VAL_S1_SRC | 10 |
| step `sp_snow_step_FSS_VAL_S30_ROUTED` | 30 | WRK_FSS_VAL_S3_ROUTED | WRK_FSS_VAL_S2_ENRICHED | 20 |
| branch `sp_snow_pub_FSS_VAL_EXC_STG_BAD_REC_MEMB` | 50 |  | WRK_FSS_VAL_S3_ROUTED | 30 |
| branch `sp_snow_pub_FSS_VAL_STG_FSS_PTY_INACTIVE_LOG` | 60 |  | WRK_FSS_VAL_S3_ROUTED | 30 |
| branch `sp_snow_pub_FSS_VAL_STG_FSS_PTY_INACTIVE_STS_NEW` | 70 |  | WRK_FSS_VAL_S3_ROUTED | 30 |
| branch `sp_snow_pub_FSS_VAL_STG_FSS_PTY_INACTIVE_STS_REACTIVATION` | 80 |  | WRK_FSS_VAL_S3_ROUTED | 30 |

Chain in words: driver gate -> step 30 (ROUTED) -> publish 50 (EXC_STG_BAD_REC_MEMB) -> publish 60 (STG_FSS_PTY_INACTIVE_LOG) -> publish 70 (STG_FSS_PTY_INACTIVE_STS_NEW) -> publish 80 (STG_FSS_PTY_INACTIVE_STS_REACTIVATION). Each unit depends only on the unit that produced the work table it consumes; publish branches all depend on the last transform step (30), not on each other, and run together in one transaction.

### m_Tgt_C_S_FSS_Pty (PREFIX FSS_PTY)

| Unit | STEP_NO | Produced | Consumed | DEPENDENT_ON |
|---|---|---|---|---|
| driver `sp_snow_main_m_Tgt_C_S_FSS_Pty` | 0 |  |  |  |
| step `sp_snow_step_FSS_PTY_S10_SRC` | 10 | WRK_FSS_PTY_S1_SRC |  |  |
| step `sp_snow_step_FSS_PTY_S20_DQ` | 20 | WRK_FSS_PTY_S2_DQ | WRK_FSS_PTY_S1_SRC | 10 |
| step `sp_snow_step_FSS_PTY_S30_DQ2` | 30 | WRK_FSS_PTY_S3_DQ2 | WRK_FSS_PTY_S2_DQ | 20 |
| step `sp_snow_step_FSS_PTY_S40_ROUTED` | 40 | WRK_FSS_PTY_S4_ROUTED | WRK_FSS_PTY_S3_DQ2 | 30 |
| branch `sp_snow_pub_FSS_PTY_C_S_FSS_PTY` | 50 |  | WRK_FSS_PTY_S4_ROUTED | 40 |
| branch `sp_snow_pub_FSS_PTY_C_S_FSS_PTY_RLE` | 60 |  | WRK_FSS_PTY_S4_ROUTED | 40 |
| branch `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_GENDER` | 70 |  | WRK_FSS_PTY_S4_ROUTED | 40 |
| branch `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH` | 80 |  | WRK_FSS_PTY_S4_ROUTED | 40 |
| branch `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY` | 90 |  | WRK_FSS_PTY_S4_ROUTED | 40 |
| branch `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_RACE` | 100 |  | WRK_FSS_PTY_S4_ROUTED | 40 |
| branch `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE` | 110 |  | WRK_FSS_PTY_S4_ROUTED | 40 |
| branch `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_SUFFIX` | 120 |  | WRK_FSS_PTY_S4_ROUTED | 40 |

Chain in words: driver gate -> step 40 (ROUTED) -> publish 50 (C_S_FSS_PTY) -> publish 60 (C_S_FSS_PTY_RLE) -> publish 70 (EXC_STG_BAD_REC_MEMB_GENDER) -> publish 80 (EXC_STG_BAD_REC_MEMB_BIRTH) -> publish 90 (EXC_STG_BAD_REC_MEMB_ETHNICITY) -> publish 100 (EXC_STG_BAD_REC_MEMB_RACE) -> publish 110 (EXC_STG_BAD_REC_MEMB_LANGUAGE) -> publish 120 (EXC_STG_BAD_REC_MEMB_SUFFIX). Each unit depends only on the unit that produced the work table it consumes; publish branches all depend on the last transform step (40), not on each other, and run together in one transaction.

### m_Tgt_C_S_FSS_Pty_Addr (PREFIX FSS_ADR)

| Unit | STEP_NO | Produced | Consumed | DEPENDENT_ON |
|---|---|---|---|---|
| driver `sp_snow_main_m_Tgt_C_S_FSS_Pty_Addr` | 0 |  |  |  |
| step `sp_snow_step_FSS_ADR_S10_SRC` | 10 | WRK_FSS_ADDR_S1_SRC |  |  |
| step `sp_snow_step_FSS_ADR_S20_VALIDATED` | 20 | WRK_FSS_ADDR_S2_VALIDATED | WRK_FSS_ADDR_S1_SRC | 10 |
| step `sp_snow_step_FSS_ADR_S30_FLAT` | 30 | WRK_FSS_ADDR_S3_FLAT | WRK_FSS_ADDR_S2_VALIDATED | 20 |
| step `sp_snow_step_FSS_ADR_S40_SCORED` | 40 | WRK_FSS_ADDR_S4_SCORED | WRK_FSS_ADDR_S3_FLAT | 30 |
| branch `sp_snow_pub_FSS_ADR_DQM_ADDRESS` | 50 |  | WRK_FSS_ADDR_S4_SCORED | 40 |
| branch `sp_snow_pub_FSS_ADR_C_S_FSS_PTY_RLE_ADDR` | 60 |  | WRK_FSS_ADDR_S4_SCORED | 40 |
| branch `sp_snow_pub_FSS_ADR_EXC_STG_BAD_REC_MEMB` | 70 |  | WRK_FSS_ADDR_S4_SCORED | 40 |

Chain in words: driver gate -> step 40 (SCORED) -> publish 50 (DQM_ADDRESS) -> publish 60 (C_S_FSS_PTY_RLE_ADDR) -> publish 70 (EXC_STG_BAD_REC_MEMB). Each unit depends only on the unit that produced the work table it consumes; publish branches all depend on the last transform step (40), not on each other, and run together in one transaction.

### m_Tgt_C_S_FSS_Pty_Rle_Alt_Id (PREFIX FSS_ALT)

| Unit | STEP_NO | Produced | Consumed | DEPENDENT_ON |
|---|---|---|---|---|
| driver `sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Alt_Id` | 0 |  |  |  |
| step `sp_snow_step_FSS_ALT_S10_SRC` | 10 | WRK_FSS_ALT_S1_SRC |  |  |
| step `sp_snow_step_FSS_ALT_S20_FILTERED` | 20 | WRK_FSS_ALT_S2_FILTERED | WRK_FSS_ALT_S1_SRC | 10 |
| branch `sp_snow_pub_FSS_ALT_C_S_FSS_PTY_RLE_ALT_ID` | 50 |  | WRK_FSS_ALT_S2_FILTERED | 20 |

Chain in words: driver gate -> step 20 (FILTERED) -> publish 50 (C_S_FSS_PTY_RLE_ALT_ID). Each unit depends only on the unit that produced the work table it consumes; publish branches all depend on the last transform step (20), not on each other, and run together in one transaction.

### m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr (PREFIX FSS_PHN)

| Unit | STEP_NO | Produced | Consumed | DEPENDENT_ON |
|---|---|---|---|---|
| driver `sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr` | 0 |  |  |  |
| step `sp_snow_step_FSS_PHN_S10_SRC` | 10 | WRK_FSS_PHN_S1_SRC |  |  |
| step `sp_snow_step_FSS_PHN_S20_DQ` | 20 | WRK_FSS_PHN_S2_DQ | WRK_FSS_PHN_S1_SRC | 10 |
| step `sp_snow_step_FSS_PHN_S30_CHECKED` | 30 | WRK_FSS_PHN_S3_CHECKED | WRK_FSS_PHN_S2_DQ | 20 |
| step `sp_snow_step_FSS_PHN_S40_ROUTED` | 40 | WRK_FSS_PHN_S4_ROUTED | WRK_FSS_PHN_S3_CHECKED | 30 |
| branch `sp_snow_pub_FSS_PHN_C_S_FSS_PTY_RLE_EADDR` | 50 |  | WRK_FSS_PHN_S4_ROUTED | 40 |
| branch `sp_snow_pub_FSS_PHN_EXC_STG_BAD_REC_MEMB_EMAIL` | 60 |  | WRK_FSS_PHN_S4_ROUTED | 40 |
| branch `sp_snow_pub_FSS_PHN_C_S_FSS_PTY_RLE_PHN` | 70 |  | WRK_FSS_PHN_S4_ROUTED | 40 |
| branch `sp_snow_pub_FSS_PHN_EXC_STG_BAD_REC_MEMB_PHONE` | 80 |  | WRK_FSS_PHN_S4_ROUTED | 40 |
| branch `sp_snow_pub_FSS_PHN_EXC_STG_BAD_REC_MEMB_EXTENSION` | 90 |  | WRK_FSS_PHN_S4_ROUTED | 40 |

Chain in words: driver gate -> step 40 (ROUTED) -> publish 50 (C_S_FSS_PTY_RLE_EADDR) -> publish 60 (EXC_STG_BAD_REC_MEMB_EMAIL) -> publish 70 (C_S_FSS_PTY_RLE_PHN) -> publish 80 (EXC_STG_BAD_REC_MEMB_PHONE) -> publish 90 (EXC_STG_BAD_REC_MEMB_EXTENSION). Each unit depends only on the unit that produced the work table it consumes; publish branches all depend on the last transform step (40), not on each other, and run together in one transaction.

### m_Tgt_C_S_FSS_Pty_Rle_Rel (PREFIX FSS_REL)

| Unit | STEP_NO | Produced | Consumed | DEPENDENT_ON |
|---|---|---|---|---|
| driver `sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Rel` | 0 |  |  |  |
| step `sp_snow_step_FSS_REL_S10_SRC` | 10 | WRK_FSS_REL_S1_SRC |  |  |
| step `sp_snow_step_FSS_REL_S20_CODED` | 20 | WRK_FSS_REL_S2_CODED | WRK_FSS_REL_S1_SRC | 10 |
| step `sp_snow_step_FSS_REL_S30_TYPED` | 30 | WRK_FSS_REL_S3_TYPED | WRK_FSS_REL_S2_CODED | 20 |
| step `sp_snow_step_FSS_REL_S40_FINAL` | 40 | WRK_FSS_REL_S4_FINAL | WRK_FSS_REL_S3_TYPED | 30 |
| branch `sp_snow_pub_FSS_REL_C_S_FSS_PTY_RLE_REL` | 50 |  | WRK_FSS_REL_S4_FINAL | 40 |
| branch `sp_snow_pub_FSS_REL_EXC_STG_BAD_REC_MEMB` | 60 |  | WRK_FSS_REL_S4_FINAL | 40 |

Chain in words: driver gate -> step 40 (FINAL) -> publish 50 (C_S_FSS_PTY_RLE_REL) -> publish 60 (EXC_STG_BAD_REC_MEMB). Each unit depends only on the unit that produced the work table it consumes; publish branches all depend on the last transform step (40), not on each other, and run together in one transaction.

## CRE

# CRE_DEPENDENCIES — m_Tgt_C_S_CRE_CARE_Clients, config-driven step-driver refactor

Workflow: `wf_CRE_Stage_Load_Ongoing`. Mapping: `m_Tgt_C_S_CRE_CARE_Clients`.
Every unit below is one row of `seed_etl_run_config_CRE.sql` (same STEP_NO,
procedure name, DEPENDENT_ON, produced/consumed work tables). Dependencies live
here, in the `l_in_*` variables, and in the config table's DEPENDENT_ON column
— never in flag names. The driver does NOT validate flag consistency: gating is
by IS_RUN_ENABLED only, and disabling a producer while a consumer stays enabled
fails loudly on the consumer's missing input table.

Work tables are pipe-delimited in the config columns; a unit that produces no
work table (publish branches) has an empty WORK_TABLES_PRODUCED. Base source
tables and final target tables are NOT work-table dependencies and are not
listed in WORK_TABLES_CONSUMED (they are named in each unit's own header).

## Units

| STEP_NO | Unit (procedure) | Kind | Produced | Consumed | DEPENDENT_ON | IS_DEPENDENT |
|---|---|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_CRE_CARE_Clients` (driver row) | DRIVER | | | | N |
| 10 | `sp_snow_step_CRE_CARE_S10_SRC_MRG` | TRANSFORM | `WRK_CRE_CARE_S1_SRC_MRG` | | | N |
| 20 | `sp_snow_step_CRE_CARE_S20_NAMED` | TRANSFORM | `WRK_CRE_CARE_S2_NAMED` | `WRK_CRE_CARE_S1_SRC_MRG` | 10 | Y |
| 30 | `sp_snow_step_CRE_CARE_S30_RANKED` | TRANSFORM | `WRK_CRE_CARE_S3_RANKED` | `WRK_CRE_CARE_S2_NAMED` | 20 | Y |
| 40 | `sp_snow_step_CRE_CARE_S40_FLAT` | TRANSFORM | `WRK_CRE_CARE_S4_FLAT` | `WRK_CRE_CARE_S3_RANKED` | 30 | Y |
| 50 | `sp_snow_step_CRE_CARE_S50_KEYED` | TRANSFORM | `WRK_CRE_CARE_S5_KEYED` | `WRK_CRE_CARE_S4_FLAT` | 40 | Y |
| 60 | `sp_snow_pub_CRE_CARE_CRE_SRC_MRG` | STATUS | | `WRK_CRE_CARE_S5_KEYED` | 50 | Y |
| 70 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_FIRST_NAME` | EXCEPTION | | `WRK_CRE_CARE_S5_KEYED` | 50 | Y |
| 80 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_LAST_NAME` | EXCEPTION | | `WRK_CRE_CARE_S5_KEYED` | 50 | Y |
| 90 | `sp_snow_pub_CRE_CARE_C_S_CRE_PTY` | SPINE | | `WRK_CRE_CARE_S5_KEYED` | 50 | Y |
| 100 | `sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE` | SPINE | | `WRK_CRE_CARE_S5_KEYED` | 50 | Y |
| 110 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_GENDER` | EXCEPTION | | `WRK_CRE_CARE_S5_KEYED` | 50 | Y |
| 120 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_SUFFIX` | EXCEPTION | | `WRK_CRE_CARE_S5_KEYED` | 50 | Y |
| 130 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_ETHNICITY` | EXCEPTION | | `WRK_CRE_CARE_S5_KEYED` | 50 | Y |
| 140 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_RACE` | EXCEPTION | | `WRK_CRE_CARE_S5_KEYED` | 50 | Y |
| 150 | `sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_ADDR` | SPINE | | `WRK_CRE_CARE_S5_KEYED` | 50 | Y |
| 160 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_ADDR` | EXCEPTION | | `WRK_CRE_CARE_S5_KEYED` | 50 | Y |
| 170 | `sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_PHN` | SPINE | | `WRK_CRE_CARE_S5_KEYED` | 50 | Y |
| 180 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_PHONE` | EXCEPTION | | `WRK_CRE_CARE_S5_KEYED` | 50 | Y |
| 190 | `sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_CARE` | SPINE | | `WRK_CRE_CARE_S5_KEYED` | 50 | Y |
| 200 | `sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_MEDICAID` | SPINE | | `WRK_CRE_CARE_S5_KEYED` | 50 | Y |
| 210 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_MEDICAID_ALT` | EXCEPTION | | `WRK_CRE_CARE_S5_KEYED` | 50 | Y |
| 220 | `sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_SSN` | SPINE | | `WRK_CRE_CARE_S5_KEYED` | 50 | Y |
| 230 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_SSN_ALT` | EXCEPTION | | `WRK_CRE_CARE_S5_KEYED` | 50 | Y |

## Dependency chains, in words

- **Transform chain (strictly linear):** step 10 produces the snapshot + merge-routing
  table; step 20 consumes it and produces the standardised table; step 30 consumes
  that and produces the ranked + enriched table; step 40 consumes that and produces
  the flattened table; step 50 consumes that and produces the keyed table. Each
  transform step depends on exactly the previous step, and on nothing else in
  work-table terms (reference lookups and helper functions are not work tables).
- **Publish fan-out:** all eighteen publish branches depend on step 50 only — each
  reads `WRK_CRE_CARE_S5_KEYED` and nothing else. No branch depends on another
  branch; branch order matters only for the original INSERT ALL order and for
  checkpoint/summary order, not for data (each branch reads the same keyed table
  with its own original WHEN guard, exactly as the original INSERT ALL branches
  each read the same final select).
- **Driver row:** step 0 depends on nothing; it gates the whole mapping. Step 5
  cleanup (dropping all five work tables) runs after the driver-row gate and
  before step 10, regardless of flags.
- **Full chain, end to end:** driver gate → step 5 cleanup → 10 → 20 → 30 → 40 → 50
  → (60, 70, 80, 90, 100, 110, 120, 130, 140, 150, 160, 170, 180, 190, 200, 210,
  220, 230 in one transaction) → job end. Disabling any single link does NOT
  cascade: downstream units that stay enabled fail on their missing input table
  instead of silently running on stale data.
- **Cross-mapping:** none. This workflow has a single mapping; no other mapping
  consumes any `WRK_CRE_*` table produced here.
