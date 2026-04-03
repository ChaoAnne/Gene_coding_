Question 2 - ADaM ADSL

Script: 02_create_adsl.R
Output: 02_adam_adsl.Rdata, 02_adsl_log.txt

========================================
Purpose
========================================

Creates the Subject-Level Analysis Dataset (ADSL) following the CDISC ADaM
Implementation Guide, using the admiral package for key derivations. The output
dataset serves as the primary subject-level reference and denominator source for
all downstream TLG outputs.

========================================
Input Data
========================================

pharmaversesdtm :: dm
    Demographics SDTM domain - primary subject spine

pharmaversesdtm :: ex
    Exposure SDTM domain - used to derive treatment start and end datetimes

pharmaversesdtm :: vs
    Vital signs SDTM domain - used to derive last available assessment date

pharmaversesdtm :: ae
    Adverse events SDTM domain - used to derive last available assessment date

pharmaversesdtm :: ds
    Disposition SDTM domain - used to derive last available assessment date

========================================
Output Variables
========================================

USUBJID   Unique Subject Identifier
          Carried through from DM.

AGE       Age
          Converted to numeric from DM.

AGEGR9    Pooled Age Group
          <18 / 18-50 / >50
          Note: suffix "9" is study-specific naming convention.

AGEGR9N   Pooled Age Group (N)
          1 / 2 / 3
          Note: suffix "9" is study-specific naming convention.

ARM       Description of Planned Arm
          Carried through from DM.

TRTSDTM   Datetime of First Exposure to Treatment
          Derived using admiral::derive_vars_dtm() on EXSTDTC.
          Only records with a complete date component (YYYY-MM-DD) are used.
          Time imputed to start of hour (time_imputation = "first") when
          time is partially or fully missing.

TRTSTMF   Time Imputation Flag for TRTSDTM
          HMS : no time component collected
          MS  : hour only collected (e.g. 2014-01-02T08)
          NA  : hour and minute present, or full datetime present

TRTEDTM   Datetime of Last Exposure to Treatment
          Derived using admiral::derive_vars_dtm() on EXENDTC.
          Only records with a complete date component (YYYY-MM-DD) are used.
          Time imputed to end of hour (time_imputation = "last") when
          time is partially or fully missing.

ITTFL     Intent-To-Treat Population Flag
          Y if ARM is non-missing and non-empty, else N.
          Confirm this definition against the SAP before submission.

LSTAVDT   Date of Last Available Assessment
          Maximum date across four sources: last VS date with a valid result,
          last AE onset date, last DS date, and TRTEDTM (date part only).
          Derived using pmax() with na.rm = TRUE.

========================================
Key Derivation Decisions
========================================

Valid dose records:
    Exposure records with EXDOSE > 0 are included. Records with EXDOSE = 0
    are included only if EXTRT contains "PLACEBO" (case-insensitive), correctly
    handling placebo arms while excluding zero-dose data entry errors.

TRTSDTM / TRTEDTM:
    Derived using admiral::derive_vars_dtm() with highest_imputation = "h".
    The first valid EXSTDTC (sorted by TRTSDTM then EXSEQ) is used for
    TRTSDTM. The last valid EXENDTC (sorted by TRTEDTM then EXSEQ) is used
    for TRTEDTM.

TRTSTMF:
    Derived by inspecting the EXSTDTC string pattern after datetime derivation.
    Flag is set to HMS when no time component is present, MS when only the hour
    is present, and NA when hour and minute or full datetime are present.

AGEGR9 / AGEGR9N:
    Study-specific age grouping variables. 

ITTFL:
    Defined as ARM non-missing and non-empty. This is a study-specific
    assumption - confirm against the SAP, as some studies define ITT based
    on randomisation flag or ARMCD.

LSTAVDT sources:
    VS  : last date where VSSTRESN or VSSTRESC is non-missing, and VSDTC
          has a complete date component
    AE  : last date where AESTDTC has a complete date component
    DS  : last date where DSSTDTC has a complete date component
    TRT : date part of TRTEDTM
    Intermediate columns (LST_VS, LST_AE, LST_DS, LST_TRT) are dropped
    from the final dataset.

========================================
QC Checks
========================================

Two QC checks are run after treatment datetime derivation and will halt
the script with an error if they fail:

    TRTSTMF check : expects 0 records where TRTSDTM is non-missing and
                    TRTSTMF is not "HMS". Prints flagged records if found.

    Date order check : expects 0 records where TRTEDTM is earlier than
                       TRTSDTM. Prints flagged records if found.

========================================
Logging
========================================

The script opens a sink to 02_adsl_log.txt at startup and closes it at the
end. The log captures:
  - Run start and end timestamps
  - Number of lines in the script file (if it exists on disk)
  - QC check results and row counts
  - Full R session info

Note: if the script errors before reaching sink(), the log file may be
incomplete or empty. To clear any stale sink connections before re-running:

    while (sink.number() > 0) sink()

========================================
Dependencies
========================================

library(admiral)
library(dplyr)
library(pharmaversesdtm)
library(lubridate)
library(stringr)
