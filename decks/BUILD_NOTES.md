# Per-Source MDM Ingestion Decks — Build Notes

Built 2026-11-03 from the model deck
`~/workspace/user/files/MDM_Data_Ingestion_Overview_ECI__2.pptx`
(17 slides, 16:9 13.33×7.5, Georgia, title pattern
"<Source full name> - <CODE>" + "Data Transformation & Ingestion").

## How the model was matched

- Each new deck was built by loading the model file fresh, deleting its
  slides, and adding slides from the model's own layouts, so masters,
  theme, fonts, and the blue sidebar with the Texas HHS logo carry over
  unchanged. The logo is the model's single picture; no stock images or
  diagrams were added.
- Title slide: 40pt Georgia centered title + "Data Transformation &
  Ingestion" subtitle, as in the model.
- Content slides: title placeholder holds the section name
  ("Landing (Pre MDM)" / "Staging (Pre-MDM)" / "Staging (MDM)") exactly
  as the model does — the model itself titles every mapping slide
  "Staging (MDM)". The mapping name is the bold lead-in of the body,
  as in the model. Slide lists below therefore name each slide by its
  lead-in.
- Body: Georgia 12pt, dark slate #0F172A, bold lead-in labels,
  pipeline chains with ➔ arrows, tight slide text (no walls of text).
- Closing slide: "Closing" + a one-paragraph flow recap.
- Builder: `/tmp/build_decks.py` (ephemeral), python-pptx venv
  `/tmp/pptxvenv`. Source trees were read only; nothing was modified.

## Verification performed

- All 5 files reopen in python-pptx; slide counts below are actuals.
  LibreOffice headless PDF render page counts match slide counts
  exactly (13 / 13 / 21 / 10 / 12), and 5 dense slides were read back
  as images with no overflow: TRS scope, TRS Address 2, CRE merge
  flag, FSS Party rules, TRS title.
- No deck contains a slide for a mapping its source does not have:
  TTF has no Address, Relationship, DQM, or EADDR mapping slides
  (its Phone slide is phone-only); WIC has no Relationship slide;
  CRE has no Validation, DQM, or valexc slides as separate mappings;
  TRS has no Validation mapping slide (validation lives in Party).
  Absent mappings are named only on scope/closing slides as explicit
  scope statements, never as content.
- The words "Snowflake" / "snowflake" appear nowhere. The area-code
  lookup is always the Oracle reference table RDM.REF_PHN_AREA_CD.
- Every C_S_* target table carries its source infix (C_S_WIC_*,
  C_S_TTF_*, C_S_FSS_*, C_S_CRE_*, C_S_TRS_*), except C_S_LU_TOA in
  the TRS deck, which has no source infix by design: it is the shared
  TOA lookup staging table, not a member load. It was NOT "fixed" to
  C_S_TRS_LU_TOA.

## Sources, in priority order

1. `~/workspace/v1_oracle_mirror/wf_<SRC>_Stage_Load/*.sql` — faithful
   Oracle translations of the IDQ mappings; each file's header comment
   gives business flow, mapplet-to-helper mapping, sources, targets.
   All mapping-slide claims come from these headers.
2. `~/workspace/snowflake_all_drivers/<SRC>/*/*_MANIFEST.md` — consulted
   for workflow order and business-flow summaries.
3. TRS only: `~/workspace/user/files/wf_TRS_Stage_Load_1_Ongoing.xml`
   and `wf_TRS_Stage_Load_TOA.xml` — real staging/delta detail.
4. CRE only: `~/workspace/your_files/CRE_MEMBER_MERGE.md` + the CRE proc
   header — CASEMOV/CASEDEL merge semantics, flag N/Y/NULL.
5. ECI critique facts already established (not re-derived): AddressDoctor
   100 = valid / 40 = exception queue; gate = type ≠ 002 AND mailability
   ≤ '3' → 40, type = 002 AND mailability < '3' AND match starts I/N
   → 40, type NULL → 40; gender M→1 / F→2 first character, B/U→NULL;
   race indicator count 1 → 001 White / 002 Black / 003 Native American
   / 004 Asian / 005 Pacific Islander, exactly 2 → 006, 3+ → 007,
   0 → NULL + Invalid_Race; county FIPS Texas kept / other state 996 /
   unknown 999.

