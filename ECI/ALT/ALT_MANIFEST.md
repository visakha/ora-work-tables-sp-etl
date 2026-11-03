# ALT_MANIFEST — m_Tgt_C_S_ECI_Pty_Rle_Alt_Id (config-driven step-driver refactor, ECI ONLY)

Example mapping for user feedback. Source of truth for business SQL:
`~/workspace/snowflake_multisource/ECI/mappings/sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id.sql`
(step map: `~/workspace/snowflake_multisource/ECI/STEP_MAP_ECI.md` §6).
Working files live under `~/workspace/snowflake_eci_drivers_v2/ECI/ALT/`
(v2 copy; v1 baseline, read-only, lives under
`~/workspace/snowflake_eci_drivers/ECI/ALT/`).

## v2 migration (this copy — changes vs v1)

- **Flag / input / count variables renamed (driver only).** The
  v1 DECLARE block's actual families were `l_flag_<nn>` (run flags),
  `l_cons_<nn>` (consumed-table strings) and `l_pub_<nn>` (publish
  counts) — NOT the RFA-style `v_run_*` / `v_in_*` / `l_pub_rows`
  families, and the consumed strings were NOT already named
  `l_in_<nn>`. All three families were renamed by the same rule
  (strip the `sp_snow_step_` / `sp_snow_pub_` prefix from the unit's
  procedure name, prepend `l_flag_` / `l_in_` / `l_pub_`):
  `l_flag_<nn>` → `l_flag_ECI_ALT_DRIVER` (driver row, formerly
  flag 0), `l_flag_ECI_ALT_S10_SRC`, `l_flag_ECI_ALT_S20_ACTIVE`,
  `l_flag_ECI_ALT_S30_ROUTED`, `l_flag_ECI_ALT_S40_READY`,
  `l_flag_ECI_ALT_C_S_ECI_PTY_RLE_ALT_ID` (step 50),
  `l_flag_ECI_ALT_EXC_STG_BAD_REC_MEMB_SSN` (step 60),
  `l_flag_ECI_ALT_EXC_STG_BAD_REC_MEMB_MEDICAID` (step 70);
  `l_cons_<nn>` → `l_in_ECI_ALT_S10_SRC`, `l_in_ECI_ALT_S20_ACTIVE`,
  `l_in_ECI_ALT_S30_ROUTED`, `l_in_ECI_ALT_S40_READY`,
  `l_in_ECI_ALT_C_S_ECI_PTY_RLE_ALT_ID`,
  `l_in_ECI_ALT_EXC_STG_BAD_REC_MEMB_SSN`,
  `l_in_ECI_ALT_EXC_STG_BAD_REC_MEMB_MEDICAID`; `l_pub_<nn>` →
  `l_pub_ECI_ALT_<branch>` on the same branch mapping.
  Branch-to-step-number assignment verified from the driver code
  itself (60 = SSN, 70 = Medicaid). 60 identifier occurrences
  renamed in total (27 `l_flag_*`, 21 `l_cons_*` → `l_in_*`,
  12 `l_pub_*`); DECLARE block, GATHER INTO list, IF conditions,
  step/publish call arguments and summary lines all updated; GATHER
  SELECT column order and INTO order unchanged; summary string
  literals unchanged.
