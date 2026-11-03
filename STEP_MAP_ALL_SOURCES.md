# Step map — all sources (modular step drivers, v2.1 style)

One section per source, in workflow order. ECI's map is the v2.1 original; the other five were rebuilt in exactly that style. Driver names/signatures are identical to the multi-source simplified mains; runners are verbatim.

---
## TRS

---
## ECI

---
## WIC

---
## TTF

---
## FSS

---
## CRE

## ECI

# STEP MAP — ECI config-driven step drivers

> **v2 note:** driver flag variables were renamed from numbers to unit names
> (`l_flag_30` → `l_flag_ECI_PTY_S30_DQ`, `l_flag_100` →
> `l_flag_ECI_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY`; same rule for `l_in_*`
> and `l_pub_*`). Step numbers, proc names, and checkpoint `STEP_NAME`
> strings below are unchanged. The checkpoint *call* is now 10 positional
> parameters (SOURCE, JOB_RUN_ID, WORKFLOW_NAME, MAPPING_NAME, STATE,
> STEP_NAME, STEP_STATUS, TARGET_TABLE, MESSAGE, ERROR_MESSAGE) — rows no
> longer carry step numbers, row counts, or work-table actions (see the
> package README for the lossy-simplification statement).

Companion to the multi-source package's `ECI/STEP_MAP_ECI.md`. Same business SQL, re-housed: each current step is one `sp_snow_step_*` proc, each current publish INSERT is one `sp_snow_pub_*` proc, and the current `_main_` proc is now a thin driver that reads `COMMON.ETL_RUN_CONFIG_TBL` and calls them conditionally. Step numbers are unchanged; publish branches take the current publish number, then +10 each.

Runner order is unchanged (`ECI/runners/sp_etl_run_wf_ECI_Stage_Load.sql`, verbatim from the multi-source package): Validation → Pty → Addr → Phn_And_EAddr → Alt_Id → Rel → Reactivation Family_Addr → Family_Phn → Medicaid. Driver signatures are identical to the current mains, so the runner needed no edit.

## PTY — m_Tgt_C_S_ECI_Pty

Driver: `sp_snow_main_m_Tgt_C_S_ECI_Pty`

| STEP_NO | Proc | Produces / target | Consumes | Kind |
|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_ECI_Pty` | _(driver)_ | _(none)_ | DRIVER |
| 10 | `sp_snow_step_ECI_PTY_S10_SRC` | `WRK_ECI_PTY_S10_SRC` | `_(none)_` | TRANSFORM |
| 20 | `sp_snow_step_ECI_PTY_S20_ACTIVE` | `WRK_ECI_PTY_S20_ACTIVE` | `WRK_ECI_PTY_S10_SRC` | TRANSFORM |
| 30 | `sp_snow_step_ECI_PTY_S30_DQ` | `WRK_ECI_PTY_S30_DQ` | `WRK_ECI_PTY_S20_ACTIVE` | TRANSFORM |
| 40 | `sp_snow_step_ECI_PTY_S40_DQ2` | `WRK_ECI_PTY_S40_DQ2` | `WRK_ECI_PTY_S30_DQ` | TRANSFORM |
| 50 | `sp_snow_step_ECI_PTY_S50_READY` | `WRK_ECI_PTY_S50_READY` | `WRK_ECI_PTY_S40_DQ2` | TRANSFORM |
| 60 | `sp_snow_pub_ECI_PTY_C_S_ECI_PTY` | `C_S_ECI_PTY` | `WRK_ECI_PTY_S50_READY` | SPINE |
| 70 | `sp_snow_pub_ECI_PTY_C_S_ECI_PTY_RLE` | `C_S_ECI_PTY_RLE` | `WRK_ECI_PTY_S50_READY` | SPINE |
| 80 | `sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_GENDER` | `EXC_STG_BAD_REC_MEMB` | `WRK_ECI_PTY_S50_READY` | EXCEPTION |
| 90 | `sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_BIRTH` | `EXC_STG_BAD_REC_MEMB` | `WRK_ECI_PTY_S50_READY` | EXCEPTION |
| 100 | `sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY` | `EXC_STG_BAD_REC_MEMB` | `WRK_ECI_PTY_S50_READY` | EXCEPTION |
| 110 | `sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_RACE` | `EXC_STG_BAD_REC_MEMB` | `WRK_ECI_PTY_S50_READY` | EXCEPTION |
| 120 | `sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE` | `EXC_STG_BAD_REC_MEMB` | `WRK_ECI_PTY_S50_READY` | EXCEPTION |

## ADR — m_Tgt_C_S_ECI_Pty_Addr

Driver: `sp_snow_main_m_Tgt_C_S_ECI_Pty_Addr`

| STEP_NO | Proc | Produces / target | Consumes | Kind |
|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_ECI_Pty_Addr` | _(driver)_ | _(none)_ | DRIVER |
| 10 | `sp_snow_step_ECI_ADR_S10_SRC` | `WRK_ECI_ADR_S10_SRC` | `_(none)_` | TRANSFORM |
| 20 | `sp_snow_step_ECI_ADR_S20_KEYED` | `WRK_ECI_ADR_S20_KEYED` | `WRK_ECI_ADR_S10_SRC` | TRANSFORM |
| 30 | `sp_snow_step_ECI_ADR_S30_VALIDATED` | `WRK_ECI_ADR_S30_VALIDATED` | `WRK_ECI_ADR_S20_KEYED` | TRANSFORM |
| 40 | `sp_snow_step_ECI_ADR_S40_FLAT` | `WRK_ECI_ADR_S40_FLAT` | `WRK_ECI_ADR_S30_VALIDATED` | TRANSFORM |
| 50 | `sp_snow_step_ECI_ADR_S50_READY` | `WRK_ECI_ADR_S50_READY` | `WRK_ECI_ADR_S40_FLAT` | TRANSFORM |
| 60 | `sp_snow_pub_ECI_ADR_DQM_ADDRESS` | `DQM_ADDRESS` | `WRK_ECI_ADR_S50_READY` | VALIDATION |
| 70 | `sp_snow_pub_ECI_ADR_C_S_ECI_PTY_RLE_ADDR` | `C_S_ECI_PTY_RLE_ADDR` | `WRK_ECI_ADR_S50_READY` | SPINE |
| 80 | `sp_snow_pub_ECI_ADR_EXC_STG_BAD_REC_MEMB` | `EXC_STG_BAD_REC_MEMB` | `WRK_ECI_ADR_S50_READY` | EXCEPTION |

## ALT — m_Tgt_C_S_ECI_Pty_Rle_Alt_Id

Driver: `sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id`

| STEP_NO | Proc | Produces / target | Consumes | Kind |
|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id` | _(driver)_ | _(none)_ | DRIVER |
| 10 | `sp_snow_step_ECI_ALT_S10_SRC` | `WRK_ECI_ALT_S10_SRC` | `_(none)_` | TRANSFORM |
| 20 | `sp_snow_step_ECI_ALT_S20_ACTIVE` | `WRK_ECI_ALT_S20_ACTIVE` | `WRK_ECI_ALT_S10_SRC` | TRANSFORM |
| 30 | `sp_snow_step_ECI_ALT_S30_ROUTED` | `WRK_ECI_ALT_S30_ROUTED` | `WRK_ECI_ALT_S20_ACTIVE` | TRANSFORM |
| 40 | `sp_snow_step_ECI_ALT_S40_READY` | `WRK_ECI_ALT_S40_READY` | `WRK_ECI_ALT_S30_ROUTED` | TRANSFORM |
| 50 | `sp_snow_pub_ECI_ALT_C_S_ECI_PTY_RLE_ALT_ID` | `C_S_ECI_PTY_RLE_ALT_ID` | `WRK_ECI_ALT_S40_READY` | SPINE |
| 60 | `sp_snow_pub_ECI_ALT_EXC_STG_BAD_REC_MEMB_SSN` | `EXC_STG_BAD_REC_MEMB` | `WRK_ECI_ALT_S40_READY` | EXCEPTION |
| 70 | `sp_snow_pub_ECI_ALT_EXC_STG_BAD_REC_MEMB_MEDICAID` | `EXC_STG_BAD_REC_MEMB` | `WRK_ECI_ALT_S40_READY` | EXCEPTION |

## PHN — m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr

Driver: `sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr`

| STEP_NO | Proc | Produces / target | Consumes | Kind |
|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr` | _(driver)_ | _(none)_ | DRIVER |
| 10 | `sp_snow_step_ECI_PHN_S10_SRC` | `WRK_ECI_PHN_S10_SRC` | `_(none)_` | TRANSFORM |
| 20 | `sp_snow_step_ECI_PHN_S20_ACTIVE` | `WRK_ECI_PHN_S20_ACTIVE` | `WRK_ECI_PHN_S10_SRC` | TRANSFORM |
| 30 | `sp_snow_step_ECI_PHN_S30_DQ` | `WRK_ECI_PHN_S30_DQ` | `WRK_ECI_PHN_S20_ACTIVE` | TRANSFORM |
| 40 | `sp_snow_step_ECI_PHN_S40_ROUTED` | `WRK_ECI_PHN_S40_ROUTED` | `WRK_ECI_PHN_S30_DQ` | TRANSFORM |
| 50 | `sp_snow_step_ECI_PHN_S50_READY` | `WRK_ECI_PHN_S50_READY` | `WRK_ECI_PHN_S40_ROUTED` | TRANSFORM |
| 60 | `sp_snow_pub_ECI_PHN_C_S_ECI_PTY_RLE_PHN` | `C_S_ECI_PTY_RLE_PHN` | `WRK_ECI_PHN_S50_READY` | SPINE |
| 70 | `sp_snow_pub_ECI_PHN_EXC_STG_BAD_REC_MEMB_PHONE` | `EXC_STG_BAD_REC_MEMB` | `WRK_ECI_PHN_S50_READY` | EXCEPTION |
| 80 | `sp_snow_pub_ECI_PHN_C_S_ECI_PTY_RLE_EADDR` | `C_S_ECI_PTY_RLE_EADDR` | `WRK_ECI_PHN_S50_READY` | SPINE |
| 90 | `sp_snow_pub_ECI_PHN_EXC_STG_BAD_REC_MEMB_EMAIL` | `EXC_STG_BAD_REC_MEMB` | `WRK_ECI_PHN_S50_READY` | EXCEPTION |

## REL — m_Tgt_C_S_ECI_Pty_Rle_Rel

Driver: `sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel`

