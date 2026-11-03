# TRS_DEPENDENCIES — TRS step-driver refactor

Every unit, its produced and consumed work tables (pipe-delimited), and
its DEPENDENT_ON (producing STEP_NOs, informational — the driver gates
on IS_RUN_ENABLED only, never on these columns).

## Rules

- Work-table dependencies are INTRA-mapping only: verified by scanning
  every step CTAS and publish INSERT — no step or branch reads a work
  table produced by a different mapping. Cross-mapping coupling happens
  only through final/staging tables and through runner order (below),
  never through WRK_TRS_* tables.
- DEPENDENT_ON lists the STEP_NOs that produce the unit's consumed work
  tables. A branch that reads a router table depends on the router step,
  not on the last transform step (for example, PTY exception branches
  depend on step 30, spine branches on step 40; PHN phone-exception
  depends on step 40, email-exception on step 60).
- A step whose consumed list is empty reads base/staging tables only
  (step 10 of every mapping, and RELDEACT step 40, which reads the MDM
  cross-reference from base tables).

## Dependency chains in words

- **Runner order, wf_TRS_Stage_Load_1_Ongoing** (see
  `runners/sp_etl_run_wf_TRS_Stage_Load_1_Ongoing.sql`, copied verbatim):
  PTY first (it builds STG_TRS_VALID_MEMBERS, which every later mapping
  joins to), then PTYDEACT, TOA, REL1, RELDEACT, REL2, PHN, MNGSW,
  AUTHREP (after MNGSW: it appends to the table MNGSW loads), NM, ALT,
  PLN, ADDR1, ADDR2 (after ADDR1: it reads the unique addresses of part
  1, STG_TRS_D_UNQ_ADDR).
- **Runner order, wf_TRS_Stage_Load_TOA**: STGTOA alone (TOA reference
  catalogue into C_S_LU_TOA).
- **Within each mapping**, the chain is the step order in its manifest,
  with two branch exceptions documented in the manifests: PTY step 40
  reads step 20, NOT step 30 (exceptions and valid rows are two branches
  of the same DQ output); REL1/REL2 step 40 reads step 20, NOT step 30
  (valid relationships only, router exceptions are a side branch);
  PHN step 60 reads step 10, NOT step 50 (emails branch off the source,
  not off phone versions); RELDEACT step 50 reads steps 30 AND 40.
- **PTYDEACT step 50** depends on the publish step (40) only in
  sequence: it records a decision after publish and consumes no table.

## All units