## WIC — MDM_Data_Ingestion_Overview_WIC.pptx — 12 slides

1. Title: "WIC" / "Data Transformation & Ingestion"
2. Landing (Pre MDM) — pattern level (see "Deliberately generic").
   Sources read: V_WIC_ETL_SRC, STG_WIC_PTY_INACTIVE_STS/LOG — named
   in `wf_WIC_Stage_Load/sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation.sql`.
3. Staging (Pre-MDM) — two phases + governing rule (exception never
   rejects a party in Party; bad address/phone logged not loaded).
4. Staging (MDM) scope — 6 targets + EXC + DQM + inactive list;
   no Relationship mapping, no SSN alt id.
5. Party Validation — `sp_snow_main_m_Tgt_C_S_WIC_Pty_Validation.sql`:
   blank std first/last → EXC + LOG (Deactivation) + STS new row H/D/P
   from C_B_PTY_XREF when no status yet; Reactivation → LOG + purge.
6. Party & Role — `sp_snow_main_m_Tgt_C_S_WIC_Pty.sql`: V_WIC_ETL_SRC
   → C_S_WIC_PTY + C_S_WIC_PTY_RLE; inactive filter; gender/ethnicity/
   race exceptions only for SOURCE_TABLE = CLIENT; birth/language
   every row; VERSION_SEQ 1; PERIOD_START_DATE = DATEKEY.
7. Party & Role (Continued) — same file: name cleanse; gender M→1/F→2;
   future DOB invalid → NULL; language/ethnicity lookup; race
   indicator-count rule 001–007; birth weight grams = ounces × 28.35
   (deliberate 3/14/2025 change, ounces only).
8. Party Address — `sp_snow_main_m_Tgt_C_S_WIC_Pty_Addr.sql`: constant
   type 002, state TX, country US, zip only; 100 → target, 40 → EXC
   only; DQM every active address; PTY_SRC_KEY LPAD 10, no F suffix;
   PERIOD_START_DATE / EFF_STRT_DT = DATE_ADDRESS_VALID_FROM.
9. Party Phone & Email — `sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr.sql`:
   one phone + possibly one email per row; phone rule usage 001
   'Telephone', 'Primary' on EVERY active row (no null-phone filter);
   area code via RDM.REF_PHN_AREA_CD (helpers 23/24 + 44).
10. Party Phone & Email (Continued) — same file: phone thresholds;
    email null filter → validation helper22 → EADDR / EXC; email key
    uses email as read (no trim), unlike ECI.
11. Party Role Alt Id — `sp_snow_main_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id.sql`:
    one per active party; WIC id LPAD 12; type 020 CLIENT / 021
    otherwise; no validation; HUB_STATE_IND left to column default.
12. Closing — flow recap.

## TTF — MDM_Data_Ingestion_Overview_TTF.pptx — 10 slides

1. Title: "TTF" / "Data Transformation & Ingestion"
2. Landing (Pre MDM) — pattern level. Sources read: V_TTF_ETL_SRC,
   STG_TTF_PTY_INACTIVE_STS/LOG — named in
   `wf_TTF_Stage_Load/sp_snow_main_m_Tgt_C_S_TTF_Pty_Validation.sql`.
3. Staging (Pre-MDM) — two phases + explicit scope fact: no Address,
   no Relationship, no DQM, phone-only (no email target).
4. Staging (MDM) scope — 4 targets + EXC + inactive list; language
   and suffix NOT loaded (ports unfed, arrive NULL).
5. Party Validation — `sp_snow_main_m_Tgt_C_S_TTF_Pty_Validation.sql`:
   key LPAD(CLIENTS_ID, 10, 0); blank or 'DECLINED' / 'DO_NOT_DISCLOSE'
   (any case) → EXC; Deactivation on blank or 'DECLINED' (NOT
   'DO_NOT_DISCLOSE') or CLIENT_EXISTS_FLAG = 'N'; Reactivation on
   status + names present not 'DECLINED' + flag 'Y'; DO_NOT_DISCLOSE
   is logged but does NOT deactivate.