| STEP_NO | Proc | Produces / target | Consumes | Kind |
|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel` | _(driver)_ | _(none)_ | DRIVER |
| 10 | `sp_snow_step_ECI_REL_S10_SRC` | `WRK_ECI_REL_S10_SRC` | `_(none)_` | TRANSFORM |
| 20 | `sp_snow_step_ECI_REL_S20_KEYED` | `WRK_ECI_REL_S20_KEYED` | `WRK_ECI_REL_S10_SRC` | TRANSFORM |
| 30 | `sp_snow_step_ECI_REL_S30_TYPED` | `WRK_ECI_REL_S30_TYPED` | `WRK_ECI_REL_S20_KEYED` | TRANSFORM |
| 40 | `sp_snow_step_ECI_REL_S40_READY` | `WRK_ECI_REL_S40_READY` | `WRK_ECI_REL_S30_TYPED` | TRANSFORM |
| 50 | `sp_snow_pub_ECI_REL_C_S_ECI_PTY_RLE_REL` | `C_S_ECI_PTY_RLE_REL` | `WRK_ECI_REL_S40_READY` | SPINE |
| 60 | `sp_snow_pub_ECI_REL_EXC_STG_BAD_REC_MEMB` | `EXC_STG_BAD_REC_MEMB` | `WRK_ECI_REL_S40_READY` | EXCEPTION |

## VAL — m_Tgt_C_S_ECI_Pty_Validation

Driver: `sp_snow_main_m_Tgt_C_S_ECI_Pty_Validation`

| STEP_NO | Proc | Produces / target | Consumes | Kind |
|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_ECI_Pty_Validation` | _(driver)_ | _(none)_ | DRIVER |
| 10 | `sp_snow_step_ECI_VAL_S10_SRC` | `WRK_ECI_VAL_S10_SRC` | `_(none)_` | TRANSFORM |
| 20 | `sp_snow_step_ECI_VAL_S20_ENRICHED` | `WRK_ECI_VAL_S20_ENRICHED` | `WRK_ECI_VAL_S10_SRC` | TRANSFORM |
| 30 | `sp_snow_step_ECI_VAL_S30_ROUTED` | `WRK_ECI_VAL_S30_ROUTED` | `WRK_ECI_VAL_S20_ENRICHED` | TRANSFORM |
| 40 | `sp_snow_pub_ECI_VAL_EXC_STG_BAD_REC_MEMB` | `EXC_STG_BAD_REC_MEMB` | `WRK_ECI_VAL_S30_ROUTED` | EXCEPTION |
| 50 | `sp_snow_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_DEACTIVATION` | `STG_ECI_PTY_INACTIVE_LOG` | `WRK_ECI_VAL_S30_ROUTED` | STATUS |
| 60 | `sp_snow_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_STS` | `STG_ECI_PTY_INACTIVE_STS` | `WRK_ECI_VAL_S30_ROUTED` | STATUS |
| 70 | `sp_snow_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_REACTIVATION` | `STG_ECI_PTY_INACTIVE_LOG` | `WRK_ECI_VAL_S30_ROUTED` | STATUS |

## RFA — m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr

Driver: `sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr`

| STEP_NO | Proc | Produces / target | Consumes | Kind |
|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr` | _(driver)_ | _(none)_ | DRIVER |
| 10 | `sp_snow_step_ECI_RFA_S10_LATEST` | `WRK_ECI_RFA_S10_LATEST` | `_(none)_` | TRANSFORM |
| 20 | `sp_snow_step_ECI_RFA_S20_KEEPNEW` | `WRK_ECI_RFA_S20_KEEPNEW` | `WRK_ECI_RFA_S10_LATEST` | TRANSFORM |
| 30 | `sp_snow_pub_ECI_RFA_STG_ECI_D_FAMILY_ADDRESS` | `STG_ECI_D_FAMILY_ADDRESS` | `WRK_ECI_RFA_S20_KEEPNEW` | STATUS |

## RFP — m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn

Driver: `sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn`

| STEP_NO | Proc | Produces / target | Consumes | Kind |
|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn` | _(driver)_ | _(none)_ | DRIVER |
| 10 | `sp_snow_step_ECI_RFP_S10_LATEST` | `WRK_ECI_RFP_S10_LATEST` | `_(none)_` | TRANSFORM |
| 20 | `sp_snow_step_ECI_RFP_S20_KEEPNEW` | `WRK_ECI_RFP_S20_KEEPNEW` | `WRK_ECI_RFP_S10_LATEST` | TRANSFORM |
| 30 | `sp_snow_pub_ECI_RFP_STG_ECI_D_FAMILY_PHONE` | `STG_ECI_D_FAMILY_PHONE` | `WRK_ECI_RFP_S20_KEEPNEW` | STATUS |

## RFM — m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid

Driver: `sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid`