- **Checkpoint signature migrated (driver + 4 step procs; 16 calls).**
  Every `sp_etl_checkpoint` call now passes exactly 10 arguments in
  this order: `P_SOURCE, P_JOB_RUN_ID, P_WORKFLOW_NAME, P_MAPPING_NAME,
  P_STATE, P_STEP_NAME, P_STEP_STATUS, P_TARGET_TABLE, P_MESSAGE,
  P_ERROR_MESSAGE`, with explicit NULLs. Dropped vs v1: `STEP_NO`,
  `ROW_COUNT`, `SOURCE_ROW_COUNT`, `WORK_TABLE_NAME`,
  `WORK_TABLE_ACTION`, `WORK_TABLE_PURPOSE`, `DROP_REASON`. Row counts
  survive only as step-proc RETURN values and driver helper36 summary
  lines, not as checkpoint arguments. Step checkpoints keep
  `MESSAGE = 'Step <n> complete.'`, `ERROR_MESSAGE = NULL`; the old
  work-table purpose strings (e.g. step 40's "Published in step 50.")
  are gone with `WORK_TABLE_PURPOSE`. Driver SKIPPED rows keep
  `MESSAGE = 'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)'`;
  publish COMPLETED rows keep their 'Published in one transaction…'
  messages; the TERMINATING 999 exception row keeps its 'Job failed;
  work tables left in place…' message and its 'See Snowflake query
  history…' error text, with `STEP_NAME 'JOB_END'`, `STATUS 'FAILED'`.
  `sp_etl_job_begin` / `sp_etl_job_finish` / `sp_etl_job_fail` are
  untouched. Publish procs still contain zero checkpoint calls
  (verified; their comment mentions were left alone).
- **v2 verification (this copy).** Regex over the driver: 0 matches
  for every OLD family — `l_flag_[0-9]+`, `l_in_[0-9]+`,
  `l_pub_[0-9]+`, `l_cons_[0-9]+` — and 0 matches for the RFA-style
  `v_run_*` / `v_in_*` families (never present here). Balanced-
  parenthesis parsing of every `sp_etl_checkpoint` call: driver 12 +
  steps 4 = 16 calls, all exactly 10 arguments in the new order, zero
  16/17-arg calls, zero dropped-parameter arguments
  (`'CREATED'`/`'NONE'`/`'KEPT'` absent from calls). GATHER INTO order
  still matches SELECT order (8 flags for STEP_NO 0/10/20/30/40/50/60/70
  then 7 consumed strings for 10/20/30/40/50/60/70). Every step CTAS
  and every publish INSERT is byte-identical to v1 after stripping
  checkpoint calls and normalising the renamed identifiers; publish
  files are byte-identical to v1 outright.

## Driver

Signature — IDENTICAL to the current main procedure (verified by string
comparison against the current file):

```sql
CREATE OR REPLACE PROCEDURE sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id (
    P_JOB_RUN_ID VARCHAR DEFAULT NULL
)
RETURNS VARCHAR
```

File: `driver_sp_snow_main_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id.sql`

Driver flow: job-run-id generation exactly as now + `sp_etl_job_begin`
→ config GATHER (nested BEGIN/EXCEPTION; flags default `'Y'`, consumed
strings default to the chain below; on exception the defaults stand and
a note line is added to the summary) → driver-row gate (STEP_NO 0 = `'N'`
writes a `MAPPING_SKIPPED` / `SKIPPED` checkpoint, calls
`sp_etl_job_finish` with a skipped message, and RETURNS before step 5)
→ step 5 cleanup (4 `DROP TABLE IF EXISTS`, no checkpoint, unchanged)
→ conditional step calls 10/20/30/40 → ONE publish transaction
(`BEGIN TRANSACTION` → branch calls 50/60/70 in order → `COMMIT`) →
publish checkpoints AFTER COMMIT only → `sp_etl_job_finish` with the
same message style as now → same RETURN format
(`'JOB_RUN_ID=' || id || CHR(10) || summary`). Exception block is
identical in shape to now (ROLLBACK + TERMINATING `JOB_END` / `FAILED`
checkpoint in the v2 10-argument form — v1 carried `STEP_NO` 999 —
+ `sp_etl_job_fail` + RAISE; verified by normalized comparison).

Constants: `c_source = 'ECI'`, `c_workflow = 'wf_ECI_Stage_Load'`,
`c_mapping = 'm_Tgt_C_S_ECI_Pty_Rle_Alt_Id'`.
Config source (qualified): `COMMON.ETL_RUN_CONFIG_TBL`, filtered on
`WORKFLOW_NAME = :c_workflow AND MAPPING_NAME = :c_mapping`, one
`COALESCE(MAX(CASE WHEN STEP_NO = n ...))` per flag / consumed string.

## Step table

Original parameters for this mapping: NONE (only `P_JOB_RUN_ID` was
appended by the current main). Every step proc therefore takes no
original parameter; its signature is `P_JOB_RUN_ID VARCHAR` +
`P_RUN_TS TIMESTAMP_NTZ` + `P_INPUT_TABLES VARCHAR DEFAULT <below>`.
`P_RUN_TS` replaces the old `:l_run_ts` and is used in SQL only by
step 40; steps 10/20/30 carry it for signature uniformity.

| STEP_NO | proc | kind | produces | consumes default | original params used | checkpoint STEP_NAME |
|---|---|---|---|---|---|---|
| 10 | `sp_snow_step_ECI_ALT_S10_SRC` | STAGE | `WRK_ECI_ALT_S10_SRC` — four alternate-id branches (018, 004, 002, 019) | `''` (empty; reads base source tables only, existence check skipped) | none | `SRC_ALT_IDS` |
| 20 | `sp_snow_step_ECI_ALT_S20_ACTIVE` | STAGE | `WRK_ECI_ALT_S20_ACTIVE` — ids of active parties only | `WRK_ECI_ALT_S10_SRC` | none | `ACTIVE_ALT_IDS` |
| 30 | `sp_snow_step_ECI_ALT_S30_ROUTED` | STAGE | `WRK_ECI_ALT_S30_ROUTED` — validated ids in valid / SSN-exception / Medicaid-exception groups | `WRK_ECI_ALT_S20_ACTIVE` | none | `VALIDATED_ROUTED` |
| 40 | `sp_snow_step_ECI_ALT_S40_READY` | STAGE (publish-ready) | `WRK_ECI_ALT_S40_READY` — publish-ready rows with insert-only guards (`uq_alt_id`, `uq_ssn_exc`, `uq_mcd_exc`) | `WRK_ECI_ALT_S30_ROUTED` | none | `READY_TO_PUBLISH` |

Step files: `steps/sp_snow_step_ECI_ALT_S10_SRC.sql`,
`steps/sp_snow_step_ECI_ALT_S20_ACTIVE.sql`,
`steps/sp_snow_step_ECI_ALT_S30_ROUTED.sql`,
`steps/sp_snow_step_ECI_ALT_S40_READY.sql`.

Each step proc: (1) input existence check (skipped when
`P_INPUT_TABLES` is NULL/empty; otherwise split on `|`, trim +
upper-case each name, check `INFORMATION_SCHEMA.TABLES` where
`TABLE_SCHEMA = CURRENT_SCHEMA()`); (2) the step's CTAS verbatim;
(3) `SELECT COUNT(*) INTO :l_rows`; (4) its own checkpoint in the v2
10-argument form, with the same `STEP_NAME` / `STEP_STATUS` /
`TARGET_TABLE` / `MESSAGE` as the v1 step checkpoint (row count is
RETURNed, not passed as a checkpoint argument); (5) `RETURN :l_rows`.
No exception block, no transactions, no target writes.

## Publish-branch table

Each branch proc signature: `P_JOB_RUN_ID VARCHAR` +
`P_RUN_TS TIMESTAMP_NTZ` + `P_INPUT_TABLES VARCHAR DEFAULT
'WRK_ECI_ALT_S40_READY'`. Each holds ONE current publish INSERT
verbatim, then returns `SQLROWCOUNT` as NUMBER. No transaction control,
no checkpoint calls (driver checkpoints after COMMIT). Order is the
original INSERT ALL order.

| STEP_NO | proc | kind | target | consumes |
|---|---|---|---|---|
| 50 | `sp_snow_pub_ECI_ALT_C_S_ECI_PTY_RLE_ALT_ID` | SPINE | `C_S_ECI_PTY_RLE_ALT_ID` (valid ids, `grp_valid AND uq_alt_id`) | `WRK_ECI_ALT_S40_READY` |
| 60 | `sp_snow_pub_ECI_ALT_EXC_STG_BAD_REC_MEMB_SSN` | NON-SPINE | `EXC_STG_BAD_REC_MEMB` (invalid SSN, `grp_ssn_exc AND uq_ssn_exc`, RUN_DATE NULL) | `WRK_ECI_ALT_S40_READY` |
| 70 | `sp_snow_pub_ECI_ALT_EXC_STG_BAD_REC_MEMB_MEDICAID` | NON-SPINE | `EXC_STG_BAD_REC_MEMB` (invalid Medicaid id, `grp_mcd_exc AND uq_mcd_exc`) | `WRK_ECI_ALT_S40_READY` |

Publish files: `publish/sp_snow_pub_ECI_ALT_C_S_ECI_PTY_RLE_ALT_ID.sql`,
`publish/sp_snow_pub_ECI_ALT_EXC_STG_BAD_REC_MEMB_SSN.sql`,
`publish/sp_snow_pub_ECI_ALT_EXC_STG_BAD_REC_MEMB_MEDICAID.sql`.

Driver publish checkpoints (after COMMIT, v2 10-argument form, no
`STEP_NO` / `ROW_COUNT` arguments): STEP_NAME
`PUBLISH_C_S_ECI_PTY_RLE_ALT_ID` (was STEP_NO 50),
`PUBLISH_EXC_STG_BAD_REC_MEMB_SSN` (was 60),
`PUBLISH_EXC_STG_BAD_REC_MEMB_MEDICAID` (was 70); each `STATE
'WORKING'`, `STEP_STATUS 'COMPLETED'`, `TARGET_TABLE` as in the table
above, plus a helper36 summary line carrying that branch's count
(the count is no longer a checkpoint argument).
Skipped branches get a `SKIPPED` row (same STEP_NAME) and a
plain-text summary line instead (helper36 is not used for skips).

## Verification performed (no live Snowflake here — see uncertainties)

- All 4 step CTAS bodies: EXACT match to the current file (after the
  single allowed substitution `:l_run_ts` → `:P_RUN_TS` in step 40;
  `:c_mapping` is unchanged text — it now binds to the step proc's
  local constant of the same value).
- All 3 publish INSERT statements: EXACT match to the current file.
- All 4 step checkpoints: v2 10-argument form (see "v2 migration"
  above); `STEP_NAME` / `STEP_STATUS` / `TARGET_TABLE` / `MESSAGE`
  match the v1 step checkpoints, with `ROW_COUNT` /
  `WORK_TABLE_*` / `DROP_REASON` arguments removed. (In v1 they
  matched the current step checkpoints under normalized comparison;
  only change then was literal `'ECI'` / `:l_job_run_id` →
  `:c_source` / `:P_JOB_RUN_ID` variables of identical value.)
- Driver signature: identical to the current main. Driver exception
  block: identical (normalized). Step 5 drops: same 4 tables, no
  checkpoint for drops.
- Counts: 1 driver + 4 step procs + 3 publish-branch procs = 8 code
  files. Every current step and every current publish INSERT has
  exactly one new proc; no step or branch is missing or duplicated.
- Style greps: 0 quoted `'DROPPED'` checkpoint args, 0
  `P_RESUME_STEP`, 0 real `CURSOR` (the word appears only in comments
  stating no cursor is used), 0 `sp_etl_checkpoint` calls in publish
  files, exactly 1 real `BEGIN TRANSACTION` + 1 `COMMIT` (driver only),
  all work tables `CREATE OR REPLACE TRANSIENT TABLE` with the same
  names as now, `P_JOB_RUN_ID` in all 8 procs, no checkpoint between
  `BEGIN TRANSACTION` and `COMMIT` (driver lines 298–311 contain only
  branch calls).

## Deviations and uncertainties (nothing silently shipped)

1. EXISTENCE-CHECK ERROR MECHANISM — FALLBACK USED. The task's primary
   (`RAISE EXCEPTION` naming the missing table) was NOT used: the
   Snowflake RAISE reference documents only `RAISE <exception_name>;`
   — a declared exception's message is fixed at declaration, so it
   cannot name a runtime-discovered table. Step procs therefore use
   the task's fallback: `EXECUTE IMMEDIATE :l_sql` where `l_sql =
   'SELECT 1 FROM ' || <first missing table>`, raising the native
   object-not-exists error naming that table; the step is identified
   by the step proc's name in the call stack / query history. NOTE
   FOR PARENT: the sibling `ECI/PTY/steps/sp_snow_step_ECI_PTY_S10_SRC.sql`
   uses `RAISE EXCEPTION '...' || :l_missing;`, which per the same
   reference may not compile — consider aligning PTY to this fallback
   (PTY files were not touched; this mapping only).
2. `SKIPPED` VOCABULARY — CHOICE TO CONFIRM. `JOB_CONTROL_ETL.STEP_STATUS`
   has no CHECK constraint (only a DDL comment listing
   STARTED | COMPLETED | FAILED), so `'SKIPPED'` rows are used for
   config-skipped steps/branches and the driver-row skip. Flag to the
   user as a choice to confirm, not a constraint change.
3. SKIPPING IS PER-STEP, NOT CASCADING. If an upstream step is skipped
   while a downstream step still runs, the downstream step fails on its
   missing input (existence check raises) — fail-closed by design.
   Do not skip step 10/20/30 while leaving later steps enabled unless
   that failure is intended. Same for publish: a skipped step 40 with
   an enabled publish branch fails on the missing S40 table at INSERT.
4. STEP 40 CHECKPOINT PURPOSE TEXT — REMOVED IN v2. In v1 it still
   said "Published in step 50." even though publish spans steps
   50/60/70, kept because step checkpoints carried the SAME values as
   the current ones. In v2 the `WORK_TABLE_PURPOSE` argument no
   longer exists, so that text appears in no checkpoint; step 40's
   message is now just 'Step 40 complete.'
5. PUBLISH PROCS DO NOT RUN THE EXISTENCE CHECK. Per the specified
   publish-proc body (INSERT + RETURN only), a missing S40 table
   surfaces as the native INSERT error, not the checked error. Only
   step procs check inputs.
6. UNUSED PARAMS, CARRIED FOR UNIFORMITY. `P_RUN_TS` is unused by all
   three publish branches (`run_ts` in their SELECTs is the S40 column)
   and by steps 10/20/30; `P_JOB_RUN_ID` is unused in publish-proc
   bodies (they write no checkpoint). `mapping_name` in publish
   branches is the S40 column, not the local `c_mapping` constant.
7. PUBLISH CHECKPOINT SHAPE CHANGED (by design). The current single
   step-50 `PUBLISH` checkpoint with the combined count across all
   branches is replaced by three per-branch checkpoints (50/60/70).
   The combined total is no longer in one row; it is the sum of the
   three branch counts, all visible in the summary lines.
8. SKIPPED-ROW ARG CHOICES (v2 form). Skipped step checkpoints carry
   NULL target; skipped publish checkpoints carry `TARGET_TABLE` (so
   the skipped target is visible). There are no longer any
   count/work-table/action arguments. Both carry the exact message
   `'Skipped by ETL_RUN_CONFIG_TBL (IS_RUN_ENABLED = N)'` with NULL
   error text. (In v1, skipped step rows carried NULL
   target/counts/work-table with action `'NONE'`, and skipped publish
   rows carried `TARGET_TABLE` with NULL counts.)
9. CONFIG-NOTE SUMMARY LINE (driver only, informational). When the
   GATHER itself fails (e.g. config table missing), the driver adds a
   `Config note: ...` line to the summary. When the table exists but
   has no rows for this mapping, defaults apply SILENTLY (COALESCE over
   an empty set) — by design, since absent rows are the default case.
10. CONFIG TABLE NOT FOUND IN WORKSPACE. No DDL for
    `COMMON.ETL_RUN_CONFIG_TBL` was located in
    `snowflake_multisource/`; column names, `IS_RUN_ENABLED` as
    VARCHAR `'Y'`/`'N'`, and `STEP_NO` as NUMBER are taken from the
    task spec. Verify against the real table before first use; if the
    flag is BOOLEAN or the consumed column differs, the GATHER needs
    adjustment.
11. `CURRENT_SCHEMA()` ASSUMPTION. The existence check requires the
    caller to run with `ECI_ETL_WRK` as current schema — the same
    assumption the original's unqualified table names already make.
    Input names are upper-cased before comparison because Snowflake
    stores unquoted identifiers uppercase.
12. NOT COMPILE-TESTED (no live Snowflake here). Verify before first
    use: the scalar-call form `l_rows := (CALL proc(...));`, the
    multi-column `SELECT ... INTO`, the nested BEGIN/EXCEPTION GATHER
    block, `EXECUTE IMMEDIATE :l_sql` with a variable, and
    `l_rows := SQLROWCOUNT` capture in publish procs.
