# VAL Manifest — m_Tgt_C_S_WIC_Pty_Validation, config-driven step-driver refactor (WIC ONLY)
Prefix: `WIC_VAL`, short: `VAL`. Base dir: `snowflake_all_drivers/WIC/`.
Source verified against: `snowflake_multisource/WIC/mappings/sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation.sql` (step map `snowflake_multisource/WIC/STEP_MAP_WIC.md` agrees; where the step map and the file agreed, no discrepancy was found).
## Driver
Signature (IDENTICAL to the current main, verified by normalised comparison):

```sql
sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation (

    P_JOB_RUN_ID VARCHAR DEFAULT NULL

) RETURNS VARCHAR
```
File: `drivers/driver_sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation.sql`

Driver behaviour: job-run-id generation exactly as now (WIC_ prefix) + `sp_etl_job_begin`; one config GATHER (nested `BEGIN/EXCEPTION`, defaults stand on failure) from `COMMON.ETL_RUN_CONFIG_TBL` (`WORKFLOW_NAME = 'wf_WIC_Stage_Load'`, `MAPPING_NAME = 'm_Tgt_C_S_WIC_Pty_Validation'`); driver-row `STEP_NO = 0` = `'N'` skips the whole mapping BEFORE step 5 cleanup (SKIPPED checkpoint `MAPPING_SKIPPED`, `sp_etl_job_finish` with a skipped message, early RETURN); step 5 cleanup unchanged (bare `DROP TABLE IF EXISTS`, no checkpoint); conditional step calls in order; ONE publish transaction calling the enabled branch procs in order; branch checkpoints ONLY after `COMMIT`; `TERMINATING` via `sp_etl_job_finish` with the same message style and RETURN format as now; exception block identical in shape (ROLLBACK + TERMINATING `JOB_END` FAILED checkpoint in v2 10-argument form + `sp_etl_job_fail` + RAISE). The exception checkpoint message uses the INFORMATION_SCHEMA wording (see ECI v2.1), not the old VW_ETL_OPEN_WORK_TABLES wording from the WIC mains.
## Steps

| STEP_NO | Proc | Kind | Produces | Consumes default | Original params used | Checkpoint STEP_NAME |
|---|---|---|---|---|---|---|
| 10 | `sp_snow_step_WIC_VAL_S10_ENRICHED` | TRANSFORM | `WRK_WIC_VAL_S10_ENRICHED` — Source parties joined to the current deactivation status (latest row per source key) and the cross-reference hub state, with standardised names computed. The status and cross-reference lookups stay inline here because they are reference lookups, not data stages. Only step that reads V_WIC_ETL_SRC. | `` | none | `ENRICHED` |
| 20 | `sp_snow_step_WIC_VAL_S20_NAMED` | TRANSFORM | `WRK_WIC_VAL_S20_NAMED` — Standardised first, middle and last names pulled out; the blank-name test applied (name_missing). | `WRK_WIC_VAL_S10_ENRICHED` | none | `NAMED_BLANK_TEST` |
| 30 | `sp_snow_step_WIC_VAL_S30_ROUTED` | TRANSFORM | `WRK_WIC_VAL_S30_ROUTED` — Exception code, attribute name and value, new deactivation status from hub state, looked-up exception description and type, run constants, and the first-row-per-exception-key flag (uq_exc_name). Computed before publish, so routing sees the pre-run status. | `WRK_WIC_VAL_S20_NAMED` |  | `ROUTED` |

Step proc signatures: the step's used original params (in original order) + `P_JOB_RUN_ID` + `P_RUN_TS` + `P_INPUT_TABLES` (pipe-delimited default naming work-table inputs; existence checked via INFORMATION_SCHEMA.TABLES + an EXECUTE IMMEDIATE probe of the first missing table — RAISE cannot carry a dynamic table name, so the native error surfaces; P_INPUT_TABLES is a declaration + check, NOT dynamic SQL; CTAS names tables literally). Step runs its CTAS verbatim + own checkpoint. Only the final step uses original params (where the mapping has any); earlier steps use no original params. Where original params carry defaults, `P_JOB_RUN_ID` / `P_RUN_TS` carry DEFAULT NULL (live-compile fix from ECI v2.1: never a required parameter after an optional one; drivers pass all parameters positionally, so behaviour is unchanged). Step files: `steps/sp_snow_step_WIC_VAL_S<nn>_<NAME>.sql`.
## Publish branches