6. Party & Role — `sp_snow_main_m_Tgt_C_S_TTF_Pty.sql`: V_TTF_ETL_SRC
   → C_S_TTF_PTY + C_S_TTF_PTY_RLE; inactive filter; birth/gender/
   ethnicity/race exceptions every row (no source-table condition);
   Invalid_Language / Invalid_Suffix groups never write (unfed ports);
   VERSION_SEQ 1; party PERIOD_START_DATE = run start (changes every
   run), role = SUBMITDATE.
7. Party & Role (Continued) — same file: name cleanse; gender two
   steps (SEXID 33→F, 34→M, else U, then helper17); ethnicity '55'
   when RACEETHNICITYID = '55'; race BY CODE on RACEETHNICITYID
   (NOT the indicator-count rule); future DOB → NULL; PRFRD_LANG_CD
   and SFX_NM unfed → NULL.
8. Party Role Alt Id — `sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id.sql`:
   party key itself, type '024'; no validation; VERSION_SEQ 1;
   PERIOD_START_DATE = run start.
9. Party Phone (phone-only) — `sp_snow_main_m_Tgt_C_S_TTF_Pty_Rle_Phn.sql`:
   → C_S_TTF_PTY_RLE_PHN only; null-phone filter; usage 001
   'Telephone', 'Primary'; Good (no code) → PHN, Bad → EXC
   ('Rejected Record'); extension branch never (port unfed);
   area code via RDM.REF_PHN_AREA_CD; VERSION_SEQ '1';
   PERIOD_START_DATE = SUBMITDATE.
10. Closing — flow recap, restating the absences as design.

## FSS — MDM_Data_Ingestion_Overview_FSS.pptx — 13 slides

1. Title: "FSS" / "Data Transformation & Ingestion"
2. Landing (Pre MDM) — pattern level. Sources read: V_FSS_ETL_SRC,
   V_FSS_ETL_SRC_RELATIONS, STG_FSS_PTY_INACTIVE_STS/LOG — named in
   `wf_FSS_Stage_Load/sp_snow_main_m_Tgt_C_S_FSS_Pty_Validation.sql`
   and `..._Pty_Rle_Rel.sql`.
3. Staging (Pre-MDM) — two phases + governing rule (Party exception
   never rejects; bad address/phone logged not loaded).
4. Staging (MDM) scope — 7 targets + EXC + DQM + inactive list;
   FSS is the one source in this set with a suffix rule.
5. Party Validation — `sp_snow_main_m_Tgt_C_S_FSS_Pty_Validation.sql`:
   checks last-active-registration rows plus all-registrations-inactive
   rows; blank name → EXC; Deactivation on blank, capture action 'D',
   or LAST_INACTV_CLIENT_YN = 'Y', STS row only when no status yet;
   Reactivation QUIRK stated neutrally as open confirmation (status
   row with DEACTIVATION_STS = 'Reactivation' linked to the STATUS
   table, not the log; later mappings skip any key with a non-null
   status, so a reactivated client stays excluded).
6. Party & Role — `sp_snow_main_m_Tgt_C_S_FSS_Pty.sql`: last active
   registration → C_S_FSS_PTY + C_S_FSS_PTY_RLE; gender/ethnicity/
   race exceptions only for SOURCE_TYPE = 'CLIENT'; birth/language/
   suffix every row; VERSION_SEQ 1; PERIOD_START_DATE = DT_LAST_UPDATE.
7. Party & Role (Continued) — same file: name cleanse with source
   suffix; gender M→1/F→2 routed on looked-up description; source DOB
   loaded even when future (language exception row writes the mapplet
   birth date, NULL for a future date); ethnicity (CD_HISPANIC) /
   language exceptions write looked-up code, routed on it
   (unconfigured = no row); race indicator-count rule 001–007;
   suffix rule_Suffix_Std without code-type filter.
8. Party Address — `sp_snow_main_m_Tgt_C_S_FSS_Pty_Addr.sql`: capture
   action not 'D'; constant type 002, zip without extension;
   100 → ADDR, 40 → EXC only; DQM every active address; family F
   suffix only for SOURCE_TYPE FSS_FAMILY, which never occurs;
   PERIOD_START_DATE = DT_CREATED, EFF_STRT_DT = DT_LAST_UPDATE.