| STEP_NO | Proc | Produces / target | Consumes | Kind |
|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid` | _(driver)_ | _(none)_ | DRIVER |
| 10 | `sp_snow_step_ECI_RFM_S10_LATEST` | `WRK_ECI_RFM_S10_LATEST` | `_(none)_` | TRANSFORM |
| 20 | `sp_snow_step_ECI_RFM_S20_KEEPNEW` | `WRK_ECI_RFM_S20_KEEPNEW` | `WRK_ECI_RFM_S10_LATEST` | TRANSFORM |
| 30 | `sp_snow_pub_ECI_RFM_STG_ECI_D_MEDICAID` | `STG_ECI_D_MEDICAID` | `WRK_ECI_RFM_S20_KEEPNEW` | STATUS |

## TRS

# TRS_STEP_MAP — TRS step-driver refactor (all 15 mappings)

Source of truth: the step numbers, step names, work tables and publish
targets below are copied from the current mains in
`snowflake_multisource/TRS/mappings/` (the simplified multi-source TRS
rewrite). Business logic is unchanged; the refactor only splits each main
into a config-driven driver + step procs + publish-branch procs, in the
ECI v2.1 template style.

## Notes (apply to every mapping below)

- **Control calls:** every checkpoint call passes exactly 10 positional
  arguments: `P_SOURCE, P_JOB_RUN_ID, P_WORKFLOW_NAME, P_MAPPING_NAME,
  P_STATE, P_STEP_NAME, P_STEP_STATUS, P_TARGET_TABLE, P_MESSAGE,
  P_ERROR_MESSAGE` (last three DEFAULT NULL in the proc definition;
  calls pass all 10 positionally). `sp_etl_job_begin` / `_finish` /
  `_fail` are untouched (STEP_NO 0 / 999).
- **Config:** `COMMON.ETL_RUN_CONFIG_TBL` (user's 8 columns +
  `STEP_NO, STEP_PROC_NAME, STEP_KIND`; NO SOURCE column — workflow +
  mapping names are globally unique). The operator only toggles
  `IS_RUN_ENABLED`; drivers do NOT validate flag consistency.
- **Step 5:** `CLEANUP_PREVIOUS_RUN` — bare `DROP TABLE IF EXISTS` for
  that mapping's own work tables only, with NO checkpoint for the drops.
  Every run rebuilds all steps from scratch; there is no step-level
  resume (`P_RESUME_STEP` does not exist).
- **Publish:** the only step that writes to final targets and the only
  step inside an explicit transaction (one transaction, all branches,
  or nothing). First branch takes the current publish step number,
  +10 per branch. Work tables are TRANSIENT, are NOT dropped at the end
  of a run, and are left standing until the next run of the same mapping
  cleans them up at its step 5. No cursors, no cleanup procedure, no
  end-of-run drops.
- **Step 999 / JOB_END:** on failure each driver writes a `TERMINATING` /
  `FAILED` checkpoint and a `sp_etl_job_fail` row; it is an error
  terminator, not a data step.
- **PTYDEACT step 50** (`DELETE_VALID_STAGE_NOT_PERFORMED`) is a
  checkpoint-only record step, called after publish: it writes NO data
  (see its manifest). It is the only non-CTAS, non-publish unit.

## Mapping to PREFIX

| IDQ mapping | Workflow | PREFIX | Driver proc |
|---|---|---|---|
| m_Tgt_C_S_TRS_Pty_OnGoing | wf_TRS_Stage_Load_1_Ongoing | PTY | `sp_snow_main_m_Tgt_C_S_TRS_Pty_OnGoing` |
| m_Tgt_C_S_TRS_Pty_Deactivation_1 | wf_TRS_Stage_Load_1_Ongoing | PTYDEACT | `sp_snow_main_m_Tgt_C_S_TRS_Pty_Deactivation_1` |
| m_Tgt_C_S_TRS_Pty_Rle_TOA | wf_TRS_Stage_Load_1_Ongoing | TOA | `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_TOA` |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | wf_TRS_Stage_Load_1_Ongoing | REL1 | `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem` |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 | wf_TRS_Stage_Load_1_Ongoing | RELDEACT | `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1` |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | wf_TRS_Stage_Load_1_Ongoing | REL2 | `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP` |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | wf_TRS_Stage_Load_1_Ongoing | PHN | `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr` |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw | wf_TRS_Stage_Load_1_Ongoing | MNGSW | `sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw` |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing | wf_TRS_Stage_Load_1_Ongoing | AUTHREP | `sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing` |
| m_Tgt_C_S_TRS_Pty_Nm | wf_TRS_Stage_Load_1_Ongoing | NM | `sp_snow_main_m_Tgt_C_S_TRS_Pty_Nm` |
| m_Tgt_C_S_TRS_Pty_Rle_Alt_Id | wf_TRS_Stage_Load_1_Ongoing | ALT | `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id` |
| m_Tgt_C_S_TRS_Pty_Rle_Pln | wf_TRS_Stage_Load_1_Ongoing | PLN | `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Pln` |
| m_Tgt_C_S_TRS_Addr_1 | wf_TRS_Stage_Load_1_Ongoing | ADDR1 | `sp_snow_main_m_Tgt_C_S_TRS_Addr_1` |
| m_Tgt_C_S_TRS_Addr_2 | wf_TRS_Stage_Load_1_Ongoing | ADDR2 | `sp_snow_main_m_Tgt_C_S_TRS_Addr_2` |
| m_Tgt_C_S_TRS_Stg_TOA | wf_TRS_Stage_Load_TOA | STGTOA | `sp_snow_main_m_Tgt_C_S_TRS_Stg_TOA` |

## All units (drivers excluded; driver row is STEP_NO 0 per mapping)

| Mapping | Workflow | STEP_NO | Proc | Kind | Target / work table |
|---|---|---|---|---|---|
| m_Tgt_C_S_TRS_Pty_OnGoing | wf_TRS_Stage_Load_1_Ongoing | 10 | `sp_snow_step_TRS_PTY_S10_SRC` | TRANSFORM | WRK_TRS_PTY_S1_SRC |
| m_Tgt_C_S_TRS_Pty_OnGoing | wf_TRS_Stage_Load_1_Ongoing | 20 | `sp_snow_step_TRS_PTY_S20_DQ` | TRANSFORM | WRK_TRS_PTY_S2_DQ |
| m_Tgt_C_S_TRS_Pty_OnGoing | wf_TRS_Stage_Load_1_Ongoing | 30 | `sp_snow_step_TRS_PTY_S30_ROUTER` | TRANSFORM | WRK_TRS_PTY_S3_ROUTER |
| m_Tgt_C_S_TRS_Pty_OnGoing | wf_TRS_Stage_Load_1_Ongoing | 40 | `sp_snow_step_TRS_PTY_S40_DEDUP` | TRANSFORM | WRK_TRS_PTY_S4_DEDUP |
| m_Tgt_C_S_TRS_Pty_OnGoing | wf_TRS_Stage_Load_1_Ongoing | 50 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_NAME` | EXCEPTION | EXC_STG_BAD_REC_MEMB |
| m_Tgt_C_S_TRS_Pty_OnGoing | wf_TRS_Stage_Load_1_Ongoing | 60 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_GENDER` | EXCEPTION | EXC_STG_BAD_REC_MEMB |
| m_Tgt_C_S_TRS_Pty_OnGoing | wf_TRS_Stage_Load_1_Ongoing | 70 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_DEATH` | EXCEPTION | EXC_STG_BAD_REC_MEMB |
| m_Tgt_C_S_TRS_Pty_OnGoing | wf_TRS_Stage_Load_1_Ongoing | 80 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH` | EXCEPTION | EXC_STG_BAD_REC_MEMB |
| m_Tgt_C_S_TRS_Pty_OnGoing | wf_TRS_Stage_Load_1_Ongoing | 90 | `sp_snow_pub_TRS_PTY_C_S_TRS_PTY` | SPINE | C_S_TRS_PTY |
| m_Tgt_C_S_TRS_Pty_OnGoing | wf_TRS_Stage_Load_1_Ongoing | 100 | `sp_snow_pub_TRS_PTY_C_S_TRS_PTY_RLE` | SPINE | C_S_TRS_PTY_RLE |
| m_Tgt_C_S_TRS_Pty_OnGoing | wf_TRS_Stage_Load_1_Ongoing | 110 | `sp_snow_pub_TRS_PTY_STG_TRS_VALID_MEMBERS` | SPINE | STG_TRS_VALID_MEMBERS |
| m_Tgt_C_S_TRS_Pty_OnGoing | wf_TRS_Stage_Load_1_Ongoing | 120 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_RACE` | EXCEPTION | EXC_STG_BAD_REC_MEMB |
| m_Tgt_C_S_TRS_Pty_OnGoing | wf_TRS_Stage_Load_1_Ongoing | 130 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY` | EXCEPTION | EXC_STG_BAD_REC_MEMB |
| m_Tgt_C_S_TRS_Pty_Deactivation_1 | wf_TRS_Stage_Load_1_Ongoing | 10 | `sp_snow_step_TRS_PTYDEACT_S10_DEACTV` | TRANSFORM | WRK_TRS_DEACT1_S10_DEACTV |
| m_Tgt_C_S_TRS_Pty_Deactivation_1 | wf_TRS_Stage_Load_1_Ongoing | 20 | `sp_snow_step_TRS_PTYDEACT_S20_DEACTV_ID` | TRANSFORM | WRK_TRS_DEACT1_S20_DEACTV_ID |
| m_Tgt_C_S_TRS_Pty_Deactivation_1 | wf_TRS_Stage_Load_1_Ongoing | 30 | `sp_snow_step_TRS_PTYDEACT_S30_READY` | TRANSFORM | WRK_TRS_DEACT1_S30_READY |
| m_Tgt_C_S_TRS_Pty_Deactivation_1 | wf_TRS_Stage_Load_1_Ongoing | 40 | `sp_snow_pub_TRS_PTYDEACT_STG_TRS_DEACTIVED_MEMBERS` | STATUS | STG_TRS_DEACTIVED_MEMBERS |
| m_Tgt_C_S_TRS_Pty_Deactivation_1 | wf_TRS_Stage_Load_1_Ongoing | 50 | `sp_snow_step_TRS_PTYDEACT_S50_NOTPERFORMED` | STATUS | STG_TRS_VALID_MEMBERS |
| m_Tgt_C_S_TRS_Pty_Rle_TOA | wf_TRS_Stage_Load_1_Ongoing | 10 | `sp_snow_step_TRS_TOA_S10_RAW` | TRANSFORM | WRK_TRS_TOA_S10_RAW |
| m_Tgt_C_S_TRS_Pty_Rle_TOA | wf_TRS_Stage_Load_1_Ongoing | 20 | `sp_snow_step_TRS_TOA_S20_LATEST` | TRANSFORM | WRK_TRS_TOA_S20_SRC |
| m_Tgt_C_S_TRS_Pty_Rle_TOA | wf_TRS_Stage_Load_1_Ongoing | 30 | `sp_snow_step_TRS_TOA_S30_KEYED` | TRANSFORM | WRK_TRS_TOA_S30_KEYED |
| m_Tgt_C_S_TRS_Pty_Rle_TOA | wf_TRS_Stage_Load_1_Ongoing | 40 | `sp_snow_step_TRS_TOA_S40_RANKED` | TRANSFORM | WRK_TRS_TOA_S40_RANKED |
| m_Tgt_C_S_TRS_Pty_Rle_TOA | wf_TRS_Stage_Load_1_Ongoing | 50 | `sp_snow_pub_TRS_TOA_EXC_STG_BAD_REC_MEMB_BAD_VALUE` | EXCEPTION | EXC_STG_BAD_REC_MEMB |
| m_Tgt_C_S_TRS_Pty_Rle_TOA | wf_TRS_Stage_Load_1_Ongoing | 60 | `sp_snow_pub_TRS_TOA_EXC_STG_BAD_REC_MEMB_DATES` | EXCEPTION | EXC_STG_BAD_REC_MEMB |
| m_Tgt_C_S_TRS_Pty_Rle_TOA | wf_TRS_Stage_Load_1_Ongoing | 70 | `sp_snow_pub_TRS_TOA_C_S_TRS_PTY_RLE_TOA` | SPINE | C_S_TRS_PTY_RLE_TOA |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | wf_TRS_Stage_Load_1_Ongoing | 10 | `sp_snow_step_TRS_REL1_S10_SRC` | TRANSFORM | WRK_TRS_REL1_S1_SRC |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | wf_TRS_Stage_Load_1_Ongoing | 20 | `sp_snow_step_TRS_REL1_S20_KEYED` | TRANSFORM | WRK_TRS_REL1_S2_KEYED |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | wf_TRS_Stage_Load_1_Ongoing | 30 | `sp_snow_step_TRS_REL1_S30_ROUTER` | TRANSFORM | WRK_TRS_REL1_S3_ROUTER |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | wf_TRS_Stage_Load_1_Ongoing | 40 | `sp_snow_step_TRS_REL1_S40_CONSOL` | TRANSFORM | WRK_TRS_REL1_S4_CONSOL |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | wf_TRS_Stage_Load_1_Ongoing | 50 | `sp_snow_step_TRS_REL1_S50_PREP` | TRANSFORM | WRK_TRS_REL1_S5_PREP |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | wf_TRS_Stage_Load_1_Ongoing | 60 | `sp_snow_step_TRS_REL1_S60_TIMELINE` | TRANSFORM | WRK_TRS_REL1_S6_TIMELINE |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | wf_TRS_Stage_Load_1_Ongoing | 70 | `sp_snow_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_MAIN_ALT_ID` | EXCEPTION | EXC_STG_BAD_REC_MEMB |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | wf_TRS_Stage_Load_1_Ongoing | 80 | `sp_snow_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_REF_ALT_ID` | EXCEPTION | EXC_STG_BAD_REC_MEMB |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | wf_TRS_Stage_Load_1_Ongoing | 90 | `sp_snow_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_LOOKUP` | EXCEPTION | EXC_STG_BAD_REC_MEMB |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | wf_TRS_Stage_Load_1_Ongoing | 100 | `sp_snow_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_DATES` | EXCEPTION | EXC_STG_BAD_REC_MEMB |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | wf_TRS_Stage_Load_1_Ongoing | 110 | `sp_snow_pub_TRS_REL1_C_S_TRS_PTY_RLE_REL` | SPINE | C_S_TRS_PTY_RLE_REL |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 | wf_TRS_Stage_Load_1_Ongoing | 10 | `sp_snow_step_TRS_RELDEACT_S10_MINPK` | TRANSFORM | WRK_TRS_RELDEACT_S10_MINPK |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 | wf_TRS_Stage_Load_1_Ongoing | 20 | `sp_snow_step_TRS_RELDEACT_S20_SRC` | TRANSFORM | WRK_TRS_RELDEACT_S20_SRC |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 | wf_TRS_Stage_Load_1_Ongoing | 30 | `sp_snow_step_TRS_RELDEACT_S30_KEYED` | TRANSFORM | WRK_TRS_RELDEACT_S30_KEYED |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 | wf_TRS_Stage_Load_1_Ongoing | 40 | `sp_snow_step_TRS_RELDEACT_S40_XREF` | TRANSFORM | WRK_TRS_RELDEACT_S40_XREF |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 | wf_TRS_Stage_Load_1_Ongoing | 50 | `sp_snow_step_TRS_RELDEACT_S50_READY` | TRANSFORM | WRK_TRS_RELDEACT_S50_READY |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 | wf_TRS_Stage_Load_1_Ongoing | 60 | `sp_snow_pub_TRS_RELDEACT_STG_TRS_DEACTIVATED_RELATIONSHIPS` | STATUS | STG_TRS_DEACTIVATED_RELATIONSHIPS |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | wf_TRS_Stage_Load_1_Ongoing | 10 | `sp_snow_step_TRS_REL2_S10_SRC` | TRANSFORM | WRK_TRS_REL2_S1_SRC |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | wf_TRS_Stage_Load_1_Ongoing | 20 | `sp_snow_step_TRS_REL2_S20_KEYED` | TRANSFORM | WRK_TRS_REL2_S2_KEYED |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | wf_TRS_Stage_Load_1_Ongoing | 30 | `sp_snow_step_TRS_REL2_S30_ROUTER` | TRANSFORM | WRK_TRS_REL2_S3_ROUTER |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | wf_TRS_Stage_Load_1_Ongoing | 40 | `sp_snow_step_TRS_REL2_S40_CONSOL` | TRANSFORM | WRK_TRS_REL2_S4_CONSOL |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | wf_TRS_Stage_Load_1_Ongoing | 50 | `sp_snow_step_TRS_REL2_S50_PREP` | TRANSFORM | WRK_TRS_REL2_S5_PREP |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | wf_TRS_Stage_Load_1_Ongoing | 60 | `sp_snow_step_TRS_REL2_S60_TIMELINE` | TRANSFORM | WRK_TRS_REL2_S6_TIMELINE |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | wf_TRS_Stage_Load_1_Ongoing | 70 | `sp_snow_pub_TRS_REL2_EXC_STG_BAD_REC_MEMB_DATES` | EXCEPTION | EXC_STG_BAD_REC_MEMB |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | wf_TRS_Stage_Load_1_Ongoing | 80 | `sp_snow_pub_TRS_REL2_EXC_STG_BAD_REC_MEMB_DEFAULT` | EXCEPTION | EXC_STG_BAD_REC_MEMB |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | wf_TRS_Stage_Load_1_Ongoing | 90 | `sp_snow_pub_TRS_REL2_C_S_TRS_PTY_RLE_REL_PROV` | SPINE | C_S_TRS_PTY_RLE_REL_PROV |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | wf_TRS_Stage_Load_1_Ongoing | 10 | `sp_snow_step_TRS_PHN_S10_SRC` | TRANSFORM | WRK_TRS_PHN_S1_SRC |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | wf_TRS_Stage_Load_1_Ongoing | 20 | `sp_snow_step_TRS_PHN_S20_SLOTS` | TRANSFORM | WRK_TRS_PHN_S2_SLOTS |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | wf_TRS_Stage_Load_1_Ongoing | 30 | `sp_snow_step_TRS_PHN_S30_CHECKED` | TRANSFORM | WRK_TRS_PHN_S3_CHECKED |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | wf_TRS_Stage_Load_1_Ongoing | 40 | `sp_snow_step_TRS_PHN_S40_PHONES` | TRANSFORM | WRK_TRS_PHN_S4_PHONES |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | wf_TRS_Stage_Load_1_Ongoing | 50 | `sp_snow_step_TRS_PHN_S50_VERSIONS` | TRANSFORM | WRK_TRS_PHN_S5_VERSIONS |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | wf_TRS_Stage_Load_1_Ongoing | 60 | `sp_snow_step_TRS_PHN_S60_EMAILS` | TRANSFORM | WRK_TRS_PHN_S6_EMAILS |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | wf_TRS_Stage_Load_1_Ongoing | 70 | `sp_snow_step_TRS_PHN_S70_EADDR` | TRANSFORM | WRK_TRS_PHN_S7_VERSIONS |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | wf_TRS_Stage_Load_1_Ongoing | 80 | `sp_snow_pub_TRS_PHN_C_S_TRS_PTY_RLE_PHN` | SPINE | C_S_TRS_PTY_RLE_PHN |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | wf_TRS_Stage_Load_1_Ongoing | 90 | `sp_snow_pub_TRS_PHN_EXC_STG_BAD_REC_MEMB_PHONE` | EXCEPTION | EXC_STG_BAD_REC_MEMB |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | wf_TRS_Stage_Load_1_Ongoing | 100 | `sp_snow_pub_TRS_PHN_C_S_TRS_PTY_RLE_EADDR` | SPINE | C_S_TRS_PTY_RLE_EADDR |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | wf_TRS_Stage_Load_1_Ongoing | 110 | `sp_snow_pub_TRS_PHN_EXC_STG_BAD_REC_MEMB_EMAIL` | EXCEPTION | EXC_STG_BAD_REC_MEMB |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw | wf_TRS_Stage_Load_1_Ongoing | 10 | `sp_snow_step_TRS_MNGSW_S10_DAILY` | TRANSFORM | WRK_TRS_MNGSW_S10_DAILY |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw | wf_TRS_Stage_Load_1_Ongoing | 20 | `sp_snow_step_TRS_MNGSW_S20_SRC` | TRANSFORM | WRK_TRS_MNGSW_S20_SRC |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw | wf_TRS_Stage_Load_1_Ongoing | 30 | `sp_snow_step_TRS_MNGSW_S30_NORM` | TRANSFORM | WRK_TRS_MNGSW_S30_NORM |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw | wf_TRS_Stage_Load_1_Ongoing | 40 | `sp_snow_step_TRS_MNGSW_S40_ATTRS` | TRANSFORM | WRK_TRS_MNGSW_S40_ATTRS |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw | wf_TRS_Stage_Load_1_Ongoing | 50 | `sp_snow_pub_TRS_MNGSW_C_S_TRS_PTY_MNG_ATTR` | SPINE | C_S_TRS_PTY_MNG_ATTR |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing | wf_TRS_Stage_Load_1_Ongoing | 10 | `sp_snow_step_TRS_AUTHREP_S10_PAYEE` | TRANSFORM | WRK_TRS_MNGAR_S10_PAYEE |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing | wf_TRS_Stage_Load_1_Ongoing | 20 | `sp_snow_step_TRS_AUTHREP_S20_SRC` | TRANSFORM | WRK_TRS_MNGAR_S20_SRC |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing | wf_TRS_Stage_Load_1_Ongoing | 30 | `sp_snow_step_TRS_AUTHREP_S30_KEYED` | TRANSFORM | WRK_TRS_MNGAR_S30_KEYED |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing | wf_TRS_Stage_Load_1_Ongoing | 40 | `sp_snow_step_TRS_AUTHREP_S40_AGG` | TRANSFORM | WRK_TRS_MNGAR_S40_AGG |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing | wf_TRS_Stage_Load_1_Ongoing | 50 | `sp_snow_pub_TRS_AUTHREP_C_S_TRS_PTY_MNG_ATTR` | SPINE | C_S_TRS_PTY_MNG_ATTR |
| m_Tgt_C_S_TRS_Pty_Nm | wf_TRS_Stage_Load_1_Ongoing | 10 | `sp_snow_step_TRS_NM_S10_SRC` | TRANSFORM | WRK_TRS_NM_S10_SRC |
| m_Tgt_C_S_TRS_Pty_Nm | wf_TRS_Stage_Load_1_Ongoing | 20 | `sp_snow_step_TRS_NM_S20_NAMED` | TRANSFORM | WRK_TRS_NM_S20_NAMED |
| m_Tgt_C_S_TRS_Pty_Nm | wf_TRS_Stage_Load_1_Ongoing | 30 | `sp_snow_step_TRS_NM_S30_STD` | TRANSFORM | WRK_TRS_NM_S30_STD |
| m_Tgt_C_S_TRS_Pty_Nm | wf_TRS_Stage_Load_1_Ongoing | 40 | `sp_snow_step_TRS_NM_S40_DEDUP` | TRANSFORM | WRK_TRS_NM_S40_DEDUP |
| m_Tgt_C_S_TRS_Pty_Nm | wf_TRS_Stage_Load_1_Ongoing | 50 | `sp_snow_pub_TRS_NM_C_S_TRS_PTY_NM` | SPINE | C_S_TRS_PTY_NM |
| m_Tgt_C_S_TRS_Pty_Rle_Alt_Id | wf_TRS_Stage_Load_1_Ongoing | 10 | `sp_snow_step_TRS_ALT_S10_SRC` | TRANSFORM | WRK_TRS_ALT_S1_SRC |
| m_Tgt_C_S_TRS_Pty_Rle_Alt_Id | wf_TRS_Stage_Load_1_Ongoing | 20 | `sp_snow_step_TRS_ALT_S20_SSN` | TRANSFORM | WRK_TRS_ALT_S2_SSN |
| m_Tgt_C_S_TRS_Pty_Rle_Alt_Id | wf_TRS_Stage_Load_1_Ongoing | 30 | `sp_snow_step_TRS_ALT_S30_NORM` | TRANSFORM | WRK_TRS_ALT_S3_NORM |
| m_Tgt_C_S_TRS_Pty_Rle_Alt_Id | wf_TRS_Stage_Load_1_Ongoing | 40 | `sp_snow_step_TRS_ALT_S40_ROUTED` | TRANSFORM | WRK_TRS_ALT_S4_ROUTED |
| m_Tgt_C_S_TRS_Pty_Rle_Alt_Id | wf_TRS_Stage_Load_1_Ongoing | 50 | `sp_snow_pub_TRS_ALT_C_S_TRS_PTY_RLE_ALT_ID` | SPINE | C_S_TRS_PTY_RLE_ALT_ID |
| m_Tgt_C_S_TRS_Pty_Rle_Alt_Id | wf_TRS_Stage_Load_1_Ongoing | 60 | `sp_snow_pub_TRS_ALT_EXC_STG_BAD_REC_MEMB` | EXCEPTION | EXC_STG_BAD_REC_MEMB |
| m_Tgt_C_S_TRS_Pty_Rle_Pln | wf_TRS_Stage_Load_1_Ongoing | 10 | `sp_snow_step_TRS_PLN_S10_SRC` | TRANSFORM | WRK_TRS_PLN_S10_SRC |
| m_Tgt_C_S_TRS_Pty_Rle_Pln | wf_TRS_Stage_Load_1_Ongoing | 20 | `sp_snow_step_TRS_PLN_S20_PLANNED` | TRANSFORM | WRK_TRS_PLN_S20_PLANNED |
| m_Tgt_C_S_TRS_Pty_Rle_Pln | wf_TRS_Stage_Load_1_Ongoing | 30 | `sp_snow_step_TRS_PLN_S30_RANKED` | TRANSFORM | WRK_TRS_PLN_S30_RANKED |
| m_Tgt_C_S_TRS_Pty_Rle_Pln | wf_TRS_Stage_Load_1_Ongoing | 40 | `sp_snow_pub_TRS_PLN_C_S_TRS_PTY_RLE_PLN` | SPINE | C_S_TRS_PTY_RLE_PLN |
| m_Tgt_C_S_TRS_Pty_Rle_Pln | wf_TRS_Stage_Load_1_Ongoing | 50 | `sp_snow_pub_TRS_PLN_EXC_STG_BAD_REC_MEMB` | EXCEPTION | EXC_STG_BAD_REC_MEMB |
| m_Tgt_C_S_TRS_Addr_1 | wf_TRS_Stage_Load_1_Ongoing | 10 | `sp_snow_step_TRS_ADDR1_S10_SRC` | TRANSFORM | WRK_TRS_ADDR1_S10_SRC |
| m_Tgt_C_S_TRS_Addr_1 | wf_TRS_Stage_Load_1_Ongoing | 20 | `sp_snow_step_TRS_ADDR1_S20_DERIVED` | TRANSFORM | WRK_TRS_ADDR1_S20_DERIVED |
| m_Tgt_C_S_TRS_Addr_1 | wf_TRS_Stage_Load_1_Ongoing | 30 | `sp_snow_step_TRS_ADDR1_S30_VALIDATED` | TRANSFORM | WRK_TRS_ADDR1_S30_VALIDATED |
| m_Tgt_C_S_TRS_Addr_1 | wf_TRS_Stage_Load_1_Ongoing | 40 | `sp_snow_step_TRS_ADDR1_S40_READY` | TRANSFORM | WRK_TRS_ADDR1_S40_READY |
| m_Tgt_C_S_TRS_Addr_1 | wf_TRS_Stage_Load_1_Ongoing | 50 | `sp_snow_pub_TRS_ADDR1_STG_TRS_D_UNQ_ADDR` | STATUS | STG_TRS_D_UNQ_ADDR |
| m_Tgt_C_S_TRS_Addr_2 | wf_TRS_Stage_Load_1_Ongoing | 10 | `sp_snow_step_TRS_ADDR2_S10_DEDUP` | TRANSFORM | WRK_TRS_ADDR2_S10_DEDUP |
| m_Tgt_C_S_TRS_Addr_2 | wf_TRS_Stage_Load_1_Ongoing | 20 | `sp_snow_step_TRS_ADDR2_S20_SRC` | TRANSFORM | WRK_TRS_ADDR2_S20_SRC |
| m_Tgt_C_S_TRS_Addr_2 | wf_TRS_Stage_Load_1_Ongoing | 30 | `sp_snow_step_TRS_ADDR2_S30_KEYED` | TRANSFORM | WRK_TRS_ADDR2_S30_KEYED |
| m_Tgt_C_S_TRS_Addr_2 | wf_TRS_Stage_Load_1_Ongoing | 40 | `sp_snow_step_TRS_ADDR2_S40_SCORED` | TRANSFORM | WRK_TRS_ADDR2_S40_SCORED |
| m_Tgt_C_S_TRS_Addr_2 | wf_TRS_Stage_Load_1_Ongoing | 50 | `sp_snow_step_TRS_ADDR2_S50_READY` | TRANSFORM | WRK_TRS_ADDR2_S50_READY |
| m_Tgt_C_S_TRS_Addr_2 | wf_TRS_Stage_Load_1_Ongoing | 60 | `sp_snow_pub_TRS_ADDR2_DQM_ADDRESS` | VALIDATION | DQM_ADDRESS |
| m_Tgt_C_S_TRS_Addr_2 | wf_TRS_Stage_Load_1_Ongoing | 70 | `sp_snow_pub_TRS_ADDR2_C_S_TRS_PTY_RLE_ADDR` | SPINE | C_S_TRS_PTY_RLE_ADDR |
| m_Tgt_C_S_TRS_Addr_2 | wf_TRS_Stage_Load_1_Ongoing | 80 | `sp_snow_pub_TRS_ADDR2_EXC_STG_BAD_REC_MEMB` | EXCEPTION | EXC_STG_BAD_REC_MEMB |
| m_Tgt_C_S_TRS_Stg_TOA | wf_TRS_Stage_Load_TOA | 10 | `sp_snow_step_TRS_STGTOA_S10_KEYED` | TRANSFORM | WRK_TRS_LUTOA_S10_KEYED |
| m_Tgt_C_S_TRS_Stg_TOA | wf_TRS_Stage_Load_TOA | 20 | `sp_snow_step_TRS_STGTOA_S20_FINAL` | TRANSFORM | WRK_TRS_LUTOA_S20_FINAL |
| m_Tgt_C_S_TRS_Stg_TOA | wf_TRS_Stage_Load_TOA | 30 | `sp_snow_pub_TRS_STGTOA_C_S_LU_TOA` | STATUS | C_S_LU_TOA |

## WIC

# WIC Step-Driver Map — wf_WIC_Stage_Load (config-driven refactor, v2.1 style)
Install location: database `MDM_ETL_WIC`, schema `WIC_ETL_WRK`. Config table: `COMMON.ETL_RUN_CONFIG_TBL` (database `MDM_ETL_COMMON`, schema `COMMON`). All table and procedure names in the refactored code are unqualified, except the config table, which is `COMMON`-qualified.
Driver names and signatures are IDENTICAL to the current mains, so every existing CALL (including the workflow runner, copied verbatim) still resolves. Run order is unchanged from the multisource runner: Validation, Party, Address, Phone/E-mail, Alt Id.
## Mapping to PREFIX

| Mapping | Driver procedure | PREFIX (unit token) | Short |
|---|---|---|---|
| `m_Tgt_C_S_WIC_Pty_Validation` | `sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation` | `WIC_VAL` | VAL |
| `m_Tgt_C_S_WIC_Pty` | `sp_snow_main_m_Tgt_C_S_WIC_Pty` | `WIC_PTY` | PTY |
| `m_Tgt_C_S_WIC_Pty_Addr` | `sp_snow_main_m_Tgt_C_S_WIC_Pty_Addr` | `WIC_ADR` | ADR |
| `m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr` | `sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr` | `WIC_PHN` | PHN |
| `m_Tgt_C_S_WIC_Pty_Rle_Alt_Id` | `sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id` | `WIC_ALT` | ALT |

Flag / input / publish-count naming rule (uniform, unit-based): strip `sp_snow_step_` / `sp_snow_pub_` from the unit procedure name, prepend `l_flag_` / `l_in_` / `l_pub_`; the driver-row flag is `l_flag_<PREFIX>_DRIVER`. Dependencies live in `l_in_*` variables, config `DEPENDENT_ON`, and `WIC_DEPENDENCIES.md` — never in flag names.

## VAL — `m_Tgt_C_S_WIC_Pty_Validation`

Driver: `drivers/driver_sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation.sql`. Manifest: `manifests/VAL_MANIFEST.md`.

| STEP_NO | Proc | Kind | Produces / Target | Consumes |
|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation` | DRIVER | — (gates whole mapping) | — |
| 10 | `sp_snow_step_WIC_VAL_S10_ENRICHED` | TRANSFORM | `WRK_WIC_VAL_S10_ENRICHED` | `` |
| 20 | `sp_snow_step_WIC_VAL_S20_NAMED` | TRANSFORM | `WRK_WIC_VAL_S20_NAMED` | `WRK_WIC_VAL_S10_ENRICHED` |
| 30 | `sp_snow_step_WIC_VAL_S30_ROUTED` | TRANSFORM | `WRK_WIC_VAL_S30_ROUTED` | `WRK_WIC_VAL_S20_NAMED` |
| 40 | `sp_snow_pub_WIC_VAL_EXC_STG_BAD_REC_MEMB` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` (invalid-name exceptions) | `WRK_WIC_VAL_S30_ROUTED` |
| 50 | `sp_snow_pub_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_DEACTIVATION` | STATUS | `STG_WIC_PTY_INACTIVE_LOG` (deactivation log rows) | `WRK_WIC_VAL_S30_ROUTED` |
| 60 | `sp_snow_pub_WIC_VAL_STG_WIC_PTY_INACTIVE_STS` | STATUS | `STG_WIC_PTY_INACTIVE_STS` (new deactivation-status rows) | `WRK_WIC_VAL_S30_ROUTED` |
| 70 | `sp_snow_pub_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_REACTIVATION` | STATUS | `STG_WIC_PTY_INACTIVE_LOG` (reactivation log rows) | `WRK_WIC_VAL_S30_ROUTED` |

Step 5 (unnumbered in config, always runs unless the driver row is 'N'): drops `WRK_WIC_VAL_S10_ENRICHED`, `WRK_WIC_VAL_S20_NAMED`, `WRK_WIC_VAL_S30_ROUTED` — bare `DROP TABLE IF EXISTS`, no checkpoint. Publish branches run inside ONE transaction; the first branch takes the current publish step number (40), +10 per branch.

## PTY — `m_Tgt_C_S_WIC_Pty`

Driver: `drivers/driver_sp_snow_main_m_Tgt_C_S_WIC_Pty.sql`. Manifest: `manifests/PTY_MANIFEST.md`.

| STEP_NO | Proc | Kind | Produces / Target | Consumes |
|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_WIC_Pty` | DRIVER | — (gates whole mapping) | — |
| 10 | `sp_snow_step_WIC_PTY_S10_ACTIVE` | TRANSFORM | `WRK_WIC_PTY_S10_ACTIVE` | `` |
| 20 | `sp_snow_step_WIC_PTY_S20_DQ` | TRANSFORM | `WRK_WIC_PTY_S20_DQ` | `WRK_WIC_PTY_S10_ACTIVE` |
| 30 | `sp_snow_step_WIC_PTY_S30_DQ2` | TRANSFORM | `WRK_WIC_PTY_S30_DQ2` | `WRK_WIC_PTY_S20_DQ` |
| 40 | `sp_snow_step_WIC_PTY_S40_ROUTED` | TRANSFORM | `WRK_WIC_PTY_S40_ROUTED` | `WRK_WIC_PTY_S30_DQ2` |
| 50 | `sp_snow_pub_WIC_PTY_C_S_WIC_PTY` | SPINE | `C_S_WIC_PTY` (valid parties) | `WRK_WIC_PTY_S40_ROUTED` |
| 60 | `sp_snow_pub_WIC_PTY_C_S_WIC_PTY_RLE` | SPINE | `C_S_WIC_PTY_RLE` (valid roles) | `WRK_WIC_PTY_S40_ROUTED` |
| 70 | `sp_snow_pub_WIC_PTY_EXC_STG_BAD_REC_MEMB_GENDER` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` (invalid-gender exceptions) | `WRK_WIC_PTY_S40_ROUTED` |
| 80 | `sp_snow_pub_WIC_PTY_EXC_STG_BAD_REC_MEMB_BIRTH` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` (invalid-birth-date exceptions) | `WRK_WIC_PTY_S40_ROUTED` |
| 90 | `sp_snow_pub_WIC_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` (invalid-ethnicity exceptions) | `WRK_WIC_PTY_S40_ROUTED` |
| 100 | `sp_snow_pub_WIC_PTY_EXC_STG_BAD_REC_MEMB_RACE` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` (invalid-race exceptions) | `WRK_WIC_PTY_S40_ROUTED` |
| 110 | `sp_snow_pub_WIC_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` (invalid-language exceptions) | `WRK_WIC_PTY_S40_ROUTED` |

Step 5 (unnumbered in config, always runs unless the driver row is 'N'): drops `WRK_WIC_PTY_S10_ACTIVE`, `WRK_WIC_PTY_S20_DQ`, `WRK_WIC_PTY_S30_DQ2`, `WRK_WIC_PTY_S40_ROUTED` — bare `DROP TABLE IF EXISTS`, no checkpoint. Publish branches run inside ONE transaction; the first branch takes the current publish step number (50), +10 per branch.

## ADR — `m_Tgt_C_S_WIC_Pty_Addr`

Driver: `drivers/driver_sp_snow_main_m_Tgt_C_S_WIC_Pty_Addr.sql`. Manifest: `manifests/ADR_MANIFEST.md`.

| STEP_NO | Proc | Kind | Produces / Target | Consumes |
|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_WIC_Pty_Addr` | DRIVER | — (gates whole mapping) | — |
| 10 | `sp_snow_step_WIC_ADR_S10_ACTIVE` | TRANSFORM | `WRK_WIC_ADDR_S10_ACTIVE` | `` |
| 20 | `sp_snow_step_WIC_ADR_S20_VALIDATED` | TRANSFORM | `WRK_WIC_ADDR_S20_VALIDATED` | `WRK_WIC_ADDR_S10_ACTIVE` |
| 30 | `sp_snow_step_WIC_ADR_S30_FLAT` | TRANSFORM | `WRK_WIC_ADDR_S30_FLAT` | `WRK_WIC_ADDR_S20_VALIDATED` |
| 40 | `sp_snow_step_WIC_ADR_S40_SCORED` | TRANSFORM | `WRK_WIC_ADDR_S40_SCORED` | `WRK_WIC_ADDR_S30_FLAT` |
| 50 | `sp_snow_pub_WIC_ADR_DQM_ADDRESS` | VALIDATION | `DQM_ADDRESS` (every active address (address-quality table)) | `WRK_WIC_ADDR_S40_SCORED` |
| 60 | `sp_snow_pub_WIC_ADR_C_S_WIC_PTY_RLE_ADDR` | SPINE | `C_S_WIC_PTY_RLE_ADDR` (good addresses) | `WRK_WIC_ADDR_S40_SCORED` |
| 70 | `sp_snow_pub_WIC_ADR_EXC_STG_BAD_REC_MEMB` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` (exception addresses) | `WRK_WIC_ADDR_S40_SCORED` |

Step 5 (unnumbered in config, always runs unless the driver row is 'N'): drops `WRK_WIC_ADDR_S10_ACTIVE`, `WRK_WIC_ADDR_S20_VALIDATED`, `WRK_WIC_ADDR_S30_FLAT`, `WRK_WIC_ADDR_S40_SCORED` — bare `DROP TABLE IF EXISTS`, no checkpoint. Publish branches run inside ONE transaction; the first branch takes the current publish step number (50), +10 per branch.

## PHN — `m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr`

Driver: `drivers/driver_sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr.sql`. Manifest: `manifests/PHN_MANIFEST.md`.

| STEP_NO | Proc | Kind | Produces / Target | Consumes |
|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr` | DRIVER | — (gates whole mapping) | — |
| 10 | `sp_snow_step_WIC_PHN_S10_SRC` | TRANSFORM | `WRK_WIC_PHN_S10_SRC` | `` |
| 20 | `sp_snow_step_WIC_PHN_S20_CHECKED` | TRANSFORM | `WRK_WIC_PHN_S20_CHECKED` | `WRK_WIC_PHN_S10_SRC` |
| 30 | `sp_snow_step_WIC_PHN_S30_ROUTED` | TRANSFORM | `WRK_WIC_PHN_S30_ROUTED` | `WRK_WIC_PHN_S20_CHECKED` |
| 40 | `sp_snow_step_WIC_PHN_S40_READY` | TRANSFORM | `WRK_WIC_PHN_S40_READY` | `WRK_WIC_PHN_S30_ROUTED` |
| 50 | `sp_snow_pub_WIC_PHN_C_S_WIC_PTY_RLE_PHN` | SPINE | `C_S_WIC_PTY_RLE_PHN` (good phones) | `WRK_WIC_PHN_S40_READY` |
| 60 | `sp_snow_pub_WIC_PHN_EXC_STG_BAD_REC_MEMB_PHONE` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` (bad-phone exceptions) | `WRK_WIC_PHN_S40_READY` |
| 70 | `sp_snow_pub_WIC_PHN_C_S_WIC_PTY_RLE_EADDR` | SPINE | `C_S_WIC_PTY_RLE_EADDR` (valid e-mails) | `WRK_WIC_PHN_S40_READY` |
| 80 | `sp_snow_pub_WIC_PHN_EXC_STG_BAD_REC_MEMB_EMAIL` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` (bad-e-mail exceptions) | `WRK_WIC_PHN_S40_READY` |

