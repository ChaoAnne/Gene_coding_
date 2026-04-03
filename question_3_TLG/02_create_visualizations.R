######################################################
### Setup
#####################################################

base_dir   <- "question_3_TLG"

log_file <- file.path(base_dir, "02_fig_log.txt")

code_file <- file.path(base_dir,"02_create_visualizations.R")   
n_code_lines <- if (file.exists(code_file)) length(readLines(code_file)) else NA_integer_

sink(log_file, split = TRUE)

cat("====================================\n")
cat("Run started at:", format(Sys.time()), "\n")
cat("Working/Output directory:", getwd(), "\n")
cat("====================================\n\n")

cat("Code Summary:\n")
cat("Number of lines of code:", n_code_lines, "\n\n")

##################################################
## 2. Visualizations
##################################################

library(dplyr)
library(ggplot2)
library(pharmaverseadam)
library(binom)
library(scales)

# Load data
adae <- pharmaverseadam::adae
adsl <- pharmaverseadam::adsl

#####################
# 2.1 AE bar plot 
#####################

# Prepare data
ae_plot <- adae %>%
  filter(TRTEMFL == "Y", !is.na(AESEV), !is.na(ACTARM)) %>%
  count(ACTARM, AESEV)

p1 <- ggplot(ae_plot, aes(x = ACTARM, y = n, fill = AESEV)) +
  geom_bar(stat = "identity") +
  labs(
    title = "AE severity distribution by treatment",
    x = "Treatment Arm",
    y = "Count of AEs",
    fill = "Severity/Intensity"
  ) +
  scale_fill_manual(
    values = c(
      "MILD" = "#F8766D",      
      "MODERATE" = "#00BA38",  
      "SEVERE" = "#619CFF"     
    )
  ) +
  theme_gray() +   
  theme(
    plot.title = element_text(face = "bold"),
    plot.title.position = "plot",
    axis.title = element_text(face = "bold"),
    legend.title = element_text(face = "bold")
  )

# Save as PNG
ggsave(
  file.path(base_dir,"02_fig1.png"),
  plot = p1,
  width = 7,
  height = 5,
  dpi = 300
)


##########################
## 2.2 Top 10 AEs
##########################

# Correct denominator
denom_df <- adae %>%
  filter(!is.na(AETERM)) %>%
  distinct(USUBJID)

N <- nrow(denom_df)   # should be 225

# Numerator
ae_summary <- adae %>%
  distinct(USUBJID, AETERM) %>%
  count(AETERM, name = "n") %>%
  arrange(desc(n)) %>%
  slice_head(n = 10)

# CI
ci <- binom.confint(ae_summary$n, N, methods = "exact")

ae_summary <- ae_summary %>%
  mutate(
    prop = n / N,
    lower = ci$lower,
    upper = ci$upper
  ) %>%
  arrange(prop) %>%
  mutate(AETERM = factor(AETERM, levels = AETERM))

# Plot
p2 <- ggplot(ae_summary, aes(y = AETERM, x = prop)) +
  geom_point(size = 3) +
  geom_errorbar(
    aes(xmin = lower, xmax = upper),
    height = 0.2,
    orientation = "y"
  ) +
  scale_x_continuous(labels = percent_format(accuracy = 1)) +
  labs(
    title = "Top 10 Most Frequent Adverse Events",
    subtitle = paste0("n = ", N, " subjects; 95% Clopper-Pearson CIs"),
    x = "Percentage of Patients (%)",
    y = NULL
  ) +
  theme_gray() +
  theme(
    plot.title = element_text(face = "bold"),
    plot.subtitle = element_text(),
    axis.title.x = element_text(face = "bold")
  )


# Save as PNG
ggsave(
  file.path(base_dir,"02_fig2.png"),
  plot = p2,
  width = 7,
  height = 5,
  dpi = 300
)



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