9. Party Role Alt Id — `sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Alt_Id.sql`:
   client id LPAD 10; type 022 CLIENT / 023 otherwise; no validation;
   last-active-registration filter; VERSION_SEQ 1;
   PERIOD_START_DATE = DT_CREATED.
10. Party Phone & Email — `sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr.sql`:
    each registration row (capture action not 'D') can give one email
    + one phone; email null filter → helper22 → EADDR / EXC
    (unconfigured code is loaded); phone null filter → Phone_Std
    001 'Telephone', 'Primary' + Extension_Std → PHN / EXC;
    area code via RDM.REF_PHN_AREA_CD; VERSION_SEQ '1';
    PERIOD_START_DATE = DT_LAST_UPDATE.
11. Party Phone & Email (Continued) — same file: good phone + bad
    extension = loaded (extension blanked) AND logged 'Bad Value';
    bad phone → 'Rejected Record'; email rules; EXC_LOOKUP_CODE_VALUE
    as the single exception catalogue.
12. Party Role Relationships — `sp_snow_main_m_Tgt_C_S_FSS_Pty_Rle_Rel.sql`:
    V_FSS_ETL_SRC_RELATIONS, one row per direction (no multiplication);
    double inactivity check (party key AND related key); code
    (CAREGIVER when missing) + related gender decoded via
    LOOKUP_CODE_VALUE ('To Child': RELN_CD_GENDER / REL_TP; else
    CD_GENDER / INVERSE_REL); untranslated → EXC 'Invalid_Relationship'
    (attribute 'Relationship|Sex'); VERSION_SEQ 1;
    PERIOD_START_DATE = RELN_DT_CREATED.
13. Closing — flow recap, reactivation quirk flagged.

## CARE — MDM_Data_Ingestion_Overview_CARE.pptx — 13 slides

(CRE = Care. File name uses CARE per the brief; title slide reads
"Care - CRE".)

1. Title: "Care - CRE" / "Data Transformation & Ingestion"
2. Landing (Pre MDM) — pattern level. Sources read:
   STG_CRE_SN_CARE_CLIENTS (snapshot), STG_CRE_D_CARE_CLIENTS (daily
   delta), STG_CRE_D_CARE_CASE_MAINT (SOURCE_ID / TARGET_ID /
   CASEMOV / CASEDEL) — named in
   `wf_CRE_Stage_Load_Ongoing/sp_snow_main_m_Tgt_C_S_CRE_CARE_Clients.sql`.
3. Staging (Pre-MDM) — two phases + governing rule (invalid members
   logged AND dropped; bad address/phone/alt-id logged not loaded;
   member still loads; insert only, never truncated).
4. Staging (MDM) scope — 5 targets + CRE_SRC_MRG + EXC; no birth-date
   rule, no email mapping, no separate Validation mapping, no DQM
   output, no valexc.
5. Input Branches — same CRE proc: regular (I, MAINT_FLAG NULL),
   move/delete sources (B / D, MAINT_FLAG D + maintenance row where
   client is SOURCE_ID, CASEMOV / CASEDEL), move targets (A, snapshot
   + maintenance row where client is TARGET_ID, CASEMOV); one row per
   CARE id, record type descending I, D, B, A; each branch feeds
   party, role, address, phone, three alt ids.
6. Merge Flag — `~/workspace/your_files/CRE_MEMBER_MERGE.md` + CRE proc:
   4 hub checks (XREF source original + target original, each in HMRG
   as SRC and as TGT); all 4 NULL → 'N' (new move → CRE_SRC_MRG row +
   downstream re-keyed to TARGET_ID); any present → 'Y' (not re-sent,
   own CARE_ID kept); grp_deletes → NULL (NOT a merge candidate:
   regular clients + case deletes, despite the name); CRE_SRC_MRG has
   no reader in this estate (consumer is the MDM batch, outside);
   OPEN question stated neutrally: second move of an already-merged
   member gets 'Y' and is never sent — intended via another route or
   genuine gap; do not flip flag logic without the batch owner's answer.
7. Party & Role — same CRE proc: valid_member requires BOTH
   standardized first and last name non-blank; version_seq_num =
   ROW_NUMBER for valid members only; is_member = seq 1; children load
   only where is_member — single-blank-name clients land in NO target;
   B / D end-dating (PERIOD_START_DATE = CARE_LASTUP_DT − 1 day,
   PERIOD_END_DATE = CARE_LASTUP_DT, TIMELINE_ACTION = 2,
   LAST_UPDATE_DATE = run start − 1 hour, role keeps run start);
   I / A rows PERIOD_START_DATE = CARE_LASTUP_DT, rest NULL.