Step 5 (unnumbered in config, always runs unless the driver row is 'N'): drops `WRK_WIC_PHN_S10_SRC`, `WRK_WIC_PHN_S20_CHECKED`, `WRK_WIC_PHN_S30_ROUTED`, `WRK_WIC_PHN_S40_READY` — bare `DROP TABLE IF EXISTS`, no checkpoint. Publish branches run inside ONE transaction; the first branch takes the current publish step number (50), +10 per branch.

## ALT — `m_Tgt_C_S_WIC_Pty_Rle_Alt_Id`

Driver: `drivers/driver_sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id.sql`. Manifest: `manifests/ALT_MANIFEST.md`.

| STEP_NO | Proc | Kind | Produces / Target | Consumes |
|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id` | DRIVER | — (gates whole mapping) | — |
| 10 | `sp_snow_step_WIC_ALT_S10_KEYS` | TRANSFORM | `WRK_WIC_ALT_S10_KEYS` | `` |
| 20 | `sp_snow_step_WIC_ALT_S20_READY` | TRANSFORM | `WRK_WIC_ALT_S20_READY` | `WRK_WIC_ALT_S10_KEYS` |
| 30 | `sp_snow_pub_WIC_ALT_C_S_WIC_PTY_RLE_ALT_ID` | SPINE | `C_S_WIC_PTY_RLE_ALT_ID` (one alternate id per active party) | `WRK_WIC_ALT_S20_READY` |

Step 5 (unnumbered in config, always runs unless the driver row is 'N'): drops `WRK_WIC_ALT_S10_KEYS`, `WRK_WIC_ALT_S20_READY` — bare `DROP TABLE IF EXISTS`, no checkpoint. Publish branches run inside ONE transaction; the first branch takes the current publish step number (30), +10 per branch.

## TTF

# TTF Step Map - config-driven step-driver refactor, workflow wf_TTF_Stage_Load

Install schema: `TTF_ETL_WRK` in database `MDM_ETL_TTF` (all table names
unqualified in code, except the config table `COMMON.ETL_RUN_CONFIG_TBL`).
Workflow run order (same as the original run script and the runner):
Pty_Validation, Pty, Pty_Rle_Alt_Id, Pty_Rle_Phn.
Every mapping starts with step 5 `CLEANUP_PREVIOUS_RUN` (bare
`DROP TABLE IF EXISTS` for that mapping's work tables only, no checkpoint
for drops), ends with a `TERMINATING` row, and leaves its work tables
standing. Restart is mapping-level only: a new run. Publish is the only
transaction in each mapping, held by the driver across all enabled branches.

## Mapping to PREFIX

| Run order | Mapping | PREFIX | Driver file |
|---|---|---|---|
| 1 | `m_Tgt_C_S_TTF_Pty_Validation` | VAL | `drivers/driver_sp_snow_main_m_Tgt_C_S_TTF_Pty_Validation.sql` |
| 2 | `m_Tgt_C_S_TTF_Pty` | PTY | `drivers/driver_sp_snow_main_m_Tgt_C_S_TTF_Pty.sql` |
| 3 | `m_Tgt_C_S_TTF_Pty_Rle_Alt_Id` | ALT | `drivers/driver_sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id.sql` |
| 4 | `m_Tgt_C_S_TTF_Pty_Rle_Phn` | PHN | `drivers/driver_sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Phn.sql` |

## 1. m_Tgt_C_S_TTF_Pty_Validation (PREFIX VAL)

Driver: `drivers/driver_sp_snow_main_m_Tgt_C_S_TTF_Pty_Validation.sql`. Reads TTF clients, standardises their names, and maintains the deactivation list every later TTF mapping relies on.

| Step | Proc | Kind | Target / work table | Consumes |
|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_TTF_Pty_Validation` | DRIVER | -- (gates whole mapping) | -- |
| 10 | `sp_snow_step_TTF_VAL_S10_ENRICHED` | TRANSFORM | `WRK_TTF_VAL_S1_ENRICHED` | -- (base tables) |
| 20 | `sp_snow_step_TTF_VAL_S20_NAMED` | TRANSFORM | `WRK_TTF_VAL_S2_NAMED` | `WRK_TTF_VAL_S1_ENRICHED` |
| 30 | `sp_snow_step_TTF_VAL_S30_ROUTED` | TRANSFORM | `WRK_TTF_VAL_S3_ROUTED` | `WRK_TTF_VAL_S2_NAMED` |
| 40 | `sp_snow_pub_TTF_VAL_EXC_STG_BAD_REC_MEMB` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` (invalid-name exceptions) | `WRK_TTF_VAL_S3_ROUTED` |
| 50 | `sp_snow_pub_TTF_VAL_STG_TTF_PTY_INACTIVE_LOG_DEACTIVATION` | STATUS | `STG_TTF_PTY_INACTIVE_LOG` (deactivation log rows) | `WRK_TTF_VAL_S3_ROUTED` |
| 60 | `sp_snow_pub_TTF_VAL_STG_TTF_PTY_INACTIVE_STS` | STATUS | `STG_TTF_PTY_INACTIVE_STS` (new deactivation status rows) | `WRK_TTF_VAL_S3_ROUTED` |
| 70 | `sp_snow_pub_TTF_VAL_STG_TTF_PTY_INACTIVE_LOG_REACTIVATION` | STATUS | `STG_TTF_PTY_INACTIVE_LOG` (reactivation log rows) | `WRK_TTF_VAL_S3_ROUTED` |

Publish: original step 40, 4 INSERT(s) in original order; first branch takes step 40, +10 per branch.

## 2. m_Tgt_C_S_TTF_Pty (PREFIX PTY)

Driver: `drivers/driver_sp_snow_main_m_Tgt_C_S_TTF_Pty.sql`. Loads the active TTF clients into the party and party-role tables, and logs demographic exceptions. Gender comes from SEXID (33 -> F, 34 -> M, else U); ethnicity is '55' when RACEETHNICITYID = '55'.

| Step | Proc | Kind | Target / work table | Consumes |
|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_TTF_Pty` | DRIVER | -- (gates whole mapping) | -- |
| 10 | `sp_snow_step_TTF_PTY_S10_ACTIVE` | TRANSFORM | `WRK_TTF_PTY_S1_ACTIVE` | -- (base tables) |
| 20 | `sp_snow_step_TTF_PTY_S20_DQ` | TRANSFORM | `WRK_TTF_PTY_S2_DQ` | `WRK_TTF_PTY_S1_ACTIVE` |
| 30 | `sp_snow_step_TTF_PTY_S30_DQ2` | TRANSFORM | `WRK_TTF_PTY_S3_DQ2` | `WRK_TTF_PTY_S2_DQ` |
| 40 | `sp_snow_step_TTF_PTY_S40_ROUTED` | TRANSFORM | `WRK_TTF_PTY_S4_ROUTED` | `WRK_TTF_PTY_S3_DQ2` |
| 50 | `sp_snow_pub_TTF_PTY_C_S_TTF_PTY` | SPINE | `C_S_TTF_PTY` (valid parties) | `WRK_TTF_PTY_S4_ROUTED` |
| 60 | `sp_snow_pub_TTF_PTY_C_S_TTF_PTY_RLE` | SPINE | `C_S_TTF_PTY_RLE` (valid roles) | `WRK_TTF_PTY_S4_ROUTED` |
| 70 | `sp_snow_pub_TTF_PTY_EXC_STG_BAD_REC_MEMB_GENDER` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` (invalid-gender exceptions) | `WRK_TTF_PTY_S4_ROUTED` |
| 80 | `sp_snow_pub_TTF_PTY_EXC_STG_BAD_REC_MEMB_BIRTH` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` (invalid-birth-date exceptions) | `WRK_TTF_PTY_S4_ROUTED` |
| 90 | `sp_snow_pub_TTF_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` (invalid-ethnicity exceptions) | `WRK_TTF_PTY_S4_ROUTED` |
| 100 | `sp_snow_pub_TTF_PTY_EXC_STG_BAD_REC_MEMB_RACE` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` (invalid-race exceptions) | `WRK_TTF_PTY_S4_ROUTED` |

Publish: original step 50, 6 INSERT(s) in original order; first branch takes step 50, +10 per branch.

## 3. m_Tgt_C_S_TTF_Pty_Rle_Alt_Id (PREFIX ALT)

Driver: `drivers/driver_sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id.sql`. One alternate id per active TTF client into C_S_TTF_PTY_RLE_ALT_ID -- the party key itself, type '024'. Active means the party is not in the inactive-status table with a status set.

| Step | Proc | Kind | Target / work table | Consumes |
|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id` | DRIVER | -- (gates whole mapping) | -- |
| 10 | `sp_snow_step_TTF_ALT_S10_KEYS` | TRANSFORM | `WRK_TTF_ALT_S1_KEYS` | -- (base tables) |
| 20 | `sp_snow_step_TTF_ALT_S20_DEDUP` | TRANSFORM | `WRK_TTF_ALT_S2_DEDUP` | `WRK_TTF_ALT_S1_KEYS` |
| 30 | `sp_snow_pub_TTF_ALT_C_S_TTF_PTY_RLE_ALT_ID` | SPINE | `C_S_TTF_PTY_RLE_ALT_ID` (one alternate id per active client, type 024) | `WRK_TTF_ALT_S2_DEDUP` |

