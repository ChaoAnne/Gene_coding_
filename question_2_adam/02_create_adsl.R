
######################################################
### Setup
#####################################################

base_dir   <- "question_2_adam"

dir.create(base_dir, showWarnings = FALSE, recursive = TRUE )

log_file <- file.path(base_dir, "02_adsl_log.txt")

code_file <- file.path(base_dir,"02_create_adsl.R")   
n_code_lines <- if (file.exists(code_file)) length(readLines(code_file)) else NA_integer_

sink(log_file, split = TRUE)

cat("====================================\n")
cat("Run started at:", format(Sys.time()), "\n")
cat("Working/Output directory:", getwd(), "\n")
cat("====================================\n\n")

cat("Code Summary:\n")
cat("Number of lines of code:", n_code_lines, "\n\n")

########################################################
### Q2, ADaM ADSL Dataset Creation 
### Chao Ma, Apr 1st, 2026
########################################################

library(admiral)
library(dplyr)
library(pharmaversesdtm)
library(lubridate)
library(stringr)

dm <- pharmaversesdtm::dm
vs <- pharmaversesdtm::vs
ex <- pharmaversesdtm::ex
ds <- pharmaversesdtm::ds
ae <- pharmaversesdtm::ae

###########################
# 1. Age
###########################
adsl <- dm %>%
  select(-any_of("DOMAIN")) %>%
  mutate(
    AGE = as.numeric(AGE),
    
    AGEGR9 = case_when(
      AGE < 18 ~ "<18",
      AGE >= 18 & AGE <= 50 ~ "18-50",
      AGE > 50 ~ ">50",
      TRUE ~ NA_character_
    ),
    
    AGEGR9N = case_when(
      AGE < 18 ~ 1,
      AGE >= 18 & AGE <= 50 ~ 2,
      AGE > 50 ~ 3,
      TRUE ~ NA_real_
    )
  )

########################################
# 2. Derive TRTSDTM/TRTSTMF as required;
#    Derive TRTEDTM for LSTAVLDT 
########################################
# 1). Valid dose records
ex_valid <- ex %>%
  filter(
    EXDOSE > 0 | (EXDOSE == 0 & str_detect(str_to_upper(EXTRT), "PLACEBO"))
  )

# 2). Start datetime dataset
ex_start <- ex_valid %>% 
  filter(str_detect(EXSTDTC, "^\\d{4}-\\d{2}-\\d{2}")) %>%
  derive_vars_dtm(
    dtc = EXSTDTC,
    new_vars_prefix = "TRTS",
    highest_imputation = "h",
    time_imputation = "first",
    ignore_seconds_flag = TRUE
  ) %>%
  mutate(
    TRTSTMF = case_when(
      # no time collected at all
      !str_detect(EXSTDTC, "T") ~ "HMS",
      # only hour collected, e.g. 2014-01-02T08
      str_detect(EXSTDTC, "^\\d{4}-\\d{2}-\\d{2}T\\d{2}$") ~ "MS",
      # hour and minute collected, seconds missing
      str_detect(EXSTDTC, "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}$") ~ NA_character_,
      # full datetime present
      str_detect(EXSTDTC, "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}$") ~ NA_character_,
      TRUE ~ NA_character_
    )
  )
# 3). End datetime dataset
ex_end <- ex_valid %>%
  filter(str_detect(EXENDTC, "^\\d{4}-\\d{2}-\\d{2}")) %>%
  derive_vars_dtm(
    dtc = EXENDTC,
    new_vars_prefix = "TRTE",
    highest_imputation = "h",
    time_imputation = "last",
    ignore_seconds_flag = TRUE
  )

# 4). Merge first treatment start datetime
adsl <- adsl %>%
  derive_vars_merged(
    dataset_add = ex_start,
    by_vars = exprs(STUDYID, USUBJID),
    order = exprs(TRTSDTM, EXSEQ),
    mode = "first",
    new_vars = exprs(TRTSDTM, TRTSTMF)
  )

