

######################################################
### Setup
#####################################################
 
base_dir   <- "question_1_sdtm"  

dir.create(base_dir, showWarnings = FALSE, recursive = TRUE )

log_file <- file.path(base_dir, "01_sdtm_log.txt")

code_file <- file.path(base_dir,"01_create_ds_domain.R")   
n_code_lines <- if (file.exists(code_file)) length(readLines(code_file)) else NA_integer_

sink(log_file, split = TRUE)

cat("====================================\n")
cat("Run started at:", format(Sys.time()), "\n")
cat("Working/Output directory:", getwd(), "\n")
cat("====================================\n\n")

cat("Code Summary:\n")
cat("Number of lines of code:", n_code_lines, "\n\n")

###########################################################
### Q1, SDTM DS Domain;
### Chao Ma, Apr 1st, 2026
##########################################################
library(dplyr)
library(stringr)
library(pharmaverseraw)
library(sdtm.oak)
library(readr)
library(labelled)

ds_raw <- pharmaverseraw::ds_raw
ec_raw <- pharmaverseraw::ec_raw
study_ct <- read_csv("https://raw.githubusercontent.com/pharmaverse/examples/refs/heads/main/metadata/sdtm_ct.csv")

#############################
## step 1. prepare CT
#############################
ct_ds <-  study_ct %>%
  filter(codelist_code == "C66727") %>% 
  mutate(
    collected_value = str_to_upper(str_trim(collected_value)),
    term_preferred_term = str_to_upper(str_trim(term_preferred_term))
    ) %>% 
  distinct()

#############################
## step 2. prepare raw data
#############################
ds_raw_clean <- ds_raw %>% 
  mutate(
    STUDYID = STUDY,
    DOMAIN = "DS",
    USUBJID = paste(STUDY, PATNUM, sep="-"),
    
    # standardize raw fields
    othersp_clean  = na_if(str_trim(OTHERSP), ""),
    othersp_clean  = na_if(othersp_clean, "NA"),
    
    dsterm_raw     = if_else(!is.na(othersp_clean), othersp_clean, IT.DSTERM),
    dsdecod_raw    = if_else(!is.na(othersp_clean), othersp_clean, IT.DSDECOD),
    
    dsterm_raw     = str_trim(dsterm_raw),
    dsdecod_raw_uc = str_to_upper(str_trim(dsdecod_raw)),
    
    dsstdat_clean  = na_if(str_trim(IT.DSSTDAT), ""),
    dsstdat_clean  = na_if(dsstdat_clean, "NA"),
    
    dsdtcol_clean  = na_if(str_trim(DSDTCOL), ""),
    dsdtcol_clean  = na_if(dsdtcol_clean, "NA"),
    
    dstmcol_clean = na_if(str_trim(DSTMCOL), ""),
    dstmcol_clean = na_if(dstmcol_clean, "NA")
  ) %>%
  filter(!is.na(dsterm_raw) | !is.na(dsdecod_raw_uc)) %>% 
  arrange(PATNUM, as.Date(dsstdat_clean, "%m-%d-%Y"))


