Question 3 - TLG Outputs

Scripts: 01_create_ae_summary_table.R, 02_create_visualizations.R
Outputs: ae_summary_table.pdf, 02_fig1.png, 02_fig2.png
Logs:    01_tbl_log.txt, 02_fig_log.txt

========================================
Purpose
========================================

Produces three TLG outputs using ADaM datasets from the pharmaverseadam
package: one adverse event summary table and two clinical figures. The two
scripts are independent of each other and can be run in either order.

========================================
Input Data
========================================

Script 1 (AE table):
    adae and adsl are accessed directly as package objects from pharmaverseadam.

Script 2 (Visualizations):
    adae <- pharmaverseadam::adae
    adsl <- pharmaverseadam::adsl

========================================
Script 1 - AE Summary Table
========================================

File:   01_create_ae_summary_table.R
Output: ae_summary_table.pdf
Log:    01_tbl_log.txt

Description:
    A treatment-emergent adverse event (TEAE) summary table produced using
    gtsummary::tbl_hierarchical(). adae is first filtered to TRTEMFL == "Y"
    to restrict to treatment-emergent records. The table is then built from
    this filtered dataset and hierarchically organised by System Organ Class
    (AESOC) and adverse event term (AETERM), stratified by actual treatment
    arm (ACTARM). An overall row at the top is labelled "Treatment Emergent
    AEs". The table is rendered and saved as PDF via gt::gtsave().

Step by step:

    Step 1 - Filter to TEAEs:
        adae.teae <- adae %>% filter(TRTEMFL == "Y")
        Restricts to treatment-emergent AE records only.

    Step 2 - Build hierarchical table:
        tbl_hierarchical() is called on adae.teae with:
          by          = ACTARM   (column stratification)
          variables   = c(AESOC, AETERM)   (row hierarchy)
          id          = USUBJID  (subject-level counting)
          denominator = adsl     (full adsl as denominator)
          overall_row = TRUE     (adds a total TEAE row at the top)
          label       = overall row labelled "Treatment Emergent AEs"

    Step 3 - Save as PDF:
        Table converted to gt object and saved via gt::gtsave().

Key decisions:

    TEAE definition:
        Treatment-emergent AEs are defined by TRTEMFL == "Y" in adae,
        which is the standard CDISC flag for treatment-emergent records.

    Denominator:
        The full adsl dataset is passed as the denominator, which is correct
        per the requirement. Percentages are calculated against all subjects
        per treatment arm (ACTARM), including those who did not experience a
        TEAE. This matches the FDA Table 10 convention where the denominator
        is the total number of subjects in each treatment group.

    AETERM at term level:
        The verbatim collected term (AETERM) is used per requirement.

    Stratification variable:
        ACTARM (actual treatment arm) is used for column grouping.

    Output format:
        PDF via gt::gtsave(). 

========================================
Script 2 - Visualizations
========================================

File:   02_create_visualizations.R
Outputs: 02_fig1.png, 02_fig2.png (both 300 dpi, 7 x 5 inches)
Log:    02_fig_log.txt

----------------------------------------
Figure 1 - AE Severity Distribution
----------------------------------------

Output: 02_fig1.png

Description:
    A stacked bar chart showing count of AE records by severity (AESEV)
    within each treatment arm (ACTARM). Filtered to TRTEMFL == "Y" and
    records where both AESEV and ACTARM are non-missing.

Key decisions:

    Unit of count:
        Counts AE records, not unique subjects. A subject with two MILD AEs
        is counted twice.

    Chart type:
        Stacked bars (position = "identity"). This makes it difficult to
        visually compare MODERATE and SEVERE counts across arms as they sit
        on different baselines.

    Colour palette:
        MILD     #F8766D (red)
        MODERATE #00BA38 (green)
        SEVERE   #619CFF (blue)
        Note: red and green are indistinguishable for the most common form
        of colour blindness (deuteranopia).

    Theme:
        theme_gray() with bold title, axis titles, and legend title.

----------------------------------------
Figure 2 - Top 10 Most Frequent AEs
----------------------------------------

Output: 02_fig2.png

Description:
    A horizontal dot plot showing the 10 most frequently occurring adverse
    event terms (AETERM) with 95% Clopper-Pearson exact confidence intervals.
    The x-axis shows percentage of patients affected. Terms are sorted by
    ascending proportion so the most frequent term appears at the top.

Step by step:

    Step 1 - Denominator:
        N is derived as the count of distinct subjects in adae where AETERM
        is non-missing. This represents all patients who had at least one
        AE record with a non-missing term. 

    Step 2 - Numerator:
        Subject-level deduplication is applied using distinct(USUBJID, AETERM)
        before counting, so each subject is counted once per term regardless
        of how many AE records they have for that term. The top 10 terms by
        descending subject count are selected using slice_head(n = 10).

    Step 3 - Proportions and CIs:
        prop  = n / N for each term
        lower and upper 95% Clopper-Pearson exact CIs calculated via
        binom.confint(ae_summary$n, N, methods = "exact").
        Terms are then re-sorted by ascending prop and AETERM is converted
        to a factor in that order so the plot displays highest frequency
        at the top of the y-axis.

    Step 4 - Plot:
        Horizontal dot plot (geom_point) with horizontal error bars
        (geom_errorbar). X-axis formatted as percentages. Subtitle displays
        the N used as denominator and the CI method.
        Theme: theme_gray() with bold title and x-axis label.

Key decisions:

    Term variable:
        AETERM (verbatim collected term) is used per requirement.

    Denominator scope:
        N is derived from all AE patients with a non-missing AETERM.

    CI method:
        Clopper-Pearson exact method is appropriate for small-sample
        clinical data and is correctly applied here.

========================================
Logging
========================================

Each script opens its own sink at startup and closes it at the end.

Script 1 log (01_tbl_log.txt) captures:
  - Run start and end timestamps
  - Number of lines in the script file (if it exists on disk)
  - Full R session info
  - Number of output lines written to the log

Script 2 log (02_fig_log.txt) captures the same items.

Note: if either script errors before reaching sink(), the log file may be
incomplete or empty. To clear any stale sink connections before re-running:

    while (sink.number() > 0) sink()

========================================
Dependencies
========================================

Script 1:
    library(pharmaverseadam)
    library(dplyr)
    library(gtsummary)
    library(flextable)

Script 2:
    library(dplyr)
    library(ggplot2)
    library(pharmaverseadam)
    library(binom)
    library(scales)