| Mapping | STEP_NO | Proc | Produced work table | Consumed work tables | DEPENDENT_ON |
|---|---|---|---|---|---|
| m_Tgt_C_S_TRS_Pty_OnGoing | 10 | `sp_snow_step_TRS_PTY_S10_SRC` | WRK_TRS_PTY_S1_SRC |  | — |
| m_Tgt_C_S_TRS_Pty_OnGoing | 20 | `sp_snow_step_TRS_PTY_S20_DQ` | WRK_TRS_PTY_S2_DQ | WRK_TRS_PTY_S1_SRC | 10 |
| m_Tgt_C_S_TRS_Pty_OnGoing | 30 | `sp_snow_step_TRS_PTY_S30_ROUTER` | WRK_TRS_PTY_S3_ROUTER | WRK_TRS_PTY_S2_DQ | 20 |
| m_Tgt_C_S_TRS_Pty_OnGoing | 40 | `sp_snow_step_TRS_PTY_S40_DEDUP` | WRK_TRS_PTY_S4_DEDUP | WRK_TRS_PTY_S2_DQ | 20 |
| m_Tgt_C_S_TRS_Pty_OnGoing | 50 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_NAME` |  | WRK_TRS_PTY_S3_ROUTER | 30 |
| m_Tgt_C_S_TRS_Pty_OnGoing | 60 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_GENDER` |  | WRK_TRS_PTY_S3_ROUTER | 30 |
| m_Tgt_C_S_TRS_Pty_OnGoing | 70 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_DEATH` |  | WRK_TRS_PTY_S3_ROUTER | 30 |
| m_Tgt_C_S_TRS_Pty_OnGoing | 80 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH` |  | WRK_TRS_PTY_S3_ROUTER | 30 |
| m_Tgt_C_S_TRS_Pty_OnGoing | 90 | `sp_snow_pub_TRS_PTY_C_S_TRS_PTY` |  | WRK_TRS_PTY_S4_DEDUP | 40 |
| m_Tgt_C_S_TRS_Pty_OnGoing | 100 | `sp_snow_pub_TRS_PTY_C_S_TRS_PTY_RLE` |  | WRK_TRS_PTY_S4_DEDUP | 40 |
| m_Tgt_C_S_TRS_Pty_OnGoing | 110 | `sp_snow_pub_TRS_PTY_STG_TRS_VALID_MEMBERS` |  | WRK_TRS_PTY_S4_DEDUP | 40 |
| m_Tgt_C_S_TRS_Pty_OnGoing | 120 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_RACE` |  | WRK_TRS_PTY_S4_DEDUP | 40 |
| m_Tgt_C_S_TRS_Pty_OnGoing | 130 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY` |  | WRK_TRS_PTY_S4_DEDUP | 40 |
| m_Tgt_C_S_TRS_Pty_Deactivation_1 | 10 | `sp_snow_step_TRS_PTYDEACT_S10_DEACTV` | WRK_TRS_DEACT1_S10_DEACTV |  | — |
| m_Tgt_C_S_TRS_Pty_Deactivation_1 | 20 | `sp_snow_step_TRS_PTYDEACT_S20_DEACTV_ID` | WRK_TRS_DEACT1_S20_DEACTV_ID | WRK_TRS_DEACT1_S10_DEACTV | 10 |
| m_Tgt_C_S_TRS_Pty_Deactivation_1 | 30 | `sp_snow_step_TRS_PTYDEACT_S30_READY` | WRK_TRS_DEACT1_S30_READY | WRK_TRS_DEACT1_S20_DEACTV_ID | 20 |
| m_Tgt_C_S_TRS_Pty_Deactivation_1 | 40 | `sp_snow_pub_TRS_PTYDEACT_STG_TRS_DEACTIVED_MEMBERS` |  | WRK_TRS_DEACT1_S30_READY | 30 |
| m_Tgt_C_S_TRS_Pty_Deactivation_1 | 50 | `sp_snow_step_TRS_PTYDEACT_S50_NOTPERFORMED` |  |  | 40 |
| m_Tgt_C_S_TRS_Pty_Rle_TOA | 10 | `sp_snow_step_TRS_TOA_S10_RAW` | WRK_TRS_TOA_S10_RAW |  | — |
| m_Tgt_C_S_TRS_Pty_Rle_TOA | 20 | `sp_snow_step_TRS_TOA_S20_LATEST` | WRK_TRS_TOA_S20_SRC | WRK_TRS_TOA_S10_RAW | 10 |
| m_Tgt_C_S_TRS_Pty_Rle_TOA | 30 | `sp_snow_step_TRS_TOA_S30_KEYED` | WRK_TRS_TOA_S30_KEYED | WRK_TRS_TOA_S20_SRC | 20 |
| m_Tgt_C_S_TRS_Pty_Rle_TOA | 40 | `sp_snow_step_TRS_TOA_S40_RANKED` | WRK_TRS_TOA_S40_RANKED | WRK_TRS_TOA_S30_KEYED | 30 |
| m_Tgt_C_S_TRS_Pty_Rle_TOA | 50 | `sp_snow_pub_TRS_TOA_EXC_STG_BAD_REC_MEMB_BAD_VALUE` |  | WRK_TRS_TOA_S40_RANKED | 40 |
| m_Tgt_C_S_TRS_Pty_Rle_TOA | 60 | `sp_snow_pub_TRS_TOA_EXC_STG_BAD_REC_MEMB_DATES` |  | WRK_TRS_TOA_S40_RANKED | 40 |
| m_Tgt_C_S_TRS_Pty_Rle_TOA | 70 | `sp_snow_pub_TRS_TOA_C_S_TRS_PTY_RLE_TOA` |  | WRK_TRS_TOA_S40_RANKED | 40 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | 10 | `sp_snow_step_TRS_REL1_S10_SRC` | WRK_TRS_REL1_S1_SRC |  | — |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | 20 | `sp_snow_step_TRS_REL1_S20_KEYED` | WRK_TRS_REL1_S2_KEYED | WRK_TRS_REL1_S1_SRC | 10 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | 30 | `sp_snow_step_TRS_REL1_S30_ROUTER` | WRK_TRS_REL1_S3_ROUTER | WRK_TRS_REL1_S2_KEYED | 20 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | 40 | `sp_snow_step_TRS_REL1_S40_CONSOL` | WRK_TRS_REL1_S4_CONSOL | WRK_TRS_REL1_S2_KEYED | 20 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | 50 | `sp_snow_step_TRS_REL1_S50_PREP` | WRK_TRS_REL1_S5_PREP | WRK_TRS_REL1_S4_CONSOL | 40 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | 60 | `sp_snow_step_TRS_REL1_S60_TIMELINE` | WRK_TRS_REL1_S6_TIMELINE | WRK_TRS_REL1_S5_PREP | 50 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | 70 | `sp_snow_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_MAIN_ALT_ID` |  | WRK_TRS_REL1_S3_ROUTER | 30 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | 80 | `sp_snow_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_REF_ALT_ID` |  | WRK_TRS_REL1_S3_ROUTER | 30 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | 90 | `sp_snow_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_LOOKUP` |  | WRK_TRS_REL1_S3_ROUTER | 30 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | 100 | `sp_snow_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_DATES` |  | WRK_TRS_REL1_S3_ROUTER | 30 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem | 110 | `sp_snow_pub_TRS_REL1_C_S_TRS_PTY_RLE_REL` |  | WRK_TRS_REL1_S6_TIMELINE | 60 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 | 10 | `sp_snow_step_TRS_RELDEACT_S10_MINPK` | WRK_TRS_RELDEACT_S10_MINPK |  | — |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 | 20 | `sp_snow_step_TRS_RELDEACT_S20_SRC` | WRK_TRS_RELDEACT_S20_SRC | WRK_TRS_RELDEACT_S10_MINPK | 10 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 | 30 | `sp_snow_step_TRS_RELDEACT_S30_KEYED` | WRK_TRS_RELDEACT_S30_KEYED | WRK_TRS_RELDEACT_S20_SRC | 20 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 | 40 | `sp_snow_step_TRS_RELDEACT_S40_XREF` | WRK_TRS_RELDEACT_S40_XREF |  | — |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 | 50 | `sp_snow_step_TRS_RELDEACT_S50_READY` | WRK_TRS_RELDEACT_S50_READY | WRK_TRS_RELDEACT_S30_KEYED|WRK_TRS_RELDEACT_S40_XREF | 30|40 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1 | 60 | `sp_snow_pub_TRS_RELDEACT_STG_TRS_DEACTIVATED_RELATIONSHIPS` |  | WRK_TRS_RELDEACT_S50_READY | 50 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | 10 | `sp_snow_step_TRS_REL2_S10_SRC` | WRK_TRS_REL2_S1_SRC |  | — |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | 20 | `sp_snow_step_TRS_REL2_S20_KEYED` | WRK_TRS_REL2_S2_KEYED | WRK_TRS_REL2_S1_SRC | 10 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | 30 | `sp_snow_step_TRS_REL2_S30_ROUTER` | WRK_TRS_REL2_S3_ROUTER | WRK_TRS_REL2_S2_KEYED | 20 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | 40 | `sp_snow_step_TRS_REL2_S40_CONSOL` | WRK_TRS_REL2_S4_CONSOL | WRK_TRS_REL2_S2_KEYED | 20 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | 50 | `sp_snow_step_TRS_REL2_S50_PREP` | WRK_TRS_REL2_S5_PREP | WRK_TRS_REL2_S4_CONSOL | 40 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | 60 | `sp_snow_step_TRS_REL2_S60_TIMELINE` | WRK_TRS_REL2_S6_TIMELINE | WRK_TRS_REL2_S5_PREP | 50 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | 70 | `sp_snow_pub_TRS_REL2_EXC_STG_BAD_REC_MEMB_DATES` |  | WRK_TRS_REL2_S3_ROUTER | 30 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | 80 | `sp_snow_pub_TRS_REL2_EXC_STG_BAD_REC_MEMB_DEFAULT` |  | WRK_TRS_REL2_S3_ROUTER | 30 |
| m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP | 90 | `sp_snow_pub_TRS_REL2_C_S_TRS_PTY_RLE_REL_PROV` |  | WRK_TRS_REL2_S6_TIMELINE | 60 |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | 10 | `sp_snow_step_TRS_PHN_S10_SRC` | WRK_TRS_PHN_S1_SRC |  | — |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | 20 | `sp_snow_step_TRS_PHN_S20_SLOTS` | WRK_TRS_PHN_S2_SLOTS | WRK_TRS_PHN_S1_SRC | 10 |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | 30 | `sp_snow_step_TRS_PHN_S30_CHECKED` | WRK_TRS_PHN_S3_CHECKED | WRK_TRS_PHN_S2_SLOTS | 20 |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | 40 | `sp_snow_step_TRS_PHN_S40_PHONES` | WRK_TRS_PHN_S4_PHONES | WRK_TRS_PHN_S3_CHECKED | 30 |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | 50 | `sp_snow_step_TRS_PHN_S50_VERSIONS` | WRK_TRS_PHN_S5_VERSIONS | WRK_TRS_PHN_S4_PHONES | 40 |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | 60 | `sp_snow_step_TRS_PHN_S60_EMAILS` | WRK_TRS_PHN_S6_EMAILS | WRK_TRS_PHN_S1_SRC | 10 |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | 70 | `sp_snow_step_TRS_PHN_S70_EADDR` | WRK_TRS_PHN_S7_VERSIONS | WRK_TRS_PHN_S6_EMAILS | 60 |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | 80 | `sp_snow_pub_TRS_PHN_C_S_TRS_PTY_RLE_PHN` |  | WRK_TRS_PHN_S5_VERSIONS | 50 |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | 90 | `sp_snow_pub_TRS_PHN_EXC_STG_BAD_REC_MEMB_PHONE` |  | WRK_TRS_PHN_S4_PHONES | 40 |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | 100 | `sp_snow_pub_TRS_PHN_C_S_TRS_PTY_RLE_EADDR` |  | WRK_TRS_PHN_S7_VERSIONS | 70 |
| m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr | 110 | `sp_snow_pub_TRS_PHN_EXC_STG_BAD_REC_MEMB_EMAIL` |  | WRK_TRS_PHN_S6_EMAILS | 60 |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw | 10 | `sp_snow_step_TRS_MNGSW_S10_DAILY` | WRK_TRS_MNGSW_S10_DAILY |  | — |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw | 20 | `sp_snow_step_TRS_MNGSW_S20_SRC` | WRK_TRS_MNGSW_S20_SRC | WRK_TRS_MNGSW_S10_DAILY | 10 |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw | 30 | `sp_snow_step_TRS_MNGSW_S30_NORM` | WRK_TRS_MNGSW_S30_NORM | WRK_TRS_MNGSW_S20_SRC | 20 |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw | 40 | `sp_snow_step_TRS_MNGSW_S40_ATTRS` | WRK_TRS_MNGSW_S40_ATTRS | WRK_TRS_MNGSW_S30_NORM | 30 |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw | 50 | `sp_snow_pub_TRS_MNGSW_C_S_TRS_PTY_MNG_ATTR` |  | WRK_TRS_MNGSW_S40_ATTRS | 40 |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing | 10 | `sp_snow_step_TRS_AUTHREP_S10_PAYEE` | WRK_TRS_MNGAR_S10_PAYEE |  | — |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing | 20 | `sp_snow_step_TRS_AUTHREP_S20_SRC` | WRK_TRS_MNGAR_S20_SRC | WRK_TRS_MNGAR_S10_PAYEE | 10 |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing | 30 | `sp_snow_step_TRS_AUTHREP_S30_KEYED` | WRK_TRS_MNGAR_S30_KEYED | WRK_TRS_MNGAR_S20_SRC | 20 |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing | 40 | `sp_snow_step_TRS_AUTHREP_S40_AGG` | WRK_TRS_MNGAR_S40_AGG | WRK_TRS_MNGAR_S30_KEYED | 30 |
| m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing | 50 | `sp_snow_pub_TRS_AUTHREP_C_S_TRS_PTY_MNG_ATTR` |  | WRK_TRS_MNGAR_S40_AGG | 40 |
| m_Tgt_C_S_TRS_Pty_Nm | 10 | `sp_snow_step_TRS_NM_S10_SRC` | WRK_TRS_NM_S10_SRC |  | — |
| m_Tgt_C_S_TRS_Pty_Nm | 20 | `sp_snow_step_TRS_NM_S20_NAMED` | WRK_TRS_NM_S20_NAMED | WRK_TRS_NM_S10_SRC | 10 |
| m_Tgt_C_S_TRS_Pty_Nm | 30 | `sp_snow_step_TRS_NM_S30_STD` | WRK_TRS_NM_S30_STD | WRK_TRS_NM_S20_NAMED | 20 |
| m_Tgt_C_S_TRS_Pty_Nm | 40 | `sp_snow_step_TRS_NM_S40_DEDUP` | WRK_TRS_NM_S40_DEDUP | WRK_TRS_NM_S30_STD | 30 |
| m_Tgt_C_S_TRS_Pty_Nm | 50 | `sp_snow_pub_TRS_NM_C_S_TRS_PTY_NM` |  | WRK_TRS_NM_S40_DEDUP | 40 |
| m_Tgt_C_S_TRS_Pty_Rle_Alt_Id | 10 | `sp_snow_step_TRS_ALT_S10_SRC` | WRK_TRS_ALT_S1_SRC |  | — |
| m_Tgt_C_S_TRS_Pty_Rle_Alt_Id | 20 | `sp_snow_step_TRS_ALT_S20_SSN` | WRK_TRS_ALT_S2_SSN | WRK_TRS_ALT_S1_SRC | 10 |
| m_Tgt_C_S_TRS_Pty_Rle_Alt_Id | 30 | `sp_snow_step_TRS_ALT_S30_NORM` | WRK_TRS_ALT_S3_NORM | WRK_TRS_ALT_S2_SSN | 20 |
| m_Tgt_C_S_TRS_Pty_Rle_Alt_Id | 40 | `sp_snow_step_TRS_ALT_S40_ROUTED` | WRK_TRS_ALT_S4_ROUTED | WRK_TRS_ALT_S3_NORM | 30 |
| m_Tgt_C_S_TRS_Pty_Rle_Alt_Id | 50 | `sp_snow_pub_TRS_ALT_C_S_TRS_PTY_RLE_ALT_ID` |  | WRK_TRS_ALT_S4_ROUTED | 40 |
| m_Tgt_C_S_TRS_Pty_Rle_Alt_Id | 60 | `sp_snow_pub_TRS_ALT_EXC_STG_BAD_REC_MEMB` |  | WRK_TRS_ALT_S4_ROUTED | 40 |
| m_Tgt_C_S_TRS_Pty_Rle_Pln | 10 | `sp_snow_step_TRS_PLN_S10_SRC` | WRK_TRS_PLN_S10_SRC |  | — |
| m_Tgt_C_S_TRS_Pty_Rle_Pln | 20 | `sp_snow_step_TRS_PLN_S20_PLANNED` | WRK_TRS_PLN_S20_PLANNED | WRK_TRS_PLN_S10_SRC | 10 |
| m_Tgt_C_S_TRS_Pty_Rle_Pln | 30 | `sp_snow_step_TRS_PLN_S30_RANKED` | WRK_TRS_PLN_S30_RANKED | WRK_TRS_PLN_S20_PLANNED | 20 |
| m_Tgt_C_S_TRS_Pty_Rle_Pln | 40 | `sp_snow_pub_TRS_PLN_C_S_TRS_PTY_RLE_PLN` |  | WRK_TRS_PLN_S30_RANKED | 30 |
| m_Tgt_C_S_TRS_Pty_Rle_Pln | 50 | `sp_snow_pub_TRS_PLN_EXC_STG_BAD_REC_MEMB` |  | WRK_TRS_PLN_S30_RANKED | 30 |
| m_Tgt_C_S_TRS_Addr_1 | 10 | `sp_snow_step_TRS_ADDR1_S10_SRC` | WRK_TRS_ADDR1_S10_SRC |  | — |
| m_Tgt_C_S_TRS_Addr_1 | 20 | `sp_snow_step_TRS_ADDR1_S20_DERIVED` | WRK_TRS_ADDR1_S20_DERIVED | WRK_TRS_ADDR1_S10_SRC | 10 |
| m_Tgt_C_S_TRS_Addr_1 | 30 | `sp_snow_step_TRS_ADDR1_S30_VALIDATED` | WRK_TRS_ADDR1_S30_VALIDATED | WRK_TRS_ADDR1_S20_DERIVED | 20 |
| m_Tgt_C_S_TRS_Addr_1 | 40 | `sp_snow_step_TRS_ADDR1_S40_READY` | WRK_TRS_ADDR1_S40_READY | WRK_TRS_ADDR1_S30_VALIDATED | 30 |
| m_Tgt_C_S_TRS_Addr_1 | 50 | `sp_snow_pub_TRS_ADDR1_STG_TRS_D_UNQ_ADDR` |  | WRK_TRS_ADDR1_S40_READY | 40 |
| m_Tgt_C_S_TRS_Addr_2 | 10 | `sp_snow_step_TRS_ADDR2_S10_DEDUP` | WRK_TRS_ADDR2_S10_DEDUP |  | — |
| m_Tgt_C_S_TRS_Addr_2 | 20 | `sp_snow_step_TRS_ADDR2_S20_SRC` | WRK_TRS_ADDR2_S20_SRC | WRK_TRS_ADDR2_S10_DEDUP | 10 |
| m_Tgt_C_S_TRS_Addr_2 | 30 | `sp_snow_step_TRS_ADDR2_S30_KEYED` | WRK_TRS_ADDR2_S30_KEYED | WRK_TRS_ADDR2_S20_SRC | 20 |
| m_Tgt_C_S_TRS_Addr_2 | 40 | `sp_snow_step_TRS_ADDR2_S40_SCORED` | WRK_TRS_ADDR2_S40_SCORED | WRK_TRS_ADDR2_S30_KEYED | 30 |
| m_Tgt_C_S_TRS_Addr_2 | 50 | `sp_snow_step_TRS_ADDR2_S50_READY` | WRK_TRS_ADDR2_S50_READY | WRK_TRS_ADDR2_S40_SCORED | 40 |
| m_Tgt_C_S_TRS_Addr_2 | 60 | `sp_snow_pub_TRS_ADDR2_DQM_ADDRESS` |  | WRK_TRS_ADDR2_S50_READY | 50 |
| m_Tgt_C_S_TRS_Addr_2 | 70 | `sp_snow_pub_TRS_ADDR2_C_S_TRS_PTY_RLE_ADDR` |  | WRK_TRS_ADDR2_S50_READY | 50 |
| m_Tgt_C_S_TRS_Addr_2 | 80 | `sp_snow_pub_TRS_ADDR2_EXC_STG_BAD_REC_MEMB` |  | WRK_TRS_ADDR2_S50_READY | 50 |
| m_Tgt_C_S_TRS_Stg_TOA | 10 | `sp_snow_step_TRS_STGTOA_S10_KEYED` | WRK_TRS_LUTOA_S10_KEYED |  | — |
| m_Tgt_C_S_TRS_Stg_TOA | 20 | `sp_snow_step_TRS_STGTOA_S20_FINAL` | WRK_TRS_LUTOA_S20_FINAL | WRK_TRS_LUTOA_S10_KEYED | 10 |
| m_Tgt_C_S_TRS_Stg_TOA | 30 | `sp_snow_pub_TRS_STGTOA_C_S_LU_TOA` |  | WRK_TRS_LUTOA_S20_FINAL | 20 |
