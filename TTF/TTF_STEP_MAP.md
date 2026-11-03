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