8. Name, Gender, Ethnicity & Race — same CRE proc: helper15 name
   (SUFFIX + junk lookups), helper17 gender, helper18 ETHNICITY/RACE
   lookups; unmapped ethnicity/gender → NULL with no flag; name/phone/
   SSN routed on looked-up code, suffix + Medicaid write computed
   code, address/gender/ethnicity/race write looked-up code or
   nothing when unconfigured. (No language rule — see Deviations.)
9. Party Address — same CRE proc: no doctor score, no DQM output;
   valid = street + city non-null; US also needs state FIPS and the
   mailability condition from the validation router; abroad state 99,
   country ZZ; FIPS defaults 002 / 48 / 996 / 998 / 99; bad address
   logged (NULL code when unconfigured), member still loads.
10. Party Phone — same CRE proc: helpers 23/24 only, number linked;
    NO toll-free check for CRE; phones cut to 10 digits; phone-type
    enrichment needs PHONE_TYPE / CRE / 'Telephone' dictionary row or
    PHN_TP NULLs; bad phone logged, member still loads.
11. Party Role Alt Id — same CRE proc: CARE id, Medicaid id, SSN;
    helper27 Medicaid, helper26 SSN (post-June-2011 rule), helper37
    CARE id; SSN 'U' / 'N' blanked and dropped, never logged; ids lose
    special characters, cut to 10; bad Medicaid/CARE id logged,
    member still loads.
12. Exception Logging — same CRE proc: one row per failed check in
    EXC_STG_BAD_REC_MEMB, never written twice; code rules as on
    slide 8; the log never blocks the member row; flag-aware views
    feed the MDM batch; nothing deleted from staging tables at tail end.
13. Closing — flow recap, restating the no-validation / no-doctor /
    single-blank-name rules.

## TRS — MDM_Data_Ingestion_Overview_TRS.pptx — 21 slides

Workflow order from
`wf_TRS_Stage_Load_1_Ongoing/run_wf_TRS_Stage_Load_1_Ongoing.sql`
(Party → Deactivation → TOA → Rel Mem-To-Mem → Rel Deactivation →
Rel Mem-To-PCP → Phone & Email → Mng_Attr_Sw → Mng_Attr_Auth_Rep →
Name → Alt_Id → Plan → Addr_1 → Addr_2), plus the separate TOA
workflow run after Ongoing.

1. Title: "TIERS - TRS" / "Data Transformation & Ingestion"
2. Landing (Pre MDM) — REAL detail from the Ongoing + TOA XMLs:
   STG_TRS_D_DC_INDV, STG_TRS_D_CV_DC_MCI_INDV, STG_TRS_D_DC_CASES,
   STG_TRS_D_DC_PRIMARY_PAYEE, STG_TRS_D_DC_RELATIONSHIPS,
   STG_TRS_D_DC_RELATIONSHIPS_A, STG_TRS_D_IN_MANAGED_CARE,
   STG_TRS_D_INDV_ADDR, STG_TRS_D_CV_DC_MCI_ALIAS,
   STG_TRS_D_DC_ALIAS, STG_TRS_D_CV_MCI_EDG_INDV_TOA,
   STG_TRS_D_LU_TOA; D = delta, H = history read-only
   (Alt_Id reads STG_TRS_H_DC_INDV for SSA-validated SSNs only).
3. Staging (Pre-MDM) — two phases + governing rules (single-name
   party loaded AND logged; deactivation source-supplied; VERSION_SEQ
   passed through; children join parents at VERSION_SEQ = 1).
4. Staging (MDM) scope — 14 targets + EXC + DQM + valid-member /
   deactivation lists + C_S_LU_TOA; no Validation mapping (validation
   lives inside Party).
