
######################################################
### Setup
#####################################################

base_dir   <- "question_3_TLG"

dir.create(base_dir, showWarnings = FALSE, recursive = TRUE )

log_file <- file.path(base_dir, "01_tbl_log.txt")

code_file <- file.path(base_dir,"01_create_ae_summary_table.R")   
n_code_lines <- if (file.exists(code_file)) length(readLines(code_file)) else NA_integer_

sink(log_file, split = TRUE)

cat("====================================\n")
cat("Run started at:", format(Sys.time()), "\n")
cat("Working/Output directory:", getwd(), "\n")
cat("====================================\n\n")

cat("Code Summary:\n")
cat("Number of lines of code:", n_code_lines, "\n\n")

#######################################################
## Question 3. 
## Chao Ma, Apr 2, 2026
#######################################################
library(pharmaverseadam)
library(dplyr)
library(gtsummary)
library(flextable)


###############################################
# 1 summary table of TEAE 
##############################################
adae_teae <- adae %>%
  filter(TRTEMFL == "Y")

teae_table <- adae_teae %>%
  tbl_hierarchical(
    by = ACTARM,
    variables = c(AESOC, AETERM),
    id = USUBJID,
    denominator = adsl,
    overall_row = TRUE, 
    label = "..ard_hierarchical_overall.." ~ "Treatment Emergent AEs"
  ) 

gt_tbl <- as_gt(teae_table)
gt::gtsave(gt_tbl, file.path(base_dir,"ae_summary_table.pdf"))


cat("\n====================================\n")
cat("Run completed successfully at:", format(Sys.time()), "\n")
cat("====================================\n\n")

cat("Session Info:\n")
print(sessionInfo())
sink()

# Count output lines
n_output_lines <- length(readLines(log_file))

# Append output summary
cat("\nOutput Summary:\n", file = log_file, append = TRUE)
cat("Number of lines in log file:", n_output_lines, "\n", file = log_file, append = TRUE)

