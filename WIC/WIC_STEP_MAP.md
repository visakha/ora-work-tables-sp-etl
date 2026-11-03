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
