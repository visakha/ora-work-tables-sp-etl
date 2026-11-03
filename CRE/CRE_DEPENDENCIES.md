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