Publish: original step 30, 1 INSERT(s) in original order; first branch takes step 30, +10 per branch.

## 4. m_Tgt_C_S_TTF_Pty_Rle_Phn (PREFIX PHN)

Driver: `drivers/driver_sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Phn.sql`. One phone per active TTF client into C_S_TTF_PTY_RLE_PHN. A good phone loads as usage '001', type 'Telephone', preference 'Primary'; a bad phone is NOT loaded, only logged as a 'Rejected Record' exception with the source phone as the attribute value.

| Step | Proc | Kind | Target / work table | Consumes |
|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Phn` | DRIVER | -- (gates whole mapping) | -- |
| 10 | `sp_snow_step_TTF_PHN_S10_SRC` | TRANSFORM | `WRK_TTF_PHN_S1_SRC` | -- (base tables) |
| 20 | `sp_snow_step_TTF_PHN_S20_CHECKED` | TRANSFORM | `WRK_TTF_PHN_S2_CHECKED` | `WRK_TTF_PHN_S1_SRC` |
| 30 | `sp_snow_step_TTF_PHN_S30_ROUTED` | TRANSFORM | `WRK_TTF_PHN_S3_ROUTED` | `WRK_TTF_PHN_S2_CHECKED` |
| 40 | `sp_snow_pub_TTF_PHN_C_S_TTF_PTY_RLE_PHN` | SPINE | `C_S_TTF_PTY_RLE_PHN` (good phones) | `WRK_TTF_PHN_S3_ROUTED` |
| 50 | `sp_snow_pub_TTF_PHN_EXC_STG_BAD_REC_MEMB` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` (bad phones as Rejected Record exceptions) | `WRK_TTF_PHN_S3_ROUTED` |

