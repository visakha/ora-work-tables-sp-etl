# FSS dependencies -- config-driven step-driver refactor (wf_FSS_Stage_Load)

Every unit, the work tables it produces and consumes (pipe-delimited;
here each unit consumes at most one work table), its DEPENDENT_ON
(producing STEP_NO within the same mapping), and the dependency chain in
words. Dependencies live in `l_in_*` variables, in the config
`DEPENDENT_ON` column, and here -- never in flag names.

Cross-mapping dependencies (target tables, not work tables -- the driver
does NOT gate on these; the workflow runner order enforces them):
- `m_Tgt_C_S_FSS_Pty_Validation` first: it maintains
  `STG_FSS_PTY_INACTIVE_STS`, which every later mapping reads via a
  NOT EXISTS (DEACTIVATION_STS IS NOT NULL) filter.
- `m_Tgt_C_S_FSS_Pty` second: it loads `C_S_FSS_PTY` / `C_S_FSS_PTY_RLE`,
  which later mappings' keys build on.
- Addresses, alternate IDs, phones / e-mails, relationships after that,
  in the original run-script order.

Within a mapping, every step consumes exactly the previous step's work
table; every publish branch consumes the last step's work table. Step 5
cleanup drops ALL of the mapping's work tables regardless of flags, so
disabling a producer while a consumer stays enabled fails loudly on the
missing input table (by design -- the operator must disable downstream
steps explicitly).

### m_Tgt_C_S_FSS_Pty_Validation (PREFIX FSS_VAL)

| Unit | STEP_NO | Produced | Consumed | DEPENDENT_ON |
|---|---|---|---|---|
| driver `sp_snow_main_m_Tgt_C_S_FSS_Pty_Validation` | 0 |  |  |  |
| step `sp_snow_step_FSS_VAL_S10_SRC` | 10 | WRK_FSS_VAL_S1_SRC |  |  |
| step `sp_snow_step_FSS_VAL_S20_ENRICHED` | 20 | WRK_FSS_VAL_S2_ENRICHED | WRK_FSS_VAL_S1_SRC | 10 |
| step `sp_snow_step_FSS_VAL_S30_ROUTED` | 30 | WRK_FSS_VAL_S3_ROUTED | WRK_FSS_VAL_S2_ENRICHED | 20 |
| branch `sp_snow_pub_FSS_VAL_EXC_STG_BAD_REC_MEMB` | 50 |  | WRK_FSS_VAL_S3_ROUTED | 30 |
| branch `sp_snow_pub_FSS_VAL_STG_FSS_PTY_INACTIVE_LOG` | 60 |  | WRK_FSS_VAL_S3_ROUTED | 30 |
| branch `sp_snow_pub_FSS_VAL_STG_FSS_PTY_INACTIVE_STS_NEW` | 70 |  | WRK_FSS_VAL_S3_ROUTED | 30 |
| branch `sp_snow_pub_FSS_VAL_STG_FSS_PTY_INACTIVE_STS_REACTIVATION` | 80 |  | WRK_FSS_VAL_S3_ROUTED | 30 |

Chain in words: driver gate -> step 30 (ROUTED) -> publish 50 (EXC_STG_BAD_REC_MEMB) -> publish 60 (STG_FSS_PTY_INACTIVE_LOG) -> publish 70 (STG_FSS_PTY_INACTIVE_STS_NEW) -> publish 80 (STG_FSS_PTY_INACTIVE_STS_REACTIVATION). Each unit depends only on the unit that produced the work table it consumes; publish branches all depend on the last transform step (30), not on each other, and run together in one transaction.

### m_Tgt_C_S_FSS_Pty (PREFIX FSS_PTY)

