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