Publish: original step 40, 2 INSERT(s) in original order; first branch takes step 40, +10 per branch.

## Runners (copied verbatim)

- `runners/sp_etl_run_wf_TTF_Stage_Load.sql` -- workflow runner, calls the 4 drivers in run order passing each mapping's original defaults in full followed by the run id. Driver names and signatures are unchanged, so runner calls still resolve.
- `runners/run_wf_TTF_Stage_Load.sql` -- SnowSQL script calling the runner.

## Config table

`ETL_RUN_CONFIG_TBL` (COMMON schema): the user's 8 columns (WORKFLOW_NAME, MAPPING_NAME, IS_DRIVER, IS_RUN_ENABLED, IS_DEPENDENT, DEPENDENT_ON, WORK_TABLES_PRODUCED, WORK_TABLES_CONSUMED) + STEP_NO, STEP_PROC_NAME, STEP_KIND. NO SOURCE column (workflow + mapping names are globally unique). The user only toggles IS_RUN_ENABLED; drivers do NOT validate flag consistency. Seed: `seed_etl_run_config_TTF.sql` (29 rows, all 'Y').

## FSS

# FSS step map -- config-driven step-driver refactor (wf_FSS_Stage_Load)

Install schema is `FSS_ETL_WRK` in database `MDM_ETL_FSS`. All table
names in the procedures are unqualified, except the config table, which
is `COMMON.ETL_RUN_CONFIG_TBL`. Driver names and signatures are IDENTICAL
to the current mains, so every existing CALL (including the workflow
runner) still works.