# 5). Merge last treatment end datetime
adsl <- adsl %>%
  derive_vars_merged(
    dataset_add = ex_end,
    by_vars = exprs(STUDYID, USUBJID),
    order = exprs(TRTEDTM, EXSEQ),
    mode = "last",
    new_vars = exprs(TRTEDTM)
  )

# --- QC ---
qc_tmf <- adsl %>%
  filter(!is.na(TRTSDTM) & TRTSTMF != "HMS")
cat("QC — TRTSTMF check (expect 0 rows flagged):", nrow(qc_tmf), "\n")
if (nrow(qc_tmf) > 0) print(qc_tmf %>% select(USUBJID, TRTSDTM, TRTSTMF))

qc_dates <- adsl %>%
  filter(!is.na(TRTSDTM) & !is.na(TRTEDTM) & TRTEDTM < TRTSDTM)
cat("QC — TRTEDTM < TRTSDTM check (expect 0 rows):", nrow(qc_dates), "\n")
if (nrow(qc_dates) > 0) print(qc_dates %>% select(USUBJID, TRTSDTM, TRTEDTM))

stopifnot(
  "TRTSTMF QC failed: unexpected records found."     = nrow(qc_tmf)   == 0,
  "Date order QC failed: TRTEDTM < TRTSDTM found."  = nrow(qc_dates) == 0
)
cat("Treatment date QC checks passed.\n\n")


######################################
# 3. ITTFL
######################################
adsl <- adsl %>%
  mutate(
    # Set to "Y" if ARM is not missing or empty, else "N"
    ITTFL = if_else(!is.na(ARM) & ARM != "", "Y", "N")
  )

######################################
# 4. LSTAVLDT
######################################
# 1). Vital Signs: last complete date with valid result
vs_date <- vs %>%
  filter(!(is.na(VSSTRESN) & (is.na(VSSTRESC) | VSSTRESC == ""))) %>%
  filter(str_detect(VSDTC, "^\\d{4}-\\d{2}-\\d{2}")) %>%
  mutate(VS_DATE = ymd(substr(VSDTC, 1, 10))) %>%
  group_by(STUDYID, USUBJID) %>%
  summarise(
    LST_VS = if (all(is.na(VS_DATE))) as.Date(NA) else max(VS_DATE, na.rm = TRUE),
    .groups = "drop"
  )

# 2). Adverse Events: last complete onset date
ae_date <- ae %>%
  filter(str_detect(AESTDTC, "^\\d{4}-\\d{2}-\\d{2}")) %>%
  mutate(AE_DATE = ymd(substr(AESTDTC, 1, 10))) %>%
  group_by(STUDYID, USUBJID) %>%
  summarise(
    LST_AE = if (all(is.na(AE_DATE))) as.Date(NA) else max(AE_DATE, na.rm = TRUE),
    .groups = "drop"
  )

# 3). Disposition: last complete disposition date
ds_date <- ds %>%
  filter(str_detect(DSSTDTC, "^\\d{4}-\\d{2}-\\d{2}")) %>%
  mutate(DS_DATE = ymd(substr(DSSTDTC, 1, 10))) %>%
  group_by(STUDYID, USUBJID) %>%
  summarise(
    LST_DS = if (all(is.na(DS_DATE))) as.Date(NA) else max(DS_DATE, na.rm = TRUE),
    .groups = "drop"
  )

# 4). Merge and derive LSTAVDT  
adsl <- adsl %>%
  left_join(vs_date, by = c("STUDYID", "USUBJID")) %>%
  left_join(ae_date, by = c("STUDYID", "USUBJID")) %>%
  left_join(ds_date, by = c("STUDYID", "USUBJID")) %>%
  mutate(
    LST_TRT  = as.Date(TRTEDTM),
    LSTAVDT  = pmax(LST_VS, LST_AE, LST_DS, LST_TRT, na.rm = TRUE)
  ) %>%
  select(-LST_VS, -LST_AE, -LST_DS, -LST_TRT)

save(adsl, file = file.path(base_dir,"02_adam_adsl.Rdata"))

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