####################################################
# Step 3. Map DSDECOD and derive required variables
####################################################
ds_der <- ds_raw_clean %>%
  left_join(ct_ds, by = c("dsdecod_raw_uc" = "collected_value")) %>%
  mutate(
    DSTERM = str_to_upper(str_trim(dsterm_raw)),
    DSDECOD = coalesce(
      str_to_upper(str_trim(term_value)),
      str_to_upper(str_trim(term_preferred_term)),
      dsdecod_raw_uc
    ),
    
    DSCAT = case_when(
      !is.na(othersp_clean) ~ "OTHER EVENT",
      str_to_upper(str_trim(IT.DSDECOD)) == "RANDOMIZED" ~ "PROTOCOL MILESTONE",
      TRUE ~ "DISPOSITION EVENT"
    ),

    VISIT    = str_trim(INSTANCE),
    # VISITNUM derived from INSTANCE patterns because no separate visit mapping specification was provided.
    # NOTES: Based on data review, ‘Ambul Ecg Removal’ appears to be a procedure-driven 
    #        event rather than a scheduled visit, so I assigned 10 exclusively for ECG removel.
    #        Unscheduled visits were retained with decimal VISITNUM values to preserve 
    #        temporal relationship with scheduled visits. 
    #        Assign 100 to Retrieval just want to be sure it is the last one.
    VISITNUM = case_when(
      str_detect(INSTANCE, "^Screening") ~ 0,
      INSTANCE == "Baseline" ~ 1,
      str_detect(INSTANCE, "^Week\\s*\\d+$") ~ 
        as.numeric(str_extract(INSTANCE, "\\d+")),
      str_detect(INSTANCE, "^Unscheduled\\s*\\d+(\\.\\d+)?$") ~ 
        as.numeric(str_extract(INSTANCE, "\\d+(\\.\\d+)?")),
      INSTANCE == "Retrieval" ~ 100,
      TRUE ~ 10   # e.g., Ambul Ecg Removal
    ),
    
    # collection date/time
    DSDTC = case_when(
      !is.na(dsdtcol_clean) & !is.na(dstmcol_clean) ~ paste0(
        format(as.Date(dsdtcol_clean, format = "%m-%d-%Y"), "%Y-%m-%d"),
        "T",
        dstmcol_clean
      ),
      !is.na(dsdtcol_clean) ~ format(as.Date(dsdtcol_clean, format = "%m-%d-%Y"), "%Y-%m-%d"),
      TRUE ~ NA_character_
    ),
    
    # event start date
    DSSTDTC = case_when(
      !is.na(dsstdat_clean) ~ format(as.Date(dsstdat_clean, format = "%m-%d-%Y"), "%Y-%m-%d"),
      TRUE ~ NA_character_
    )
  )

#################################
# 4. Derive DSSEQ within subject
#################################
ds_der <- ds_der %>%
  group_by(USUBJID) %>%
  arrange(USUBJID, DSSTDTC, DSDTC, .by_group = TRUE) %>%
  mutate(DSSEQ = row_number()) %>%
  ungroup()

##############################################################
# 5. Derive DSSTDY
#    Reference start date exists in EC dataset 
##############################################################
rfstdtc_df <- ec_raw %>%
  mutate(
    EXSTDTC = as.Date(IT.ECSTDAT, format = "%d-%b-%Y")
  ) %>%
  group_by(STUDY, PATNUM) %>%
  summarise(
    RFSTDTC = min(EXSTDTC, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    USUBJID = paste(STUDY, PATNUM, sep = "-"),
    RFSTDTC = format(RFSTDTC, "%Y-%m-%d")
  )

ds_final <- ds_der %>%
  left_join(
    rfstdtc_df %>%
      select(USUBJID, RFSTDTC),
    by = "USUBJID"
  ) %>%
  mutate(
    DSSTDY = case_when(
      !is.na(DSSTDTC) & !is.na(RFSTDTC) ~
        as.integer(as.Date(DSSTDTC) - as.Date(RFSTDTC)) +
        if_else(as.Date(DSSTDTC) >= as.Date(RFSTDTC), 1L, 0L),
      TRUE ~ NA_integer_
    )
  ) %>%
  select(
    STUDYID,
    DOMAIN,
    USUBJID,
    DSSEQ,
    DSTERM,
    DSDECOD,
    DSCAT,
    VISITNUM,
    VISIT,
    DSDTC,
    DSSTDTC,
    DSSTDY
  )

var_label(ds_final) <- list(
  STUDYID = "Study Identifier",
  DOMAIN  = "Domain Abbreviation",
  USUBJID = "Unique Subject Identifier",
  DSSEQ   = "Sequence Number",
  DSTERM  = "Reported Term for the Disposition Event",
  DSDECOD = "Standardized Disposition Term",
  DSCAT   = "Category for Disposition Event",
  VISITNUM = "Visit Number",
  VISIT    = "Visit Name",
  DSDTC    = "Date/Time of Collection",
  DSSTDTC  = "Start Date/Time of Disposition Event",
  DSSTDY   = "Study Day of Start of Disposition Event"
)

save(ds_final, file = file.path(base_dir,"01_sdtm_DS.Rdata"))

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
cat("Number of output lines generated:", n_output_lines, "\n", file = log_file, append = TRUE)

