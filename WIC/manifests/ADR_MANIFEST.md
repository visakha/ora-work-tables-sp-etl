# ADR Manifest — m_Tgt_C_S_WIC_Pty_Addr, config-driven step-driver refactor (WIC ONLY)
Prefix: `WIC_ADR`, short: `ADR`. Base dir: `snowflake_all_drivers/WIC/`.
Source verified against: `snowflake_multisource/WIC/mappings/sp_snow_main_m_Tgt_C_S_WIC_Pty_Addr.sql` (step map `snowflake_multisource/WIC/STEP_MAP_WIC.md` agrees; where the step map and the file agreed, no discrepancy was found).
## Driver
Signature (IDENTICAL to the current main, verified by normalised comparison):

```sql
sp_snow_main_m_Tgt_C_S_WIC_Pty_Addr (

    P_MEMBER_HIERARCHY_CODE VARCHAR DEFAULT 'Member',        -- $Member_Hierarchy_Code
    P_MEMBER_HM_REL_TP_CD   VARCHAR DEFAULT 'Member Addr',   -- $Member_HM_REL_TP_CD
    P_JOB_RUN_ID            VARCHAR DEFAULT NULL

) RETURNS VARCHAR
```
File: `drivers/driver_sp_snow_main_m_Tgt_C_S_WIC_Pty_Addr.sql`

Driver behaviour: job-run-id generation exactly as now (WIC_ prefix) + `sp_etl_job_begin`; one config GATHER (nested `BEGIN/EXCEPTION`, defaults stand on failure) from `COMMON.ETL_RUN_CONFIG_TBL` (`WORKFLOW_NAME = 'wf_WIC_Stage_Load'`, `MAPPING_NAME = 'm_Tgt_C_S_WIC_Pty_Addr'`); driver-row `STEP_NO = 0` = `'N'` skips the whole mapping BEFORE step 5 cleanup (SKIPPED checkpoint `MAPPING_SKIPPED`, `sp_etl_job_finish` with a skipped message, early RETURN); step 5 cleanup unchanged (bare `DROP TABLE IF EXISTS`, no checkpoint); conditional step calls in order; ONE publish transaction calling the enabled branch procs in order; branch checkpoints ONLY after `COMMIT`; `TERMINATING` via `sp_etl_job_finish` with the same message style and RETURN format as now; exception block identical in shape (ROLLBACK + TERMINATING `JOB_END` FAILED checkpoint in v2 10-argument form + `sp_etl_job_fail` + RAISE). The exception checkpoint message uses the INFORMATION_SCHEMA wording (see ECI v2.1), not the old VW_ETL_OPEN_WORK_TABLES wording from the WIC mains.
## Steps

| STEP_NO | Proc | Kind | Produces | Consumes default | Original params used | Checkpoint STEP_NAME |
|---|---|---|---|---|---|---|
| 10 | `sp_snow_step_WIC_ADR_S10_ACTIVE` | TRANSFORM | `WRK_WIC_ADDR_S10_ACTIVE` — Active source addresses only (deactivation-status filter) plus the address key. Only step that reads V_WIC_ETL_SRC. | `` | none | `ACTIVE` |
| 20 | `sp_snow_step_WIC_ADR_S20_VALIDATED` | TRANSFORM | `WRK_WIC_ADDR_S20_VALIDATED` — Address validation with state TX, country US, zip only; state code resolved from the state lookup. | `WRK_WIC_ADDR_S10_ACTIVE` | none | `VALIDATED` |
| 30 | `sp_snow_step_WIC_ADR_S30_FLAT` | TRANSFORM | `WRK_WIC_ADDR_S30_FLAT` — Validation result pulled out into flat columns; match-code description resolved. | `WRK_WIC_ADDR_S20_VALIDATED` | none | `FLAT` |
| 40 | `sp_snow_step_WIC_ADR_S40_SCORED` | TRANSFORM | `WRK_WIC_ADDR_S40_SCORED` — Score (100 or 40), exception detail, held address lines, run constants, and the insert-only guards (uq_addr, uq_addr_exc). Target guard evaluated here, before publish, as in the original single query. | `WRK_WIC_ADDR_S30_FLAT` | `P_MEMBER_HIERARCHY_CODE`, `P_MEMBER_HM_REL_TP_CD` | `SCORED` |