| Unit | STEP_NO | Produced | Consumed | DEPENDENT_ON |
|---|---|---|---|---|
| driver `sp_snow_main_m_Tgt_C_S_FSS_Pty` | 0 |  |  |  |
| step `sp_snow_step_FSS_PTY_S10_SRC` | 10 | WRK_FSS_PTY_S1_SRC |  |  |
| step `sp_snow_step_FSS_PTY_S20_DQ` | 20 | WRK_FSS_PTY_S2_DQ | WRK_FSS_PTY_S1_SRC | 10 |
| step `sp_snow_step_FSS_PTY_S30_DQ2` | 30 | WRK_FSS_PTY_S3_DQ2 | WRK_FSS_PTY_S2_DQ | 20 |
| step `sp_snow_step_FSS_PTY_S40_ROUTED` | 40 | WRK_FSS_PTY_S4_ROUTED | WRK_FSS_PTY_S3_DQ2 | 30 |
| branch `sp_snow_pub_FSS_PTY_C_S_FSS_PTY` | 50 |  | WRK_FSS_PTY_S4_ROUTED | 40 |
| branch `sp_snow_pub_FSS_PTY_C_S_FSS_PTY_RLE` | 60 |  | WRK_FSS_PTY_S4_ROUTED | 40 |
| branch `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_GENDER` | 70 |  | WRK_FSS_PTY_S4_ROUTED | 40 |
| branch `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH` | 80 |  | WRK_FSS_PTY_S4_ROUTED | 40 |
| branch `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY` | 90 |  | WRK_FSS_PTY_S4_ROUTED | 40 |
| branch `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_RACE` | 100 |  | WRK_FSS_PTY_S4_ROUTED | 40 |
| branch `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE` | 110 |  | WRK_FSS_PTY_S4_ROUTED | 40 |
| branch `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_SUFFIX` | 120 |  | WRK_FSS_PTY_S4_ROUTED | 40 |

Chain in words: driver gate -> step 40 (ROUTED) -> publish 50 (C_S_FSS_PTY) -> publish 60 (C_S_FSS_PTY_RLE) -> publish 70 (EXC_STG_BAD_REC_MEMB_GENDER) -> publish 80 (EXC_STG_BAD_REC_MEMB_BIRTH) -> publish 90 (EXC_STG_BAD_REC_MEMB_ETHNICITY) -> publish 100 (EXC_STG_BAD_REC_MEMB_RACE) -> publish 110 (EXC_STG_BAD_REC_MEMB_LANGUAGE) -> publish 120 (EXC_STG_BAD_REC_MEMB_SUFFIX). Each unit depends only on the unit that produced the work table it consumes; publish branches all depend on the last transform step (40), not on each other, and run together in one transaction.

### m_Tgt_C_S_FSS_Pty_Addr (PREFIX FSS_ADR)

| Unit | STEP_NO | Produced | Consumed | DEPENDENT_ON |
|---|---|---|---|---|
| driver `sp_snow_main_m_Tgt_C_S_FSS_Pty_Addr` | 0 |  |  |  |
| step `sp_snow_step_FSS_ADR_S10_SRC` | 10 | WRK_FSS_ADDR_S1_SRC |  |  |
| step `sp_snow_step_FSS_ADR_S20_VALIDATED` | 20 | WRK_FSS_ADDR_S2_VALIDATED | WRK_FSS_ADDR_S1_SRC | 10 |
| step `sp_snow_step_FSS_ADR_S30_FLAT` | 30 | WRK_FSS_ADDR_S3_FLAT | WRK_FSS_ADDR_S2_VALIDATED | 20 |
| step `sp_snow_step_FSS_ADR_S40_SCORED` | 40 | WRK_FSS_ADDR_S4_SCORED | WRK_FSS_ADDR_S3_FLAT | 30 |
| branch `sp_snow_pub_FSS_ADR_DQM_ADDRESS` | 50 |  | WRK_FSS_ADDR_S4_SCORED | 40 |
| branch `sp_snow_pub_FSS_ADR_C_S_FSS_PTY_RLE_ADDR` | 60 |  | WRK_FSS_ADDR_S4_SCORED | 40 |
| branch `sp_snow_pub_FSS_ADR_EXC_STG_BAD_REC_MEMB` | 70 |  | WRK_FSS_ADDR_S4_SCORED | 40 |

Chain in words: driver gate -> step 40 (SCORED) -> publish 50 (DQM_ADDRESS) -> publish 60 (C_S_FSS_PTY_RLE_ADDR) -> publish 70 (EXC_STG_BAD_REC_MEMB). Each unit depends only on the unit that produced the work table it consumes; publish branches all depend on the last transform step (40), not on each other, and run together in one transaction.

### m_Tgt_C_S_FSS_Pty_Rle_Alt_Id (PREFIX FSS_ALT)

| Unit | STEP_NO | Produced | Consumed | DEPENDENT_ON |
|---|---|---|---|---|
| driver `sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Alt_Id` | 0 |  |  |  |
| step `sp_snow_step_FSS_ALT_S10_SRC` | 10 | WRK_FSS_ALT_S1_SRC |  |  |
| step `sp_snow_step_FSS_ALT_S20_FILTERED` | 20 | WRK_FSS_ALT_S2_FILTERED | WRK_FSS_ALT_S1_SRC | 10 |
| branch `sp_snow_pub_FSS_ALT_C_S_FSS_PTY_RLE_ALT_ID` | 50 |  | WRK_FSS_ALT_S2_FILTERED | 20 |