Original publish was one step 40 with 4 INSERTs in one transaction. Each INSERT is now one branch proc, called by the driver inside ONE transaction in the same order, checkpointed by the driver only after COMMIT.

| STEP_NO | Proc | Kind | Target | WHERE guard | Consumes |
|---|---|---|---|---|---|
| 40 | `sp_snow_pub_WIC_VAL_EXC_STG_BAD_REC_MEMB` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` (invalid-name exceptions) | `name_missing AND uq_exc_name` | `WRK_WIC_VAL_S30_ROUTED` |
| 50 | `sp_snow_pub_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_DEACTIVATION` | STATUS | `STG_WIC_PTY_INACTIVE_LOG` (deactivation log rows) | `name_missing` | `WRK_WIC_VAL_S30_ROUTED` |
| 60 | `sp_snow_pub_WIC_VAL_STG_WIC_PTY_INACTIVE_STS` | STATUS | `STG_WIC_PTY_INACTIVE_STS` (new deactivation-status rows) | `name_missing AND deactivation_sts IS NULL` | `WRK_WIC_VAL_S30_ROUTED` |
| 70 | `sp_snow_pub_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_REACTIVATION` | STATUS | `STG_WIC_PTY_INACTIVE_LOG` (reactivation log rows) | `deactivation_sts IS NOT NULL AND NOT name_missing` | `WRK_WIC_VAL_S30_ROUTED` |

Branch proc signatures: `P_JOB_RUN_ID` + `P_RUN_TS` + `P_INPUT_TABLES` (default `WRK_WIC_VAL_S30_ROUTED`), no original params. Each returns `SQLROWCOUNT` as `NUMBER`. No transaction control, no checkpoint calls. Driver checkpoint STEP_NAMEs: `PUBLISH_EXC_STG_BAD_REC_MEMB`, `PUBLISH_STG_WIC_PTY_INACTIVE_LOG_DEACTIVATION`, `PUBLISH_STG_WIC_PTY_INACTIVE_STS`, `PUBLISH_STG_WIC_PTY_INACTIVE_LOG_REACTIVATION`. Branch files: `publish/sp_snow_pub_WIC_VAL_<TARGET>[_<BRANCH>].sql`.
## Phase-flow diagram

Six phases following the actual driver flow. Publish stays ONE subgraph (one transaction); spine, status, exception and validation branch groups are distinguished by label prefixes inside that subgraph, never by splitting the transaction.

```mermaid
flowchart LR
    subgraph P1["Phase 1 - Begin"]
        direction TB
        a1["Job begin"]
    end
    subgraph P2["Phase 2 - Configure"]
        direction TB
        b1["Config gather"] --> b2["Driver gate"]
    end
    subgraph P3["Phase 3 - Clean"]
        direction TB
        c1["Step 5 cleanup"]
    end
    subgraph P4["Phase 4 - Transform"]
        direction TB
        t10["Step 10 ENRICHED"] --> t20["Step 20 NAMED"] --> t30["Step 30 ROUTED"]
    end
    subgraph P5["Phase 5 - Publish"]
        direction TB
        p40["EXCEPTION Step 40 EXC_STG_BAD_REC_MEMB"] --> p50["STATUS Step 50 STG_WIC_PTY_INACTIVE_LOG"] --> p60["STATUS Step 60 STG_WIC_PTY_INACTIVE_STS"] --> p70["STATUS Step 70 STG_WIC_PTY_INACTIVE_LOG"]
    end
    subgraph P6["Phase 6 - Close"]
        direction TB
        z1["Job end"] --> z2["Work tables left standing"] --> z3["RETURN summary"]
    end
    P1 --> P2
    P2 --> P3
    P3 --> P4
    P4 --> P5
    P5 --> P6