Step proc signatures: the step's used original params (in original order) + `P_JOB_RUN_ID` + `P_RUN_TS` + `P_INPUT_TABLES` (pipe-delimited default naming work-table inputs; existence checked via INFORMATION_SCHEMA.TABLES + an EXECUTE IMMEDIATE probe of the first missing table — RAISE cannot carry a dynamic table name, so the native error surfaces; P_INPUT_TABLES is a declaration + check, NOT dynamic SQL; CTAS names tables literally). Step runs its CTAS verbatim + own checkpoint. Only the final step uses original params (where the mapping has any); earlier steps use no original params. Where original params carry defaults, `P_JOB_RUN_ID` / `P_RUN_TS` carry DEFAULT NULL (live-compile fix from ECI v2.1: never a required parameter after an optional one; drivers pass all parameters positionally, so behaviour is unchanged). Step files: `steps/sp_snow_step_WIC_ADR_S<nn>_<NAME>.sql`.
## Publish branches

Original publish was one step 50 with 3 INSERTs in one transaction. Each INSERT is now one branch proc, called by the driver inside ONE transaction in the same order, checkpointed by the driver only after COMMIT.

| STEP_NO | Proc | Kind | Target | WHERE guard | Consumes |
|---|---|---|---|---|---|
| 50 | `sp_snow_pub_WIC_ADR_DQM_ADDRESS` | VALIDATION | `DQM_ADDRESS` (every active address (address-quality table)) | `(unconditional)` | `WRK_WIC_ADDR_S40_SCORED` |
| 60 | `sp_snow_pub_WIC_ADR_C_S_WIC_PTY_RLE_ADDR` | SPINE | `C_S_WIC_PTY_RLE_ADDR` (good addresses) | `score = '100' AND uq_addr` | `WRK_WIC_ADDR_S40_SCORED` |
| 70 | `sp_snow_pub_WIC_ADR_EXC_STG_BAD_REC_MEMB` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` (exception addresses) | `score = '40' AND uq_addr_exc` | `WRK_WIC_ADDR_S40_SCORED` |

Branch proc signatures: `P_JOB_RUN_ID` + `P_RUN_TS` + `P_INPUT_TABLES` (default `WRK_WIC_ADDR_S40_SCORED`), no original params. Each returns `SQLROWCOUNT` as `NUMBER`. No transaction control, no checkpoint calls. Driver checkpoint STEP_NAMEs: `PUBLISH_DQM_ADDRESS`, `PUBLISH_C_S_WIC_PTY_RLE_ADDR`, `PUBLISH_EXC_STG_BAD_REC_MEMB`. Branch files: `publish/sp_snow_pub_WIC_ADR_<TARGET>[_<BRANCH>].sql`.
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
        t10["Step 10 ACTIVE"] --> t20["Step 20 VALIDATED"] --> t30["Step 30 FLAT"] --> t40["Step 40 SCORED"]
    end
    subgraph P5["Phase 5 - Publish"]
        direction TB
        p50["VALIDATION Step 50 DQM_ADDRESS"] --> p60["SPINE Step 60 C_S_WIC_PTY_RLE_ADDR"] --> p70["EXCEPTION Step 70 EXC_STG_BAD_REC_MEMB"]
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

- Insert-only: IDQ truncate of C_S_WIC_PTY_RLE_ADDR is not performed.
- Address type is the constant 002, so with the pass-through validator every address scores 100; exception addresses are logged only (Invalid Address per Address Doctor, Bad Value).
- Unfed ports are written as NULL, including SRC_STATE, even though TX goes to the validator.
- DQM_ADDRESS.PTY_SRC_KEY is LPAD(ID, 10, 0); the ECI-only F suffix never applies.
- VERSION_SEQ = 1; PERIOD_START_DATE and EFF_STRT_DT = DATE_ADDRESS_VALID_FROM; EFF_END_DT and PERIOD_REFERENCE_TIME are NULL.

## Verification performed (no live Snowflake available)

- All step CTAS compared to the current file after whitespace normalisation and the allowed substitutions only (`:l_run_ts` → `:P_RUN_TS`, `:c_mapping` → the local constant of the same name and value): all MATCH.
- All branch INSERTs compared likewise: all MATCH.
- Driver name/signature compared to the current main (normalised): IDENTICAL.
- Style greps (code lines): 0 `DROPPED` checkpoint calls, 0 `P_RESUME_STEP`, 0 cursors, 0 `sp_etl_checkpoint` calls and 0 transaction statements in publish-branch code, 0 checkpoint calls between the driver's `BEGIN TRANSACTION` and `COMMIT`, `TRANSIENT` work tables only with unchanged names, `P_JOB_RUN_ID` in every new proc.
- Every `sp_etl_checkpoint` call parses (balanced-paren) to exactly 10 arguments; no `||` in any `COMMENT ON` (no COMMENT ON statements are emitted by this package at all); no required-after-optional signature order.
- Flag/input/publish-count naming uniform under the unit rule (strip `sp_snow_step_` / `sp_snow_pub_`, prepend `l_flag_` / `l_in_` / `l_pub_`); zero `l_flag_[0-9]`, `l_cons_`, `l_run_`, `v_run_`, `l_cfg_` names.
- No live Snowflake compile, run, or row-count parity run was possible in this environment; that step is required before use.
- Scope: WIC `m_Tgt_C_S_WIC_Pty_Addr` only. No other source was touched; the current main file was not modified.
## Deviations / uncertainties — nothing silently shipped

1. **Combined publish checkpoint split (by design, per brief).** The current file writes ONE step-50 `PUBLISH` checkpoint with the routed-row count. The refactor writes one checkpoint per branch (STEP_NOs 50–70) with that branch's count, plus a per-branch helper36 summary line instead of the single publish line. Total published rows are recoverable by summing the branch counts; there is no longer a single combined publish row.
2. **Step checkpoint TARGET_TABLE is NULL for every step.** The WIC mains pass NULL as the step target (the publish target list lives only on the old combined publish checkpoint); the refactor keeps NULL on step checkpoints and puts the single branch target on each branch checkpoint.
3. **Config columns not read.** `IS_DEPENDENT`, `DEPENDENT_ON` and `WORK_TABLES_PRODUCED` exist in `ETL_RUN_CONFIG_TBL` but are not read by this driver; gating is by `IS_RUN_ENABLED` only, per the brief.
4. **No cascade on skip.** Skipping is per step/branch only. If an upstream step is disabled but a downstream step stays enabled, the downstream step's existence check raises the missing work table rather than running on stale data. Operators must disable downstream steps explicitly.
5. **'SKIPPED' status is a choice to confirm.** `JOB_CONTROL_ETL.STEP_STATUS` has no CHECK constraint (only a DDL comment listing STARTED | COMPLETED | FAILED); `SKIPPED` rows are used here as specified and should be confirmed by the user.
6. **Compile-time verification items (no live Snowflake here).** `l_rows := (CALL proc(...));` scalar-call capture form; `IF` blocks inside the driver's `BEGIN TRANSACTION` / `COMMIT` region (branch CALLs gated by flags); the multi-variable `SELECT ... INTO :a, :b, ...` in the GATHER; unused-parameter warnings, if any, for `P_RUN_TS` in steps/branches where it is carried for signature uniformity.
