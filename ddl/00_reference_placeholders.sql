-- ============================================================================
-- 00_reference_placeholders.sql — MINIMAL placeholder shapes for the 7 reference
-- objects read by the common lookup helpers (00_framework/common/02_*.sql).
--
-- PLACEHOLDERS, NOT REAL DEFINITIONS. Every column below is derived from the
-- helper function's own SELECT list (and, for helper44, its WHERE clause).
-- Nothing here is invented from outside the tree: if a column is not read by
-- any helper, it is not listed, and the real table will have more columns.
-- These tables are EMPTY. Install them so the lookup functions COMPILE; replace
-- them with the real Oracle definitions (extracted from the source system)
-- before any real run, or every lookup join will return no rows and the ETL
-- will silently produce NULL enrichments and missing exception descriptions.
--
-- Install order: this file FIRST (before 00_framework/common/02_*.sql), and
-- the RDM schema must already exist (DBA pre-action — see below).
-- V_LOOKUP_CODE_VALUE is created here as a TABLE, following the earlier
-- mirrors' pattern; in Oracle it is a VIEW, so replacing it later needs
-- DROP TABLE then CREATE VIEW.
-- ============================================================================

-- helper40 (EXCEPTION_CODE, EXCEPTION_DESC, EXCEPTION_TYPE).
-- Caller: every EXC publish branch joins it for the description/type of a code.
-- If missing: helper40 fails to compile; every EXC branch fails with it.
-- If empty: EXCEPTION_DESC comes back NULL (the catalogue-miss marker in the
-- later v3 line does NOT exist here — this tree predates it).
CREATE TABLE EXC_LOOKUP_CODE_VALUE (
    EXCEPTION_CODE VARCHAR2(4000),
    EXCEPTION_DESC VARCHAR2(4000),
    EXCEPTION_TYPE VARCHAR2(4000)
);

-- helpers 41 (CODE_TYPE, SRC_SYS, SRC_CODE_VALUE, MSTR_CODE_VALUE) and
-- 42 (SRC_SYS, SRC_CODE_VALUE, MSTR_CODE_VALUE).
-- Callers: all enrich/lookup joins (phone type, gender, ethnicity, language,
-- and every other code translation). If missing: helpers 41/42 fail to compile.
-- If empty: every translated code comes back NULL.
CREATE TABLE V_LOOKUP_CODE_VALUE (
    CODE_TYPE      VARCHAR2(4000),
    SRC_SYS        VARCHAR2(4000),
    SRC_CODE_VALUE VARCHAR2(4000),
    MSTR_CODE_VALUE VARCHAR2(4000)
);

-- helper43 (NAME, EDIT_LIMITATION -> IS_FIRST_JUNK / IS_LAST_JUNK).
-- Caller: name-junk checks. If missing: helper43 fails to compile.
-- If empty: no name is ever classified junk.
CREATE TABLE REF_JUNK_NAME_LIST (
    NAME            VARCHAR2(4000),
    EDIT_LIMITATION VARCHAR2(4000)
);

-- helper44 (NPA_ID, SERVICE + WHERE filter columns).
-- Caller: phone standardization (area-code -> service lookup).
-- DBA PRE-ACTION: schema RDM must exist before this statement runs; if it
-- does not, this statement fails with ORA-01918 and the install stops.
-- If missing: helper44 fails to compile. If empty: no area code resolves.
CREATE TABLE RDM.REF_PHN_AREA_CD (
    NPA_ID        VARCHAR2(4000),
    SERVICE       VARCHAR2(4000),
    IN_SERVICE    VARCHAR2(4000),
    IN_SERVICE_DT DATE,
    COUNTRY       VARCHAR2(4000)
);

-- helper45 (CODE_TYPE, SRC_SYS, MSTR_REF_CODE, MSTR_REF_LABEL).
-- Callers: PHN_USG_TP and ALT_ID_TP lookups. If missing: helper45 fails.
-- If empty: phone-usage and alt-id-type labels come back NULL.
CREATE TABLE LOOKUP_CODE_VALUE (
    CODE_TYPE     VARCHAR2(4000),
    SRC_SYS       VARCHAR2(4000),
    MSTR_REF_CODE VARCHAR2(4000),
    MSTR_REF_LABEL VARCHAR2(4000)
);

-- helper46 (MATCH_CODE, DESCRIPTION).
-- Caller: AddressDoctor match-code text. If missing: helper46 fails.
-- If empty: match-code descriptions come back NULL.
CREATE TABLE REF_MATCHCODE_DESC (
    MATCH_CODE  VARCHAR2(4000),
    DESCRIPTION VARCHAR2(4000)
);

-- helper47 (DST TIMESTAMP).
-- Caller: daylight-saving correction (timeline). If missing: helper47 fails.
-- If empty: DST corrections never match.
CREATE TABLE REF_DYLGHT_SVNGS_TM (
    DST TIMESTAMP
);