Chain in words: driver gate -> step 20 (FILTERED) -> publish 50 (C_S_FSS_PTY_RLE_ALT_ID). Each unit depends only on the unit that produced the work table it consumes; publish branches all depend on the last transform step (20), not on each other, and run together in one transaction.

### m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr (PREFIX FSS_PHN)

| Unit | STEP_NO | Produced | Consumed | DEPENDENT_ON |
|---|---|---|---|---|
| driver `sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr` | 0 |  |  |  |
| step `sp_snow_step_FSS_PHN_S10_SRC` | 10 | WRK_FSS_PHN_S1_SRC |  |  |
| step `sp_snow_step_FSS_PHN_S20_DQ` | 20 | WRK_FSS_PHN_S2_DQ | WRK_FSS_PHN_S1_SRC | 10 |
| step `sp_snow_step_FSS_PHN_S30_CHECKED` | 30 | WRK_FSS_PHN_S3_CHECKED | WRK_FSS_PHN_S2_DQ | 20 |
| step `sp_snow_step_FSS_PHN_S40_ROUTED` | 40 | WRK_FSS_PHN_S4_ROUTED | WRK_FSS_PHN_S3_CHECKED | 30 |
| branch `sp_snow_pub_FSS_PHN_C_S_FSS_PTY_RLE_EADDR` | 50 |  | WRK_FSS_PHN_S4_ROUTED | 40 |
| branch `sp_snow_pub_FSS_PHN_EXC_STG_BAD_REC_MEMB_EMAIL` | 60 |  | WRK_FSS_PHN_S4_ROUTED | 40 |
| branch `sp_snow_pub_FSS_PHN_C_S_FSS_PTY_RLE_PHN` | 70 |  | WRK_FSS_PHN_S4_ROUTED | 40 |
| branch `sp_snow_pub_FSS_PHN_EXC_STG_BAD_REC_MEMB_PHONE` | 80 |  | WRK_FSS_PHN_S4_ROUTED | 40 |
| branch `sp_snow_pub_FSS_PHN_EXC_STG_BAD_REC_MEMB_EXTENSION` | 90 |  | WRK_FSS_PHN_S4_ROUTED | 40 |

Chain in words: driver gate -> step 40 (ROUTED) -> publish 50 (C_S_FSS_PTY_RLE_EADDR) -> publish 60 (EXC_STG_BAD_REC_MEMB_EMAIL) -> publish 70 (C_S_FSS_PTY_RLE_PHN) -> publish 80 (EXC_STG_BAD_REC_MEMB_PHONE) -> publish 90 (EXC_STG_BAD_REC_MEMB_EXTENSION). Each unit depends only on the unit that produced the work table it consumes; publish branches all depend on the last transform step (40), not on each other, and run together in one transaction.

### m_Tgt_C_S_FSS_Pty_Rle_Rel (PREFIX FSS_REL)

| Unit | STEP_NO | Produced | Consumed | DEPENDENT_ON |
|---|---|---|---|---|
| driver `sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Rel` | 0 |  |  |  |
| step `sp_snow_step_FSS_REL_S10_SRC` | 10 | WRK_FSS_REL_S1_SRC |  |  |
| step `sp_snow_step_FSS_REL_S20_CODED` | 20 | WRK_FSS_REL_S2_CODED | WRK_FSS_REL_S1_SRC | 10 |
| step `sp_snow_step_FSS_REL_S30_TYPED` | 30 | WRK_FSS_REL_S3_TYPED | WRK_FSS_REL_S2_CODED | 20 |
| step `sp_snow_step_FSS_REL_S40_FINAL` | 40 | WRK_FSS_REL_S4_FINAL | WRK_FSS_REL_S3_TYPED | 30 |
| branch `sp_snow_pub_FSS_REL_C_S_FSS_PTY_RLE_REL` | 50 |  | WRK_FSS_REL_S4_FINAL | 40 |
| branch `sp_snow_pub_FSS_REL_EXC_STG_BAD_REC_MEMB` | 60 |  | WRK_FSS_REL_S4_FINAL | 40 |

Chain in words: driver gate -> step 40 (FINAL) -> publish 50 (C_S_FSS_PTY_RLE_REL) -> publish 60 (EXC_STG_BAD_REC_MEMB). Each unit depends only on the unit that produced the work table it consumes; publish branches all depend on the last transform step (40), not on each other, and run together in one transaction.