5. Party — `sp_snow_main_m_Tgt_C_S_TRS_Pty_OnGoing.sql`: TIERS
   individuals valid today → C_S_TRS_PTY + C_S_TRS_PTY_RLE +
   STG_TRS_VALID_MEMBERS (new keys only); Valid_Party = first OR last
   name present (single-name loaded AND logged); death date after run
   start → Invalid_Death_Date; gender/death/race/ethnicity exceptions
   only when configured; VERSION_SEQ hard-coded 1 (MD5 counter
   commented out); PERIOD_START_DATE = CREATE_DT; key INDV_ID +
   DC_INDV for DC rows, INDV_ID alone for MCI rows.
6. Party Deactivation — `sp_snow_main_m_Tgt_C_S_TRS_Pty_Deactivation_1.sql`:
   source-supplied; valid members inactive/deleted in DC_INDV or
   inactive in MCI_INDV → STG_TRS_DEACTIVED_MEMBERS (database
   spelling), PROCESSED_YN 'N', LOAD_DATE = run start, new keys only;
   later process sends unprocessed keys to MDM; IDQ also deletes the
   rows from STG_TRS_VALID_MEMBERS; no C_S_ target, no exceptions.
7. Party Role TOA — `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_TOA.sql`:
   latest create per individual/EDG/program/MCI seq; keeps only
   version 1 (last record per key); untranslated TOA (LOOKUP_CODE_VALUE
   TOA, 'TRS') → Invalid_TOA; begin > end → date exception; both →
   BOTH rows; key as on slide.
8. Party Role Relationships (Mem-To-Mem) —
   `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem.sql`: both sides
   valid members; type must translate (V_LOOKUP_CODE_VALUE PTY_REL);
   Invalid_Main_Alt_Id / Invalid_Ref_Alt_Id / Invalid_Lookup /
   reversed dates, one row logged once per matched group; real
   versioning: DST correction (helper35 + REF_DYLGHT_SVNGS_TM, end
   +1 hour when start = end or end + 2h is a DST change), end-dated
   rows emitted TWICE (closed + open copy), VERSION_SEQ re-ranked per
   key; HUB_STATE_IND forced to 1 on open VERSION_SEQ 1 row.
9. Relationship Deactivation —
   `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1.sql`:
   STG_TRS_D_DC_RELATIONSHIPS_A, both sides valid members →
   STG_TRS_DEACTIVATED_RELATIONSHIPS (new unprocessed + present in
   C_B_PTY_RLE_REL_XREF); key member | ref member | master type;
   untranslated type → key ending '|' → no xref → dropped;
   PROCESSED_YN left to column default; no valid-list removal target
   exists despite the mapping description mentioning one.
10. Party Role Relationships (Mem-To-PCP) —
    `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP.sql`:
    STG_TRS_D_IN_MANAGED_CARE with a provider; provider number must be
    numeric (non-numeric dropped silently) + known as C21 TPI '006';
    type 'Member PCO' when key holds HCO, else 'Member PCP'; reversed
    dates + missing keys log; same timeline as Mem-To-Mem.
11. Party Phone & Email — `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr.sql`:
    case delta (STG_TRS_D_DC_CASES × case-individual) valid members
    only; phones main 001 / work 002 / other 003 through rule_Phone_Std,
    null filter, LOOKUP_CODE_VALUE PHN_USG_TP; valid → consolidation →
    PHN, failed → EXC 'Bad Value'; work extension combined then dropped
    by a 10-character port; email null filter → helper22 routed on
    looked-up code → EADDR / EXC; area code via RDM.REF_PHN_AREA_CD;
    toll-free check never runs (inputs not linked).
12. Party Phone & Email (Continued) — same file: consolidation (last
    row per key wins); VERSION_SEQ is a real running count of distinct
    versions per key (not forced to 1); stored filters NOT applied
    (INDV_ID 504937068 single-member filter; 100,000-row cap) because
    neither is part of the custom query.
13. Managed-Care Attributes (Sw) — `sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw.sql`:
    runs BEFORE Auth_Rep, both append to C_S_TRS_PTY_MNG_ATTR; five
    attributes (File_Clearance_SW, SSA_Validation_SW, TW_Convert_Ind,
    LTC_Convert_Ind, Source_Table); null/blank dropped; latest
    DC_INDV / MCI row per individual joined to VALID_MEMBERS; key
    party key + attribute type; VERSION_SEQ hard-coded 1 (running
    counter commented out); PERIOD_START_DATE = EFF_BEGIN_DT; end /
    reference / action NULL (unfed).