Workflow run order (unchanged from `run_wf_FSS_Stage_Load.sql`):

1. `m_Tgt_C_S_FSS_Pty_Validation` (maintains STG_FSS_PTY_INACTIVE_STS, the
   deactivation list every later mapping reads)
2. `m_Tgt_C_S_FSS_Pty`
3. `m_Tgt_C_S_FSS_Pty_Addr`
4. `m_Tgt_C_S_FSS_Pty_Rle_Alt_Id`
5. `m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr`
6. `m_Tgt_C_S_FSS_Pty_Rle_Rel`

Every mapping: job begin -> one config GATHER -> driver-row gate (STEP_NO 0)
-> step 5 cleanup (bare DROPs, no checkpoint) -> conditional work steps ->
ONE publish transaction across enabled branches -> branch checkpoints only
after COMMIT -> job end. Work tables are left standing after the run.
There is no step-level restart and no resume parameter -- a restart is
simply a new run.

## Mapping -> PREFIX

| Mapping | PREFIX | Driver |
|---|---|---|
| `m_Tgt_C_S_FSS_Pty_Validation` | `FSS_VAL` | `sp_snow_main_Tgt_C_S_FSS_Pty_Validation` |
| `m_Tgt_C_S_FSS_Pty` | `FSS_PTY` | `sp_snow_main_Tgt_C_S_FSS_Pty` |
| `m_Tgt_C_S_FSS_Pty_Addr` | `FSS_ADR` | `sp_snow_main_Tgt_C_S_FSS_Pty_Addr` |
| `m_Tgt_C_S_FSS_Pty_Rle_Alt_Id` | `FSS_ALT` | `sp_snow_main_Tgt_C_S_FSS_Pty_Rle_Alt_Id` |
| `m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr` | `FSS_PHN` | `sp_snow_main_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr` |
| `m_Tgt_C_S_FSS_Pty_Rle_Rel` | `FSS_REL` | `sp_snow_main_Tgt_C_S_FSS_Pty_Rle_Rel` |

## Steps and branches

### m_Tgt_C_S_FSS_Pty_Validation (FSS_VAL)

| STEP_NO | Proc | Kind | Target / work table |
|---|---|---|---|
| 10 | `sp_snow_step_FSS_VAL_S10_SRC` | TRANSFORM | `WRK_FSS_VAL_S1_SRC` |
| 20 | `sp_snow_step_FSS_VAL_S20_ENRICHED` | TRANSFORM | `WRK_FSS_VAL_S2_ENRICHED` |
| 30 | `sp_snow_step_FSS_VAL_S30_ROUTED` | TRANSFORM | `WRK_FSS_VAL_S3_ROUTED` |
| 50 | `sp_snow_pub_FSS_VAL_EXC_STG_BAD_REC_MEMB` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` |
| 60 | `sp_snow_pub_FSS_VAL_STG_FSS_PTY_INACTIVE_LOG` | STATUS | `STG_FSS_PTY_INACTIVE_LOG` |
| 70 | `sp_snow_pub_FSS_VAL_STG_FSS_PTY_INACTIVE_STS_NEW` | STATUS | `STG_FSS_PTY_INACTIVE_STS` |
| 80 | `sp_snow_pub_FSS_VAL_STG_FSS_PTY_INACTIVE_STS_REACTIVATION` | STATUS | `STG_FSS_PTY_INACTIVE_STS` |

### m_Tgt_C_S_FSS_Pty (FSS_PTY)

| STEP_NO | Proc | Kind | Target / work table |
|---|---|---|---|
| 10 | `sp_snow_step_FSS_PTY_S10_SRC` | TRANSFORM | `WRK_FSS_PTY_S1_SRC` |
| 20 | `sp_snow_step_FSS_PTY_S20_DQ` | TRANSFORM | `WRK_FSS_PTY_S2_DQ` |
| 30 | `sp_snow_step_FSS_PTY_S30_DQ2` | TRANSFORM | `WRK_FSS_PTY_S3_DQ2` |
| 40 | `sp_snow_step_FSS_PTY_S40_ROUTED` | TRANSFORM | `WRK_FSS_PTY_S4_ROUTED` |
| 50 | `sp_snow_pub_FSS_PTY_C_S_FSS_PTY` | SPINE | `C_S_FSS_PTY` |
| 60 | `sp_snow_pub_FSS_PTY_C_S_FSS_PTY_RLE` | SPINE | `C_S_FSS_PTY_RLE` |
| 70 | `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_GENDER` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` |
| 80 | `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` |
| 90 | `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` |
| 100 | `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_RACE` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` |
| 110 | `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` |
| 120 | `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_SUFFIX` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` |

### m_Tgt_C_S_FSS_Pty_Addr (FSS_ADR)

| STEP_NO | Proc | Kind | Target / work table |
|---|---|---|---|
| 10 | `sp_snow_step_FSS_ADR_S10_SRC` | TRANSFORM | `WRK_FSS_ADDR_S1_SRC` |
| 20 | `sp_snow_step_FSS_ADR_S20_VALIDATED` | TRANSFORM | `WRK_FSS_ADDR_S2_VALIDATED` |
| 30 | `sp_snow_step_FSS_ADR_S30_FLAT` | TRANSFORM | `WRK_FSS_ADDR_S3_FLAT` |
| 40 | `sp_snow_step_FSS_ADR_S40_SCORED` | TRANSFORM | `WRK_FSS_ADDR_S4_SCORED` |
| 50 | `sp_snow_pub_FSS_ADR_DQM_ADDRESS` | VALIDATION | `DQM_ADDRESS` |
| 60 | `sp_snow_pub_FSS_ADR_C_S_FSS_PTY_RLE_ADDR` | SPINE | `C_S_FSS_PTY_RLE_ADDR` |
| 70 | `sp_snow_pub_FSS_ADR_EXC_STG_BAD_REC_MEMB` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` |

### m_Tgt_C_S_FSS_Pty_Rle_Alt_Id (FSS_ALT)

| STEP_NO | Proc | Kind | Target / work table |
|---|---|---|---|
| 10 | `sp_snow_step_FSS_ALT_S10_SRC` | TRANSFORM | `WRK_FSS_ALT_S1_SRC` |
| 20 | `sp_snow_step_FSS_ALT_S20_FILTERED` | TRANSFORM | `WRK_FSS_ALT_S2_FILTERED` |
| 50 | `sp_snow_pub_FSS_ALT_C_S_FSS_PTY_RLE_ALT_ID` | SPINE | `C_S_FSS_PTY_RLE_ALT_ID` |

### m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr (FSS_PHN)

| STEP_NO | Proc | Kind | Target / work table |
|---|---|---|---|
| 10 | `sp_snow_step_FSS_PHN_S10_SRC` | TRANSFORM | `WRK_FSS_PHN_S1_SRC` |
| 20 | `sp_snow_step_FSS_PHN_S20_DQ` | TRANSFORM | `WRK_FSS_PHN_S2_DQ` |
| 30 | `sp_snow_step_FSS_PHN_S30_CHECKED` | TRANSFORM | `WRK_FSS_PHN_S3_CHECKED` |
| 40 | `sp_snow_step_FSS_PHN_S40_ROUTED` | TRANSFORM | `WRK_FSS_PHN_S4_ROUTED` |
| 50 | `sp_snow_pub_FSS_PHN_C_S_FSS_PTY_RLE_EADDR` | SPINE | `C_S_FSS_PTY_RLE_EADDR` |
| 60 | `sp_snow_pub_FSS_PHN_EXC_STG_BAD_REC_MEMB_EMAIL` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` |
| 70 | `sp_snow_pub_FSS_PHN_C_S_FSS_PTY_RLE_PHN` | SPINE | `C_S_FSS_PTY_RLE_PHN` |
| 80 | `sp_snow_pub_FSS_PHN_EXC_STG_BAD_REC_MEMB_PHONE` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` |
| 90 | `sp_snow_pub_FSS_PHN_EXC_STG_BAD_REC_MEMB_EXTENSION` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` |

### m_Tgt_C_S_FSS_Pty_Rle_Rel (FSS_REL)

| STEP_NO | Proc | Kind | Target / work table |
|---|---|---|---|
| 10 | `sp_snow_step_FSS_REL_S10_SRC` | TRANSFORM | `WRK_FSS_REL_S1_SRC` |
| 20 | `sp_snow_step_FSS_REL_S20_CODED` | TRANSFORM | `WRK_FSS_REL_S2_CODED` |
| 30 | `sp_snow_step_FSS_REL_S30_TYPED` | TRANSFORM | `WRK_FSS_REL_S3_TYPED` |
| 40 | `sp_snow_step_FSS_REL_S40_FINAL` | TRANSFORM | `WRK_FSS_REL_S4_FINAL` |
| 50 | `sp_snow_pub_FSS_REL_C_S_FSS_PTY_RLE_REL` | SPINE | `C_S_FSS_PTY_RLE_REL` |
| 60 | `sp_snow_pub_FSS_REL_EXC_STG_BAD_REC_MEMB` | EXCEPTION | `EXC_STG_BAD_REC_MEMB` |

Totals: 6 drivers + 21 steps + 23 branches = 50 procedures. Seed rows: 50 (6 drivers + steps + branches).

## CRE

# CRE_STEP_MAP — CRE step-driver package (config-driven, ECI v2.1 style)

Source of truth: the step numbers, step names, work tables and publish targets below are copied
from the simplified-v2 CRE main procedure
(`snowflake_multisource/CRE/mappings/sp_snow_main_m_Tgt_C_S_CRE_CARE_Clients.sql`) and its
step map (`snowflake_multisource/CRE/STEP_MAP_CRE.md`). Business logic is unchanged; the only
adaptation is the config-driven driver split (see the manifest). Step names are the checkpoint
`P_STEP_NAME` values, verbatim. Prefix: `CRE_CARE`.

