# WORKFLOW-STEPS — step-driver chain matrix (Oracle layout)

One table per workflow, one row per unit (driver row + transform steps + publish branches),
in execution order. Step numbers and procedure names are the ETL_RUN_CONFIG_TBL seed values,
verified identical to the driver call order and to the step/publish code (CTAS targets and
P_INPUT_TABLES defaults). Produced/consumed are the work tables; staging reads are noted
in the IICS mapping note, not in the consumed column, because P_INPUT_TABLES lists
WORK-TABLE inputs only (the step header says so explicitly).

Handoff vocabulary (output-side rule, SAME WORKFLOW ONLY):

- `TABLE:<table>` — a later unit in the same workflow reads that table.
- `CONTROL:success-only` — no later unit in this workflow reads the output; the next unit only needs this unit to have succeeded.
- `NONE` — the workflow-final unit; nothing after it in this workflow.

Cross-workflow reads exist for one shared table (EXC_STG_BAD_REC_MEMB is read by other
workflows' steps) — they do NOT change a row's handoff here, because the handoff rule is
per workflow. See the TDD §9 for the shared-table note.

A step is one IICS mapping. A publish branch is one IICS mapping. The driver row is taskflow
control, not a mapping: it gates on STEP_NO = 0, drops all work tables at step 5, runs the
enabled steps, then runs the enabled publish branches inside ONE transaction.

Generated from seeds + code; see ORA-WORK-TABLES-TDD.md for the pattern, the lifecycle,
and the recovery rules. Static derivation only — no database was connected.

## Workflow: wf_TRS_Stage_Load_1_Ongoing

Runner: `TRS/runners/sp_etl_run_wf_TRS_Stage_Load_1_Ongoing.sql` (14). Mappings in runner order: `m_Tgt_C_S_TRS_Pty_OnGoing`, `m_Tgt_C_S_TRS_Pty_Deactivation_1`, `m_Tgt_C_S_TRS_Pty_Rle_TOA`, `m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem`, `m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1`, `m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP`, `m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr`, `m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw`, `m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing`, `m_Tgt_C_S_TRS_Pty_Nm`, `m_Tgt_C_S_TRS_Pty_Rle_Alt_Id`, `m_Tgt_C_S_TRS_Pty_Rle_Pln`, `m_Tgt_C_S_TRS_Addr_1`, `m_Tgt_C_S_TRS_Addr_2`.

### Mapping: `m_Tgt_C_S_TRS_Pty_OnGoing` (4 steps + 9 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_TRS_Pty_OnGoing` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_TRS_PTY_S10_SRC` | `WRK_TRS_PTY_S1_SRC` | — | TABLE:WRK_TRS_PTY_S1_SRC | IICS mapping: staging/WRK sources → `WRK_TRS_PTY_S1_SRC`. |
| 20 | `sp_snow_step_TRS_PTY_S20_DQ` | `WRK_TRS_PTY_S2_DQ` | `WRK_TRS_PTY_S1_SRC` | TABLE:WRK_TRS_PTY_S2_DQ | IICS mapping: staging/WRK sources → `WRK_TRS_PTY_S2_DQ`. |
| 30 | `sp_snow_step_TRS_PTY_S30_ROUTER` | `WRK_TRS_PTY_S3_ROUTER` | `WRK_TRS_PTY_S2_DQ` | TABLE:WRK_TRS_PTY_S3_ROUTER | IICS mapping: staging/WRK sources → `WRK_TRS_PTY_S3_ROUTER`. |
| 40 | `sp_snow_step_TRS_PTY_S40_DEDUP` | `WRK_TRS_PTY_S4_DEDUP` | `WRK_TRS_PTY_S2_DQ` | TABLE:WRK_TRS_PTY_S4_DEDUP | IICS mapping: staging/WRK sources → `WRK_TRS_PTY_S4_DEDUP`. |
| 50 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_NAME` | `EXC_STG_BAD_REC_MEMB` | `WRK_TRS_PTY_S3_ROUTER` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_TRS_PTY_S3_ROUTER` → `EXC_STG_BAD_REC_MEMB`. |
| 60 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_GENDER` | `EXC_STG_BAD_REC_MEMB` | `WRK_TRS_PTY_S3_ROUTER` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_TRS_PTY_S3_ROUTER` → `EXC_STG_BAD_REC_MEMB`. |
| 70 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_DEATH` | `EXC_STG_BAD_REC_MEMB` | `WRK_TRS_PTY_S3_ROUTER` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_TRS_PTY_S3_ROUTER` → `EXC_STG_BAD_REC_MEMB`. |
| 80 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH` | `EXC_STG_BAD_REC_MEMB` | `WRK_TRS_PTY_S3_ROUTER` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_TRS_PTY_S3_ROUTER` → `EXC_STG_BAD_REC_MEMB`. |
| 90 | `sp_snow_pub_TRS_PTY_C_S_TRS_PTY` | `C_S_TRS_PTY` | `WRK_TRS_PTY_S4_DEDUP` | CONTROL:success-only | IICS mapping: `WRK_TRS_PTY_S4_DEDUP` → `C_S_TRS_PTY`. |
| 100 | `sp_snow_pub_TRS_PTY_C_S_TRS_PTY_RLE` | `C_S_TRS_PTY_RLE` | `WRK_TRS_PTY_S4_DEDUP` | CONTROL:success-only | IICS mapping: `WRK_TRS_PTY_S4_DEDUP` → `C_S_TRS_PTY_RLE`. |
| 110 | `sp_snow_pub_TRS_PTY_STG_TRS_VALID_MEMBERS` | `STG_TRS_VALID_MEMBERS` | `WRK_TRS_PTY_S4_DEDUP` | TABLE:STG_TRS_VALID_MEMBERS | IICS mapping: `WRK_TRS_PTY_S4_DEDUP` → `STG_TRS_VALID_MEMBERS`. |
| 120 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_RACE` | `EXC_STG_BAD_REC_MEMB` | `WRK_TRS_PTY_S4_DEDUP` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_TRS_PTY_S4_DEDUP` → `EXC_STG_BAD_REC_MEMB`. |
| 130 | `sp_snow_pub_TRS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY` | `EXC_STG_BAD_REC_MEMB` | `WRK_TRS_PTY_S4_DEDUP` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_TRS_PTY_S4_DEDUP` → `EXC_STG_BAD_REC_MEMB`. |
### Mapping: `m_Tgt_C_S_TRS_Pty_Deactivation_1` (4 steps + 1 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_TRS_Pty_Deactivation_1` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_TRS_PTYDEACT_S10_DEACTV` | `WRK_TRS_DEACT1_S10_DEACTV` | — | TABLE:WRK_TRS_DEACT1_S10_DEACTV | IICS mapping: staging/WRK sources → `WRK_TRS_DEACT1_S10_DEACTV`. |
| 20 | `sp_snow_step_TRS_PTYDEACT_S20_DEACTV_ID` | `WRK_TRS_DEACT1_S20_DEACTV_ID` | `WRK_TRS_DEACT1_S10_DEACTV` | TABLE:WRK_TRS_DEACT1_S20_DEACTV_ID | IICS mapping: staging/WRK sources → `WRK_TRS_DEACT1_S20_DEACTV_ID`. |
| 30 | `sp_snow_step_TRS_PTYDEACT_S30_READY` | `WRK_TRS_DEACT1_S30_READY` | `WRK_TRS_DEACT1_S20_DEACTV_ID` | TABLE:WRK_TRS_DEACT1_S30_READY | IICS mapping: staging/WRK sources → `WRK_TRS_DEACT1_S30_READY`. |
| 40 | `sp_snow_pub_TRS_PTYDEACT_STG_TRS_DEACTIVED_MEMBERS` | `STG_TRS_DEACTIVED_MEMBERS` | `WRK_TRS_DEACT1_S30_READY` | CONTROL:success-only | IICS mapping: `WRK_TRS_DEACT1_S30_READY` → `STG_TRS_DEACTIVED_MEMBERS`. |
| 50 | `sp_snow_step_TRS_PTYDEACT_S50_NOTPERFORMED` | — | — | CONTROL:success-only | Checkpoint-only step: writes no table. IICS mapping with no target — a control/signal step only. |
### Mapping: `m_Tgt_C_S_TRS_Pty_Rle_TOA` (4 steps + 3 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_TOA` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_TRS_TOA_S10_RAW` | `WRK_TRS_TOA_S10_RAW` | — | TABLE:WRK_TRS_TOA_S10_RAW | IICS mapping: staging/WRK sources → `WRK_TRS_TOA_S10_RAW`. |
| 20 | `sp_snow_step_TRS_TOA_S20_LATEST` | `WRK_TRS_TOA_S20_SRC` | `WRK_TRS_TOA_S10_RAW` | TABLE:WRK_TRS_TOA_S20_SRC | IICS mapping: staging/WRK sources → `WRK_TRS_TOA_S20_SRC`. |
| 30 | `sp_snow_step_TRS_TOA_S30_KEYED` | `WRK_TRS_TOA_S30_KEYED` | `WRK_TRS_TOA_S20_SRC` | TABLE:WRK_TRS_TOA_S30_KEYED | IICS mapping: staging/WRK sources → `WRK_TRS_TOA_S30_KEYED`. |
| 40 | `sp_snow_step_TRS_TOA_S40_RANKED` | `WRK_TRS_TOA_S40_RANKED` | `WRK_TRS_TOA_S30_KEYED` | TABLE:WRK_TRS_TOA_S40_RANKED | IICS mapping: staging/WRK sources → `WRK_TRS_TOA_S40_RANKED`. |
| 50 | `sp_snow_pub_TRS_TOA_EXC_STG_BAD_REC_MEMB_BAD_VALUE` | `EXC_STG_BAD_REC_MEMB` | `WRK_TRS_TOA_S40_RANKED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_TRS_TOA_S40_RANKED` → `EXC_STG_BAD_REC_MEMB`. |
| 60 | `sp_snow_pub_TRS_TOA_EXC_STG_BAD_REC_MEMB_DATES` | `EXC_STG_BAD_REC_MEMB` | `WRK_TRS_TOA_S40_RANKED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_TRS_TOA_S40_RANKED` → `EXC_STG_BAD_REC_MEMB`. |
| 70 | `sp_snow_pub_TRS_TOA_C_S_TRS_PTY_RLE_TOA` | `C_S_TRS_PTY_RLE_TOA` | `WRK_TRS_TOA_S40_RANKED` | CONTROL:success-only | IICS mapping: `WRK_TRS_TOA_S40_RANKED` → `C_S_TRS_PTY_RLE_TOA`. |
### Mapping: `m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem` (6 steps + 5 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_TRS_REL1_S10_SRC` | `WRK_TRS_REL1_S1_SRC` | — | TABLE:WRK_TRS_REL1_S1_SRC | IICS mapping: staging/WRK sources → `WRK_TRS_REL1_S1_SRC`. |
| 20 | `sp_snow_step_TRS_REL1_S20_KEYED` | `WRK_TRS_REL1_S2_KEYED` | `WRK_TRS_REL1_S1_SRC` | TABLE:WRK_TRS_REL1_S2_KEYED | IICS mapping: staging/WRK sources → `WRK_TRS_REL1_S2_KEYED`. |
| 30 | `sp_snow_step_TRS_REL1_S30_ROUTER` | `WRK_TRS_REL1_S3_ROUTER` | `WRK_TRS_REL1_S2_KEYED` | TABLE:WRK_TRS_REL1_S3_ROUTER | IICS mapping: staging/WRK sources → `WRK_TRS_REL1_S3_ROUTER`. |
| 40 | `sp_snow_step_TRS_REL1_S40_CONSOL` | `WRK_TRS_REL1_S4_CONSOL` | `WRK_TRS_REL1_S2_KEYED` | TABLE:WRK_TRS_REL1_S4_CONSOL | IICS mapping: staging/WRK sources → `WRK_TRS_REL1_S4_CONSOL`. |
| 50 | `sp_snow_step_TRS_REL1_S50_PREP` | `WRK_TRS_REL1_S5_PREP` | `WRK_TRS_REL1_S4_CONSOL` | TABLE:WRK_TRS_REL1_S5_PREP | IICS mapping: staging/WRK sources → `WRK_TRS_REL1_S5_PREP`. |
| 60 | `sp_snow_step_TRS_REL1_S60_TIMELINE` | `WRK_TRS_REL1_S6_TIMELINE` | `WRK_TRS_REL1_S5_PREP` | TABLE:WRK_TRS_REL1_S6_TIMELINE | IICS mapping: staging/WRK sources → `WRK_TRS_REL1_S6_TIMELINE`. |
| 70 | `sp_snow_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_MAIN_ALT_ID` | `EXC_STG_BAD_REC_MEMB` | `WRK_TRS_REL1_S3_ROUTER` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_TRS_REL1_S3_ROUTER` → `EXC_STG_BAD_REC_MEMB`. |
| 80 | `sp_snow_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_REF_ALT_ID` | `EXC_STG_BAD_REC_MEMB` | `WRK_TRS_REL1_S3_ROUTER` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_TRS_REL1_S3_ROUTER` → `EXC_STG_BAD_REC_MEMB`. |
| 90 | `sp_snow_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_LOOKUP` | `EXC_STG_BAD_REC_MEMB` | `WRK_TRS_REL1_S3_ROUTER` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_TRS_REL1_S3_ROUTER` → `EXC_STG_BAD_REC_MEMB`. |
| 100 | `sp_snow_pub_TRS_REL1_EXC_STG_BAD_REC_MEMB_DATES` | `EXC_STG_BAD_REC_MEMB` | `WRK_TRS_REL1_S3_ROUTER` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_TRS_REL1_S3_ROUTER` → `EXC_STG_BAD_REC_MEMB`. |
| 110 | `sp_snow_pub_TRS_REL1_C_S_TRS_PTY_RLE_REL` | `C_S_TRS_PTY_RLE_REL` | `WRK_TRS_REL1_S6_TIMELINE` | CONTROL:success-only | IICS mapping: `WRK_TRS_REL1_S6_TIMELINE` → `C_S_TRS_PTY_RLE_REL`. |
### Mapping: `m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1` (5 steps + 1 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_TRS_RELDEACT_S10_MINPK` | `WRK_TRS_RELDEACT_S10_MINPK` | — | TABLE:WRK_TRS_RELDEACT_S10_MINPK | IICS mapping: staging/WRK sources → `WRK_TRS_RELDEACT_S10_MINPK`. |
| 20 | `sp_snow_step_TRS_RELDEACT_S20_SRC` | `WRK_TRS_RELDEACT_S20_SRC` | `WRK_TRS_RELDEACT_S10_MINPK` | TABLE:WRK_TRS_RELDEACT_S20_SRC | IICS mapping: staging/WRK sources → `WRK_TRS_RELDEACT_S20_SRC`. |
| 30 | `sp_snow_step_TRS_RELDEACT_S30_KEYED` | `WRK_TRS_RELDEACT_S30_KEYED` | `WRK_TRS_RELDEACT_S20_SRC` | TABLE:WRK_TRS_RELDEACT_S30_KEYED | IICS mapping: staging/WRK sources → `WRK_TRS_RELDEACT_S30_KEYED`. |
| 40 | `sp_snow_step_TRS_RELDEACT_S40_XREF` | `WRK_TRS_RELDEACT_S40_XREF` | — | TABLE:WRK_TRS_RELDEACT_S40_XREF | IICS mapping: staging/WRK sources → `WRK_TRS_RELDEACT_S40_XREF`. |
| 50 | `sp_snow_step_TRS_RELDEACT_S50_READY` | `WRK_TRS_RELDEACT_S50_READY` | `WRK_TRS_RELDEACT_S30_KEYED`, `WRK_TRS_RELDEACT_S40_XREF` | TABLE:WRK_TRS_RELDEACT_S50_READY | IICS mapping: staging/WRK sources → `WRK_TRS_RELDEACT_S50_READY`. |
| 60 | `sp_snow_pub_TRS_RELDEACT_STG_TRS_DEACTIVATED_RELATIONSHIPS` | `STG_TRS_DEACTIVATED_RELATIONSHIPS` | `WRK_TRS_RELDEACT_S50_READY` | CONTROL:success-only | IICS mapping: `WRK_TRS_RELDEACT_S50_READY` → `STG_TRS_DEACTIVATED_RELATIONSHIPS`. |
### Mapping: `m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP` (6 steps + 3 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_TRS_REL2_S10_SRC` | `WRK_TRS_REL2_S1_SRC` | — | TABLE:WRK_TRS_REL2_S1_SRC | IICS mapping: staging/WRK sources → `WRK_TRS_REL2_S1_SRC`. |
| 20 | `sp_snow_step_TRS_REL2_S20_KEYED` | `WRK_TRS_REL2_S2_KEYED` | `WRK_TRS_REL2_S1_SRC` | TABLE:WRK_TRS_REL2_S2_KEYED | IICS mapping: staging/WRK sources → `WRK_TRS_REL2_S2_KEYED`. |
| 30 | `sp_snow_step_TRS_REL2_S30_ROUTER` | `WRK_TRS_REL2_S3_ROUTER` | `WRK_TRS_REL2_S2_KEYED` | TABLE:WRK_TRS_REL2_S3_ROUTER | IICS mapping: staging/WRK sources → `WRK_TRS_REL2_S3_ROUTER`. |
| 40 | `sp_snow_step_TRS_REL2_S40_CONSOL` | `WRK_TRS_REL2_S4_CONSOL` | `WRK_TRS_REL2_S2_KEYED` | TABLE:WRK_TRS_REL2_S4_CONSOL | IICS mapping: staging/WRK sources → `WRK_TRS_REL2_S4_CONSOL`. |
| 50 | `sp_snow_step_TRS_REL2_S50_PREP` | `WRK_TRS_REL2_S5_PREP` | `WRK_TRS_REL2_S4_CONSOL` | TABLE:WRK_TRS_REL2_S5_PREP | IICS mapping: staging/WRK sources → `WRK_TRS_REL2_S5_PREP`. |
| 60 | `sp_snow_step_TRS_REL2_S60_TIMELINE` | `WRK_TRS_REL2_S6_TIMELINE` | `WRK_TRS_REL2_S5_PREP` | TABLE:WRK_TRS_REL2_S6_TIMELINE | IICS mapping: staging/WRK sources → `WRK_TRS_REL2_S6_TIMELINE`. |
| 70 | `sp_snow_pub_TRS_REL2_EXC_STG_BAD_REC_MEMB_DATES` | `EXC_STG_BAD_REC_MEMB` | `WRK_TRS_REL2_S3_ROUTER` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_TRS_REL2_S3_ROUTER` → `EXC_STG_BAD_REC_MEMB`. |
| 80 | `sp_snow_pub_TRS_REL2_EXC_STG_BAD_REC_MEMB_DEFAULT` | `EXC_STG_BAD_REC_MEMB` | `WRK_TRS_REL2_S3_ROUTER` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_TRS_REL2_S3_ROUTER` → `EXC_STG_BAD_REC_MEMB`. |
| 90 | `sp_snow_pub_TRS_REL2_C_S_TRS_PTY_RLE_REL_PROV` | `C_S_TRS_PTY_RLE_REL_PROV` | `WRK_TRS_REL2_S6_TIMELINE` | CONTROL:success-only | IICS mapping: `WRK_TRS_REL2_S6_TIMELINE` → `C_S_TRS_PTY_RLE_REL_PROV`. |
### Mapping: `m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr` (7 steps + 4 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_TRS_PHN_S10_SRC` | `WRK_TRS_PHN_S1_SRC` | — | TABLE:WRK_TRS_PHN_S1_SRC | IICS mapping: staging/WRK sources → `WRK_TRS_PHN_S1_SRC`. |
| 20 | `sp_snow_step_TRS_PHN_S20_SLOTS` | `WRK_TRS_PHN_S2_SLOTS` | `WRK_TRS_PHN_S1_SRC` | TABLE:WRK_TRS_PHN_S2_SLOTS | IICS mapping: staging/WRK sources → `WRK_TRS_PHN_S2_SLOTS`. |
| 30 | `sp_snow_step_TRS_PHN_S30_CHECKED` | `WRK_TRS_PHN_S3_CHECKED` | `WRK_TRS_PHN_S2_SLOTS` | TABLE:WRK_TRS_PHN_S3_CHECKED | IICS mapping: staging/WRK sources → `WRK_TRS_PHN_S3_CHECKED`. |
| 40 | `sp_snow_step_TRS_PHN_S40_PHONES` | `WRK_TRS_PHN_S4_PHONES` | `WRK_TRS_PHN_S3_CHECKED` | TABLE:WRK_TRS_PHN_S4_PHONES | IICS mapping: staging/WRK sources → `WRK_TRS_PHN_S4_PHONES`. |
| 50 | `sp_snow_step_TRS_PHN_S50_VERSIONS` | `WRK_TRS_PHN_S5_VERSIONS` | `WRK_TRS_PHN_S4_PHONES` | TABLE:WRK_TRS_PHN_S5_VERSIONS | IICS mapping: staging/WRK sources → `WRK_TRS_PHN_S5_VERSIONS`. |
| 60 | `sp_snow_step_TRS_PHN_S60_EMAILS` | `WRK_TRS_PHN_S6_EMAILS` | `WRK_TRS_PHN_S1_SRC` | TABLE:WRK_TRS_PHN_S6_EMAILS | IICS mapping: staging/WRK sources → `WRK_TRS_PHN_S6_EMAILS`. |
| 70 | `sp_snow_step_TRS_PHN_S70_EADDR` | `WRK_TRS_PHN_S7_VERSIONS` | `WRK_TRS_PHN_S6_EMAILS` | TABLE:WRK_TRS_PHN_S7_VERSIONS | IICS mapping: staging/WRK sources → `WRK_TRS_PHN_S7_VERSIONS`. |
| 80 | `sp_snow_pub_TRS_PHN_C_S_TRS_PTY_RLE_PHN` | `C_S_TRS_PTY_RLE_PHN` | `WRK_TRS_PHN_S5_VERSIONS` | CONTROL:success-only | IICS mapping: `WRK_TRS_PHN_S5_VERSIONS` → `C_S_TRS_PTY_RLE_PHN`. |
| 90 | `sp_snow_pub_TRS_PHN_EXC_STG_BAD_REC_MEMB_PHONE` | `EXC_STG_BAD_REC_MEMB` | `WRK_TRS_PHN_S4_PHONES` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_TRS_PHN_S4_PHONES` → `EXC_STG_BAD_REC_MEMB`. |
| 100 | `sp_snow_pub_TRS_PHN_C_S_TRS_PTY_RLE_EADDR` | `C_S_TRS_PTY_RLE_EADDR` | `WRK_TRS_PHN_S7_VERSIONS` | CONTROL:success-only | IICS mapping: `WRK_TRS_PHN_S7_VERSIONS` → `C_S_TRS_PTY_RLE_EADDR`. |
| 110 | `sp_snow_pub_TRS_PHN_EXC_STG_BAD_REC_MEMB_EMAIL` | `EXC_STG_BAD_REC_MEMB` | `WRK_TRS_PHN_S6_EMAILS` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_TRS_PHN_S6_EMAILS` → `EXC_STG_BAD_REC_MEMB`. |
### Mapping: `m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw` (4 steps + 1 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_TRS_MNGSW_S10_DAILY` | `WRK_TRS_MNGSW_S10_DAILY` | — | TABLE:WRK_TRS_MNGSW_S10_DAILY | IICS mapping: staging/WRK sources → `WRK_TRS_MNGSW_S10_DAILY`. |
| 20 | `sp_snow_step_TRS_MNGSW_S20_SRC` | `WRK_TRS_MNGSW_S20_SRC` | `WRK_TRS_MNGSW_S10_DAILY` | TABLE:WRK_TRS_MNGSW_S20_SRC | IICS mapping: staging/WRK sources → `WRK_TRS_MNGSW_S20_SRC`. |
| 30 | `sp_snow_step_TRS_MNGSW_S30_NORM` | `WRK_TRS_MNGSW_S30_NORM` | `WRK_TRS_MNGSW_S20_SRC` | TABLE:WRK_TRS_MNGSW_S30_NORM | IICS mapping: staging/WRK sources → `WRK_TRS_MNGSW_S30_NORM`. |
| 40 | `sp_snow_step_TRS_MNGSW_S40_ATTRS` | `WRK_TRS_MNGSW_S40_ATTRS` | `WRK_TRS_MNGSW_S30_NORM` | TABLE:WRK_TRS_MNGSW_S40_ATTRS | IICS mapping: staging/WRK sources → `WRK_TRS_MNGSW_S40_ATTRS`. |
| 50 | `sp_snow_pub_TRS_MNGSW_C_S_TRS_PTY_MNG_ATTR` | `C_S_TRS_PTY_MNG_ATTR` | `WRK_TRS_MNGSW_S40_ATTRS` | TABLE:C_S_TRS_PTY_MNG_ATTR | IICS mapping: `WRK_TRS_MNGSW_S40_ATTRS` → `C_S_TRS_PTY_MNG_ATTR`. |
### Mapping: `m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing` (4 steps + 1 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_TRS_AUTHREP_S10_PAYEE` | `WRK_TRS_MNGAR_S10_PAYEE` | — | TABLE:WRK_TRS_MNGAR_S10_PAYEE | IICS mapping: staging/WRK sources → `WRK_TRS_MNGAR_S10_PAYEE`. |
| 20 | `sp_snow_step_TRS_AUTHREP_S20_SRC` | `WRK_TRS_MNGAR_S20_SRC` | `WRK_TRS_MNGAR_S10_PAYEE` | TABLE:WRK_TRS_MNGAR_S20_SRC | IICS mapping: staging/WRK sources → `WRK_TRS_MNGAR_S20_SRC`. |
| 30 | `sp_snow_step_TRS_AUTHREP_S30_KEYED` | `WRK_TRS_MNGAR_S30_KEYED` | `WRK_TRS_MNGAR_S20_SRC` | TABLE:WRK_TRS_MNGAR_S30_KEYED | IICS mapping: staging/WRK sources → `WRK_TRS_MNGAR_S30_KEYED`. |
| 40 | `sp_snow_step_TRS_AUTHREP_S40_AGG` | `WRK_TRS_MNGAR_S40_AGG` | `WRK_TRS_MNGAR_S30_KEYED` | TABLE:WRK_TRS_MNGAR_S40_AGG | IICS mapping: staging/WRK sources → `WRK_TRS_MNGAR_S40_AGG`. |
| 50 | `sp_snow_pub_TRS_AUTHREP_C_S_TRS_PTY_MNG_ATTR` | `C_S_TRS_PTY_MNG_ATTR` | `WRK_TRS_MNGAR_S40_AGG` | CONTROL:success-only | IICS mapping: `WRK_TRS_MNGAR_S40_AGG` → `C_S_TRS_PTY_MNG_ATTR`. |
### Mapping: `m_Tgt_C_S_TRS_Pty_Nm` (4 steps + 1 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_TRS_Pty_Nm` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_TRS_NM_S10_SRC` | `WRK_TRS_NM_S10_SRC` | — | TABLE:WRK_TRS_NM_S10_SRC | IICS mapping: staging/WRK sources → `WRK_TRS_NM_S10_SRC`. |
| 20 | `sp_snow_step_TRS_NM_S20_NAMED` | `WRK_TRS_NM_S20_NAMED` | `WRK_TRS_NM_S10_SRC` | TABLE:WRK_TRS_NM_S20_NAMED | IICS mapping: staging/WRK sources → `WRK_TRS_NM_S20_NAMED`. |
| 30 | `sp_snow_step_TRS_NM_S30_STD` | `WRK_TRS_NM_S30_STD` | `WRK_TRS_NM_S20_NAMED` | TABLE:WRK_TRS_NM_S30_STD | IICS mapping: staging/WRK sources → `WRK_TRS_NM_S30_STD`. |
| 40 | `sp_snow_step_TRS_NM_S40_DEDUP` | `WRK_TRS_NM_S40_DEDUP` | `WRK_TRS_NM_S30_STD` | TABLE:WRK_TRS_NM_S40_DEDUP | IICS mapping: staging/WRK sources → `WRK_TRS_NM_S40_DEDUP`. |
| 50 | `sp_snow_pub_TRS_NM_C_S_TRS_PTY_NM` | `C_S_TRS_PTY_NM` | `WRK_TRS_NM_S40_DEDUP` | CONTROL:success-only | IICS mapping: `WRK_TRS_NM_S40_DEDUP` → `C_S_TRS_PTY_NM`. |
### Mapping: `m_Tgt_C_S_TRS_Pty_Rle_Alt_Id` (4 steps + 2 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_TRS_ALT_S10_SRC` | `WRK_TRS_ALT_S1_SRC` | — | TABLE:WRK_TRS_ALT_S1_SRC | IICS mapping: staging/WRK sources → `WRK_TRS_ALT_S1_SRC`. |
| 20 | `sp_snow_step_TRS_ALT_S20_SSN` | `WRK_TRS_ALT_S2_SSN` | `WRK_TRS_ALT_S1_SRC` | TABLE:WRK_TRS_ALT_S2_SSN | IICS mapping: staging/WRK sources → `WRK_TRS_ALT_S2_SSN`. |
| 30 | `sp_snow_step_TRS_ALT_S30_NORM` | `WRK_TRS_ALT_S3_NORM` | `WRK_TRS_ALT_S2_SSN` | TABLE:WRK_TRS_ALT_S3_NORM | IICS mapping: staging/WRK sources → `WRK_TRS_ALT_S3_NORM`. |
| 40 | `sp_snow_step_TRS_ALT_S40_ROUTED` | `WRK_TRS_ALT_S4_ROUTED` | `WRK_TRS_ALT_S3_NORM` | TABLE:WRK_TRS_ALT_S4_ROUTED | IICS mapping: staging/WRK sources → `WRK_TRS_ALT_S4_ROUTED`. |
| 50 | `sp_snow_pub_TRS_ALT_C_S_TRS_PTY_RLE_ALT_ID` | `C_S_TRS_PTY_RLE_ALT_ID` | `WRK_TRS_ALT_S4_ROUTED` | CONTROL:success-only | IICS mapping: `WRK_TRS_ALT_S4_ROUTED` → `C_S_TRS_PTY_RLE_ALT_ID`. |
| 60 | `sp_snow_pub_TRS_ALT_EXC_STG_BAD_REC_MEMB` | `EXC_STG_BAD_REC_MEMB` | `WRK_TRS_ALT_S4_ROUTED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_TRS_ALT_S4_ROUTED` → `EXC_STG_BAD_REC_MEMB`. |
### Mapping: `m_Tgt_C_S_TRS_Pty_Rle_Pln` (3 steps + 2 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Pln` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_TRS_PLN_S10_SRC` | `WRK_TRS_PLN_S10_SRC` | — | TABLE:WRK_TRS_PLN_S10_SRC | IICS mapping: staging/WRK sources → `WRK_TRS_PLN_S10_SRC`. |
| 20 | `sp_snow_step_TRS_PLN_S20_PLANNED` | `WRK_TRS_PLN_S20_PLANNED` | `WRK_TRS_PLN_S10_SRC` | TABLE:WRK_TRS_PLN_S20_PLANNED | IICS mapping: staging/WRK sources → `WRK_TRS_PLN_S20_PLANNED`. |
| 30 | `sp_snow_step_TRS_PLN_S30_RANKED` | `WRK_TRS_PLN_S30_RANKED` | `WRK_TRS_PLN_S20_PLANNED` | TABLE:WRK_TRS_PLN_S30_RANKED | IICS mapping: staging/WRK sources → `WRK_TRS_PLN_S30_RANKED`. |
| 40 | `sp_snow_pub_TRS_PLN_C_S_TRS_PTY_RLE_PLN` | `C_S_TRS_PTY_RLE_PLN` | `WRK_TRS_PLN_S30_RANKED` | CONTROL:success-only | IICS mapping: `WRK_TRS_PLN_S30_RANKED` → `C_S_TRS_PTY_RLE_PLN`. |
| 50 | `sp_snow_pub_TRS_PLN_EXC_STG_BAD_REC_MEMB` | `EXC_STG_BAD_REC_MEMB` | `WRK_TRS_PLN_S30_RANKED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_TRS_PLN_S30_RANKED` → `EXC_STG_BAD_REC_MEMB`. |
### Mapping: `m_Tgt_C_S_TRS_Addr_1` (4 steps + 1 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_TRS_Addr_1` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_TRS_ADDR1_S10_SRC` | `WRK_TRS_ADDR1_S10_SRC` | — | TABLE:WRK_TRS_ADDR1_S10_SRC | IICS mapping: staging/WRK sources → `WRK_TRS_ADDR1_S10_SRC`. |
| 20 | `sp_snow_step_TRS_ADDR1_S20_DERIVED` | `WRK_TRS_ADDR1_S20_DERIVED` | `WRK_TRS_ADDR1_S10_SRC` | TABLE:WRK_TRS_ADDR1_S20_DERIVED | IICS mapping: staging/WRK sources → `WRK_TRS_ADDR1_S20_DERIVED`. |
| 30 | `sp_snow_step_TRS_ADDR1_S30_VALIDATED` | `WRK_TRS_ADDR1_S30_VALIDATED` | `WRK_TRS_ADDR1_S20_DERIVED` | TABLE:WRK_TRS_ADDR1_S30_VALIDATED | IICS mapping: staging/WRK sources → `WRK_TRS_ADDR1_S30_VALIDATED`. |
| 40 | `sp_snow_step_TRS_ADDR1_S40_READY` | `WRK_TRS_ADDR1_S40_READY` | `WRK_TRS_ADDR1_S30_VALIDATED` | TABLE:WRK_TRS_ADDR1_S40_READY | IICS mapping: staging/WRK sources → `WRK_TRS_ADDR1_S40_READY`. |
| 50 | `sp_snow_pub_TRS_ADDR1_STG_TRS_D_UNQ_ADDR` | `STG_TRS_D_UNQ_ADDR` | `WRK_TRS_ADDR1_S40_READY` | TABLE:STG_TRS_D_UNQ_ADDR | IICS mapping: `WRK_TRS_ADDR1_S40_READY` → `STG_TRS_D_UNQ_ADDR`. |
### Mapping: `m_Tgt_C_S_TRS_Addr_2` (5 steps + 3 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_TRS_Addr_2` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_TRS_ADDR2_S10_DEDUP` | `WRK_TRS_ADDR2_S10_DEDUP` | — | TABLE:WRK_TRS_ADDR2_S10_DEDUP | IICS mapping: staging/WRK sources → `WRK_TRS_ADDR2_S10_DEDUP`. |
| 20 | `sp_snow_step_TRS_ADDR2_S20_SRC` | `WRK_TRS_ADDR2_S20_SRC` | `WRK_TRS_ADDR2_S10_DEDUP` | TABLE:WRK_TRS_ADDR2_S20_SRC | IICS mapping: staging/WRK sources → `WRK_TRS_ADDR2_S20_SRC`. |
| 30 | `sp_snow_step_TRS_ADDR2_S30_KEYED` | `WRK_TRS_ADDR2_S30_KEYED` | `WRK_TRS_ADDR2_S20_SRC` | TABLE:WRK_TRS_ADDR2_S30_KEYED | IICS mapping: staging/WRK sources → `WRK_TRS_ADDR2_S30_KEYED`. |
| 40 | `sp_snow_step_TRS_ADDR2_S40_SCORED` | `WRK_TRS_ADDR2_S40_SCORED` | `WRK_TRS_ADDR2_S30_KEYED` | TABLE:WRK_TRS_ADDR2_S40_SCORED | IICS mapping: staging/WRK sources → `WRK_TRS_ADDR2_S40_SCORED`. |
| 50 | `sp_snow_step_TRS_ADDR2_S50_READY` | `WRK_TRS_ADDR2_S50_READY` | `WRK_TRS_ADDR2_S40_SCORED` | TABLE:WRK_TRS_ADDR2_S50_READY | IICS mapping: staging/WRK sources → `WRK_TRS_ADDR2_S50_READY`. |
| 60 | `sp_snow_pub_TRS_ADDR2_DQM_ADDRESS` | `DQM_ADDRESS` | `WRK_TRS_ADDR2_S50_READY` | CONTROL:success-only | IICS mapping: `WRK_TRS_ADDR2_S50_READY` → `DQM_ADDRESS`. |
| 70 | `sp_snow_pub_TRS_ADDR2_C_S_TRS_PTY_RLE_ADDR` | `C_S_TRS_PTY_RLE_ADDR` | `WRK_TRS_ADDR2_S50_READY` | CONTROL:success-only | IICS mapping: `WRK_TRS_ADDR2_S50_READY` → `C_S_TRS_PTY_RLE_ADDR`. |
| 80 | `sp_snow_pub_TRS_ADDR2_EXC_STG_BAD_REC_MEMB` | `EXC_STG_BAD_REC_MEMB` | `WRK_TRS_ADDR2_S50_READY` | NONE | IICS mapping: `WRK_TRS_ADDR2_S50_READY` → `EXC_STG_BAD_REC_MEMB`. |

## Workflow: wf_TRS_Stage_Load_TOA

Runner: `TRS/runners/sp_etl_run_wf_TRS_Stage_Load_TOA.sql` (1). Mappings in runner order: `m_Tgt_C_S_TRS_Stg_TOA`.

### Mapping: `m_Tgt_C_S_TRS_Stg_TOA` (2 steps + 1 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_TRS_Stg_TOA` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_TRS_STGTOA_S10_KEYED` | `WRK_TRS_LUTOA_S10_KEYED` | — | TABLE:WRK_TRS_LUTOA_S10_KEYED | IICS mapping: staging/WRK sources → `WRK_TRS_LUTOA_S10_KEYED`. |
| 20 | `sp_snow_step_TRS_STGTOA_S20_FINAL` | `WRK_TRS_LUTOA_S20_FINAL` | `WRK_TRS_LUTOA_S10_KEYED` | TABLE:WRK_TRS_LUTOA_S20_FINAL | IICS mapping: staging/WRK sources → `WRK_TRS_LUTOA_S20_FINAL`. |
| 30 | `sp_snow_pub_TRS_STGTOA_C_S_LU_TOA` | `C_S_LU_TOA` | `WRK_TRS_LUTOA_S20_FINAL` | NONE | IICS mapping: `WRK_TRS_LUTOA_S20_FINAL` → `C_S_LU_TOA`. |

## Workflow: wf_ECI_Stage_Load

Runner: `ECI/runners/sp_etl_run_wf_ECI_Stage_Load.sql` (9). Mappings in runner order: `m_Tgt_C_S_ECI_Pty_Validation`, `m_Tgt_C_S_ECI_Pty`, `m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr`, `m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn`, `m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid`, `m_Tgt_C_S_ECI_Pty_Rle_Alt_Id`, `m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr`, `m_Tgt_C_S_ECI_Pty_Addr`, `m_Tgt_C_S_ECI_Pty_Rle_Rel`.

### Mapping: `m_Tgt_C_S_ECI_Pty_Validation` (3 steps + 4 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_ECI_Pty_Validation` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_ECI_VAL_S10_SRC` | `WRK_ECI_VAL_S10_SRC` | — | TABLE:WRK_ECI_VAL_S10_SRC | IICS mapping: staging/WRK sources → `WRK_ECI_VAL_S10_SRC`. |
| 20 | `sp_snow_step_ECI_VAL_S20_ENRICHED` | `WRK_ECI_VAL_S20_ENRICHED` | `WRK_ECI_VAL_S10_SRC` | TABLE:WRK_ECI_VAL_S20_ENRICHED | IICS mapping: staging/WRK sources → `WRK_ECI_VAL_S20_ENRICHED`. |
| 30 | `sp_snow_step_ECI_VAL_S30_ROUTED` | `WRK_ECI_VAL_S30_ROUTED` | `WRK_ECI_VAL_S20_ENRICHED` | TABLE:WRK_ECI_VAL_S30_ROUTED | IICS mapping: staging/WRK sources → `WRK_ECI_VAL_S30_ROUTED`. |
| 40 | `sp_snow_pub_ECI_VAL_EXC_STG_BAD_REC_MEMB` | `EXC_STG_BAD_REC_MEMB` | `WRK_ECI_VAL_S30_ROUTED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_ECI_VAL_S30_ROUTED` → `EXC_STG_BAD_REC_MEMB`. |
| 50 | `sp_snow_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_DEACTIVATION` | `STG_ECI_PTY_INACTIVE_LOG` | `WRK_ECI_VAL_S30_ROUTED` | TABLE:STG_ECI_PTY_INACTIVE_LOG | IICS mapping: `WRK_ECI_VAL_S30_ROUTED` → `STG_ECI_PTY_INACTIVE_LOG`. |
| 60 | `sp_snow_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_STS` | `STG_ECI_PTY_INACTIVE_STS` | `WRK_ECI_VAL_S30_ROUTED` | TABLE:STG_ECI_PTY_INACTIVE_STS | IICS mapping: `WRK_ECI_VAL_S30_ROUTED` → `STG_ECI_PTY_INACTIVE_STS`. |
| 70 | `sp_snow_pub_ECI_VAL_STG_ECI_PTY_INACTIVE_LOG_REACTIVATION` | `STG_ECI_PTY_INACTIVE_LOG` | `WRK_ECI_VAL_S30_ROUTED` | CONTROL:success-only | IICS mapping: `WRK_ECI_VAL_S30_ROUTED` → `STG_ECI_PTY_INACTIVE_LOG`. |
### Mapping: `m_Tgt_C_S_ECI_Pty` (5 steps + 7 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_ECI_Pty` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_ECI_PTY_S10_SRC` | `WRK_ECI_PTY_S10_SRC` | — | TABLE:WRK_ECI_PTY_S10_SRC | IICS mapping: staging/WRK sources → `WRK_ECI_PTY_S10_SRC`. |
| 20 | `sp_snow_step_ECI_PTY_S20_ACTIVE` | `WRK_ECI_PTY_S20_ACTIVE` | `WRK_ECI_PTY_S10_SRC` | TABLE:WRK_ECI_PTY_S20_ACTIVE | IICS mapping: staging/WRK sources → `WRK_ECI_PTY_S20_ACTIVE`. |
| 30 | `sp_snow_step_ECI_PTY_S30_DQ` | `WRK_ECI_PTY_S30_DQ` | `WRK_ECI_PTY_S20_ACTIVE` | TABLE:WRK_ECI_PTY_S30_DQ | IICS mapping: staging/WRK sources → `WRK_ECI_PTY_S30_DQ`. |
| 40 | `sp_snow_step_ECI_PTY_S40_DQ2` | `WRK_ECI_PTY_S40_DQ2` | `WRK_ECI_PTY_S30_DQ` | TABLE:WRK_ECI_PTY_S40_DQ2 | IICS mapping: staging/WRK sources → `WRK_ECI_PTY_S40_DQ2`. |
| 50 | `sp_snow_step_ECI_PTY_S50_READY` | `WRK_ECI_PTY_S50_READY` | `WRK_ECI_PTY_S40_DQ2` | TABLE:WRK_ECI_PTY_S50_READY | IICS mapping: staging/WRK sources → `WRK_ECI_PTY_S50_READY`. |
| 60 | `sp_snow_pub_ECI_PTY_C_S_ECI_PTY` | `C_S_ECI_PTY` | `WRK_ECI_PTY_S50_READY` | CONTROL:success-only | IICS mapping: `WRK_ECI_PTY_S50_READY` → `C_S_ECI_PTY`. |
| 70 | `sp_snow_pub_ECI_PTY_C_S_ECI_PTY_RLE` | `C_S_ECI_PTY_RLE` | `WRK_ECI_PTY_S50_READY` | CONTROL:success-only | IICS mapping: `WRK_ECI_PTY_S50_READY` → `C_S_ECI_PTY_RLE`. |
| 80 | `sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_GENDER` | `EXC_STG_BAD_REC_MEMB` | `WRK_ECI_PTY_S50_READY` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_ECI_PTY_S50_READY` → `EXC_STG_BAD_REC_MEMB`. |
| 90 | `sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_BIRTH` | `EXC_STG_BAD_REC_MEMB` | `WRK_ECI_PTY_S50_READY` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_ECI_PTY_S50_READY` → `EXC_STG_BAD_REC_MEMB`. |
| 100 | `sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY` | `EXC_STG_BAD_REC_MEMB` | `WRK_ECI_PTY_S50_READY` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_ECI_PTY_S50_READY` → `EXC_STG_BAD_REC_MEMB`. |
| 110 | `sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_RACE` | `EXC_STG_BAD_REC_MEMB` | `WRK_ECI_PTY_S50_READY` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_ECI_PTY_S50_READY` → `EXC_STG_BAD_REC_MEMB`. |
| 120 | `sp_snow_pub_ECI_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE` | `EXC_STG_BAD_REC_MEMB` | `WRK_ECI_PTY_S50_READY` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_ECI_PTY_S50_READY` → `EXC_STG_BAD_REC_MEMB`. |
### Mapping: `m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr` (2 steps + 1 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Addr` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_ECI_RFA_S10_LATEST` | `WRK_ECI_RFA_S10_LATEST` | — | TABLE:WRK_ECI_RFA_S10_LATEST | IICS mapping: staging/WRK sources → `WRK_ECI_RFA_S10_LATEST`. |
| 20 | `sp_snow_step_ECI_RFA_S20_KEEPNEW` | `WRK_ECI_RFA_S20_KEEPNEW` | `WRK_ECI_RFA_S10_LATEST` | TABLE:WRK_ECI_RFA_S20_KEEPNEW | IICS mapping: staging/WRK sources → `WRK_ECI_RFA_S20_KEEPNEW`. |
| 30 | `sp_snow_pub_ECI_RFA_STG_ECI_D_FAMILY_ADDRESS` | `STG_ECI_D_FAMILY_ADDRESS` | `WRK_ECI_RFA_S20_KEEPNEW` | CONTROL:success-only | IICS mapping: `WRK_ECI_RFA_S20_KEEPNEW` → `STG_ECI_D_FAMILY_ADDRESS`. |
### Mapping: `m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn` (2 steps + 1 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Family_Phn` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_ECI_RFP_S10_LATEST` | `WRK_ECI_RFP_S10_LATEST` | — | TABLE:WRK_ECI_RFP_S10_LATEST | IICS mapping: staging/WRK sources → `WRK_ECI_RFP_S10_LATEST`. |
| 20 | `sp_snow_step_ECI_RFP_S20_KEEPNEW` | `WRK_ECI_RFP_S20_KEEPNEW` | `WRK_ECI_RFP_S10_LATEST` | TABLE:WRK_ECI_RFP_S20_KEEPNEW | IICS mapping: staging/WRK sources → `WRK_ECI_RFP_S20_KEEPNEW`. |
| 30 | `sp_snow_pub_ECI_RFP_STG_ECI_D_FAMILY_PHONE` | `STG_ECI_D_FAMILY_PHONE` | `WRK_ECI_RFP_S20_KEEPNEW` | CONTROL:success-only | IICS mapping: `WRK_ECI_RFP_S20_KEEPNEW` → `STG_ECI_D_FAMILY_PHONE`. |
### Mapping: `m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid` (2 steps + 1 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_Stg_ECI_Pty_Reactivation_D_Medicaid` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_ECI_RFM_S10_LATEST` | `WRK_ECI_RFM_S10_LATEST` | — | TABLE:WRK_ECI_RFM_S10_LATEST | IICS mapping: staging/WRK sources → `WRK_ECI_RFM_S10_LATEST`. |
| 20 | `sp_snow_step_ECI_RFM_S20_KEEPNEW` | `WRK_ECI_RFM_S20_KEEPNEW` | `WRK_ECI_RFM_S10_LATEST` | TABLE:WRK_ECI_RFM_S20_KEEPNEW | IICS mapping: staging/WRK sources → `WRK_ECI_RFM_S20_KEEPNEW`. |
| 30 | `sp_snow_pub_ECI_RFM_STG_ECI_D_MEDICAID` | `STG_ECI_D_MEDICAID` | `WRK_ECI_RFM_S20_KEEPNEW` | TABLE:STG_ECI_D_MEDICAID | IICS mapping: `WRK_ECI_RFM_S20_KEEPNEW` → `STG_ECI_D_MEDICAID`. |
### Mapping: `m_Tgt_C_S_ECI_Pty_Rle_Alt_Id` (4 steps + 3 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_ECI_ALT_S10_SRC` | `WRK_ECI_ALT_S10_SRC` | — | TABLE:WRK_ECI_ALT_S10_SRC | IICS mapping: staging/WRK sources → `WRK_ECI_ALT_S10_SRC`. |
| 20 | `sp_snow_step_ECI_ALT_S20_ACTIVE` | `WRK_ECI_ALT_S20_ACTIVE` | `WRK_ECI_ALT_S10_SRC` | TABLE:WRK_ECI_ALT_S20_ACTIVE | IICS mapping: staging/WRK sources → `WRK_ECI_ALT_S20_ACTIVE`. |
| 30 | `sp_snow_step_ECI_ALT_S30_ROUTED` | `WRK_ECI_ALT_S30_ROUTED` | `WRK_ECI_ALT_S20_ACTIVE` | TABLE:WRK_ECI_ALT_S30_ROUTED | IICS mapping: staging/WRK sources → `WRK_ECI_ALT_S30_ROUTED`. |
| 40 | `sp_snow_step_ECI_ALT_S40_READY` | `WRK_ECI_ALT_S40_READY` | `WRK_ECI_ALT_S30_ROUTED` | TABLE:WRK_ECI_ALT_S40_READY | IICS mapping: staging/WRK sources → `WRK_ECI_ALT_S40_READY`. |
| 50 | `sp_snow_pub_ECI_ALT_C_S_ECI_PTY_RLE_ALT_ID` | `C_S_ECI_PTY_RLE_ALT_ID` | `WRK_ECI_ALT_S40_READY` | CONTROL:success-only | IICS mapping: `WRK_ECI_ALT_S40_READY` → `C_S_ECI_PTY_RLE_ALT_ID`. |
| 60 | `sp_snow_pub_ECI_ALT_EXC_STG_BAD_REC_MEMB_SSN` | `EXC_STG_BAD_REC_MEMB` | `WRK_ECI_ALT_S40_READY` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_ECI_ALT_S40_READY` → `EXC_STG_BAD_REC_MEMB`. |
| 70 | `sp_snow_pub_ECI_ALT_EXC_STG_BAD_REC_MEMB_MEDICAID` | `EXC_STG_BAD_REC_MEMB` | `WRK_ECI_ALT_S40_READY` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_ECI_ALT_S40_READY` → `EXC_STG_BAD_REC_MEMB`. |
### Mapping: `m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr` (5 steps + 4 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_ECI_PHN_S10_SRC` | `WRK_ECI_PHN_S10_SRC` | — | TABLE:WRK_ECI_PHN_S10_SRC | IICS mapping: staging/WRK sources → `WRK_ECI_PHN_S10_SRC`. |
| 20 | `sp_snow_step_ECI_PHN_S20_ACTIVE` | `WRK_ECI_PHN_S20_ACTIVE` | `WRK_ECI_PHN_S10_SRC` | TABLE:WRK_ECI_PHN_S20_ACTIVE | IICS mapping: staging/WRK sources → `WRK_ECI_PHN_S20_ACTIVE`. |
| 30 | `sp_snow_step_ECI_PHN_S30_DQ` | `WRK_ECI_PHN_S30_DQ` | `WRK_ECI_PHN_S20_ACTIVE` | TABLE:WRK_ECI_PHN_S30_DQ | IICS mapping: staging/WRK sources → `WRK_ECI_PHN_S30_DQ`. |
| 40 | `sp_snow_step_ECI_PHN_S40_ROUTED` | `WRK_ECI_PHN_S40_ROUTED` | `WRK_ECI_PHN_S30_DQ` | TABLE:WRK_ECI_PHN_S40_ROUTED | IICS mapping: staging/WRK sources → `WRK_ECI_PHN_S40_ROUTED`. |
| 50 | `sp_snow_step_ECI_PHN_S50_READY` | `WRK_ECI_PHN_S50_READY` | `WRK_ECI_PHN_S40_ROUTED` | TABLE:WRK_ECI_PHN_S50_READY | IICS mapping: staging/WRK sources → `WRK_ECI_PHN_S50_READY`. |
| 60 | `sp_snow_pub_ECI_PHN_C_S_ECI_PTY_RLE_PHN` | `C_S_ECI_PTY_RLE_PHN` | `WRK_ECI_PHN_S50_READY` | CONTROL:success-only | IICS mapping: `WRK_ECI_PHN_S50_READY` → `C_S_ECI_PTY_RLE_PHN`. |
| 70 | `sp_snow_pub_ECI_PHN_EXC_STG_BAD_REC_MEMB_PHONE` | `EXC_STG_BAD_REC_MEMB` | `WRK_ECI_PHN_S50_READY` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_ECI_PHN_S50_READY` → `EXC_STG_BAD_REC_MEMB`. |
| 80 | `sp_snow_pub_ECI_PHN_C_S_ECI_PTY_RLE_EADDR` | `C_S_ECI_PTY_RLE_EADDR` | `WRK_ECI_PHN_S50_READY` | CONTROL:success-only | IICS mapping: `WRK_ECI_PHN_S50_READY` → `C_S_ECI_PTY_RLE_EADDR`. |
| 90 | `sp_snow_pub_ECI_PHN_EXC_STG_BAD_REC_MEMB_EMAIL` | `EXC_STG_BAD_REC_MEMB` | `WRK_ECI_PHN_S50_READY` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_ECI_PHN_S50_READY` → `EXC_STG_BAD_REC_MEMB`. |
### Mapping: `m_Tgt_C_S_ECI_Pty_Addr` (5 steps + 3 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_ECI_Pty_Addr` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_ECI_ADR_S10_SRC` | `WRK_ECI_ADR_S10_SRC` | — | TABLE:WRK_ECI_ADR_S10_SRC | IICS mapping: staging/WRK sources → `WRK_ECI_ADR_S10_SRC`. |
| 20 | `sp_snow_step_ECI_ADR_S20_KEYED` | `WRK_ECI_ADR_S20_KEYED` | `WRK_ECI_ADR_S10_SRC` | TABLE:WRK_ECI_ADR_S20_KEYED | IICS mapping: staging/WRK sources → `WRK_ECI_ADR_S20_KEYED`. |
| 30 | `sp_snow_step_ECI_ADR_S30_VALIDATED` | `WRK_ECI_ADR_S30_VALIDATED` | `WRK_ECI_ADR_S20_KEYED` | TABLE:WRK_ECI_ADR_S30_VALIDATED | IICS mapping: staging/WRK sources → `WRK_ECI_ADR_S30_VALIDATED`. |
| 40 | `sp_snow_step_ECI_ADR_S40_FLAT` | `WRK_ECI_ADR_S40_FLAT` | `WRK_ECI_ADR_S30_VALIDATED` | TABLE:WRK_ECI_ADR_S40_FLAT | IICS mapping: staging/WRK sources → `WRK_ECI_ADR_S40_FLAT`. |
| 50 | `sp_snow_step_ECI_ADR_S50_READY` | `WRK_ECI_ADR_S50_READY` | `WRK_ECI_ADR_S40_FLAT` | TABLE:WRK_ECI_ADR_S50_READY | IICS mapping: staging/WRK sources → `WRK_ECI_ADR_S50_READY`. |
| 60 | `sp_snow_pub_ECI_ADR_DQM_ADDRESS` | `DQM_ADDRESS` | `WRK_ECI_ADR_S50_READY` | CONTROL:success-only | IICS mapping: `WRK_ECI_ADR_S50_READY` → `DQM_ADDRESS`. |
| 70 | `sp_snow_pub_ECI_ADR_C_S_ECI_PTY_RLE_ADDR` | `C_S_ECI_PTY_RLE_ADDR` | `WRK_ECI_ADR_S50_READY` | CONTROL:success-only | IICS mapping: `WRK_ECI_ADR_S50_READY` → `C_S_ECI_PTY_RLE_ADDR`. |
| 80 | `sp_snow_pub_ECI_ADR_EXC_STG_BAD_REC_MEMB` | `EXC_STG_BAD_REC_MEMB` | `WRK_ECI_ADR_S50_READY` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_ECI_ADR_S50_READY` → `EXC_STG_BAD_REC_MEMB`. |
### Mapping: `m_Tgt_C_S_ECI_Pty_Rle_Rel` (4 steps + 2 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Rel` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_ECI_REL_S10_SRC` | `WRK_ECI_REL_S10_SRC` | — | TABLE:WRK_ECI_REL_S10_SRC | IICS mapping: staging/WRK sources → `WRK_ECI_REL_S10_SRC`. |
| 20 | `sp_snow_step_ECI_REL_S20_KEYED` | `WRK_ECI_REL_S20_KEYED` | `WRK_ECI_REL_S10_SRC` | TABLE:WRK_ECI_REL_S20_KEYED | IICS mapping: staging/WRK sources → `WRK_ECI_REL_S20_KEYED`. |
| 30 | `sp_snow_step_ECI_REL_S30_TYPED` | `WRK_ECI_REL_S30_TYPED` | `WRK_ECI_REL_S20_KEYED` | TABLE:WRK_ECI_REL_S30_TYPED | IICS mapping: staging/WRK sources → `WRK_ECI_REL_S30_TYPED`. |
| 40 | `sp_snow_step_ECI_REL_S40_READY` | `WRK_ECI_REL_S40_READY` | `WRK_ECI_REL_S30_TYPED` | TABLE:WRK_ECI_REL_S40_READY | IICS mapping: staging/WRK sources → `WRK_ECI_REL_S40_READY`. |
| 50 | `sp_snow_pub_ECI_REL_C_S_ECI_PTY_RLE_REL` | `C_S_ECI_PTY_RLE_REL` | `WRK_ECI_REL_S40_READY` | CONTROL:success-only | IICS mapping: `WRK_ECI_REL_S40_READY` → `C_S_ECI_PTY_RLE_REL`. |
| 60 | `sp_snow_pub_ECI_REL_EXC_STG_BAD_REC_MEMB` | `EXC_STG_BAD_REC_MEMB` | `WRK_ECI_REL_S40_READY` | NONE | IICS mapping: `WRK_ECI_REL_S40_READY` → `EXC_STG_BAD_REC_MEMB`. |

## Workflow: wf_FSS_Stage_Load

Runner: `FSS/runners/sp_etl_run_wf_FSS_Stage_Load.sql` (6). Mappings in runner order: `m_Tgt_C_S_FSS_Pty_Validation`, `m_Tgt_C_S_FSS_Pty`, `m_Tgt_C_S_FSS_Pty_Addr`, `m_Tgt_C_S_FSS_Pty_Rle_Alt_Id`, `m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr`, `m_Tgt_C_S_FSS_Pty_Rle_Rel`.

### Mapping: `m_Tgt_C_S_FSS_Pty_Validation` (3 steps + 4 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_FSS_Pty_Validation` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_FSS_VAL_S10_SRC` | `WRK_FSS_VAL_S1_SRC` | — | TABLE:WRK_FSS_VAL_S1_SRC | IICS mapping: staging/WRK sources → `WRK_FSS_VAL_S1_SRC`. |
| 20 | `sp_snow_step_FSS_VAL_S20_ENRICHED` | `WRK_FSS_VAL_S2_ENRICHED` | `WRK_FSS_VAL_S1_SRC` | TABLE:WRK_FSS_VAL_S2_ENRICHED | IICS mapping: staging/WRK sources → `WRK_FSS_VAL_S2_ENRICHED`. |
| 30 | `sp_snow_step_FSS_VAL_S30_ROUTED` | `WRK_FSS_VAL_S3_ROUTED` | `WRK_FSS_VAL_S2_ENRICHED` | TABLE:WRK_FSS_VAL_S3_ROUTED | IICS mapping: staging/WRK sources → `WRK_FSS_VAL_S3_ROUTED`. |
| 50 | `sp_snow_pub_FSS_VAL_EXC_STG_BAD_REC_MEMB` | `EXC_STG_BAD_REC_MEMB` | `WRK_FSS_VAL_S3_ROUTED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_FSS_VAL_S3_ROUTED` → `EXC_STG_BAD_REC_MEMB`. |
| 60 | `sp_snow_pub_FSS_VAL_STG_FSS_PTY_INACTIVE_LOG` | `STG_FSS_PTY_INACTIVE_LOG` | `WRK_FSS_VAL_S3_ROUTED` | CONTROL:success-only | IICS mapping: `WRK_FSS_VAL_S3_ROUTED` → `STG_FSS_PTY_INACTIVE_LOG`. |
| 70 | `sp_snow_pub_FSS_VAL_STG_FSS_PTY_INACTIVE_STS_NEW` | `STG_FSS_PTY_INACTIVE_STS` | `WRK_FSS_VAL_S3_ROUTED` | TABLE:STG_FSS_PTY_INACTIVE_STS | IICS mapping: `WRK_FSS_VAL_S3_ROUTED` → `STG_FSS_PTY_INACTIVE_STS`. |
| 80 | `sp_snow_pub_FSS_VAL_STG_FSS_PTY_INACTIVE_STS_REACTIVATION` | `STG_FSS_PTY_INACTIVE_STS` | `WRK_FSS_VAL_S3_ROUTED` | TABLE:STG_FSS_PTY_INACTIVE_STS | IICS mapping: `WRK_FSS_VAL_S3_ROUTED` → `STG_FSS_PTY_INACTIVE_STS`. |
### Mapping: `m_Tgt_C_S_FSS_Pty` (4 steps + 8 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_FSS_Pty` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_FSS_PTY_S10_SRC` | `WRK_FSS_PTY_S1_SRC` | — | TABLE:WRK_FSS_PTY_S1_SRC | IICS mapping: staging/WRK sources → `WRK_FSS_PTY_S1_SRC`. |
| 20 | `sp_snow_step_FSS_PTY_S20_DQ` | `WRK_FSS_PTY_S2_DQ` | `WRK_FSS_PTY_S1_SRC` | TABLE:WRK_FSS_PTY_S2_DQ | IICS mapping: staging/WRK sources → `WRK_FSS_PTY_S2_DQ`. |
| 30 | `sp_snow_step_FSS_PTY_S30_DQ2` | `WRK_FSS_PTY_S3_DQ2` | `WRK_FSS_PTY_S2_DQ` | TABLE:WRK_FSS_PTY_S3_DQ2 | IICS mapping: staging/WRK sources → `WRK_FSS_PTY_S3_DQ2`. |
| 40 | `sp_snow_step_FSS_PTY_S40_ROUTED` | `WRK_FSS_PTY_S4_ROUTED` | `WRK_FSS_PTY_S3_DQ2` | TABLE:WRK_FSS_PTY_S4_ROUTED | IICS mapping: staging/WRK sources → `WRK_FSS_PTY_S4_ROUTED`. |
| 50 | `sp_snow_pub_FSS_PTY_C_S_FSS_PTY` | `C_S_FSS_PTY` | `WRK_FSS_PTY_S4_ROUTED` | CONTROL:success-only | IICS mapping: `WRK_FSS_PTY_S4_ROUTED` → `C_S_FSS_PTY`. |
| 60 | `sp_snow_pub_FSS_PTY_C_S_FSS_PTY_RLE` | `C_S_FSS_PTY_RLE` | `WRK_FSS_PTY_S4_ROUTED` | CONTROL:success-only | IICS mapping: `WRK_FSS_PTY_S4_ROUTED` → `C_S_FSS_PTY_RLE`. |
| 70 | `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_GENDER` | `EXC_STG_BAD_REC_MEMB` | `WRK_FSS_PTY_S4_ROUTED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_FSS_PTY_S4_ROUTED` → `EXC_STG_BAD_REC_MEMB`. |
| 80 | `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_BIRTH` | `EXC_STG_BAD_REC_MEMB` | `WRK_FSS_PTY_S4_ROUTED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_FSS_PTY_S4_ROUTED` → `EXC_STG_BAD_REC_MEMB`. |
| 90 | `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY` | `EXC_STG_BAD_REC_MEMB` | `WRK_FSS_PTY_S4_ROUTED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_FSS_PTY_S4_ROUTED` → `EXC_STG_BAD_REC_MEMB`. |
| 100 | `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_RACE` | `EXC_STG_BAD_REC_MEMB` | `WRK_FSS_PTY_S4_ROUTED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_FSS_PTY_S4_ROUTED` → `EXC_STG_BAD_REC_MEMB`. |
| 110 | `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE` | `EXC_STG_BAD_REC_MEMB` | `WRK_FSS_PTY_S4_ROUTED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_FSS_PTY_S4_ROUTED` → `EXC_STG_BAD_REC_MEMB`. |
| 120 | `sp_snow_pub_FSS_PTY_EXC_STG_BAD_REC_MEMB_SUFFIX` | `EXC_STG_BAD_REC_MEMB` | `WRK_FSS_PTY_S4_ROUTED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_FSS_PTY_S4_ROUTED` → `EXC_STG_BAD_REC_MEMB`. |
### Mapping: `m_Tgt_C_S_FSS_Pty_Addr` (4 steps + 3 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_FSS_Pty_Addr` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_FSS_ADR_S10_SRC` | `WRK_FSS_ADDR_S1_SRC` | — | TABLE:WRK_FSS_ADDR_S1_SRC | IICS mapping: staging/WRK sources → `WRK_FSS_ADDR_S1_SRC`. |
| 20 | `sp_snow_step_FSS_ADR_S20_VALIDATED` | `WRK_FSS_ADDR_S2_VALIDATED` | `WRK_FSS_ADDR_S1_SRC` | TABLE:WRK_FSS_ADDR_S2_VALIDATED | IICS mapping: staging/WRK sources → `WRK_FSS_ADDR_S2_VALIDATED`. |
| 30 | `sp_snow_step_FSS_ADR_S30_FLAT` | `WRK_FSS_ADDR_S3_FLAT` | `WRK_FSS_ADDR_S2_VALIDATED` | TABLE:WRK_FSS_ADDR_S3_FLAT | IICS mapping: staging/WRK sources → `WRK_FSS_ADDR_S3_FLAT`. |
| 40 | `sp_snow_step_FSS_ADR_S40_SCORED` | `WRK_FSS_ADDR_S4_SCORED` | `WRK_FSS_ADDR_S3_FLAT` | TABLE:WRK_FSS_ADDR_S4_SCORED | IICS mapping: staging/WRK sources → `WRK_FSS_ADDR_S4_SCORED`. |
| 50 | `sp_snow_pub_FSS_ADR_DQM_ADDRESS` | `DQM_ADDRESS` | `WRK_FSS_ADDR_S4_SCORED` | CONTROL:success-only | IICS mapping: `WRK_FSS_ADDR_S4_SCORED` → `DQM_ADDRESS`. |
| 60 | `sp_snow_pub_FSS_ADR_C_S_FSS_PTY_RLE_ADDR` | `C_S_FSS_PTY_RLE_ADDR` | `WRK_FSS_ADDR_S4_SCORED` | CONTROL:success-only | IICS mapping: `WRK_FSS_ADDR_S4_SCORED` → `C_S_FSS_PTY_RLE_ADDR`. |
| 70 | `sp_snow_pub_FSS_ADR_EXC_STG_BAD_REC_MEMB` | `EXC_STG_BAD_REC_MEMB` | `WRK_FSS_ADDR_S4_SCORED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_FSS_ADDR_S4_SCORED` → `EXC_STG_BAD_REC_MEMB`. |
### Mapping: `m_Tgt_C_S_FSS_Pty_Rle_Alt_Id` (2 steps + 1 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Alt_Id` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_FSS_ALT_S10_SRC` | `WRK_FSS_ALT_S1_SRC` | — | TABLE:WRK_FSS_ALT_S1_SRC | IICS mapping: staging/WRK sources → `WRK_FSS_ALT_S1_SRC`. |
| 20 | `sp_snow_step_FSS_ALT_S20_FILTERED` | `WRK_FSS_ALT_S2_FILTERED` | `WRK_FSS_ALT_S1_SRC` | TABLE:WRK_FSS_ALT_S2_FILTERED | IICS mapping: staging/WRK sources → `WRK_FSS_ALT_S2_FILTERED`. |
| 50 | `sp_snow_pub_FSS_ALT_C_S_FSS_PTY_RLE_ALT_ID` | `C_S_FSS_PTY_RLE_ALT_ID` | `WRK_FSS_ALT_S2_FILTERED` | CONTROL:success-only | IICS mapping: `WRK_FSS_ALT_S2_FILTERED` → `C_S_FSS_PTY_RLE_ALT_ID`. |
### Mapping: `m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr` (4 steps + 5 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_FSS_PHN_S10_SRC` | `WRK_FSS_PHN_S1_SRC` | — | TABLE:WRK_FSS_PHN_S1_SRC | IICS mapping: staging/WRK sources → `WRK_FSS_PHN_S1_SRC`. |
| 20 | `sp_snow_step_FSS_PHN_S20_DQ` | `WRK_FSS_PHN_S2_DQ` | `WRK_FSS_PHN_S1_SRC` | TABLE:WRK_FSS_PHN_S2_DQ | IICS mapping: staging/WRK sources → `WRK_FSS_PHN_S2_DQ`. |
| 30 | `sp_snow_step_FSS_PHN_S30_CHECKED` | `WRK_FSS_PHN_S3_CHECKED` | `WRK_FSS_PHN_S2_DQ` | TABLE:WRK_FSS_PHN_S3_CHECKED | IICS mapping: staging/WRK sources → `WRK_FSS_PHN_S3_CHECKED`. |
| 40 | `sp_snow_step_FSS_PHN_S40_ROUTED` | `WRK_FSS_PHN_S4_ROUTED` | `WRK_FSS_PHN_S3_CHECKED` | TABLE:WRK_FSS_PHN_S4_ROUTED | IICS mapping: staging/WRK sources → `WRK_FSS_PHN_S4_ROUTED`. |
| 50 | `sp_snow_pub_FSS_PHN_C_S_FSS_PTY_RLE_EADDR` | `C_S_FSS_PTY_RLE_EADDR` | `WRK_FSS_PHN_S4_ROUTED` | CONTROL:success-only | IICS mapping: `WRK_FSS_PHN_S4_ROUTED` → `C_S_FSS_PTY_RLE_EADDR`. |
| 60 | `sp_snow_pub_FSS_PHN_EXC_STG_BAD_REC_MEMB_EMAIL` | `EXC_STG_BAD_REC_MEMB` | `WRK_FSS_PHN_S4_ROUTED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_FSS_PHN_S4_ROUTED` → `EXC_STG_BAD_REC_MEMB`. |
| 70 | `sp_snow_pub_FSS_PHN_C_S_FSS_PTY_RLE_PHN` | `C_S_FSS_PTY_RLE_PHN` | `WRK_FSS_PHN_S4_ROUTED` | CONTROL:success-only | IICS mapping: `WRK_FSS_PHN_S4_ROUTED` → `C_S_FSS_PTY_RLE_PHN`. |
| 80 | `sp_snow_pub_FSS_PHN_EXC_STG_BAD_REC_MEMB_PHONE` | `EXC_STG_BAD_REC_MEMB` | `WRK_FSS_PHN_S4_ROUTED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_FSS_PHN_S4_ROUTED` → `EXC_STG_BAD_REC_MEMB`. |
| 90 | `sp_snow_pub_FSS_PHN_EXC_STG_BAD_REC_MEMB_EXTENSION` | `EXC_STG_BAD_REC_MEMB` | `WRK_FSS_PHN_S4_ROUTED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_FSS_PHN_S4_ROUTED` → `EXC_STG_BAD_REC_MEMB`. |
### Mapping: `m_Tgt_C_S_FSS_Pty_Rle_Rel` (4 steps + 2 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Rel` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_FSS_REL_S10_SRC` | `WRK_FSS_REL_S1_SRC` | — | TABLE:WRK_FSS_REL_S1_SRC | IICS mapping: staging/WRK sources → `WRK_FSS_REL_S1_SRC`. |
| 20 | `sp_snow_step_FSS_REL_S20_CODED` | `WRK_FSS_REL_S2_CODED` | `WRK_FSS_REL_S1_SRC` | TABLE:WRK_FSS_REL_S2_CODED | IICS mapping: staging/WRK sources → `WRK_FSS_REL_S2_CODED`. |
| 30 | `sp_snow_step_FSS_REL_S30_TYPED` | `WRK_FSS_REL_S3_TYPED` | `WRK_FSS_REL_S2_CODED` | TABLE:WRK_FSS_REL_S3_TYPED | IICS mapping: staging/WRK sources → `WRK_FSS_REL_S3_TYPED`. |
| 40 | `sp_snow_step_FSS_REL_S40_FINAL` | `WRK_FSS_REL_S4_FINAL` | `WRK_FSS_REL_S3_TYPED` | TABLE:WRK_FSS_REL_S4_FINAL | IICS mapping: staging/WRK sources → `WRK_FSS_REL_S4_FINAL`. |
| 50 | `sp_snow_pub_FSS_REL_C_S_FSS_PTY_RLE_REL` | `C_S_FSS_PTY_RLE_REL` | `WRK_FSS_REL_S4_FINAL` | CONTROL:success-only | IICS mapping: `WRK_FSS_REL_S4_FINAL` → `C_S_FSS_PTY_RLE_REL`. |
| 60 | `sp_snow_pub_FSS_REL_EXC_STG_BAD_REC_MEMB` | `EXC_STG_BAD_REC_MEMB` | `WRK_FSS_REL_S4_FINAL` | NONE | IICS mapping: `WRK_FSS_REL_S4_FINAL` → `EXC_STG_BAD_REC_MEMB`. |

## Workflow: wf_WIC_Stage_Load

Runner: `WIC/runners/sp_etl_run_wf_WIC_Stage_Load.sql` (5). Mappings in runner order: `m_Tgt_C_S_WIC_Pty_Validation`, `m_Tgt_C_S_WIC_Pty`, `m_Tgt_C_S_WIC_Pty_Addr`, `m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr`, `m_Tgt_C_S_WIC_Pty_Rle_Alt_Id`.

### Mapping: `m_Tgt_C_S_WIC_Pty_Validation` (3 steps + 4 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_WIC_VAL_S10_ENRICHED` | `WRK_WIC_VAL_S10_ENRICHED` | — | TABLE:WRK_WIC_VAL_S10_ENRICHED | IICS mapping: staging/WRK sources → `WRK_WIC_VAL_S10_ENRICHED`. |
| 20 | `sp_snow_step_WIC_VAL_S20_NAMED` | `WRK_WIC_VAL_S20_NAMED` | `WRK_WIC_VAL_S10_ENRICHED` | TABLE:WRK_WIC_VAL_S20_NAMED | IICS mapping: staging/WRK sources → `WRK_WIC_VAL_S20_NAMED`. |
| 30 | `sp_snow_step_WIC_VAL_S30_ROUTED` | `WRK_WIC_VAL_S30_ROUTED` | `WRK_WIC_VAL_S20_NAMED` | TABLE:WRK_WIC_VAL_S30_ROUTED | IICS mapping: staging/WRK sources → `WRK_WIC_VAL_S30_ROUTED`. |
| 40 | `sp_snow_pub_WIC_VAL_EXC_STG_BAD_REC_MEMB` | `EXC_STG_BAD_REC_MEMB` | `WRK_WIC_VAL_S30_ROUTED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_WIC_VAL_S30_ROUTED` → `EXC_STG_BAD_REC_MEMB`. |
| 50 | `sp_snow_pub_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_DEACTIVATION` | `STG_WIC_PTY_INACTIVE_LOG` | `WRK_WIC_VAL_S30_ROUTED` | TABLE:STG_WIC_PTY_INACTIVE_LOG | IICS mapping: `WRK_WIC_VAL_S30_ROUTED` → `STG_WIC_PTY_INACTIVE_LOG`. |
| 60 | `sp_snow_pub_WIC_VAL_STG_WIC_PTY_INACTIVE_STS` | `STG_WIC_PTY_INACTIVE_STS` | `WRK_WIC_VAL_S30_ROUTED` | TABLE:STG_WIC_PTY_INACTIVE_STS | IICS mapping: `WRK_WIC_VAL_S30_ROUTED` → `STG_WIC_PTY_INACTIVE_STS`. |
| 70 | `sp_snow_pub_WIC_VAL_STG_WIC_PTY_INACTIVE_LOG_REACTIVATION` | `STG_WIC_PTY_INACTIVE_LOG` | `WRK_WIC_VAL_S30_ROUTED` | CONTROL:success-only | IICS mapping: `WRK_WIC_VAL_S30_ROUTED` → `STG_WIC_PTY_INACTIVE_LOG`. |
### Mapping: `m_Tgt_C_S_WIC_Pty` (4 steps + 7 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_WIC_Pty` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_WIC_PTY_S10_ACTIVE` | `WRK_WIC_PTY_S10_ACTIVE` | — | TABLE:WRK_WIC_PTY_S10_ACTIVE | IICS mapping: staging/WRK sources → `WRK_WIC_PTY_S10_ACTIVE`. |
| 20 | `sp_snow_step_WIC_PTY_S20_DQ` | `WRK_WIC_PTY_S20_DQ` | `WRK_WIC_PTY_S10_ACTIVE` | TABLE:WRK_WIC_PTY_S20_DQ | IICS mapping: staging/WRK sources → `WRK_WIC_PTY_S20_DQ`. |
| 30 | `sp_snow_step_WIC_PTY_S30_DQ2` | `WRK_WIC_PTY_S30_DQ2` | `WRK_WIC_PTY_S20_DQ` | TABLE:WRK_WIC_PTY_S30_DQ2 | IICS mapping: staging/WRK sources → `WRK_WIC_PTY_S30_DQ2`. |
| 40 | `sp_snow_step_WIC_PTY_S40_ROUTED` | `WRK_WIC_PTY_S40_ROUTED` | `WRK_WIC_PTY_S30_DQ2` | TABLE:WRK_WIC_PTY_S40_ROUTED | IICS mapping: staging/WRK sources → `WRK_WIC_PTY_S40_ROUTED`. |
| 50 | `sp_snow_pub_WIC_PTY_C_S_WIC_PTY` | `C_S_WIC_PTY` | `WRK_WIC_PTY_S40_ROUTED` | CONTROL:success-only | IICS mapping: `WRK_WIC_PTY_S40_ROUTED` → `C_S_WIC_PTY`. |
| 60 | `sp_snow_pub_WIC_PTY_C_S_WIC_PTY_RLE` | `C_S_WIC_PTY_RLE` | `WRK_WIC_PTY_S40_ROUTED` | CONTROL:success-only | IICS mapping: `WRK_WIC_PTY_S40_ROUTED` → `C_S_WIC_PTY_RLE`. |
| 70 | `sp_snow_pub_WIC_PTY_EXC_STG_BAD_REC_MEMB_GENDER` | `EXC_STG_BAD_REC_MEMB` | `WRK_WIC_PTY_S40_ROUTED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_WIC_PTY_S40_ROUTED` → `EXC_STG_BAD_REC_MEMB`. |
| 80 | `sp_snow_pub_WIC_PTY_EXC_STG_BAD_REC_MEMB_BIRTH` | `EXC_STG_BAD_REC_MEMB` | `WRK_WIC_PTY_S40_ROUTED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_WIC_PTY_S40_ROUTED` → `EXC_STG_BAD_REC_MEMB`. |
| 90 | `sp_snow_pub_WIC_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY` | `EXC_STG_BAD_REC_MEMB` | `WRK_WIC_PTY_S40_ROUTED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_WIC_PTY_S40_ROUTED` → `EXC_STG_BAD_REC_MEMB`. |
| 100 | `sp_snow_pub_WIC_PTY_EXC_STG_BAD_REC_MEMB_RACE` | `EXC_STG_BAD_REC_MEMB` | `WRK_WIC_PTY_S40_ROUTED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_WIC_PTY_S40_ROUTED` → `EXC_STG_BAD_REC_MEMB`. |
| 110 | `sp_snow_pub_WIC_PTY_EXC_STG_BAD_REC_MEMB_LANGUAGE` | `EXC_STG_BAD_REC_MEMB` | `WRK_WIC_PTY_S40_ROUTED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_WIC_PTY_S40_ROUTED` → `EXC_STG_BAD_REC_MEMB`. |
### Mapping: `m_Tgt_C_S_WIC_Pty_Addr` (4 steps + 3 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_WIC_Pty_Addr` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_WIC_ADR_S10_ACTIVE` | `WRK_WIC_ADDR_S10_ACTIVE` | — | TABLE:WRK_WIC_ADDR_S10_ACTIVE | IICS mapping: staging/WRK sources → `WRK_WIC_ADDR_S10_ACTIVE`. |
| 20 | `sp_snow_step_WIC_ADR_S20_VALIDATED` | `WRK_WIC_ADDR_S20_VALIDATED` | `WRK_WIC_ADDR_S10_ACTIVE` | TABLE:WRK_WIC_ADDR_S20_VALIDATED | IICS mapping: staging/WRK sources → `WRK_WIC_ADDR_S20_VALIDATED`. |
| 30 | `sp_snow_step_WIC_ADR_S30_FLAT` | `WRK_WIC_ADDR_S30_FLAT` | `WRK_WIC_ADDR_S20_VALIDATED` | TABLE:WRK_WIC_ADDR_S30_FLAT | IICS mapping: staging/WRK sources → `WRK_WIC_ADDR_S30_FLAT`. |
| 40 | `sp_snow_step_WIC_ADR_S40_SCORED` | `WRK_WIC_ADDR_S40_SCORED` | `WRK_WIC_ADDR_S30_FLAT` | TABLE:WRK_WIC_ADDR_S40_SCORED | IICS mapping: staging/WRK sources → `WRK_WIC_ADDR_S40_SCORED`. |
| 50 | `sp_snow_pub_WIC_ADR_DQM_ADDRESS` | `DQM_ADDRESS` | `WRK_WIC_ADDR_S40_SCORED` | CONTROL:success-only | IICS mapping: `WRK_WIC_ADDR_S40_SCORED` → `DQM_ADDRESS`. |
| 60 | `sp_snow_pub_WIC_ADR_C_S_WIC_PTY_RLE_ADDR` | `C_S_WIC_PTY_RLE_ADDR` | `WRK_WIC_ADDR_S40_SCORED` | CONTROL:success-only | IICS mapping: `WRK_WIC_ADDR_S40_SCORED` → `C_S_WIC_PTY_RLE_ADDR`. |
| 70 | `sp_snow_pub_WIC_ADR_EXC_STG_BAD_REC_MEMB` | `EXC_STG_BAD_REC_MEMB` | `WRK_WIC_ADDR_S40_SCORED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_WIC_ADDR_S40_SCORED` → `EXC_STG_BAD_REC_MEMB`. |
### Mapping: `m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr` (4 steps + 4 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_WIC_PHN_S10_SRC` | `WRK_WIC_PHN_S10_SRC` | — | TABLE:WRK_WIC_PHN_S10_SRC | IICS mapping: staging/WRK sources → `WRK_WIC_PHN_S10_SRC`. |
| 20 | `sp_snow_step_WIC_PHN_S20_CHECKED` | `WRK_WIC_PHN_S20_CHECKED` | `WRK_WIC_PHN_S10_SRC` | TABLE:WRK_WIC_PHN_S20_CHECKED | IICS mapping: staging/WRK sources → `WRK_WIC_PHN_S20_CHECKED`. |
| 30 | `sp_snow_step_WIC_PHN_S30_ROUTED` | `WRK_WIC_PHN_S30_ROUTED` | `WRK_WIC_PHN_S20_CHECKED` | TABLE:WRK_WIC_PHN_S30_ROUTED | IICS mapping: staging/WRK sources → `WRK_WIC_PHN_S30_ROUTED`. |
| 40 | `sp_snow_step_WIC_PHN_S40_READY` | `WRK_WIC_PHN_S40_READY` | `WRK_WIC_PHN_S30_ROUTED` | TABLE:WRK_WIC_PHN_S40_READY | IICS mapping: staging/WRK sources → `WRK_WIC_PHN_S40_READY`. |
| 50 | `sp_snow_pub_WIC_PHN_C_S_WIC_PTY_RLE_PHN` | `C_S_WIC_PTY_RLE_PHN` | `WRK_WIC_PHN_S40_READY` | CONTROL:success-only | IICS mapping: `WRK_WIC_PHN_S40_READY` → `C_S_WIC_PTY_RLE_PHN`. |
| 60 | `sp_snow_pub_WIC_PHN_EXC_STG_BAD_REC_MEMB_PHONE` | `EXC_STG_BAD_REC_MEMB` | `WRK_WIC_PHN_S40_READY` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_WIC_PHN_S40_READY` → `EXC_STG_BAD_REC_MEMB`. |
| 70 | `sp_snow_pub_WIC_PHN_C_S_WIC_PTY_RLE_EADDR` | `C_S_WIC_PTY_RLE_EADDR` | `WRK_WIC_PHN_S40_READY` | CONTROL:success-only | IICS mapping: `WRK_WIC_PHN_S40_READY` → `C_S_WIC_PTY_RLE_EADDR`. |
| 80 | `sp_snow_pub_WIC_PHN_EXC_STG_BAD_REC_MEMB_EMAIL` | `EXC_STG_BAD_REC_MEMB` | `WRK_WIC_PHN_S40_READY` | CONTROL:success-only | IICS mapping: `WRK_WIC_PHN_S40_READY` → `EXC_STG_BAD_REC_MEMB`. |
### Mapping: `m_Tgt_C_S_WIC_Pty_Rle_Alt_Id` (2 steps + 1 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_WIC_ALT_S10_KEYS` | `WRK_WIC_ALT_S10_KEYS` | — | TABLE:WRK_WIC_ALT_S10_KEYS | IICS mapping: staging/WRK sources → `WRK_WIC_ALT_S10_KEYS`. |
| 20 | `sp_snow_step_WIC_ALT_S20_READY` | `WRK_WIC_ALT_S20_READY` | `WRK_WIC_ALT_S10_KEYS` | TABLE:WRK_WIC_ALT_S20_READY | IICS mapping: staging/WRK sources → `WRK_WIC_ALT_S20_READY`. |
| 30 | `sp_snow_pub_WIC_ALT_C_S_WIC_PTY_RLE_ALT_ID` | `C_S_WIC_PTY_RLE_ALT_ID` | `WRK_WIC_ALT_S20_READY` | NONE | IICS mapping: `WRK_WIC_ALT_S20_READY` → `C_S_WIC_PTY_RLE_ALT_ID`. |

## Workflow: wf_TTF_Stage_Load

Runner: `TTF/runners/sp_etl_run_wf_TTF_Stage_Load.sql` (4). Mappings in runner order: `m_Tgt_C_S_TTF_Pty_Validation`, `m_Tgt_C_S_TTF_Pty`, `m_Tgt_C_S_TTF_Pty_Rle_Alt_Id`, `m_Tgt_C_S_TTF_Pty_Rle_Phn`.

### Mapping: `m_Tgt_C_S_TTF_Pty_Validation` (3 steps + 4 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_TTF_Pty_Validation` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_TTF_VAL_S10_ENRICHED` | `WRK_TTF_VAL_S1_ENRICHED` | — | TABLE:WRK_TTF_VAL_S1_ENRICHED | IICS mapping: staging/WRK sources → `WRK_TTF_VAL_S1_ENRICHED`. |
| 20 | `sp_snow_step_TTF_VAL_S20_NAMED` | `WRK_TTF_VAL_S2_NAMED` | `WRK_TTF_VAL_S1_ENRICHED` | TABLE:WRK_TTF_VAL_S2_NAMED | IICS mapping: staging/WRK sources → `WRK_TTF_VAL_S2_NAMED`. |
| 30 | `sp_snow_step_TTF_VAL_S30_ROUTED` | `WRK_TTF_VAL_S3_ROUTED` | `WRK_TTF_VAL_S2_NAMED` | TABLE:WRK_TTF_VAL_S3_ROUTED | IICS mapping: staging/WRK sources → `WRK_TTF_VAL_S3_ROUTED`. |
| 40 | `sp_snow_pub_TTF_VAL_EXC_STG_BAD_REC_MEMB` | `EXC_STG_BAD_REC_MEMB` | `WRK_TTF_VAL_S3_ROUTED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_TTF_VAL_S3_ROUTED` → `EXC_STG_BAD_REC_MEMB`. |
| 50 | `sp_snow_pub_TTF_VAL_STG_TTF_PTY_INACTIVE_LOG_DEACTIVATION` | `STG_TTF_PTY_INACTIVE_LOG` | `WRK_TTF_VAL_S3_ROUTED` | TABLE:STG_TTF_PTY_INACTIVE_LOG | IICS mapping: `WRK_TTF_VAL_S3_ROUTED` → `STG_TTF_PTY_INACTIVE_LOG`. |
| 60 | `sp_snow_pub_TTF_VAL_STG_TTF_PTY_INACTIVE_STS` | `STG_TTF_PTY_INACTIVE_STS` | `WRK_TTF_VAL_S3_ROUTED` | TABLE:STG_TTF_PTY_INACTIVE_STS | IICS mapping: `WRK_TTF_VAL_S3_ROUTED` → `STG_TTF_PTY_INACTIVE_STS`. |
| 70 | `sp_snow_pub_TTF_VAL_STG_TTF_PTY_INACTIVE_LOG_REACTIVATION` | `STG_TTF_PTY_INACTIVE_LOG` | `WRK_TTF_VAL_S3_ROUTED` | CONTROL:success-only | IICS mapping: `WRK_TTF_VAL_S3_ROUTED` → `STG_TTF_PTY_INACTIVE_LOG`. |
### Mapping: `m_Tgt_C_S_TTF_Pty` (4 steps + 6 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_TTF_Pty` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_TTF_PTY_S10_ACTIVE` | `WRK_TTF_PTY_S1_ACTIVE` | — | TABLE:WRK_TTF_PTY_S1_ACTIVE | IICS mapping: staging/WRK sources → `WRK_TTF_PTY_S1_ACTIVE`. |
| 20 | `sp_snow_step_TTF_PTY_S20_DQ` | `WRK_TTF_PTY_S2_DQ` | `WRK_TTF_PTY_S1_ACTIVE` | TABLE:WRK_TTF_PTY_S2_DQ | IICS mapping: staging/WRK sources → `WRK_TTF_PTY_S2_DQ`. |
| 30 | `sp_snow_step_TTF_PTY_S30_DQ2` | `WRK_TTF_PTY_S3_DQ2` | `WRK_TTF_PTY_S2_DQ` | TABLE:WRK_TTF_PTY_S3_DQ2 | IICS mapping: staging/WRK sources → `WRK_TTF_PTY_S3_DQ2`. |
| 40 | `sp_snow_step_TTF_PTY_S40_ROUTED` | `WRK_TTF_PTY_S4_ROUTED` | `WRK_TTF_PTY_S3_DQ2` | TABLE:WRK_TTF_PTY_S4_ROUTED | IICS mapping: staging/WRK sources → `WRK_TTF_PTY_S4_ROUTED`. |
| 50 | `sp_snow_pub_TTF_PTY_C_S_TTF_PTY` | `C_S_TTF_PTY` | `WRK_TTF_PTY_S4_ROUTED` | CONTROL:success-only | IICS mapping: `WRK_TTF_PTY_S4_ROUTED` → `C_S_TTF_PTY`. |
| 60 | `sp_snow_pub_TTF_PTY_C_S_TTF_PTY_RLE` | `C_S_TTF_PTY_RLE` | `WRK_TTF_PTY_S4_ROUTED` | CONTROL:success-only | IICS mapping: `WRK_TTF_PTY_S4_ROUTED` → `C_S_TTF_PTY_RLE`. |
| 70 | `sp_snow_pub_TTF_PTY_EXC_STG_BAD_REC_MEMB_GENDER` | `EXC_STG_BAD_REC_MEMB` | `WRK_TTF_PTY_S4_ROUTED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_TTF_PTY_S4_ROUTED` → `EXC_STG_BAD_REC_MEMB`. |
| 80 | `sp_snow_pub_TTF_PTY_EXC_STG_BAD_REC_MEMB_BIRTH` | `EXC_STG_BAD_REC_MEMB` | `WRK_TTF_PTY_S4_ROUTED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_TTF_PTY_S4_ROUTED` → `EXC_STG_BAD_REC_MEMB`. |
| 90 | `sp_snow_pub_TTF_PTY_EXC_STG_BAD_REC_MEMB_ETHNICITY` | `EXC_STG_BAD_REC_MEMB` | `WRK_TTF_PTY_S4_ROUTED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_TTF_PTY_S4_ROUTED` → `EXC_STG_BAD_REC_MEMB`. |
| 100 | `sp_snow_pub_TTF_PTY_EXC_STG_BAD_REC_MEMB_RACE` | `EXC_STG_BAD_REC_MEMB` | `WRK_TTF_PTY_S4_ROUTED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_TTF_PTY_S4_ROUTED` → `EXC_STG_BAD_REC_MEMB`. |
### Mapping: `m_Tgt_C_S_TTF_Pty_Rle_Alt_Id` (2 steps + 1 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_TTF_ALT_S10_KEYS` | `WRK_TTF_ALT_S1_KEYS` | — | TABLE:WRK_TTF_ALT_S1_KEYS | IICS mapping: staging/WRK sources → `WRK_TTF_ALT_S1_KEYS`. |
| 20 | `sp_snow_step_TTF_ALT_S20_DEDUP` | `WRK_TTF_ALT_S2_DEDUP` | `WRK_TTF_ALT_S1_KEYS` | TABLE:WRK_TTF_ALT_S2_DEDUP | IICS mapping: staging/WRK sources → `WRK_TTF_ALT_S2_DEDUP`. |
| 30 | `sp_snow_pub_TTF_ALT_C_S_TTF_PTY_RLE_ALT_ID` | `C_S_TTF_PTY_RLE_ALT_ID` | `WRK_TTF_ALT_S2_DEDUP` | CONTROL:success-only | IICS mapping: `WRK_TTF_ALT_S2_DEDUP` → `C_S_TTF_PTY_RLE_ALT_ID`. |
### Mapping: `m_Tgt_C_S_TTF_Pty_Rle_Phn` (3 steps + 2 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Phn` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_TTF_PHN_S10_SRC` | `WRK_TTF_PHN_S1_SRC` | — | TABLE:WRK_TTF_PHN_S1_SRC | IICS mapping: staging/WRK sources → `WRK_TTF_PHN_S1_SRC`. |
| 20 | `sp_snow_step_TTF_PHN_S20_CHECKED` | `WRK_TTF_PHN_S2_CHECKED` | `WRK_TTF_PHN_S1_SRC` | TABLE:WRK_TTF_PHN_S2_CHECKED | IICS mapping: staging/WRK sources → `WRK_TTF_PHN_S2_CHECKED`. |
| 30 | `sp_snow_step_TTF_PHN_S30_ROUTED` | `WRK_TTF_PHN_S3_ROUTED` | `WRK_TTF_PHN_S2_CHECKED` | TABLE:WRK_TTF_PHN_S3_ROUTED | IICS mapping: staging/WRK sources → `WRK_TTF_PHN_S3_ROUTED`. |
| 40 | `sp_snow_pub_TTF_PHN_C_S_TTF_PTY_RLE_PHN` | `C_S_TTF_PTY_RLE_PHN` | `WRK_TTF_PHN_S3_ROUTED` | CONTROL:success-only | IICS mapping: `WRK_TTF_PHN_S3_ROUTED` → `C_S_TTF_PTY_RLE_PHN`. |
| 50 | `sp_snow_pub_TTF_PHN_EXC_STG_BAD_REC_MEMB` | `EXC_STG_BAD_REC_MEMB` | `WRK_TTF_PHN_S3_ROUTED` | NONE | IICS mapping: `WRK_TTF_PHN_S3_ROUTED` → `EXC_STG_BAD_REC_MEMB`. |

## Workflow: wf_CRE_Stage_Load_Ongoing

Runner: `CRE/runners/sp_etl_run_wf_CRE_Stage_Load_Ongoing.sql` (1). Mappings in runner order: `m_Tgt_C_S_CRE_CARE_Clients`.

### Mapping: `m_Tgt_C_S_CRE_CARE_Clients` (5 steps + 18 publish branches + driver row)

| step_no | step_proc | work tables produced | work tables consumed | handoff mechanism | IICS mapping note |
|---:|---|---|---|---|---|
| 0 | `sp_snow_main_m_Tgt_C_S_CRE_CARE_Clients` | — | — | CONTROL:success-only | Taskflow control: STEP_NO = 0 gate, step-5 drop-all, step calls, publish transaction, step-999 job end. Not a mapping. |
| 10 | `sp_snow_step_CRE_CARE_S10_SRC_MRG` | `WRK_CRE_CARE_S1_SRC_MRG` | — | TABLE:WRK_CRE_CARE_S1_SRC_MRG | IICS mapping: staging/WRK sources → `WRK_CRE_CARE_S1_SRC_MRG`. |
| 20 | `sp_snow_step_CRE_CARE_S20_NAMED` | `WRK_CRE_CARE_S2_NAMED` | `WRK_CRE_CARE_S1_SRC_MRG` | TABLE:WRK_CRE_CARE_S2_NAMED | IICS mapping: staging/WRK sources → `WRK_CRE_CARE_S2_NAMED`. |
| 30 | `sp_snow_step_CRE_CARE_S30_RANKED` | `WRK_CRE_CARE_S3_RANKED` | `WRK_CRE_CARE_S2_NAMED` | TABLE:WRK_CRE_CARE_S3_RANKED | IICS mapping: staging/WRK sources → `WRK_CRE_CARE_S3_RANKED`. |
| 40 | `sp_snow_step_CRE_CARE_S40_FLAT` | `WRK_CRE_CARE_S4_FLAT` | `WRK_CRE_CARE_S3_RANKED` | TABLE:WRK_CRE_CARE_S4_FLAT | IICS mapping: staging/WRK sources → `WRK_CRE_CARE_S4_FLAT`. |
| 50 | `sp_snow_step_CRE_CARE_S50_KEYED` | `WRK_CRE_CARE_S5_KEYED` | `WRK_CRE_CARE_S4_FLAT` | TABLE:WRK_CRE_CARE_S5_KEYED | IICS mapping: staging/WRK sources → `WRK_CRE_CARE_S5_KEYED`. |
| 60 | `sp_snow_pub_CRE_CARE_CRE_SRC_MRG` | `CRE_SRC_MRG` | `WRK_CRE_CARE_S5_KEYED` | CONTROL:success-only | IICS mapping: `WRK_CRE_CARE_S5_KEYED` → `CRE_SRC_MRG`. |
| 70 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_FIRST_NAME` | `EXC_STG_BAD_REC_MEMB` | `WRK_CRE_CARE_S5_KEYED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_CRE_CARE_S5_KEYED` → `EXC_STG_BAD_REC_MEMB`. |
| 80 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_LAST_NAME` | `EXC_STG_BAD_REC_MEMB` | `WRK_CRE_CARE_S5_KEYED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_CRE_CARE_S5_KEYED` → `EXC_STG_BAD_REC_MEMB`. |
| 90 | `sp_snow_pub_CRE_CARE_C_S_CRE_PTY` | `C_S_CRE_PTY` | `WRK_CRE_CARE_S5_KEYED` | CONTROL:success-only | IICS mapping: `WRK_CRE_CARE_S5_KEYED` → `C_S_CRE_PTY`. |
| 100 | `sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE` | `C_S_CRE_PTY_RLE` | `WRK_CRE_CARE_S5_KEYED` | CONTROL:success-only | IICS mapping: `WRK_CRE_CARE_S5_KEYED` → `C_S_CRE_PTY_RLE`. |
| 110 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_GENDER` | `EXC_STG_BAD_REC_MEMB` | `WRK_CRE_CARE_S5_KEYED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_CRE_CARE_S5_KEYED` → `EXC_STG_BAD_REC_MEMB`. |
| 120 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_SUFFIX` | `EXC_STG_BAD_REC_MEMB` | `WRK_CRE_CARE_S5_KEYED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_CRE_CARE_S5_KEYED` → `EXC_STG_BAD_REC_MEMB`. |
| 130 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_ETHNICITY` | `EXC_STG_BAD_REC_MEMB` | `WRK_CRE_CARE_S5_KEYED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_CRE_CARE_S5_KEYED` → `EXC_STG_BAD_REC_MEMB`. |
| 140 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_RACE` | `EXC_STG_BAD_REC_MEMB` | `WRK_CRE_CARE_S5_KEYED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_CRE_CARE_S5_KEYED` → `EXC_STG_BAD_REC_MEMB`. |
| 150 | `sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_ADDR` | `C_S_CRE_PTY_RLE_ADDR` | `WRK_CRE_CARE_S5_KEYED` | CONTROL:success-only | IICS mapping: `WRK_CRE_CARE_S5_KEYED` → `C_S_CRE_PTY_RLE_ADDR`. |
| 160 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_ADDR` | `EXC_STG_BAD_REC_MEMB` | `WRK_CRE_CARE_S5_KEYED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_CRE_CARE_S5_KEYED` → `EXC_STG_BAD_REC_MEMB`. |
| 170 | `sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_PHN` | `C_S_CRE_PTY_RLE_PHN` | `WRK_CRE_CARE_S5_KEYED` | CONTROL:success-only | IICS mapping: `WRK_CRE_CARE_S5_KEYED` → `C_S_CRE_PTY_RLE_PHN`. |
| 180 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_PHONE` | `EXC_STG_BAD_REC_MEMB` | `WRK_CRE_CARE_S5_KEYED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_CRE_CARE_S5_KEYED` → `EXC_STG_BAD_REC_MEMB`. |
| 190 | `sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_CARE` | `C_S_CRE_PTY_RLE_ALT_ID` | `WRK_CRE_CARE_S5_KEYED` | TABLE:C_S_CRE_PTY_RLE_ALT_ID | IICS mapping: `WRK_CRE_CARE_S5_KEYED` → `C_S_CRE_PTY_RLE_ALT_ID`. |
| 200 | `sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_MEDICAID` | `C_S_CRE_PTY_RLE_ALT_ID` | `WRK_CRE_CARE_S5_KEYED` | TABLE:C_S_CRE_PTY_RLE_ALT_ID | IICS mapping: `WRK_CRE_CARE_S5_KEYED` → `C_S_CRE_PTY_RLE_ALT_ID`. |
| 210 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_MEDICAID_ALT` | `EXC_STG_BAD_REC_MEMB` | `WRK_CRE_CARE_S5_KEYED` | TABLE:EXC_STG_BAD_REC_MEMB | IICS mapping: `WRK_CRE_CARE_S5_KEYED` → `EXC_STG_BAD_REC_MEMB`. |
| 220 | `sp_snow_pub_CRE_CARE_C_S_CRE_PTY_RLE_ALT_ID_SSN` | `C_S_CRE_PTY_RLE_ALT_ID` | `WRK_CRE_CARE_S5_KEYED` | CONTROL:success-only | IICS mapping: `WRK_CRE_CARE_S5_KEYED` → `C_S_CRE_PTY_RLE_ALT_ID`. |
| 230 | `sp_snow_pub_CRE_CARE_EXC_STG_BAD_REC_MEMB_SSN_ALT` | `EXC_STG_BAD_REC_MEMB` | `WRK_CRE_CARE_S5_KEYED` | NONE | IICS mapping: `WRK_CRE_CARE_S5_KEYED` → `EXC_STG_BAD_REC_MEMB`. |