```
## Preserved quirks (business logic preserved, not fixed)

- Insert-only: the IDQ delete of STG_WIC_PTY_INACTIVE_STS is NOT performed. A reactivation therefore only writes a log row; the status row stays, so the party stays excluded by the downstream NOT EXISTS filters until something else removes the status row. This is the Snowflake Yes/No reactivation verdict for WIC (IDQ re-admits via Upd_Delete_Inactive, which the Snowflake code does not perform).
- Deactivation detection is pure ETL interpretation: no source deactivation flag is read. Only the blank-standardised-name test (name_missing) drives deactivation and reactivation.
- The cross-reference lookup filters on TRIM(ROWID_SYSTEM) = WIC.
- No timeline handling in this mapping (no VERSION_SEQ).
- Step 30 (and therefore the publish) is computed before any publish INSERT runs, so all routing sees the pre-run deactivation status, as in the original single INSERT ALL.

## Verification performed (no live Snowflake available)

- All step CTAS compared to the current file after whitespace normalisation and the allowed substitutions only (`:l_run_ts` → `:P_RUN_TS`, `:c_mapping` → the local constant of the same name and value): all MATCH.
- All branch INSERTs compared likewise: all MATCH.
- Driver name/signature compared to the current main (normalised): IDENTICAL.
- Style greps (code lines): 0 `DROPPED` checkpoint calls, 0 `P_RESUME_STEP`, 0 cursors, 0 `sp_etl_checkpoint` calls and 0 transaction statements in publish-branch code, 0 checkpoint calls between the driver's `BEGIN TRANSACTION` and `COMMIT`, `TRANSIENT` work tables only with unchanged names, `P_JOB_RUN_ID` in every new proc.
- Every `sp_etl_checkpoint` call parses (balanced-paren) to exactly 10 arguments; no `||` in any `COMMENT ON` (no COMMENT ON statements are emitted by this package at all); no required-after-optional signature order.
- Flag/input/publish-count naming uniform under the unit rule (strip `sp_snow_step_` / `sp_snow_pub_`, prepend `l_flag_` / `l_in_` / `l_pub_`); zero `l_flag_[0-9]`, `l_cons_`, `l_run_`, `v_run_`, `l_cfg_` names.
- No live Snowflake compile, run, or row-count parity run was possible in this environment; that step is required before use.
- Scope: WIC `m_Tgt_C_S_WIC_Pty_Validation` only. No other source was touched; the current main file was not modified.
## Deviations / uncertainties — nothing silently shipped

1. **Combined publish checkpoint split (by design, per brief).** The current file writes ONE step-40 `PUBLISH` checkpoint with the routed-row count. The refactor writes one checkpoint per branch (STEP_NOs 40–70) with that branch's count, plus a per-branch helper36 summary line instead of the single publish line. Total published rows are recoverable by summing the branch counts; there is no longer a single combined publish row.
2. **Step checkpoint TARGET_TABLE is NULL for every step.** The WIC mains pass NULL as the step target (the publish target list lives only on the old combined publish checkpoint); the refactor keeps NULL on step checkpoints and puts the single branch target on each branch checkpoint.
3. **Config columns not read.** `IS_DEPENDENT`, `DEPENDENT_ON` and `WORK_TABLES_PRODUCED` exist in `ETL_RUN_CONFIG_TBL` but are not read by this driver; gating is by `IS_RUN_ENABLED` only, per the brief.
4. **No cascade on skip.** Skipping is per step/branch only. If an upstream step is disabled but a downstream step stays enabled, the downstream step's existence check raises the missing work table rather than running on stale data. Operators must disable downstream steps explicitly.
5. **'SKIPPED' status is a choice to confirm.** `JOB_CONTROL_ETL.STEP_STATUS` has no CHECK constraint (only a DDL comment listing STARTED | COMPLETED | FAILED); `SKIPPED` rows are used here as specified and should be confirmed by the user.
6. **Compile-time verification items (no live Snowflake here).** `l_rows := (CALL proc(...));` scalar-call capture form; `IF` blocks inside the driver's `BEGIN TRANSACTION` / `COMMIT` region (branch CALLs gated by flags); the multi-variable `SELECT ... INTO :a, :b, ...` in the GATHER; unused-parameter warnings, if any, for `P_RUN_TS` in steps/branches where it is carried for signature uniformity.
