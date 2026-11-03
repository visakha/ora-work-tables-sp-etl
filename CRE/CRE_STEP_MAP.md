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
