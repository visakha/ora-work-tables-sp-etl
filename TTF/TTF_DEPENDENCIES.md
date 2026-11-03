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
