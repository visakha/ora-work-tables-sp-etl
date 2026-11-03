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