## Notes (apply to this mapping)

- **Control calls:** every control call passes SOURCE first: `sp_etl_job_begin('CRE', …)`,
  `sp_etl_checkpoint('CRE', …)` (v2 10-argument form), `sp_etl_job_finish('CRE', …)`,
  `sp_etl_job_fail('CRE', …)` (via a `c_source VARCHAR DEFAULT 'CRE'` variable in each
  procedure; the driver uses the `'CRE'` literal, as in the ECI v2.1 template).
  Job-run-id prefixes are `CRE_` for the mapping, `CRE_WF_` for the workflow runner.
- **Control table:** the shared job-control table with a SOURCE column (framework-owned),
  not a CRE-only table. Config table: `COMMON.ETL_RUN_CONFIG_TBL` (no SOURCE column;
  workflow + mapping names are globally unique).
- **Install schema:** all table names are unqualified, except the config table
  (`COMMON.ETL_RUN_CONFIG_TBL`). Install in schema `CRE_ETL_WRK` in database `MDM_ETL_CRE`,
  so unqualified names resolve to that schema's tables.
- **Step 5 (not listed per step):** `CLEANUP_PREVIOUS_RUN` — bare `DROP TABLE IF EXISTS` for
  this mapping's own work tables only, with NO checkpoint for the drops. Every run then
  rebuilds all steps from scratch; there is no step-level resume. Step 5 drops ALL work
  tables regardless of config flags.
- **Publish:** the only step that writes to final targets and the only step inside an explicit
  transaction (one transaction, all enabled branches, or nothing). Branch checkpoints are
  written by the driver ONLY after COMMIT. Work tables are TRANSIENT, are NOT dropped at the
  end of a run, and are left standing until the next run of the same mapping cleans them up
  at its step 5. No step-level resume parameter, no end-of-run drops.
- **Step 999 / JOB_END:** on failure the driver writes a `TERMINATING` / `FAILED` checkpoint
  and a `sp_etl_job_fail` row; it is an error terminator, not a data step, so it is not
  listed per step.
- **Driver-row gate:** a config row with STEP_NO = 0 and IS_RUN_ENABLED = 'N' skips the whole
  mapping BEFORE step 5 cleanup (no work tables are dropped); a `MAPPING_SKIPPED` checkpoint
  row is written. The operator ONLY toggles IS_RUN_ENABLED; the driver does NOT validate
  flag consistency — disabling a producer while a consumer stays enabled fails loudly on the
  consumer's missing input table.
- **Combined publish checkpoint split (by design):** the current main writes ONE step-60
  `PUBLISH` checkpoint with a members count. The refactor writes one checkpoint per branch
  (STEP_NOs 60–230) with that branch's row count, plus a per-branch summary line. Total
  published rows are recoverable by summing the eighteen branch counts; there is no longer
  a single combined publish row, and the members-only headline count (`is_member`) is no
  longer computed as a separate line.

## Workflow: wf_CRE_Stage_Load_Ongoing

Runner: `runners/sp_etl_run_wf_CRE_Stage_Load_Ongoing.sql` (copied verbatim from the
multi-source package; run script: `runners/run_wf_CRE_Stage_Load_Ongoing.sql`, also verbatim).
Driver name and signature are identical to the current main, so the runner calls still resolve.

### 1. m_Tgt_C_S_CRE_CARE_Clients

- Driver file: `drivers/driver_sp_snow_main_m_Tgt_C_S_CRE_CARE_Clients.sql`
- Workflow: `wf_CRE_Stage_Load_Ongoing`
- Original parameters (in order, before the appended `P_JOB_RUN_ID`):
  `P_PHYSICAL_ADDR_TYPE_CD` = `'002'`, `P_RLE_BO_CLASS_CD_MEMBER` = `'Member'`,
  `P_DEFAULT_TX_STATE_CD` = `'48'`, `P_COUNTY_CD_NONTX` = `'996'`,
  `P_COUNTYCD_DEFAULTALL` = `'998'`, `P_DEFAULT_NONUS_STATE_CD` = `'99'`
- Steps (step 5 cleanup precedes all of these; see Notes):

| STEP_NO | Proc | Kind | Checkpoint STEP_NAME | Produces (work table) | Consumes (default) | Original params used |
|---|---|---|---|---|---|---|
| 10 | `sp_snow_step_CRE_CARE_S10_SRC_MRG` | TRANSFORM | `SRC_MERGE_ROUTING` | `WRK_CRE_CARE_S1_SRC_MRG` | _(none — base source tables)_ | none |
| 20 | `sp_snow_step_CRE_CARE_S20_NAMED` | TRANSFORM | `NAME_STANDARDISE_VALIDATE` | `WRK_CRE_CARE_S2_NAMED` | `WRK_CRE_CARE_S1_SRC_MRG` | none |
| 30 | `sp_snow_step_CRE_CARE_S30_RANKED` | TRANSFORM | `RANK_ENRICH` | `WRK_CRE_CARE_S3_RANKED` | `WRK_CRE_CARE_S2_NAMED` | none |
| 40 | `sp_snow_step_CRE_CARE_S40_FLAT` | TRANSFORM | `FLAT_ADDR_ALTID` | `WRK_CRE_CARE_S4_FLAT` | `WRK_CRE_CARE_S3_RANKED` | `P_RLE_BO_CLASS_CD_MEMBER`, `P_DEFAULT_NONUS_STATE_CD` |
| 50 | `sp_snow_step_CRE_CARE_S50_KEYED` | TRANSFORM | `KEYED_ROUTES_GUARDS` | `WRK_CRE_CARE_S5_KEYED` | `WRK_CRE_CARE_S4_FLAT` | `P_PHYSICAL_ADDR_TYPE_CD`, `P_RLE_BO_CLASS_CD_MEMBER`, `P_DEFAULT_TX_STATE_CD`, `P_COUNTY_CD_NONTX`, `P_COUNTYCD_DEFAULTALL` |

- Work-table mapping, prescribed steps S1–S5 (names preserved verbatim from the main):

| Prescribed step | Work table | Contents |
|---|---|---|
| S1 (step 10) | `WRK_CRE_CARE_S1_SRC_MRG` | CARE snapshot + merge routing (original CTEs: `src`, `xref`, `hmrg_src`, `hmrg_tgt`, routed select) |
| S2 (step 20) | `WRK_CRE_CARE_S2_NAMED` | Name standardisation + member validity (original CTEs: `named`, members select) |
| S3 (step 30) | `WRK_CRE_CARE_S3_RANKED` | Rank per CARE id + validation enrichment (original CTEs: `ranked`, `dq`, `dq2`) |
| S4 (step 40) | `WRK_CRE_CARE_S4_FLAT` | Flattened load-ready rows (original CTEs: `alt_tp`, `flat`) |
| S5 (step 50) | `WRK_CRE_CARE_S5_KEYED` | Route flags + unique-key guards (original CTEs: `keyed` + final select) |

- Publish branches (one per original publish INSERT, in original order; all consume
  `WRK_CRE_CARE_S5_KEYED`; all inside ONE driver transaction):

| STEP_NO | Proc | Kind | Checkpoint STEP_NAME | Target | Original branch |
|---|---|---|---|---|---|
| 60 | `sp_snow_pub_CRE_CARE_CRE_SRC_MRG` | STATUS | `PUBLISH_CRE_SRC_MRG` | `CRE_SRC_MRG` | 60a |
| 70 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_FIRST_NAME` | EXCEPTION | `PUBLISH_EXC_FIRST_NAME` | `EXC_STG_BAD_REC_MEMB` | 60b |
| 80 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_LAST_NAME` | EXCEPTION | `PUBLISH_EXC_LAST_NAME` | `EXC_STG_BAD_REC_MEMB` | 60c |
| 90 | `sp_snow_pub_CRE_CARE_C_S_CRE_PTY` | SPINE | `PUBLISH_C_S_CRE_PTY` | `C_S_CRE_PTY` | 60d |
| 100 | `sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE` | SPINE | `PUBLISH_C_S_CRE_PTY_RLE` | `C_S_CRE_PTY_RLE` | 60e |
| 110 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_GENDER` | EXCEPTION | `PUBLISH_EXC_GENDER` | `EXC_STG_BAD_REC_MEMB` | 60f |
| 120 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_SUFFIX` | EXCEPTION | `PUBLISH_EXC_SUFFIX` | `EXC_STG_BAD_REC_MEMB` | 60g |
| 130 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_ETHNICITY` | EXCEPTION | `PUBLISH_EXC_ETHNICITY` | `EXC_STG_BAD_REC_MEMB` | 60h |
| 140 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_RACE` | EXCEPTION | `PUBLISH_EXC_RACE` | `EXC_STG_BAD_REC_MEMB` | 60i |
| 150 | `sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_ADDR` | SPINE | `PUBLISH_C_S_CRE_PTY_RLE_ADDR` | `C_S_CRE_PTY_RLE_ADDR` | 60j |
| 160 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_ADDR` | EXCEPTION | `PUBLISH_EXC_ADDR` | `EXC_STG_BAD_REC_MEMB` | 60k |
| 170 | `sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_PHN` | SPINE | `PUBLISH_C_S_CRE_PTY_RLE_PHN` | `C_S_CRE_PTY_RLE_PHN` | 60l |
| 180 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_PHONE` | EXCEPTION | `PUBLISH_EXC_PHONE` | `EXC_STG_BAD_REC_MEMB` | 60m |
| 190 | `sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_CARE` | SPINE | `PUBLISH_ALT_ID_CARE` | `C_S_CRE_PTY_RLE_ALT_ID` | 60n |
| 200 | `sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_MEDICAID` | SPINE | `PUBLISH_ALT_ID_MEDICAID` | `C_S_CRE_PTY_RLE_ALT_ID` | 60o |
| 210 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_MEDICAID_ALT` | EXCEPTION | `PUBLISH_EXC_MEDICAID_ALT` | `EXC_STG_BAD_REC_MEMB` | 60p |
| 220 | `sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_SSN` | SPINE | `PUBLISH_ALT_ID_SSN` | `C_S_CRE_PTY_RLE_ALT_ID` | 60q |
| 230 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_SSN_ALT` | EXCEPTION | `PUBLISH_EXC_SSN_ALT` | `EXC_STG_BAD_REC_MEMB` | 60r |

- Publish targets (7): `CRE_SRC_MRG`, `C_S_CRE_PTY`, `C_S_CRE_PTY_RLE`,
  `C_S_CRE_PTY_RLE_ADDR`, `C_S_CRE_PTY_RLE_PHN`, `C_S_CRE_PTY_RLE_ALT_ID`,
  `EXC_STG_BAD_REC_MEMB`.
- Spine vs non-spine: the spine path is the `C_S_*` writes (steps 90, 100, 150, 170,
  190, 200, 220) plus the merge-routing `CRE_SRC_MRG` write (step 60, kind STATUS); the
  non-spine path is the `EXC_STG_BAD_REC_MEMB` exception writes (all other branches).
  The two are kept visibly separate in the manifest's phase-flow diagram by SPINE /
  STATUS / EXCEPTION label prefixes inside the single Publish phase, and in the
  branch tables above by the Kind column.
