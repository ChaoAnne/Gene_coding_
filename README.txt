SDTM / ADaM / TLG Coding Assessment
=====================================
Author   : Chao Ma
Date     : April 2026
Language : R

========================================
Overview
========================================

This project contains four R scripts covering a full clinical programming
pipeline from raw CRF data through to SDTM domain creation, ADaM dataset
derivation, and TLG output production. The scripts are organised across
three question folders.

========================================
Repository Structure
========================================

project_root/
|
|-- README.txt                              This file
|
|-- question_1_sdtm/
|   |-- README.txt                          SDTM-specific documentation
|   |-- 01_create_ds_domain.R
|   |-- 01_sdtm_DS.Rdata
|   |-- 01_sdtm_log.txt
|
|-- question_2_adam/
|   |-- README.txt                          ADaM-specific documentation
|   |-- 02_create_adsl.R
|   |-- 02_adam_adsl.Rdata
|   `-- 02_adsl_log.txt
|
`-- question_3_TLG/
    |-- README.txt                          TLG-specific documentation
    |-- 01_create_ae_summary_table.R
    |-- 02_create_visualizations.R
    |-- 01_tbl_log.txt
    |-- 02_fig_log.txt
    |-- ae_summary_table.pdf
    |-- 02_fig1.png
    `-- 02_fig2.png

========================================
Pipeline Summary
========================================

Step  Folder              Script                          Output
----  ------              ------                          ------
1     question_1_sdtm     01_create_ds_domain.R           01_sdtm_DS.Rdata
2     question_2_adam     02_create_adsl.R                02_adam_adsl.Rdata
3     question_3_TLG      01_create_ae_summary_table.R    ae_summary_table.pdf
4     question_3_TLG      02_create_visualizations.R      02_fig1.png
                                                          02_fig2.png

Scripts 3 and 4 are independent of each other but both depend on the ADaM
datasets from pharmaverseadam. Script 2 output (02_adam_adsl.Rdata) is not
directly consumed by Scripts 3 or 4 in this assessment as TLG scripts source
data from pharmaverseadam directly.

========================================
Script Descriptions
========================================

Script 1 - SDTM DS Domain (01_create_ds_domain.R)
--------------------------------------------------
Creates the Disposition (DS) SDTM domain following the CDISC SDTM
Implementation Guide. Raw CRF data is sourced from pharmaverseraw.
Key derivations include DSTERM, DSDECOD (mapped via CT codelist C66727),
DSCAT, VISITNUM, DSDTC, DSSTDTC, and DSSTDY. Reference start date
(RFSTDTC) is derived from the EC dataset as the earliest exposure date
per subject. Variable labels are applied to all output variables.

Script 2 - ADaM ADSL (02_create_adsl.R)
----------------------------------------
Creates the Subject-Level Analysis Dataset (ADSL) using the admiral
package. Key derivations include age groupings (AGEGR9/AGEGR9N),
first and last treatment datetimes (TRTSDTM, TRTEDTM) with time
imputation flag (TRTSTMF), population flag (ITTFL), and last available
assessment date (LSTAVDT) taken as the maximum across VS, AE, DS, and
treatment end date. Two QC checks are run on treatment dates and will
halt the script if unexpected records are found.

Script 3 - AE Summary Table (01_create_ae_summary_table.R)
-----------------------------------------------------------
Produces a treatment-emergent adverse event (TEAE) summary table using
gtsummary::tbl_hierarchical(). adae is filtered to TRTEMFL == "Y" before
building the table. Rows are organised by AESOC and AETERM, stratified
by ACTARM. Percentages are calculated against the full adsl as denominator,
consistent with FDA Table 10 convention. Output saved as PDF.

Script 4 - Visualizations (02_create_visualizations.R)
-------------------------------------------------------
Produces two clinical figures saved as high-resolution PNG (300 dpi).

Figure 1 (02_fig1.png): Stacked bar chart of TEAE record counts by
severity (AESEV) within each treatment arm (ACTARM), filtered to
TRTEMFL == "Y".

Figure 2 (02_fig2.png): Horizontal dot plot of the top 10 most frequent
adverse event terms (AETERM) by subject count, with 95% Clopper-Pearson
exact confidence intervals. Denominator is distinct subjects in adae
with a non-missing AETERM (no TRTEMFL filter applied).

========================================
How to Run
========================================

Run scripts in the following order from the project root:

    source("question_1_sdtm/01_create_ds_domain.R")
    source("question_2_adam/02_create_adsl.R")
    source("question_3_TLG/01_create_ae_summary_table.R")
    source("question_3_TLG/02_create_visualizations.R")

If a script errors mid-run and the log file is not generated, clear any
stale sink connections before re-running:

    while (sink.number() > 0) sink()

========================================
Dependencies
========================================

CRAN packages:

    install.packages(c(
      "dplyr", "stringr", "lubridate", "labelled", "readr",
      "admiral", "gtsummary", "flextable", "ggplot2", "binom", "scales"
    ))

Pharmaverse packages (GitHub):

    remotes::install_github("pharmaverse/pharmaverseraw")
    remotes::install_github("pharmaverse/pharmaversesdtm")
    remotes::install_github("pharmaverse/pharmaverseadam")
    remotes::install_github("pharmaverse/sdtm.oak")

Package usage by script:

    Script 1 : dplyr, stringr, pharmaverseraw, sdtm.oak, readr, labelled
    Script 2 : admiral, dplyr, pharmaversesdtm, lubridate, stringr
    Script 3 : pharmaverseadam, dplyr, gtsummary, flextable
    Script 4 : dplyr, ggplot2, pharmaverseadam, binom, scales

========================================
Notes
========================================

Controlled terminology (Script 1):
    sdtm_ct is loaded directly from GitHub and requires internet access.
    In locked-down clinical environments, download the file locally to
    question_1_sdtm/ before running.

Logging:
    Each script writes a timestamped log file to its output directory
    capturing run start/end times, script line count, session info, and
    QC results where applicable.

Known issues:
    See each question's README.txt for script-specific known issues and
    assumptions that should be confirmed against the SAP before submission.
