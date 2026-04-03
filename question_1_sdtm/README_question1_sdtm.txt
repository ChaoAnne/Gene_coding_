Question 1 - SDTM DS Domain

Script: 01_create_ds_domain.R
Output: 01_sdtm_DS.Rdata, 01_sdtm_log.txt

========================================
Purpose
========================================

Creates the Disposition (DS) SDTM domain following the CDISC SDTM Implementation
Guide. Raw CRF data is sourced from the pharmaverseraw package. The output dataset
is saved as an R data file for downstream ADaM consumption.

========================================
Input Data
========================================

pharmaverseraw :: ds_raw
    Raw disposition CRF data

pharmaverseraw :: ec_raw
    Exposure CRF data - used to derive RFSTDTC

GitHub URL :: sdtm_ct.csv
    CDISC controlled terminology (codelist C66727)
    Loaded directly from:
    https://raw.githubusercontent.com/pharmaverse/examples/refs/heads/main/metadata/sdtm_ct.csv
    Note: requires internet access. In locked-down clinical environments,
    download this file locally before running the script.

========================================
Output Variables
========================================

STUDYID   Study Identifier
          Sourced directly from raw STUDY field.

DOMAIN    Domain Abbreviation
          Hardcoded as "DS".

USUBJID   Unique Subject Identifier
          Concatenation of STUDY and PATNUM separated by a hyphen.

DSSEQ     Sequence Number
          Row number within USUBJID, assigned after sorting by DSSTDTC
          then DSDTC. Records with missing dates sort last by default.

DSTERM    Reported Term for the Disposition Event
          Verbatim term uppercased. If OTHERSP is populated, OTHERSP is
          used in place of IT.DSTERM.

DSDECOD   Standardized Disposition Term
          Mapped via CT codelist C66727 using a left join on collected_value.
          Coalesce order: term_value -> term_preferred_term -> raw value.
          Falls back to the uppercased raw value if no CT match is found.

DSCAT     Category for Disposition Event
          OTHER EVENT        : OTHERSP is populated
          PROTOCOL MILESTONE : IT.DSDECOD equals "RANDOMIZED"
          DISPOSITION EVENT  : all other records

VISITNUM  Visit Number
          Derived from INSTANCE text patterns (no formal visit mapping
          specification was provided):
            Screening*       -> 0
            Baseline         -> 1
            Week N           -> N (numeric extracted from string)
            Unscheduled N    -> N (decimal values preserved)
            Retrieval        -> 100 (assigned last)
            All others       -> 10 (e.g. Ambul Ecg Removal, procedure-driven)

VISIT     Visit Name
          Trimmed INSTANCE value.

DSDTC     Date/Time of Collection
          ISO 8601 format. Combined as YYYY-MM-DDThh:mm when both DSDTCOL
          and DSTMCOL are present; date only (YYYY-MM-DD) when only DSDTCOL
          is present. Raw date format expected: MM-DD-YYYY.

DSSTDTC   Start Date/Time of Disposition Event
          ISO 8601 date format (YYYY-MM-DD) from IT.DSSTDAT.
          Raw date format expected: MM-DD-YYYY.

DSSTDY    Study Day of Start of Disposition Event
          Calculated as (DSSTDTC - RFSTDTC) + 1 for on/post reference date,
          or (DSSTDTC - RFSTDTC) for pre-reference date. No day 0 per CDISC
          convention. Set to NA if either DSSTDTC or RFSTDTC is missing.

========================================
Key Derivation Decisions
========================================

DSCAT assignment:
    Records where OTHERSP is populated are categorised as OTHER EVENT.
    Records where IT.DSDECOD equals "RANDOMIZED" are categorised as
    PROTOCOL MILESTONE. All remaining records are DISPOSITION EVENT.

VISITNUM:
    Derived from INSTANCE text patterns as no formal visit mapping
    specification was provided. Ambul Ecg Removal is treated as a
    procedure-driven event (not a scheduled visit) and assigned VISITNUM 10.
    Unscheduled visits retain decimal VISITNUM values to preserve their
    temporal relationship with scheduled visits. Retrieval is assigned 100
    to ensure it always sorts last.

RFSTDTC:
    Derived from the EC dataset as the minimum exposure start date per
    subject (IT.ECSTDAT, raw format DD-Mon-YYYY). Subjects present in DS
    but absent from EC will have DSSTDY set to NA with no warning raised
    by this script.

Date format:
    DS raw dates (IT.DSSTDAT, DSDTCOL) are parsed with format MM-DD-YYYY.
    EC raw dates (IT.ECSTDAT) are parsed with format DD-Mon-YYYY.
    Verify both formats against the actual raw data before running.


========================================
Logging
========================================

The script opens a sink to 01_sdtm_log.txt at startup and closes it at the
end. The log captures:
  - Run start and end timestamps
  - Number of lines in the script file (if it exists on disk)
  - Full R session info
  - Number of output lines written to the log

Note: if the script errors before reaching sink(), the log file may be
incomplete or empty. To clear any stale sink connections before re-running:

    while (sink.number() > 0) sink()

========================================
Dependencies
========================================

library(dplyr)
library(stringr)
library(pharmaverseraw)
library(sdtm.oak)
library(readr)
library(labelled)