14. Managed-Care Attributes (Auth_Rep) —
    `sp_snow_main_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing.sql`:
    runs AFTER Sw; Auth_Rep_Flag = 'Y' + verified + sent; codes CS /
    FH / LD / OA + SENT_AUTHREP_SW = 'Y'; six union branches over
    payee / case / EDG delta tables; dedup one row per key
    (INDV_ID + Auth_Rep_Flag); VERSION_SEQ 1;
    PERIOD_START_DATE = EFF_BEGIN_DT of last row,
    PERIOD_END_DATE = MAX(EFF_END_DT).
15. Party Name — `sp_snow_main_m_Tgt_C_S_TRS_Pty_Nm.sql`: alias names
    of valid members (STG_TRS_D_CV_DC_MCI_ALIAS + STG_TRS_D_DC_ALIAS)
    → C_S_TRS_PTY_NM, type '002' (Alias); alias without first AND
    last dropped; trailing numbers removed + helper15 std; key party
    key + 002 + sequence; VERSION_SEQ 1 (rank commented out);
    prefix/suffix NULL (source-system input not linked).
16. Party Role Alt Id — `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id.sql`:
    MCI / DC_INDV / merged keys of valid members, longest latest SSN
    → C_S_TRS_PTY_RLE_ALT_ID; SSN used ONLY when STG_TRS_H_DC_INDV
    has it SSA-validated; invalid SSN blanked + dropped, NEVER logged;
    member id fed as Medicaid id (9 characters; 10-character member
    id fails, not loaded, logged computed code + looked-up description,
    type 'Bad Value'); one row per non-empty id; VERSION_SEQ 1;
    PERIOD_START_DATE / CREATE_DATE / SRC_LAST_UPD_DT = START_DT.
17. Party Role Plan — `sp_snow_main_m_Tgt_C_S_TRS_Pty_Rle_Pln.sql`:
    STG_TRS_D_IN_MANAGED_CARE with a plan, begin before end or open →
    C_S_TRS_PTY_RLE_PLN; plan must translate (V_LOOKUP_CODE_VALUE
    PLAN_CD, 'MAX'); valid → dedup → target; invalid → FIRST invalid
    row per individual → EXC 'Invalid_Plan' (computed code, looked-up
    description); begin >= end dropped by source query; VERSION_SEQ 1;
    PERIOD_START / END = BEGIN / END of last (latest) segment.
18. Party Address 1 — `sp_snow_main_m_Tgt_C_S_TRS_Addr_1.sql`:
    STG_TRS_D_INDV_ADDR distinct on address parts, validated ONCE
    (~a tenth of volume); every result (good or bad) →
    STG_TRS_D_UNQ_ADDR (insert only); score computed later in Addr_2;
    line derivation as on slide (direction EA/NO/SO/WE → first letter,
    any case; zip = zip5 + zip4; derived lines kept in SRC_ADDR_LN_*).
19. Party Address 2 — `sp_snow_main_m_Tgt_C_S_TRS_Addr_2.sql`: latest
    create per individual/address type/case/EDG joined to UNQ_ADDR +
    valid members → C_S_TRS_PTY_RLE_ADDR + DQM_ADDRESS (every row) +
    EXC; ADDR_TP lookup (V_LOOKUP_CODE_VALUE ADDR_TP, 'TRS');
    untranslated type scores 40; 100 → ADDR, 40 → EXC 'Invalid_Address'
    (looked-up code, NULL when unconfigured); VERSION_SEQ running
    per role-address key (real timeline); SRC_ROWID = key + VERSION_SEQ;
    PERIOD_REFERENCE_TIME = run start when EFF_END_DT set; EFF_END_DT
    50-year quirk: year difference compared as TEXT against '50', so
    end dates > 50 years away AND 6–10 years away both become NULL.
20. TOA Catalogue — `sp_snow_main_m_Tgt_C_S_TRS_Stg_TOA.sql`:
    separate workflow, daily parent runs it AFTER Ongoing;
    STG_TRS_D_LU_TOA every row incl. history/expired → C_S_LU_TOA;
    TOA master code becomes the key, program NOT part of key;
    MEMBER_PRG via MEMBER_PRG label (NULL when unconfigured); no
    router, no exceptions; code without TOA master label → NULL key →
    row rejected by target constraint, nothing logged; survivor of a
    code listed under several programs/history rows is undefined in
    IDQ (no ORDER BY; procedure keeps latest by UPDATE_DT then
    UNIQUE_TRANS_ID — confirm with business); VERSION_SEQ literal '1'.
