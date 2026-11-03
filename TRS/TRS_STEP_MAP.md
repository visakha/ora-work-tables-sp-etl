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