21. Closing — flow recap.

## Mappings covered — none missing

Every mapping in each workflow's run script is covered by at least
one slide: WIC 5/5, TTF 4/4, FSS 6/6, CRE 1/1, TRS 15/15 (14 Ongoing
+ 1 TOA). No mapping was left uncovered for lack of sources; all
mapping slides rest on the proc headers listed above.

## Details deliberately left generic (with why)

- WIC / TTF / FSS / CRE landing and staging (Pre-MDM) slides are at
  pattern level: landing layer → staging change detection → delta
  tables the MDM mappings actually read, named from the proc sources.
  No per-source staging-workflow export is on file for these four
  sources, so no session names, connection variables, commit sizes,
  .bad file names, or source-system names are asserted. TRS landing /
  staging slides use real XML detail because its exports are on file.
- The SN prefix on CRE staging tables (STG_CRE_SN_*) is not expanded:
  no source on file defines it. The slides call it "snapshot", which
  is what the table behaves as (the full client list the delta joins
  to), without asserting an expansion.
- CRE address slide headline follows the brief (valid = street + city
  non-null) and also carries the header's US mailability condition and
  state-FIPS requirement, so neither statement stands alone.
- DQM_ADDRESS county/state FIPS rules (Texas kept / other 996 /
  unknown 999) are stated for WIC, FSS, and TRS DQM outputs, where the
  headers cite them. CRE has no DQM output, so no FIPS rule is claimed
  for CRE beyond its own proc defaults (48 / 996 / 998 / 99).
- Email validation rules (local-part / domain / TLD) are stated for
  WIC, FSS, and TRS, where helper22 is cited. TTF and CRE have no email
  mapping, so no email rules are claimed for them.
- The race indicator-count rule (001–007) is stated only for WIC and
  FSS (+ ECI in the model deck). TTF race is by code; CRE race is by
  code lookup; TRS race is by code. No deck generalizes the count rule
  to a source that does not use it.
- The area-code lookup RDM.REF_PHN_AREA_CD is cited for WIC, TTF, FSS,
  and TRS phone mappings, where the headers cite helper44. CRE phone
  slides do NOT claim it (CRE header cites helpers 23/24 only, and no
  toll-free check).

## Deviations from the brief

1. CRE stage list: the brief listed "name/gender/ethnicity/language"
   as a CRE stage. No language rule appears in the CRE proc header
   (validations listed: name, gender, ethnicity/race, phone, Medicaid,
   SSN, CARE id, address). The slide is titled "Name, Gender,
   Ethnicity & Race" and states "No language rule exists in this
   mapping." No CRE language rule was invented.
2. Title names: no full-name expansions for WIC, TTF, or FSS were
   found in any source on file (grep over the v1 mirror report,
   step-driver README/DEPENDENCIES, and manifests returned nothing),
   so those decks are titled with the code only. CRE is titled
   "Care - CRE" (the user's own word "Care" from his 2026-11-03
   message + code). TRS is titled "TIERS - TRS" (TIERS grounded in
   TRS proc headers: "TIERS individuals/members"). Titles are a
   one-line change in the builder if the parent prefers otherwise.
3. Slide counts vs the planned targets: WIC 12 (planned 13), TTF 10
   (planned 11), FSS 13 (planned 14), CRE 13 (as planned), TRS 21
   (as planned). The planned counts double-counted one slide each for
   WIC, TTF, and FSS; the built counts are the actual content (WIC 10
   content slides, TTF 8, FSS 11, CRE 11, TRS 19, each + title +
   closing). No mapping slide was dropped to reach these counts.
4. CRE address: brief headline "valid = street + city non-null" is
   kept as the headline, with the header's US mailability condition
   and FIPS requirement added (see "Deliberately generic" above).
5. Nothing was pushed, zipped, or committed, and no source tree was
   modified, per the subagent brief. The parent verifies and pushes.
