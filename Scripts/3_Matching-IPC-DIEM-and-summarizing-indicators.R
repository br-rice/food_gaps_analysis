
# # library and globals
# ---- setup1 ----
#### Library ####
library(tidyverse)
library(RMySQL)

library(countrycode)
library(lubridate)

library(stats)

library(gt)
library(DT)

library(rsconnect)

library(factoextra)

library(skimr)

library(openxlsx)

options(digits = 3)

#### Global folders ####

dataFolder <- "C:/Users/BRICE/IFPRI Dropbox/Brendan Rice/DIEM_IPC_analysis/Data"
outputFolder <- "C:/Users/BRICE/IFPRI Dropbox/Brendan Rice/DIEM_IPC_analysis/Output"
outputVizInOutputFolder <- "C:/Users/BRICE/IFPRI Dropbox/Brendan Rice/DIEM_IPC_analysis/Output/PlotsTablesForPaper"
finalTablesFolder <- "C:/Users/BRICE/IFPRI Dropbox/Brendan Rice/DIEM_IPC_analysis/Output/PlotsTablesForPaper_final"
if (!dir.exists(finalTablesFolder)) dir.create(finalTablesFolder, recursive = TRUE)
finalFiguresFolder <- "C:/Users/BRICE/IFPRI Dropbox/Brendan Rice/DIEM_IPC_analysis/Output/FiguresForPaper_final"
if (!dir.exists(finalFiguresFolder)) dir.create(finalFiguresFolder, recursive = TRUE)

# Helper: export a data frame to Excel matching the paper's table style
# Style: 11pt throughout; headers bold + centered; body first col left-aligned,
# remaining cols centered; thin black borders on all cells; no background shading.
write_paper_table <- function(df, filepath, sheet = "Sheet1", footnote = NULL) {
  wb <- createWorkbook()
  addWorksheet(wb, sheet)
  writeData(wb, sheet = sheet, x = df, startCol = 1, startRow = 1,
            colNames = TRUE, rowNames = FALSE)

  df <- df %>% mutate(across(where(is.numeric), ~round(., 1)))

  header_style <- createStyle(
    textDecoration = "bold", halign = "center", valign = "center",
    wrapText = TRUE, fontName = "Times New Roman", fontSize = 9,
    border = "TopBottomLeftRight", borderStyle = "thin", fgFill = "#BDD7EE"
  )
  addStyle(wb, sheet = sheet, style = header_style,
           rows = 1, cols = 1:ncol(df), gridExpand = TRUE)

  first_col_style <- createStyle(
    halign = "left", valign = "center", fontName = "Times New Roman", fontSize = 9,
    border = "TopBottomLeftRight", borderStyle = "thin"
  )
  addStyle(wb, sheet = sheet, style = first_col_style,
           rows = 2:(nrow(df) + 1), cols = 1, gridExpand = TRUE)

  if (ncol(df) > 1) {
    body_style <- createStyle(
      halign = "center", valign = "center", fontName = "Times New Roman", fontSize = 9,
      border = "TopBottomLeftRight", borderStyle = "thin"
    )
    addStyle(wb, sheet = sheet, style = body_style,
             rows = 2:(nrow(df) + 1), cols = 2:ncol(df), gridExpand = TRUE)
  }

  if (!is.null(footnote)) {
    footnote_row <- nrow(df) + 3
    writeData(wb, sheet = sheet, x = footnote, startCol = 1, startRow = footnote_row,
              colNames = FALSE)
    addStyle(wb, sheet = sheet,
             style = createStyle(fontName = "Times New Roman", fontSize = 9, textDecoration = "italic", halign = "left"),
             rows = footnote_row, cols = 1)
  }

  setColWidths(wb, sheet = sheet, cols = 1:ncol(df), widths = 15)
  saveWorkbook(wb, filepath, overwrite = TRUE)
}

# Helper: export a correlation matrix with conditional cell shading.
# |r| > 0.6  → green;  0.4 ≤ |r| ≤ 0.6 → yellow;  |r| < 0.4 → light red.
# Diagonal cells (value == 1) are left unshaded.
write_correlation_table <- function(df, filepath, sheet = "Sheet1") {
  # Round numeric columns to 3 decimal places; diagonal (== 1) stays as 1
  df <- df %>% mutate(across(where(is.numeric), ~round(., 2)))
  wb <- createWorkbook()
  addWorksheet(wb, sheet)
  writeData(wb, sheet = sheet, x = df, startCol = 1, startRow = 1,
            colNames = TRUE, rowNames = FALSE)

  df <- df %>% mutate(across(where(is.numeric), ~round(., 1)))

  header_style <- createStyle(
    textDecoration = "bold", halign = "center", valign = "center",
    wrapText = TRUE, fontName = "Times New Roman", fontSize = 9,
    border = "TopBottomLeftRight", borderStyle = "thin", fgFill = "#BDD7EE"
  )
  addStyle(wb, sheet = sheet, style = header_style,
           rows = 1, cols = 1:ncol(df), gridExpand = TRUE)

  first_col_style <- createStyle(
    halign = "left", valign = "center", fontName = "Times New Roman", fontSize = 9,
    border = "TopBottomLeftRight", borderStyle = "thin"
  )
  addStyle(wb, sheet = sheet, style = first_col_style,
           rows = 2:(nrow(df) + 1), cols = 1, gridExpand = TRUE)

  green_style  <- createStyle(halign = "center", valign = "center", fontName = "Times New Roman", fontSize = 9,
                               border = "TopBottomLeftRight", borderStyle = "thin",
                               fgFill = "#CCFFCC")
  yellow_style <- createStyle(halign = "center", valign = "center", fontName = "Times New Roman", fontSize = 9,
                               border = "TopBottomLeftRight", borderStyle = "thin",
                               fgFill = "#FFFF99")
  red_style    <- createStyle(halign = "center", valign = "center", fontName = "Times New Roman", fontSize = 9,
                               border = "TopBottomLeftRight", borderStyle = "thin",
                               fgFill = "#FFCCCC")
  plain_style  <- createStyle(halign = "center", valign = "center", fontName = "Times New Roman", fontSize = 9,
                               border = "TopBottomLeftRight", borderStyle = "thin")

  for (col_idx in 2:ncol(df)) {
    for (row_idx in seq_len(nrow(df))) {
      val <- df[[col_idx]][row_idx]
      if (is.na(val) || val == 1) {
        style <- plain_style
      } else if (abs(val) > 0.6) {
        style <- green_style
      } else if (abs(val) >= 0.4) {
        style <- yellow_style
      } else {
        style <- red_style
      }
      addStyle(wb, sheet = sheet, style = style,
               rows = row_idx + 1, cols = col_idx)
    }
  }

  setColWidths(wb, sheet = sheet, cols = 1:ncol(df), widths = 15)
  saveWorkbook(wb, filepath, overwrite = TRUE)
}


summarize_column <- function(df, column_name) {
  df %>%
    summarize(
      variable = quo_name(enquo(column_name)),      
      mean = mean({{ column_name }}, na.rm = TRUE),
      median = median({{ column_name }}, na.rm = TRUE),
      sd = sd({{ column_name }}, na.rm = TRUE),
      min = min({{ column_name }}, na.rm = TRUE),
      max = max({{ column_name }}, na.rm = TRUE),
      count = sum(!is.na({{ column_name }}))    
      )
}




# # Import data
# ## Import DIEM hh data

# ---- importMatchedDIEMAndIPC ----

DIEM_FoodSecurity_HH <- readRDS(file.path(dataFolder, "DIEM_hh_joinedAndClean.rds"))


# import just the 2023+ data so that we can do the correlation with FIES
DIEM_FoodSecurity_HHPost2022 <- readRDS(file.path(dataFolder, "DIEM_hhpost2022AndClean.rds"))




# ## Import matched DIEMHH and IPC
# ---- importMatchedDIEMAndIPC_2 ----
IPCDIEM_hh_imported <- readRDS(file.path(dataFolder, "IPC_DIEM_hh_joinedAndClean.rds"))
IPCDIEM_hh <- IPCDIEM_hh_imported

# ---- dedup_diagnostics ----
# Diagnostics: before vs after deduplication to closest IPC match per (household, survey round)

cat("=== BEFORE deduplication ===\n")
cat("Total rows (household × IPC match pairs):", nrow(IPCDIEM_hh), "\n")
cat("Unique households (OBJECTID):", n_distinct(IPCDIEM_hh$OBJECTID), "\n")
cat("Unique household-rounds (OBJECTID × survey_date):", n_distinct(paste(IPCDIEM_hh$OBJECTID, IPCDIEM_hh$survey_date)), "\n")

before_by_country <- IPCDIEM_hh %>%
  group_by(adm0_name) %>%
  summarise(
    rows            = n(),
    unique_hh       = n_distinct(OBJECTID),
    unique_hh_round = n_distinct(paste(OBJECTID, survey_date)),
    .groups = "drop"
  )
print(before_by_country)

# How many household-rounds have more than one IPC match?
multi_match <- IPCDIEM_hh %>%
  group_by(OBJECTID, survey_date) %>%
  summarise(n_ipc_matches = n(), .groups = "drop")
cat("\nHousehold-rounds with >1 IPC match:", sum(multi_match$n_ipc_matches > 1), "\n")
cat("Household-rounds with exactly 1 IPC match:", sum(multi_match$n_ipc_matches == 1), "\n")

# Deduplicate: per (household, survey round) keep closest IPC analysis in time
IPCDIEM_hh <- IPCDIEM_hh %>%
  group_by(OBJECTID, survey_date) %>%
  slice_min(abs(as.numeric(as.Date(survey_date) - as.Date(country_analysis_date))), n = 1, with_ties = FALSE) %>%
  ungroup()

cat("\n=== AFTER deduplication ===\n")
cat("Total rows:", nrow(IPCDIEM_hh), "\n")
cat("Unique households (OBJECTID):", n_distinct(IPCDIEM_hh$OBJECTID), "\n")
cat("Unique household-rounds:", n_distinct(paste(IPCDIEM_hh$OBJECTID, IPCDIEM_hh$survey_date)), "\n")

after_by_country <- IPCDIEM_hh %>%
  group_by(adm0_name) %>%
  summarise(
    rows            = n(),
    unique_hh       = n_distinct(OBJECTID),
    unique_hh_round = n_distinct(paste(OBJECTID, survey_date)),
    .groups = "drop"
  )
print(after_by_country)

cat("\nRows removed by deduplication:", nrow(IPCDIEM_hh_imported) - nrow(IPCDIEM_hh), "\n")



# ## Import DIEM aggregated, IPC, and DIEM hh pre 2023

# ---- dataImport ----
DIEM_FoodSecurityImported<- read_csv(file.path(dataFolder, "DIEM_household_surveys_aggregated_data_(food_security_thematic_area)_-5236016848326234343.csv")) %>%
  rename(iso3 = adm0_iso3) %>%
  mutate(coll_start_date = mdy_hms(coll_start_date))

DIEM_IncomeImported<- read_csv(file.path(dataFolder, "DIEM_household_surveys_aggregated_data_(income_shocks_and_needs_thematic_areas)_-8295228611698009492.csv")) %>%
  rename(iso3 = adm0_iso3)

IPCdataImported <- readRDS(file.path(dataFolder, "IPCdata_imported.rds")) %>%
  select(
    country_ISO2Code:country_current_period_dates, country_phase1_population:country_phase5_percentage,
    area_name, area_overall_phase,area_p3plus_percentage,
         area_phase1_percentage, area_phase2_percentage, area_phase3_percentage, 
         area_phase4_percentage, area_phase5_percentage,
    area_phase1_population, area_phase2_population, area_phase3_population, area_phase4_population, area_phase5_population
         ) %>%
  mutate(iso3 = countrycode::countrycode(country_ISO2Code, origin = "iso2c", destination = "iso3c")) %>%
  relocate(iso3, .after = country_ISO2Code) %>% select(-country_ISO2Code) %>%
  mutate(country_analysis_date = as.Date(country_analysis_date)) %>%
   rename(adm_name = area_name) 
  # 
  # # create fgt type calorie gap
  # mutate(
  #   IPC1_calDef_upper = IPC1_calDef_upper,
  #   IPC2_calDef_upper = IPC2_calDef_upper,
  #   IPC3_calDef_upper = IPC3_calDef_upper,
  #   IPC4_calDef_upper = IPC4_calDef_upper,
  #   IPC5_calDef_upper = IPC5_calDef_upper,
  #   
  #   IPC1_calDef_lower = IPC1_calDef_lower,
  #   IPC2_calDef_lower = IPC2_calDef_lower,
  #   IPC3_calDef_lower = IPC3_calDef_lower,
  #   IPC4_calDef_lower = IPC4_calDef_lower,
  #   IPC5_calDef_lower = IPC5_calDef_lower,
  #   ) 


DIEM_microData_pre2023Imported <- read_csv(file.path(dataFolder, "Household_Surveys_Microdata_6215924197953569388.csv")) 
  






# # Summary of this file
# I get IPC and FAO DIEM data and merge it by admin level 2 and year. Then I provide some desciptives of the food security indicators for the entire sample (of merged data) and summarize those indicators by IPC phase - to see how IPC matches to these food security indicators. 

# #================================================================
# # Summarizing matched IPC DIEM data

# ---- IPCdiemDescribe ----
#checking Nigeria
checkingNigeria <- IPCDIEM_hh %>%
  filter(adm0_name == "Nigeria") %>%
  select(adm0_name, country_title, adm_name, area_overall_phase) %>%
  distinct() %>%
  arrange(adm0_name, country_title) %>%
  group_by(country_title) %>% count(adm_name)

describingIPC_DIEM <- IPCDIEM_hh %>%
  select(adm0_name, adm_name, country_title, country_analysis_date, area_overall_phase) %>%
  mutate(year = year(country_analysis_date)) %>% select(-country_analysis_date) %>%
  distinct()
  
del <- describingIPC_DIEM %>%
  group_by(adm0_name) %>%
  count(area_overall_phase, name = "n_analyses") %>% ungroup() %>%
  pivot_wider(names_from = area_overall_phase, values_from = n_analyses) %>%
  rename(IPC1 = `1`,
         IPC2 = `2`,
         IPC3 = `3`,
         IPC4 = `4`) %>%
  select(adm0_name, IPC1, IPC2, IPC3, IPC4) %>%
  arrange(adm0_name) %>%
  mutate(across(everything(), ~replace_na(., 0))) %>%
  bind_rows(
    summarise(., adm0_name = "Total", across(where(is.numeric), sum))
  )

write_paper_table(del, file.path(finalTablesFolder, "Table1_matched_areas_by_country.xlsx"))

# ---- matchedHHcountByCountry ----
# Count of matched households by country and IPC phase
del_hh <- IPCDIEM_hh %>%
  group_by(adm0_name) %>%
  count(area_overall_phase, name = "n_households") %>%
  ungroup() %>%
  pivot_wider(names_from = area_overall_phase, values_from = n_households,
              names_prefix = "IPC") %>%
  select(adm0_name, any_of(c("IPC1", "IPC2", "IPC3", "IPC4"))) %>%
  arrange(adm0_name) %>%
  mutate(across(where(is.numeric), ~replace_na(., 0L))) %>%
  bind_rows(
    summarise(., adm0_name = "Total", across(where(is.numeric), sum))
  ) %>%
  rename(Country = adm0_name)

write_paper_table(del_hh, file.path(finalTablesFolder, "Table1b_matched_households_by_country_and_phase.xlsx"))

# ---- multiplePhaseMatches ----
# Households matched to 2+ different IPC phases (across different IPC analyses)
multi_phase <- IPCDIEM_hh %>%
  group_by(OBJECTID) %>%
  summarise(n_phases = n_distinct(area_overall_phase), .groups = "drop")

multi_phase_summary <- IPCDIEM_hh %>%
  select(OBJECTID, adm0_name) %>%
  distinct() %>%
  left_join(multi_phase, by = "OBJECTID") %>%
  group_by(adm0_name) %>%
  summarise(
    n_hh_total        = n(),
    n_hh_multi_phase  = sum(n_phases > 1),
    pct_multi_phase   = round(100 * mean(n_phases > 1), 1),
    .groups = "drop"
  ) %>%
  bind_rows(
    summarise(.,
      adm0_name        = "Overall",
      n_hh_total       = sum(n_hh_total),
      n_hh_multi_phase = sum(n_hh_multi_phase),
      pct_multi_phase  = round(100 * sum(n_hh_multi_phase) / sum(n_hh_total), 1)
    )
  ) %>%
  rename(
    Country                           = adm0_name,
    "Total matched HH"                = n_hh_total,
    "HH matched to 2+ IPC phases (n)" = n_hh_multi_phase,
    "HH matched to 2+ IPC phases (%)" = pct_multi_phase
  )

write_paper_table(multi_phase_summary,
  file.path(finalTablesFolder, "Table_other_1_multi_phase_matches.xlsx"))

# ---- hhDataCompleteness ----
# Share of matched households with no missing in ANY of FCS, HDDS, HHS, RCSI
completeness_by_country <- IPCDIEM_hh %>%
  mutate(all_complete = !is.na(fcs) & !is.na(hdds_score) & !is.na(hhs) & !is.na(rcsi_score)) %>%
  group_by(adm0_name) %>%
  summarise(
    N_households = n(),
    pct_complete = round(100 * mean(all_complete), 1),
    .groups = "drop"
  ) %>%
  arrange(adm0_name)

completeness_overall <- IPCDIEM_hh %>%
  mutate(all_complete = !is.na(fcs) & !is.na(hdds_score) & !is.na(hhs) & !is.na(rcsi_score)) %>%
  summarise(
    adm0_name    = "Overall",
    N_households = n(),
    pct_complete = round(100 * mean(all_complete), 1)
  )

completeness_tbl <- bind_rows(completeness_by_country, completeness_overall) %>%
  rename(
    Country                             = adm0_name,
    "N matched HH"                      = N_households,
    "HH with complete data, all 4 indicators (%)" = pct_complete
  )

write_paper_table(completeness_tbl, file.path(finalTablesFolder, "TableA6_HH_data_completeness.xlsx"))

# by time (appendix)
del <- describingIPC_DIEM %>%
  group_by(year) %>%
  count(area_overall_phase, name = "n_analyses") %>% ungroup() %>%
  pivot_wider(names_from = area_overall_phase, values_from = n_analyses) %>%
  rename(IPC1 = `1`,
         IPC2 = `2`,
         IPC3 = `3`,
         IPC4 = `4`) %>%
  relocate(IPC1, .before = IPC2)

write_paper_table(del, file.path(finalTablesFolder, "TableA1_time_coverage.xlsx"))



# #================================================================

# # Summarizing calorie gaps 
# ## table of calorie gap assumed
# ---- calGaps ----
# baseTable <- data.frame(
#   IPC_phase = c("IPC1", "IPC2", "IPC3", "IPC4", "IPC5"),
#   Percentage_of_IPC1_UpperBound = c(1- IPC1_calDef_upper , 1-IPC2_calDef_upper , 1-IPC3_calDef_upper, 1-IPC4_calDef_upper , 1-IPC5_calDef_upper),
#   Percentage_of_IPC1_LowerBound =  c(1- IPC1_calDef_lower , 1-IPC2_calDef_lower , 1-IPC3_calDef_lower, 1-IPC4_calDef_lower , 1-IPC5_calDef_lower),
#   assumedCalorieDeficit = c("0%", "0%", "< 20%", ">=20% <50%", ">50%")
#   ) 
# 
# 
# tableForPaper <- baseTable %>%
#   mutate(fullIntake = 2100) %>%
#   mutate(
#     calorieIntake_upper = fullIntake * Percentage_of_IPC1_UpperBound,
#     calorieIntake_lower = fullIntake * Percentage_of_IPC1_LowerBound, 
#     calorieDeficit_upper = fullIntake - calorieIntake_upper,
#     calorieDeficit_lower = fullIntake - calorieIntake_lower,
#     # now convert to kcal
#     cerealkgDeficit_upper = round(calorieDeficit_upper * .1/379, 2),
#     cerealkgDeficit_lower = round(calorieDeficit_lower * .1/379, 2),
#     "Assumed caloric deficit in KCal pp/pd" = paste(calorieDeficit_lower, " - ", calorieDeficit_upper),
#     "Assumed average consumption in KCal pp/pd" = paste(calorieIntake_upper, " - ", calorieIntake_lower),
#     "Assumed average deficit in cereals kg/pp/pd" = paste(cerealkgDeficit_lower, " - ", cerealkgDeficit_upper)
#   ) %>%
#   #fix the 0-0 versions
#   mutate(
#     `Assumed caloric deficit in KCal pp/pd` = case_when(
#       `Assumed caloric deficit in KCal pp/pd` == "0  -  0" ~ "0",
#       `Assumed caloric deficit in KCal pp/pd` == "1050  -  1050" ~ "1050+",
#       TRUE ~ `Assumed caloric deficit in KCal pp/pd`),
#     
#     `Assumed average consumption in KCal pp/pd` = case_when(
#       `Assumed average consumption in KCal pp/pd` == "2100  -  2100" ~ "2100",
#       `Assumed average consumption in KCal pp/pd` == "1050  -  1050" ~ "<= 1050",
#       TRUE ~ `Assumed average consumption in KCal pp/pd`),
#     
#     `Assumed average deficit in cereals kg/pp/pd` = case_when(
#       `Assumed average deficit in cereals kg/pp/pd` ==  "0  -  0" ~ "0",
#       `Assumed average deficit in cereals kg/pp/pd` ==  "0.28  -  0.28" ~ ">= 0.28",
#       TRUE ~ `Assumed average deficit in cereals kg/pp/pd`)
#   ) %>%
#   select(IPC_phase, assumedCalorieDeficit, 
#          `Assumed caloric deficit in KCal pp/pd`:`Assumed average deficit in cereals kg/pp/pd`) %>%
#   rename(
#     "Assumed caloric deficit (%)" = assumedCalorieDeficit,
#     "IPC Phase" = IPC_phase
#   )
# 
# # Define path
# excel_file <- file.path(outputVizInOutputFolder, "baseTableForCalorieGaps.xlsx")
# 
# # Create workbook and worksheet
# wb <- createWorkbook()
# addWorksheet(wb, "Base table")
# 
# # Write plain data
# writeData(
#   wb,
#   sheet = "Base table",
#   x = tableForPaper,
#   startCol = 1,
#   startRow = 1,
#   colNames = TRUE,
#   rowNames = FALSE
# )
# 
# # Header style: bold, centered, wrapped
# header_style <- createStyle(
#   textDecoration = "bold",
#   halign = "center",
#   valign = "center",
#   wrapText = TRUE,
#   fontName = "Times New Roman", fontSize = 9
# )
# addStyle(
#   wb,
#   sheet = "Base table",
#   style = header_style,
#   rows = 1,
#   cols = 1:ncol(tableForPaper),
#   gridExpand = TRUE
# )
# 
# # Body style: center-align
# body_style <- createStyle(
#   halign = "center",
#   valign = "center"
# )
# addStyle(
#   wb,
#   sheet = "Base table",
#   style = body_style,
#   rows = 2:(nrow(tableForPaper) + 1),
#   cols = 1:ncol(tableForPaper),
#   gridExpand = TRUE
# )
# 
# # 🔲 Border style: thin border around all cells (including headers)
# border_style <- createStyle(
#   border = "TopBottomLeftRight",
#   borderStyle = "thin"
# )
# addStyle(
#   wb,
#   sheet = "Base table",
#   style = border_style,
#   rows = 1:(nrow(tableForPaper) + 1),
#   cols = 1:ncol(tableForPaper),
#   gridExpand = TRUE,
#   stack = TRUE  # Preserve previous styles
# )
# 
# # Set compact column widths
# setColWidths(wb, sheet = "Base table", cols = 1:ncol(tableForPaper), widths = 15)
# 
# # Save the workbook
# saveWorkbook(wb, excel_file, overwrite = TRUE)
# 






# ---- IPCdataImportPrep_3 ----
## tables with ranges
# 
# IPCcalculations <- IPCdataImported %>%
#   mutate(
#     calGap_FGT_upper = IPC1_calDef_upper*area_phase1_percentage + IPC2_calDef_upper*area_phase2_percentage + IPC3_calDef_upper*area_phase3_percentage +   IPC4_calDef_upper*area_phase4_percentage + IPC5_calDef_upper*area_phase5_percentage,
#     
#     calGap_FGT_lower = IPC1_calDef_lower*area_phase1_percentage + IPC2_calDef_lower*area_phase2_percentage + IPC3_calDef_lower*area_phase3_percentage +
#       IPC4_calDef_lower*area_phase4_percentage + IPC5_calDef_lower*area_phase5_percentage,    
#   ) %>%
#   select(-c(IPC1_calDef_upper:IPC5_calDef_lower)) %>%
#   
#   mutate(
#     gap_inKcal_upper = IPC1 - kcal_per_person_per_day_UpperBound,
#     gap_inKcal_lower = IPC1 - kcal_per_person_per_day_LowerBound,
#     gap_inKcal_byPhase_acrossPopulation_upper= population_inPhase * gap_inKcal_upper,
#     gap_inKcal_byPhase_acrossPopulation_lower= population_inPhase * gap_inKcal_lower
#          ) %>%
#   group_by(country_title) %>%
#   mutate(
#     totalGap_inKcal_byAnalysis_upper = sum(gap_inKcal_byPhase_acrossPopulation_upper),
#     totalGap_inKcal_byAnalysis_lower = sum(gap_inKcal_byPhase_acrossPopulation_lower)
#     ) %>%ungroup() %>%
#   select(countryName:population_inPhase, gap_inKcal_lower, gap_inKcal_upper, gap_inKcal_byPhase_acrossPopulation_lower,gap_inKcal_byPhase_acrossPopulation_upper, totalGap_inKcal_byAnalysis_lower,
#          totalGap_inKcal_byAnalysis_upper) %>%
#   mutate(country_title = paste(countryName, " - ", country_title)) %>% #select(-c(countryName, country_analysis_date_year)) %>%
#   rename(
#     KcalNeeds_byPhase_lower = gap_inKcal_byPhase_acrossPopulation_lower,
#     KcalNeeds_byPhase_upper = gap_inKcal_byPhase_acrossPopulation_upper
# 
#     )




# 
# 
#   mutate(
#     calGap_FGT_upper = IPC1_calDef_upper*area_phase1_percentage + IPC2_calDef_upper*area_phase2_percentage + IPC3_calDef_upper*area_phase3_percentage +   IPC4_calDef_upper*area_phase4_percentage + IPC5_calDef_upper*area_phase5_percentage,
#     
#     calGap_FGT_lower = IPC1_calDef_lower*area_phase1_percentage + IPC2_calDef_lower*area_phase2_percentage + IPC3_calDef_lower*area_phase3_percentage +
#       IPC4_calDef_lower*area_phase4_percentage + IPC5_calDef_lower*area_phase5_percentage,    
#   ) 



# # Data work

# Here is a summary of the data work:

# - Get IPC phase per country per area (admin level 2) 
# - Take the DIEM food security module data, which contains several food security indicators like food consumption scores, reduced coping index, etc. The income module looked less relevant, but at the link in the next bullet point you can take a look at other modules and variables available. To me, nothing from DIEM looks suitable for estimating calorie gaps. 
# - Selected what indicators to include (see the list in the section below). To see all variables for all modules, see this file: https://www.dropbox.com/scl/fi/rsagth53r1q0pxdrpktxh/DIEM_2023_-_Fields_descriptions.xlsx?rlkey=vn9t7po3fwla9c1ahvz0hwfgj&dl=0
# - I merged DIEM data and IPC phase data by admin level 2 columns in both datasets and by time period of the indicator/IPC analysis. For the sake of speed, I didn't touch any values in the admin level 2 columns of either dataset; I just merged what was already clearly a pair. For merging by time period, I created a window of time based on the start date of the survey/IPC analysis and then filtered as follows:   start_dateForMatching_IPC <= end_dateForMatching_DIEM &      end_dateForMatching_IPC >= start_dateForMatching_DIEM.

# <br>
# <br>
# <hr>

# # Selected indicators

# Below are the key indicators, categorized by type. In the data shown below, I include even a more filtered list:

# **Food Insecurity Experience Scale (FIES)**  
# - `fies_rawscore_median`, `fies_rawscore_wmean`: Median and weighted mean FIES raw scores.  
# - `p_mod_median`, `p_mod_wmean`: Prevalence of recent moderate or severe household food insecurity (FIES). Values range from 0 to 1.  
# - `fies_rawscore_0` to `fies_rawscore_8`: Breakdown of FIES raw scores.  

# **Livelihood Coping Strategy Index (LCSI)**  
# - `lcsi_0` to `lcsi_3`: Different levels of livelihood coping strategies.  

# **Household Diet Diversity Score (HDDS)**  
# - `hdds_class_1` to `hdds_class_3`: Classification of household diet diversity.  

# **Household Hunger Scale (HHS)**  
# - `hhs_0` to `hhs_6`: Measures of household hunger severity.  

# **Food Consumption Score (FCS)**  
# - `fcs_median`, `fcs_wmean`: Median and weighted mean Food Consumption Scores.  

# **Food Consumption Groups (FCG)**  
# - `fcg_1` to `fcg_3`: Classification of households based on food consumption. Additional scores per food group are available if needed.  

# **Reduced Coping Strategies Index (rCSI)**  
# - `rcsi_score_median`, `rcsi_score_wmean`: Median and weighted mean reduced coping strategies index scores.  

# <br>
# <br>
# <hr>


# Caloric deficit midpoints by IPC phase (midpoints used throughout script for calGap_FGT and IPCthresholds)
IPC1_calDef <- 0
IPC2_calDef <- 0
IPC3_calDef <- 0.105   # midpoint of 1%-20%
IPC4_calDef <- 0.355   # midpoint of 21%-50%
IPC5_calDef <- 0.5     # user-specified

# ---- dataMaching ----
DIEM_FoodSecurity <- DIEM_FoodSecurityImported %>%
  mutate(start_dateForMatching_DIEM = coll_start_date %m-% months(5),
         end_dateForMatching_DIEM = coll_start_date %m+% months(5)) %>%
  relocate(c(start_dateForMatching_DIEM, end_dateForMatching_DIEM), .before =coll_start_date ) %>%
  select(iso3, adm2_name, adm_name, coll_start_date, start_dateForMatching_DIEM, end_dateForMatching_DIEM,
         # all the indicators we want
         # FIES
         fies_rawscore_median,fies_rawscore_wmean, p_mod_median, p_mod_wmean, # prevalence of recent moderate or severe household food insecurity (FIES). The values range from 0 to 1
         fies_rawscore_0: fies_rawscore_8,
         #Livelihood coping strategy
         lcsi_0: lcsi_3,
         #hh diet diversity score
         hdds_class_1: hdds_class_3, hdds_score_wmean,
         # hh hunger score
         hhs_0: hhs_6,
         #fcs
         fcs_median, fcs_wmean,
         #food consumption group (there's also scores per food group if needed
         fcg_1: fcg_3,
         #reduced coping strategies index
         rcsi_score_median, rcsi_score_wmean
         )

IPCdata <- IPCdataImported %>%
  mutate(start_dateForMatching_IPC = country_analysis_date %m-% months(5),
         end_dateForMatching_IPC = country_analysis_date %m+% months(5)) %>%
  relocate(c(start_dateForMatching_IPC, end_dateForMatching_IPC), .before = country_analysis_date )

# joining based on admin2
IPC_DIEM <- DIEM_FoodSecurity %>%
  left_join(IPCdata, c("adm_name", "iso3")) %>%
  filter(
    start_dateForMatching_IPC <= end_dateForMatching_DIEM &
      end_dateForMatching_IPC >= start_dateForMatching_DIEM
  ) %>%
  select(iso3, adm_name, coll_start_date,
         # the indicators wanted here
          # FIES
         fies_rawscore_median,fies_rawscore_wmean, p_mod_median, p_mod_wmean, # prevalence of recent moderate or severe household food insecurity (FIES). The values range from 0 to 1
         fies_rawscore_0: fies_rawscore_8,
         #Livelihood coping strategy
         lcsi_0: lcsi_3,
         #hh diet diversity score
         hdds_class_1: hdds_class_3, hdds_score_wmean,
         # hh hunger score
         hhs_0: hhs_6,
         #fcs
         fcs_median, fcs_wmean,
         #food consumption group (there's also scores per food group if needed
         fcg_1: fcg_3,
         #reduced coping strategies index
         rcsi_score_median, rcsi_score_wmean,
          country_title, country_analysis_date, country_current_period_dates,
         area_overall_phase, area_p3plus_percentage,
         area_phase1_percentage, area_phase2_percentage, area_phase3_percentage,
         area_phase4_percentage, area_phase5_percentage,

             area_phase1_population, area_phase2_population, area_phase3_population, area_phase4_population, area_phase5_population


         ) %>%



  rename(DIEM_startDate=coll_start_date,
         IPC_country_title = country_title,
         IPC_analysis_date = country_analysis_date,
         IPC_current_period_dates = country_current_period_dates) %>%
  mutate(
    # FGT1 kcal gap index: population-weighted avg caloric deficit across IPC phases
    calGap_FGT = IPC1_calDef * area_phase1_percentage +
                 IPC2_calDef * area_phase2_percentage +
                 IPC3_calDef * area_phase3_percentage +
                 IPC4_calDef * area_phase4_percentage +
                 IPC5_calDef * area_phase5_percentage
  )


# id matched countries and rounds

IPC_DIEM %>%
  mutate(year = year(DIEM_startDate)) %>%
  select(iso3, year) %>% distinct() %>%
  arrange(iso3, year) %>%
  mutate(country = countrycode(iso3, origin = "iso3c", destination = "country.name")) %>%
  select(country, year)

del <- IPC_DIEM %>%
  arrange(iso3, DIEM_startDate)




# <br>
# <br>
# <hr>



# # Viewing the data
# ---- viewingData ----
datatable(IPC_DIEM %>% arrange(iso3), options = list(pageLength = 5, scrollX = TRUE))

# <br>
# <br>
# <hr>


# # ===========================================================================

# # Indicator distributions

# ## Food consumption score 

# ### FCS distribution (district med)
# ---- FCS_1 ----
ggplot(IPC_DIEM, aes(x = fcs_median)) +
  geom_density(binwidth = 5, color = "black", alpha = 0.7) +
  labs(title = "Distribution of FCS median values - across matched data",
       x = "FCS Median Values",
       y = "Count") +
  theme_minimal()


# ### FCS distribution across (DIEM hh)
# ---- FCS_distribution_DIEMhh ----
ggplot(IPCDIEM_hh, aes(x = fcs)) +
  geom_density(binwidth = 5, color = "black", alpha = 0.7) +
  labs(title = "Distribution of FCS (from hh-level data) - across matched data",
       x = "FCS",
       y = "Count") +
  theme_minimal()


# ### FCS summarized by phase (district med)
# ---- FCS_2 ----
IPC_DIEM %>%
  group_by(area_overall_phase) %>%
  summarize_column(fcs_median) %>%
  mutate(mean = round(mean, 1),
         sd = round(sd, 1)
         ) %>%
  gt() %>%
    tab_header(
    title = "Food Consumption Scores summarized by IPC phase"
  )



# ---- FCS_SummarizedbyIPCPHase ----
ggplot(IPC_DIEM, aes(x = factor(area_overall_phase), y = fcs_median)) +
  geom_boxplot() +
  labs(x = "IPC Phase", y = "FCS Median", title = "Distribution of FCS Median by IPC Phase") +
  theme_minimal()

ggplot(IPC_DIEM, aes(x = fcs_median, fill = factor(area_overall_phase))) +
  geom_density(alpha = 0.5) +
  labs(x = "FCS Median", y = "Density", title = "Density Distribution of FCS Median by IPC Phase", fill = "IPC Phase") +
  theme_minimal()



# ### FCS summarized by phase (DIEM hh)
# ---- FCS summarized by IPC phase hh-level data ----
IPCDIEM_hh %>%
  group_by(area_overall_phase) %>%
  summarize_column(fcs) %>%
  mutate(mean = round(mean, 1),
         sd = round(sd, 1)
         ) %>%
  gt() %>%
    tab_header(
    title = "Food Consumption Scores (from hh-level data) summarized by IPC phase"
  )



# ---- FCS_hhdata_SummarizedbyIPCPHase ----
ggplot(IPCDIEM_hh, aes(x = factor(area_overall_phase), y = fcs)) +
  geom_boxplot() +
  labs(x = "IPC Phase", y = "FCS", title = "Distribution of FCS (hh-level data) by IPC Phase") +
  theme_minimal()

ggplot(IPCDIEM_hh, aes(x = fcs, fill = factor(area_overall_phase))) +
  geom_density(alpha = 0.5) +
  labs(x = "FCS", y = "Density", title = "Density Distribution of FCS (hh-level data) by IPC Phase", fill = "IPC Phase") +
  theme_minimal()




# <br>

# ---- FCS_7 ----

### FCS using the district level weighted mean

# ggplot(IPC_DIEM, aes(x = fcs_wmean)) +
#   geom_density(binwidth = 5, color = "black", alpha = 0.7) +
#   labs(title = "Distribution of FCS w mean values - across matched data",
#        x = "FCS weighted mean values",
#        y = "Count") +
#   theme_minimal()




# ---- FCS_5 ----
### FCS w mean score at admin 2 level summarized by IPC phase

# IPC_DIEM %>%
#   group_by(area_overall_phase) %>%
#   summarize_column(fcs_wmean) %>%
#   mutate(mean = round(mean, 1),
#          sd = round(sd, 1)
#          ) %>%
#   gt() %>%
#     tab_header(
#     title = "Food Consumption Scores (weighted mean) summarized by IPC phase"
#   )



# ---- FCS_6 ----
# ggplot(IPC_DIEM, aes(x = factor(area_overall_phase), y = fcs_wmean)) +
#   geom_boxplot() +
#   labs(x = "IPC Phase", y = "FCS weighted mean", title = "Distribution of FCS w mean values by IPC Phase") +
#   theme_minimal()
# 
# ggplot(IPC_DIEM, aes(x = fcs_wmean, fill = factor(area_overall_phase))) +
#   geom_density(alpha = 0.5) +
#   labs(x = "FCS w mean", y = "Density", title = "Density Distribution of FCS weighted mean values by IPC Phase", fill = "IPC Phase") +
#   theme_minimal()



# <br>
# <br>
# <hr>

# ---- commentedOutOldFCSGapcalculation ----

# # FCS gap calculation 
# WFP indicates a FCS >35 as adequate. Therefore, the deficit is calculated based on this.
# 
# \begin{equation}
# \text{Consumption Gap}_i = 
# \begin{cases}
# \frac{z - y_i}{z}, & \text{if } y_i < z \\
# 0, & \text{if } y_i \geq z
# \end{cases}
# \end{equation}
# 
# where $y_i$ is the district-level median Food Consumption Score (FCS), and $z$ is the FCS adequacy threshold of 35.
# 
# 
# \begin{equation}
# \text{Food Consumption Gap Index by IPC Phase} = \frac{1}{N} \sum_{i=1}^{N} \text{Consumption Gap}_i
# \end{equation}
# 
# where $i$ is the district and $N$ is the number of districts. The following table summarizes the nutrient gap by phase. 
# 
# 
# cutoff <- 35
# IPC_DIEM_withFCSCalculation <- IPC_DIEM %>%
#   select(iso3, adm_name, DIEM_startDate,fcs_median, IPC_country_title: last_col() ) %>%
#   mutate(FCS_povGapMeasure = (cutoff - fcs_median)/cutoff) %>%
#   mutate(FCS_povGapMeasure = case_when(
#     FCS_povGapMeasure < 0 ~ 0,
#     TRUE ~ FCS_povGapMeasure) 
#     ) %>%
#   relocate(FCS_povGapMeasure, .after = fcs_median)
# 
# 
# 
# 
# avgGapByPhase <- IPC_DIEM_withFCSCalculation %>%
#   group_by(area_overall_phase) %>%
#   summarize(
#     FCS_povGapMeasure_ByIPCPhase = mean(FCS_povGapMeasure, na.rm = TRUE)) 
# avgGapByPhase %>% gt() %>%
#       tab_header(
#     title = "Average FCS gap (defined as below a score of 35) per IPC phase"
#   )
# 
# 
# ## with weighted mean
# 
# cutoff <- 35
# IPC_DIEM_withFCSCalculation <- IPC_DIEM %>%
#   select(iso3, adm_name, DIEM_startDate,fcs_wmean, IPC_country_title: last_col() ) %>%
#   mutate(FCS_povGapMeasure = (cutoff - fcs_wmean)/cutoff) %>%
#   mutate(FCS_povGapMeasure = case_when(
#     FCS_povGapMeasure < 0 ~ 0,
#     TRUE ~ FCS_povGapMeasure) 
#     ) #%>%
#  # relocate(FCS_povGapMeasure, .after = fcs_median)
# 
# 
# 
# avgGapByPhase <- IPC_DIEM_withFCSCalculation %>%
#   group_by(area_overall_phase) %>%
#   summarize(
#     FCS_povGapMeasure_ByIPCPhase = mean(FCS_povGapMeasure, na.rm = TRUE)) 
# avgGapByPhase %>% gt() %>%
#       tab_header(
#     title = "Average FCS gap (defined as below a score of 35) per IPC phase"
#   )
# 
# 
# 
# <!-- Now we would need to associate these consumption gaps with calorie gaps. There is some work done on this like in Wiesmann et al. (2009). All related papers are in our resource folder in the shared folder: C:\Users\BRICE\IFPRI Dropbox\Brendan Rice\DIEM_IPC_analysis.  -->
# 
# <!-- Here is one particularly relevant table from that paper: -->
# 
# <!-- **Thresholds for creating calorie consumption groups** -->
# 
# <!-- | Calorie consumption in kilocalories/capita/day | Shortfall, in percentage | Profile    | -->
# <!-- |------------------------------------------------|---------------------------|------------| -->
# <!-- | < 1,470                                        | > 30                      | Poor       | -->
# <!-- | ≥ 1,470 – < 2,100                              | ≤ 30 – > 0                | Borderline | -->
# <!-- | ≥ 2,100                                        | 0                         | Acceptable | -->
# 
# <!-- *Source: Food consumption shortfalls described in World Food Programme (2005, 139).* -->
# 
# 



# <hr>
# ## Reduced coping strategies index

# ### rcsi distribution (district med)
# ---- FCS_1.5 ----
ggplot(IPC_DIEM, aes(x = rcsi_score_median)) +
  geom_density(binwidth = 5, color = "black", alpha = 0.7) +
  labs(title = "Distribution of RCSI median values - across matched data",
       x = "RCSI Median Values",
       y = "Count") +
  theme_minimal()



# ### RCSI summarized by phase (district med)
# ---- RCSI_2 ----
IPC_DIEM %>%
  group_by(area_overall_phase) %>%
  summarize_column(rcsi_score_median) %>%
  mutate(mean = round(mean, 1),
         sd = round(sd, 1)
         ) %>%
  gt() %>%
    tab_header(
    title = "RCSI scores summarized by IPC phase"
  )




# ---- RCSI_3 ----
ggplot(IPC_DIEM, aes(x = factor(area_overall_phase), y = rcsi_score_median)) +
  geom_boxplot() +
  labs(x = "IPC Phase", y = "RCSI Median Score", title = "Distribution of RCSI median scores by IPC Phase") +
  theme_minimal()

ggplot(IPC_DIEM, aes(x = rcsi_score_median, fill = factor(area_overall_phase))) +
  geom_density(alpha = 0.5) +
  labs(x = "RCSI median score", y = "Density", title = "Density Distribution of RCSI median scores by IPC Phase", fill = "IPC Phase") +
  theme_minimal()





# ### rcsi distribution (DIEM hh)
# ---- FCS_1.5_hhlevel ----
ggplot(IPCDIEM_hh, aes(x = rcsi_score)) +
  geom_density(binwidth = 5, color = "black", alpha = 0.7) +
  labs(title = "Distribution of RCSI scores (from hh-level data) - across matched data",
       x = "RCSI score",
       y = "Count") +
  theme_minimal()



# ### RCSI summarized by phase (DIEM hh)
# ---- RCSI_2_hhlevel ----
IPCDIEM_hh %>%
  group_by(area_overall_phase) %>%
  summarize_column(rcsi_score) %>%
  mutate(mean = round(mean, 1),
         sd = round(sd, 1)
         ) %>%
  gt() %>%
    tab_header(
    title = "RCSI scores (from hh-level data) summarized by IPC phase"
  )





# ---- RCSI_3_hhlevel ----
ggplot(IPCDIEM_hh, aes(x = factor(area_overall_phase), y = rcsi_score)) +
  geom_boxplot() +
  labs(x = "IPC Phase", y = "RCSI Score", title = "Distribution of RCSI scores (from hh-level data) by IPC Phase") +
  theme_minimal()

ggplot(IPCDIEM_hh, aes(x = rcsi_score, fill = factor(area_overall_phase))) +
  geom_density(alpha = 0.5) +
  labs(x = "RCSI score", y = "Density", title = "Density Distribution of RCSI scores (from hh-level data) by IPC Phase", fill = "IPC Phase") +
  theme_minimal()





# ## Fies_rawscore_median

# ### FIES raw score (district med)
# ---- fies_1 ----
ggplot(IPC_DIEM, aes(x = fies_rawscore_median)) +
  geom_density(binwidth = 5, color = "black", alpha = 0.7) +
  labs(title = "Distribution of FIES raw score median values - across matched data",
       x = "FIES raw score median values",
       y = "Count") +
  theme_minimal()



# ### FIES median raw score summarized by IPC phase
# ---- FIES_2 ----
IPC_DIEM %>%
  group_by(area_overall_phase) %>%
  summarize_column(fies_rawscore_median) %>%
  mutate(mean = round(mean, 1),
         sd = round(sd, 1)
         ) %>%
  gt() %>%
    tab_header(
    title = "FIES Raw Scores summarized by IPC phase"
  )



# ---- FIES_3 ----
ggplot(IPC_DIEM, aes(x = factor(area_overall_phase), y = fies_rawscore_median)) +
  geom_boxplot() +
  labs(x = "IPC Phase", y = "FIES Median Raw Score", title = "Distribution of FIES raw score median values by IPC Phase") +
  theme_minimal()

ggplot(IPC_DIEM, aes(x = fies_rawscore_median, fill = factor(area_overall_phase))) +
  geom_density(alpha = 0.5) +
  labs(x = "FIES median raw scores", y = "Density", title = "Density Distribution of FIES Median values by IPC Phase", fill = "IPC Phase") +
  theme_minimal()




# ## Household hunger score


# ### HHS 3+ distribution (district med.)
# Percentage of households that resulted with Household Hunger Score equals to 3 or above.

# ---- hhs1 ----
IPC_DIEM_HHS <- IPC_DIEM  %>%
  select(iso3, adm_name,area_overall_phase, hhs_0:hhs_6) %>%
  rowwise() %>%
  mutate(
    hhs_3plusPercentage = sum(c_across(hhs_3:hhs_6), na.rm = TRUE)
  ) %>%
  select(iso3, adm_name,area_overall_phase, hhs_3plusPercentage)

IPC_DIEM_HHS %>%
  group_by(area_overall_phase) %>%
  summarize_column(hhs_3plusPercentage) %>%
  mutate(mean = round(mean, 1),
         sd = round(sd, 1)
         ) %>%
  gt() %>%
    tab_header(
    title = "Percentage of the population in HHS 3+ summarized by IPC phase"
  )

ggplot(IPC_DIEM_HHS, aes(x = hhs_3plusPercentage)) +
  geom_density(binwidth = 5, color = "black", alpha = 0.7) +
  labs(title = "Distribution of percentage in HHS 3+ across matched data",
       x = "Percentage of population in HHS 3+",
       y = "") +
  theme_minimal()

ggplot(IPC_DIEM_HHS, aes(x = factor(area_overall_phase), y = hhs_3plusPercentage)) +
  geom_boxplot() +
  labs(x = "IPC Phase", y = "Percentage of population in HHS 3+", title = "") +
  theme_minimal()

ggplot(IPC_DIEM_HHS, aes(x = hhs_3plusPercentage, fill = factor(area_overall_phase))) +
  geom_density(alpha = 0.5) +
  labs(x = "Percentage of population in HHS 3+", y = "Density", title = "Percentage of population in HHS 3+", fill = "IPC Phase") +
  theme_minimal()





# ### HHS summarized by phase (DIEM hh)

# ---- hhs1_hhlevel ----
IPCDIEM_hh %>%
  group_by(area_overall_phase) %>%
  summarize_column(hhs) %>%
  mutate(mean = round(mean, 1),
         sd = round(sd, 1)
         ) %>%
  gt() %>%
    tab_header(
    title = "HHS (from hh-level data) summarized by IPC phase"
  )

ggplot(IPCDIEM_hh, aes(x = hhs)) +
  geom_density(binwidth = 5, color = "black", alpha = 0.7) +
  labs(title = "Distribution HHS (from hh-level data) across matched data",
       x = "HHS",
       y = "") +
  theme_minimal()

ggplot(IPCDIEM_hh, aes(x = factor(area_overall_phase), y = hhs)) +
  geom_boxplot() +
  labs(x = "IPC Phase", y = "HHS", title = "") +
  theme_minimal()

ggplot(IPCDIEM_hh, aes(x = hhs, fill = factor(area_overall_phase))) +
  geom_density(alpha = 0.5) +
  labs(x = "HHS", y = "Density", title = "HHS by IPC phase (hh-level data)", fill = "IPC Phase") +
  theme_minimal()



# ## Household Dietary Diversity Score

# ### HDDS summarized by phase (district med.)
# Percentage of households that resulted with Household Dietary Diversity Score(HDDS) - Low dietary diversity

# ---- hdds ----
IPC_DIEM_HDDS <- IPC_DIEM  %>%
  select(iso3, adm_name,area_overall_phase, hdds_class_1, hdds_class_2, hdds_class_3, hdds_score_wmean) %>%
  mutate(hdds_class_1 = case_when(
    is.na(hdds_class_1) ~ 0, 
    TRUE ~ hdds_class_1
  )) %>%
    select(iso3, adm_name,area_overall_phase, hdds_class_1)


IPC_DIEM_HDDS %>%
  group_by(area_overall_phase) %>%
  summarize_column(hdds_class_1) %>%
  mutate(mean = round(mean, 1),
         sd = round(sd, 1)
         ) %>%
  gt() %>%
    tab_header(
    title = "Percentage of the population with low HDDS as defined in DIEM data"
  )

ggplot(IPC_DIEM_HDDS, aes(x = hdds_class_1)) +
  geom_density(binwidth = 5, color = "black", alpha = 0.7) +
  labs(title = "Distribution of percentage with low HDDS score",
       x = "Percentage of population with low HDDS score",
       y = "") +
  theme_minimal()

ggplot(IPC_DIEM_HDDS, aes(x = factor(area_overall_phase), y = hdds_class_1)) +
  geom_boxplot() +
  labs(x = "IPC Phase", y = "Percentage of population with low HDDS score", title = "") +
  theme_minimal()

ggplot(IPC_DIEM_HDDS, aes(x = hdds_class_1, fill = factor(area_overall_phase))) +
  geom_density(alpha = 0.5) +
  labs(x = "Percentage of population with low hdds score", y = "Density", title = "Percentage of population with low HDDS score", fill = "IPC Phase") +
  theme_minimal()


# v2 with just the score...........................................................................

IPC_DIEM_HDDS <- IPC_DIEM  %>%
  select(iso3, adm_name,area_overall_phase, hdds_score_wmean) 

IPC_DIEM_HDDS %>%
  group_by(area_overall_phase) %>%
  summarize_column(hdds_score_wmean) %>%
  mutate(mean = round(mean, 1),
         sd = round(sd, 1)
         ) %>%
  gt() %>%
    tab_header(
    title = "HHDS score summarized by IPC phase "
  )

ggplot(IPC_DIEM_HDDS, aes(x = hdds_score_wmean)) +
  geom_density(binwidth = 5, color = "black", alpha = 0.7) +
  labs(title = "Distribution of HHDS score",
       x = "",
       y = "") +
  theme_minimal()

ggplot(IPC_DIEM_HDDS, aes(x = factor(area_overall_phase), y = hdds_score_wmean)) +
  geom_boxplot() +
  labs(x = "IPC Phase", y = "HHDS score weighted mean", title = "") +
  theme_minimal()

ggplot(IPC_DIEM_HDDS, aes(x = hdds_score_wmean, fill = factor(area_overall_phase))) +
  geom_density(alpha = 0.5) +
  labs(x = "HHDS score weighted mean", y = "Density", title = "HHDS score", fill = "IPC Phase") +
  theme_minimal()



# ### HDDS by phase (DIEM hh)
# ---- hdds_hhlevel ----



IPCDIEM_hh %>%
  group_by(area_overall_phase) %>%
  summarize_column(hdds_score) %>%
  mutate(mean = round(mean, 1),
         sd = round(sd, 1)
         ) %>%
  gt() %>%
    tab_header(
    title = "HHDS score (from hh-level data) summarized by IPC phase "
  )

ggplot(IPCDIEM_hh, aes(x = hdds_score)) +
  geom_density(binwidth = 5, color = "black", alpha = 0.7) +
  labs(title = "Distribution of HHDS score (from hh-level data)",
       x = "",
       y = "") +
  theme_minimal()

ggplot(IPCDIEM_hh, aes(x = factor(area_overall_phase), y = hdds_score)) +
  geom_boxplot() +
  labs(x = "IPC Phase", y = "HHDS score", title = "") +
  theme_minimal()

ggplot(IPCDIEM_hh, aes(x = hdds_score, fill = factor(area_overall_phase))) +
  geom_density(alpha = 0.5) +
  labs(x = "HHDS score", y = "Density", title = "HHDS score (from hh-level data)", fill = "IPC Phase") +
  theme_minimal()
  


# ---- publishing ----

#deployApp(appName = "IPC_DIEM_Matching")



# # ======================================================
# # Indicators (hh) by IPC level - by country and year

# ## FCS - by country and year
# ---- FCSsummarizedAcrossYearAndCountry ----
fcs_byPhase_allObservations <- IPCDIEM_hh %>%
  group_by(area_overall_phase) %>%
  summarize_column(fcs) %>% ungroup() %>%
  mutate(mean = round(mean, 1),
         sd = round(sd, 1)
         ) %>%
  mutate(value = paste0(mean, " (", sd, ") ")) %>%
    select(area_overall_phase, variable, value) %>%
    pivot_wider(
    names_from = area_overall_phase,
    values_from = value,
      names_prefix = "IPC_"
  ) %>%
  mutate(variable = "fcs",
         adm0_name = "_all observations")  %>%
  select(adm0_name, variable, IPC_1, IPC_2, IPC_3, IPC_4 )


#now by country 
fcs_byPhase_byCountry <- IPCDIEM_hh %>%
  group_by(adm0_name, area_overall_phase) %>%
  summarize_column(fcs) %>% ungroup() %>%
  mutate(mean = round(mean, 1),
         sd = round(sd, 1)
         ) %>%
  mutate(value = paste0(mean, " (", sd, ") ")) %>%
    select(adm0_name, area_overall_phase, variable, value) %>%
    pivot_wider(
    names_from = area_overall_phase,
    values_from = value,
      names_prefix = "IPC_"
  ) %>%
  select(adm0_name, variable, IPC_1, IPC_2, IPC_3, IPC_4 )

fcs_acrossCountries <- bind_rows(fcs_byPhase_allObservations, fcs_byPhase_byCountry) %>%
  gt() %>%
    tab_header(
    title = "Food Consumption Scores (from hh-level data) summarized by IPC phase - across countries"
  ) 
fcs_acrossCountries

#now by year 
fcs_byPhase_byYear <- IPCDIEM_hh %>%
  # get year
  mutate(year_fromIPCAnalysis = year(country_analysis_date)) %>%
  group_by(year_fromIPCAnalysis, area_overall_phase) %>%
  summarize_column(fcs) %>% ungroup() %>%
  mutate(mean = round(mean, 1),
         sd = round(sd, 1)
         ) %>%
  mutate(value = paste0(mean, " (", sd, ") ")) %>%
    select(year_fromIPCAnalysis, area_overall_phase, variable, value) %>%
    pivot_wider(
    names_from = area_overall_phase,
    values_from = value,
      names_prefix = "IPC_"
  ) %>%
  mutate(year_fromIPCAnalysis = as.character(year_fromIPCAnalysis)) %>%
  select(year_fromIPCAnalysis, variable, IPC_1, IPC_2, IPC_3, IPC_4 )

fcs_acrossYears <- bind_rows(fcs_byPhase_allObservations %>% rename(
  year_fromIPCAnalysis = adm0_name), fcs_byPhase_byYear) %>%
  filter(year_fromIPCAnalysis != "2020") %>%
  gt() %>%
    tab_header(
    title = "Food Consumption Scores (from hh-level data) summarized by IPC phase - across years"
  )
fcs_acrossYears




# ## RCSI - by country and year
# ---- RCSIsummarizedAcrossYearAndCountry ----
rcsi_score_byPhase_allObservations <- IPCDIEM_hh %>%
  group_by(area_overall_phase) %>%
  summarize_column(rcsi_score) %>% ungroup() %>%
  mutate(mean = round(mean, 1),
         sd = round(sd, 1)
         ) %>%
  mutate(value = paste0(mean, " (", sd, ") ")) %>%
    select(area_overall_phase, variable, value) %>%
    pivot_wider(
    names_from = area_overall_phase,
    values_from = value,
      names_prefix = "IPC_"
  ) %>%
  mutate(variable = "rcsi_score",
         adm0_name = "_all observations")  %>%
  select(adm0_name, variable, IPC_1, IPC_2, IPC_3, IPC_4 )


#now by country 
rcsi_score_byPhase_byCountry <- IPCDIEM_hh %>%
  group_by(adm0_name, area_overall_phase) %>%
  summarize_column(rcsi_score) %>% ungroup() %>%
  mutate(mean = round(mean, 1),
         sd = round(sd, 1)
         ) %>%
  mutate(value = paste0(mean, " (", sd, ") ")) %>%
    select(adm0_name, area_overall_phase, variable, value) %>%
    pivot_wider(
    names_from = area_overall_phase,
    values_from = value,
      names_prefix = "IPC_"
  ) %>%
  select(adm0_name, variable, IPC_1, IPC_2, IPC_3, IPC_4 )

rcsi_score_acrossCountries <- bind_rows(rcsi_score_byPhase_allObservations, rcsi_score_byPhase_byCountry) %>%
  gt() %>%
    tab_header(
    title = "rcsi_score (from hh-level data) summarized by IPC phase - across countries"
  ) 
rcsi_score_acrossCountries


#now by year 
rcsi_score_byPhase_byYear <- IPCDIEM_hh %>%
  # get year
  mutate(year_fromIPCAnalysis = year(country_analysis_date)) %>%
  group_by(year_fromIPCAnalysis, area_overall_phase) %>%
  summarize_column(rcsi_score) %>% ungroup() %>%
  mutate(mean = round(mean, 1),
         sd = round(sd, 1)
         ) %>%
  mutate(value = paste0(mean, " (", sd, ") ")) %>%
    select(year_fromIPCAnalysis, area_overall_phase, variable, value) %>%
    pivot_wider(
    names_from = area_overall_phase,
    values_from = value,
      names_prefix = "IPC_"
  ) %>%
  mutate(year_fromIPCAnalysis = as.character(year_fromIPCAnalysis)) %>%
  select(year_fromIPCAnalysis, variable, IPC_1, IPC_2, IPC_3, IPC_4 )

rcsi_score_acrossYears <- bind_rows(rcsi_score_byPhase_allObservations %>% rename(
  year_fromIPCAnalysis = adm0_name), rcsi_score_byPhase_byYear) %>%
  filter(year_fromIPCAnalysis != "2020") %>%
  gt() %>%
    tab_header(
    title = "rcsi_score (from hh-level data) summarized by IPC phase - across years"
  ) 
rcsi_score_acrossYears




# ## hdds_score - by country and year
# ---- hdds_scoresummarizedAcrossYearAndCountry ----
hdds_score_byPhase_allObservations <- IPCDIEM_hh %>%
  group_by(area_overall_phase) %>%
  summarize_column(hdds_score) %>% ungroup() %>%
  mutate(mean = round(mean, 1),
         sd = round(sd, 1)
         ) %>%
  mutate(value = paste0(mean, " (", sd, ") ")) %>%
    select(area_overall_phase, variable, value) %>%
    pivot_wider(
    names_from = area_overall_phase,
    values_from = value,
      names_prefix = "IPC_"
  ) %>%
  mutate(variable = "hdds_score",
         adm0_name = "_all observations")  %>%
  select(adm0_name, variable, IPC_1, IPC_2, IPC_3, IPC_4 )


#now by country 
hdds_score_byPhase_byCountry <- IPCDIEM_hh %>%
  group_by(adm0_name, area_overall_phase) %>%
  summarize_column(hdds_score) %>% ungroup() %>%
  mutate(mean = round(mean, 1),
         sd = round(sd, 1)
         ) %>%
  mutate(value = paste0(mean, " (", sd, ") ")) %>%
    select(adm0_name, area_overall_phase, variable, value) %>%
    pivot_wider(
    names_from = area_overall_phase,
    values_from = value,
      names_prefix = "IPC_"
  ) %>%
  select(adm0_name, variable, IPC_1, IPC_2, IPC_3, IPC_4 )

hdds_score_acrossCountries <- bind_rows(hdds_score_byPhase_allObservations, hdds_score_byPhase_byCountry) %>%
  gt() %>%
    tab_header(
    title = "hdds_score (from hh-level data) summarized by IPC phase - across countries"
  ) 
hdds_score_acrossCountries


#now by year 
hdds_score_byPhase_byYear <- IPCDIEM_hh %>%
  # get year
  mutate(year_fromIPCAnalysis = year(country_analysis_date)) %>%
  group_by(year_fromIPCAnalysis, area_overall_phase) %>%
  summarize_column(hdds_score) %>% ungroup() %>%
  mutate(mean = round(mean, 1),
         sd = round(sd, 1)
         ) %>%
  mutate(value = paste0(mean, " (", sd, ") ")) %>%
    select(year_fromIPCAnalysis, area_overall_phase, variable, value) %>%
    pivot_wider(
    names_from = area_overall_phase,
    values_from = value,
      names_prefix = "IPC_"
  ) %>%
  mutate(year_fromIPCAnalysis = as.character(year_fromIPCAnalysis)) %>%
  select(year_fromIPCAnalysis, variable, IPC_1, IPC_2, IPC_3, IPC_4 )

hdds_score_acrossYears <- bind_rows(hdds_score_byPhase_allObservations %>% rename(
  year_fromIPCAnalysis = adm0_name), hdds_score_byPhase_byYear) %>%
  filter(year_fromIPCAnalysis != "2020") %>%
  gt() %>%
    tab_header(
    title = "hdds_score (from hh-level data) summarized by IPC phase - across years"
  ) 
hdds_score_acrossYears



# ## HHS - by country and year
# ---- HHSsummarizedAcrossYearAndCountry ----
hhs_byPhase_allObservations <- IPCDIEM_hh %>%
  group_by(area_overall_phase) %>%
  summarize_column(hhs) %>% ungroup() %>%
  mutate(mean = round(mean, 1),
         sd = round(sd, 1)
         ) %>%
  mutate(value = paste0(mean, " (", sd, ") ")) %>%
    select(area_overall_phase, variable, value) %>%
    pivot_wider(
    names_from = area_overall_phase,
    values_from = value,
      names_prefix = "IPC_"
  ) %>%
  mutate(variable = "hhs",
         adm0_name = "_all observations")  %>%
  select(adm0_name, variable, IPC_1, IPC_2, IPC_3, IPC_4 )


#now by country 
hhs_byPhase_byCountry <- IPCDIEM_hh %>%
  group_by(adm0_name, area_overall_phase) %>%
  summarize_column(hhs) %>% ungroup() %>%
  mutate(mean = round(mean, 1),
         sd = round(sd, 1)
         ) %>%
  mutate(value = paste0(mean, " (", sd, ") ")) %>%
    select(adm0_name, area_overall_phase, variable, value) %>%
    pivot_wider(
    names_from = area_overall_phase,
    values_from = value,
      names_prefix = "IPC_"
  ) %>%
  select(adm0_name, variable, IPC_1, IPC_2, IPC_3, IPC_4 )

hhs_acrossCountries <- bind_rows(hhs_byPhase_allObservations, hhs_byPhase_byCountry) %>%
  gt() %>%
    tab_header(
    title = "HHS Scores (from hh-level data) summarized by IPC phase - across countries"
  ) 
hhs_acrossCountries


#now by year 
hhs_byPhase_byYear <- IPCDIEM_hh %>%
  # get year
  mutate(year_fromIPCAnalysis = year(country_analysis_date)) %>%
  group_by(year_fromIPCAnalysis, area_overall_phase) %>%
  summarize_column(hhs) %>% ungroup() %>%
  mutate(mean = round(mean, 1),
         sd = round(sd, 1)
         ) %>%
  mutate(value = paste0(mean, " (", sd, ") ")) %>%
    select(year_fromIPCAnalysis, area_overall_phase, variable, value) %>%
    pivot_wider(
    names_from = area_overall_phase,
    values_from = value,
      names_prefix = "IPC_"
  ) %>%
  mutate(year_fromIPCAnalysis = as.character(year_fromIPCAnalysis)) %>%
  select(year_fromIPCAnalysis, variable, IPC_1, IPC_2, IPC_3, IPC_4 )

hhs_acrossYears <- bind_rows(hhs_byPhase_allObservations %>% rename(
  year_fromIPCAnalysis = adm0_name), hhs_byPhase_byYear) %>%
  filter(year_fromIPCAnalysis != "2020") %>%
  gt() %>%
    tab_header(
    title = "HHS Scores (from hh-level data) summarized by IPC phase - across years"
  )
hhs_acrossYears



# # ======================================================
# # CORRELATION B/W INDICATORS

# ## Descriptives of DIEM data only (not matched to IPC phase)

# ### hh-level diem
# ---- summarizehhDIEM ----

#DIEM_FoodSecurity_HH %>%
 #  select(area_overall_phase, fies_rawscore_wmean, fcs_wmean, rcsi_score_wmean, hhs_3:hhs_6) %>%
 # rowwise() %>%
 #  mutate(
 #    hhs_3plusPercentage = sum(c_across(hhs_3:hhs_6), na.rm = TRUE)
 #  ) %>%
 #  ungroup() %>% 
 #  select(-(hhs_3: hhs_6)) %>%
 #  pivot_longer(everything(), names_to = "indicator", values_to = "value") %>%
 #  group_by(indicator) %>%
 #  summarise(
 #    mean    = mean(value, na.rm = TRUE),
 #    median  = median(value, na.rm = TRUE),
 #    min     = min(value, na.rm = TRUE),
 #    max     = max(value, na.rm = TRUE),
 #    q25     = quantile(value, 0.25, na.rm = TRUE),
 #    q75     = quantile(value, 0.75, na.rm = TRUE),
 #    missing = sum(is.na(value)),
 #    .groups = "drop"
 #  )



# ## Compare IPCDIEM data hh-level district-level

# ### Describing indicators (DIEM district)
# ---- correlation ----
IPC_DIEM %>%
  select(area_overall_phase, fies_rawscore_wmean, fcs_wmean, rcsi_score_wmean, hhs_3:hhs_6) %>%
 rowwise() %>%
  mutate(
    hhs_3plusPercentage = sum(c_across(hhs_3:hhs_6), na.rm = TRUE)
  ) %>%
  ungroup() %>% 
  select(-(hhs_3: hhs_6)) %>%
  group_by(area_overall_phase) %>%
  summarise(
    mean_fcs = mean(fcs_wmean, na.rm = TRUE),
    sd_fcs = sd(fcs_wmean, na.rm = TRUE),
    mean_rcsi = mean(rcsi_score_wmean, na.rm = TRUE),
    sd_rcsi = sd(rcsi_score_wmean, na.rm = TRUE),
    mean_hhs = mean(hhs_3plusPercentage, na.rm = TRUE),
    sd_hhs = sd(hhs_3plusPercentage, na.rm = TRUE),
    mean_fies = mean(fies_rawscore_wmean, na.rm = TRUE),
    sd_fies = sd(fies_rawscore_wmean, na.rm = TRUE)
    ) %>%
  mutate(
    fies = sprintf("%.2f (%.2f)", mean_fies, sd_fies),
    fcs = sprintf("%.2f (%.2f)", mean_fcs, sd_fcs),
    rcsi = sprintf("%.2f (%.2f)", mean_rcsi, sd_rcsi),
    "hhs_pct3+" = sprintf("%.2f (%.2f)", mean_hhs, sd_hhs),
  ) %>%
  select(area_overall_phase, fcs, rcsi, `hhs_pct3+`, fies) %>%
  gt() %>%
    tab_header(
    title = "Indicator district means summarized - among districts matched to IPC phases"
  ) %>%
  tab_options(table.font.size = px(12)) %>%
  tab_footnote(
    footnote = "SD shown in parentheses."
  )


# now summarizing in more depth............................
IPC_DIEM %>%
  select(area_overall_phase, fies_rawscore_wmean, fcs_wmean, rcsi_score_wmean, hhs_3:hhs_6) %>%
 rowwise() %>%
  mutate(
    hhs_3plusPercentage = sum(c_across(hhs_3:hhs_6), na.rm = TRUE)
  ) %>%
  ungroup() %>% 
  select(-(hhs_3: hhs_6)) %>%
  pivot_longer(everything(), names_to = "indicator", values_to = "value") %>%
  group_by(indicator) %>%
  summarise(
    mean    = mean(value, na.rm = TRUE),
    median  = median(value, na.rm = TRUE),
    min     = min(value, na.rm = TRUE),
    max     = max(value, na.rm = TRUE),
    q25     = quantile(value, 0.25, na.rm = TRUE),
    q75     = quantile(value, 0.75, na.rm = TRUE),
    missing = sum(is.na(value)),
    .groups = "drop"
  )





# ### Describing indicators (DIEM hh)
# ---- correlation_hh ----

IPCDIEM_hh %>%
  select(area_overall_phase, fcs, rcsi_score, hhs, hdds_score) %>%
  ungroup() %>% 
  group_by(area_overall_phase) %>%
   summarize(
    mean_fcs = mean(fcs, na.rm = TRUE),
    sd_fcs = sd(fcs, na.rm = TRUE),
    mean_rcsi = mean(rcsi_score, na.rm = TRUE),
    sd_rcsi = sd(rcsi_score, na.rm = TRUE),
    mean_hdds = mean(hdds_score, na.rm = TRUE),
    sd_hdds = sd(hdds_score, na.rm = TRUE),
    mean_hhs = mean(hhs, na.rm = TRUE),
    sd_hhs = sd(hhs, na.rm = TRUE)  
    )%>%
  mutate(
    fcs = sprintf("%.2f (%.2f)", mean_fcs, sd_fcs),
    rcsi = sprintf("%.2f (%.2f)", mean_rcsi, sd_rcsi),
    hhs = sprintf("%.2f (%.2f)", mean_hhs, sd_hhs),
    hdds = sprintf("%.2f (%.2f)", mean_hdds, sd_hdds)
  ) %>%
  select(area_overall_phase, fcs, rcsi, hhs, hdds) %>%
  gt() %>%
    tab_header(
    title = "Indicator means (from hh-level data) summarized - among districts matched to IPC phases"
  ) %>%
  tab_options(table.font.size = px(12)) %>%
  tab_footnote(
    footnote = "SD shown in parentheses."
  )
#IPCDIEM_hh

# now further summary........................
IPCDIEM_hh %>%
  select(fcs, rcsi_score, hhs, hdds_score) %>%
  pivot_longer(everything(), names_to = "indicator", values_to = "value") %>%
  group_by(indicator) %>%
  summarise(
    mean    = mean(value, na.rm = TRUE),
    median  = median(value, na.rm = TRUE),
    min     = min(value, na.rm = TRUE),
    max     = max(value, na.rm = TRUE),
    q25     = quantile(value, 0.25, na.rm = TRUE),
    q75     = quantile(value, 0.75, na.rm = TRUE),
    missing = sum(is.na(value)),
    .groups = "drop"
  )


# ---- sum_normalized ----
# Table 6: Raw indicator means and SDs by IPC phase (household level, deduplicated by OBJECTID)
toShow_base <- IPCDIEM_hh %>%
  select(OBJECTID, area_overall_phase, fcs, hdds_score, rcsi_score,
         any_of("fies_rawscore"), hhs) %>%
  ungroup()

# Add FIES column of NAs if not present in dataset
if (!"fies_rawscore" %in% names(toShow_base)) {
  toShow_base <- toShow_base %>% mutate(fies_rawscore = NA_real_)
}

fmt_mean_sd <- function(m, s) {
  ifelse(is.na(m), "n.a.", sprintf("%.1f (%.1f)", m, s))
}

toShow_stats <- toShow_base %>%
  mutate(area_overall_phase = as.character(area_overall_phase)) %>%
  group_by(area_overall_phase) %>%
  summarize(
    fcs_mean  = round(mean(fcs,          na.rm = TRUE), 1),
    fcs_sd    = round(sd(fcs,            na.rm = TRUE), 1),
    hdds_mean = round(mean(hdds_score,   na.rm = TRUE), 1),
    hdds_sd   = round(sd(hdds_score,     na.rm = TRUE), 1),
    rcsi_mean = round(mean(rcsi_score,   na.rm = TRUE), 1),
    rcsi_sd   = round(sd(rcsi_score,     na.rm = TRUE), 1),
    fies_mean = round(mean(fies_rawscore,na.rm = TRUE), 1),
    fies_sd   = round(sd(fies_rawscore,  na.rm = TRUE), 1),
    hhs_mean  = round(mean(hhs,          na.rm = TRUE), 1),
    hhs_sd    = round(sd(hhs,            na.rm = TRUE), 1),
    .groups = "drop"
  ) %>%
  bind_rows(
    toShow_base %>%
      summarize(
        area_overall_phase = "Overall",
        fcs_mean  = round(mean(fcs,          na.rm = TRUE), 1),
        fcs_sd    = round(sd(fcs,            na.rm = TRUE), 1),
        hdds_mean = round(mean(hdds_score,   na.rm = TRUE), 1),
        hdds_sd   = round(sd(hdds_score,     na.rm = TRUE), 1),
        rcsi_mean = round(mean(rcsi_score,   na.rm = TRUE), 1),
        rcsi_sd   = round(sd(rcsi_score,     na.rm = TRUE), 1),
        fies_mean = round(mean(fies_rawscore,na.rm = TRUE), 1),
        fies_sd   = round(sd(fies_rawscore,  na.rm = TRUE), 1),
        hhs_mean  = round(mean(hhs,          na.rm = TRUE), 1),
        hhs_sd    = round(sd(hhs,            na.rm = TRUE), 1)
      )
  )

toShow <- toShow_stats %>%
  mutate(
    FCS         = fmt_mean_sd(fcs_mean,  fcs_sd),
    HDDS        = fmt_mean_sd(hdds_mean, hdds_sd),
    rCSI        = fmt_mean_sd(rcsi_mean, rcsi_sd),
    `FIES (raw score)` = fmt_mean_sd(fies_mean, fies_sd),
    HHS         = fmt_mean_sd(hhs_mean,  hhs_sd)
  ) %>%
  select(area_overall_phase, FCS, HDDS, rCSI, `FIES (raw score)`, HHS) %>%
  bind_rows(
    tibble(
      area_overall_phase = "Threshold",
      FCS  = "35", HDDS = "3", rCSI = "19",
      `FIES (raw score)` = "n.a.", HHS = "3"
    )
  ) %>%
  rename("IPC Phase" = area_overall_phase)

toShow %>%
  gt() %>%
  tab_header(title = "Table 6: Indicator means by IPC phase (household level, raw values)") %>%
  tab_options(table.font.size = px(12)) %>%
  tab_footnote(footnote = "Mean (SD). FIES available for 2023+ data only.")

write_paper_table(
  toShow,
  file.path(finalTablesFolder, "Table6_indicator_means_by_phase.xlsx"),
  footnote = "Mean (SD). FIES available for 2023+ data only."
)







# ## Correlations (DIEM hh)

# ### All observations

# ---- cor_entirehhdata ----
variablesForCorrelation <- DIEM_FoodSecurity_HH %>% 
  select(fcs:rcsi_score)   %>% select(-lcsi)
  
variablesForCorrelation <- na.omit(variablesForCorrelation)
# Calculate Spearman correlation matrix
cor_spearman <- cor(variablesForCorrelation, method = "spearman") %>%
   as.data.frame() %>%
  rownames_to_column("Variable") 

cor_spearman%>%
  gt() %>%
  fmt_number(columns = where(is.numeric), decimals = 2) %>%
    tab_header(
    title = md("**Spearman Correlation Matrix - all observations (DIEM hh)**")) %>%
  print()


#export to its own excel file.............................

tableForPaper<- cor_spearman

write_paper_table(cor_spearman, file.path(outputVizInOutputFolder, "correlations_household_allData.xlsx"))







# ###All observations (2023+ data)
# This is so that we can include FIES in the correlation matrix
# ---- cor_entirehhdata_2023+ ----

# Countries included in household-level correlation (Table7)
cat("Countries in household-level correlation (Table7):\n")
DIEM_FoodSecurity_HHPost2022 %>%
  select(adm0_name) %>% distinct() %>%
  arrange(adm0_name) %>% pull(adm0_name) %>% paste(collapse = ", ") %>% cat("\n")

variablesForCorrelation <- DIEM_FoodSecurity_HHPost2022 %>%
  select(fies_rawscore, fcs, rcsi_score, hdds_score, hhs) %>%
  rename(
    "FIES raw score"         = fies_rawscore,
    "Food consumption score" = fcs,
    "rCSI score"             = rcsi_score,
    "HDDS score"             = hdds_score,
    "HHS score"              = hhs
  )

variablesForCorrelation <- na.omit(variablesForCorrelation)
# Calculate Spearman correlation matrix
cor_spearman <- cor(variablesForCorrelation, method = "spearman") %>%
   as.data.frame() %>%
  rownames_to_column("Variable")

cor_spearman%>%
  gt() %>%
  fmt_number(columns = where(is.numeric), decimals = 2) %>%
    tab_header(
    title = md("**Spearman Correlation Matrix - all observations (DIEM hh)**")) %>%
  print()


#export to excel............................

tableForPaper <- cor_spearman

write_correlation_table(tableForPaper, file.path(finalTablesFolder, "Table5b_correlations_household.xlsx"))




# ### All obs. - normalized

# Now with all of the values normalized as so:
# $$
# \text{Dimension index} = \frac{\text{actual value} - \text{minimum value}}{\text{maximum value} - \text{minimum value}}
# $$

# ---- cor_entirehhdata_normalized ----
variablesForCorrelation <- DIEM_FoodSecurity_HH %>% 
  mutate(id = paste(OBJECTID, survey_id)) %>% 
  select(id, fcs:rcsi_score)  %>%
    pivot_longer(
    cols = 2:last_col(), 
    names_to = "indicator", 
    values_to = "value"
  ) %>%
    group_by(indicator) %>%
  mutate(
    max_value = max(value, na.rm = TRUE),
    min_value = min(value, na.rm = TRUE)
  ) %>% ungroup() %>%
  mutate(value_normalized = case_when(
    indicator %in% c("lcsi", "hhs", "rcsi_score") ~ (value - min_value)/(max_value-min_value),
    indicator %in% c("fcs", "hdds_score") ~ (value - max_value)/(min_value-max_value),
    TRUE ~ -999999999)
  ) %>%
  select(id, indicator, value_normalized) %>%
  pivot_wider(
    names_from = indicator,
    values_from = value_normalized
  )  %>% select(-id)
  
variablesForCorrelation <- na.omit(variablesForCorrelation)
# Calculate Spearman correlation matrix
cor_spearman <- cor(variablesForCorrelation, method = "spearman") %>%
   as.data.frame() %>%
  rownames_to_column("Variable") %>%
  gt() %>%
  fmt_number(columns = where(is.numeric), decimals = 2) %>%
    tab_header(
    title = md("**Spearman Correlation Matrix - all observations (DIEM hh) normalized values**")) %>%
  print()

#cor(variablesForCorrelation$fcs,variablesForCorrelation$hhs )




# ### By country
# ---- cor_entirehhdata_byCountry ----

# Assuming your main data has `admin0` and the food security vars
admin_list <- unique(DIEM_FoodSecurity_HH$adm0_name)

# Build multi-sheet workbook for per-country correlations
wb_country_corr <- createWorkbook()

# Styles for conditional shading (matching write_correlation_table)
cc_header  <- createStyle(textDecoration = "bold", halign = "center", valign = "center",
                          wrapText = TRUE, fontName = "Times New Roman", fontSize = 9,
                          border = "TopBottomLeftRight", borderStyle = "thin")
cc_first   <- createStyle(halign = "left", valign = "center", fontName = "Times New Roman", fontSize = 9,
                          border = "TopBottomLeftRight", borderStyle = "thin")
cc_green   <- createStyle(halign = "center", valign = "center", fontName = "Times New Roman", fontSize = 9,
                          border = "TopBottomLeftRight", borderStyle = "thin", fgFill = "#CCFFCC")
cc_yellow  <- createStyle(halign = "center", valign = "center", fontName = "Times New Roman", fontSize = 9,
                          border = "TopBottomLeftRight", borderStyle = "thin", fgFill = "#FFFF99")
cc_red     <- createStyle(halign = "center", valign = "center", fontName = "Times New Roman", fontSize = 9,
                          border = "TopBottomLeftRight", borderStyle = "thin", fgFill = "#FFCCCC")
cc_plain   <- createStyle(halign = "center", valign = "center", fontName = "Times New Roman", fontSize = 9,
                          border = "TopBottomLeftRight", borderStyle = "thin")

for (adm in admin_list) {
  message("Processing: ", adm)

  # Filter for this admin0
  data_sub <- DIEM_FoodSecurity_HH %>%
    filter(adm0_name == adm) %>%
    select(fcs:rcsi_score) %>%
    select(-lcsi) %>%
    na.omit()

  # Skip empty subsets
  if (nrow(data_sub) == 0) next

  # Compute correlation
  cor_df <- cor(data_sub, method = "spearman") %>%
    as.data.frame() %>%
    rownames_to_column("Variable") %>%
    mutate(across(where(is.numeric), ~round(., 3)))

  # Print gt table
  cor_df %>%
    gt() %>%
    fmt_number(columns = where(is.numeric), decimals = 2) %>%
    tab_header(title = md(paste0("**Spearman Correlation Matrix – ", adm, "**"))) %>%
    print()

  # Add sheet (Excel sheet names max 31 chars)
  sheet_name <- substr(adm, 1, 31)
  addWorksheet(wb_country_corr, sheet_name)
  writeData(wb_country_corr, sheet = sheet_name, x = cor_df, startRow = 1, colNames = TRUE)
  addStyle(wb_country_corr, sheet = sheet_name, style = cc_header,
           rows = 1, cols = 1:ncol(cor_df), gridExpand = TRUE)
  addStyle(wb_country_corr, sheet = sheet_name, style = cc_first,
           rows = 2:(nrow(cor_df) + 1), cols = 1)
  for (col_idx in 2:ncol(cor_df)) {
    for (row_idx in seq_len(nrow(cor_df))) {
      val <- cor_df[[col_idx]][row_idx]
      sty <- if (is.na(val) || val == 1) cc_plain else if (abs(val) > 0.6) cc_green else if (abs(val) >= 0.4) cc_yellow else cc_red
      addStyle(wb_country_corr, sheet = sheet_name, style = sty, rows = row_idx + 1, cols = col_idx)
    }
  }
  setColWidths(wb_country_corr, sheet = sheet_name, cols = 1:ncol(cor_df), widths = 15)
}

saveWorkbook(wb_country_corr,
             file.path(finalTablesFolder, "Table_other_2_correlations_by_country.xlsx"),
             overwrite = TRUE)





# ### Table FCS-other indic corr. by country

# ---- cor_fcs_bycountry ----

variablesForCorrelation <- DIEM_FoodSecurity_HH %>% 
  select(fcs:rcsi_score)  
  
variablesForCorrelation <- na.omit(variablesForCorrelation)
# Calculate Spearman correlation matrix
cor_spearmanfcs_all <- cor(variablesForCorrelation, method = "spearman") %>%
   as.data.frame() %>%
  rownames_to_column("Variable") %>%
  slice(1) %>%
  mutate(filter = "All observations") %>%
  select(filter, everything()) %>% select(-Variable)


# Define the country list
admin_list <- unique(DIEM_FoodSecurity_HH$adm0_name)

# Initialize an empty list to store results
cor_list <- list()

# ---- All observations ----
variablesForCorrelation <- DIEM_FoodSecurity_HH %>% 
  select(fcs:rcsi_score) %>% 
  na.omit()

if (nrow(variablesForCorrelation) > 0) {
  cor_all <- cor(variablesForCorrelation, method = "spearman") %>%
    as.data.frame() %>%
    rownames_to_column("Variable") %>%
    slice(1) %>%  # take the first row
    mutate(filter = "_all observations") %>%
    select(filter, everything(), -Variable)
  
  cor_list[["_all observations"]] <- cor_all
}

# ---- Per country ----
for (adm in admin_list) {
  message("Processing: ", adm)
  
  data_sub <- DIEM_FoodSecurity_HH %>%
    filter(adm0_name == adm) %>%
    select(fcs:rcsi_score) %>%
    na.omit()
  
  # Skip if no data
  if (nrow(data_sub) == 0) next
  
  cor_sub <- cor(data_sub, method = "spearman") %>%
    as.data.frame() %>%
    rownames_to_column("Variable") %>%
    slice(1) %>%
    mutate(filter = adm) %>%
    select(filter, everything(), -Variable)
  
  cor_list[[adm]] <- cor_sub
  
}

# ---- Combine all correlation results ----
cor_spearman_allCountries <- bind_rows(cor_list) %>%
  arrange(filter) %>%
  gt() %>%
   tab_header(
    title = "Cor FCS and other indicators - by country"
  ) 

cor_spearman_allCountries  



# ### Table FCS-other indic corr. by year

# ---- cor_fcs_byyear ----

DIEM_FoodSecurity_HH_uniqueYears <- DIEM_FoodSecurity_HH %>%
  mutate(year = year(survey_date)) %>%
  arrange(year)

# Define the list of unique years
year_list <- unique(DIEM_FoodSecurity_HH_uniqueYears$year)

# Initialize an empty list to store correlation results
cor_list <- list()

# ---- All observations ----
variablesForCorrelation <- DIEM_FoodSecurity_HH_uniqueYears %>%
  select(fcs:rcsi_score) %>%
  na.omit()

if (nrow(variablesForCorrelation) > 0) {
  cor_all <- cor(variablesForCorrelation, method = "spearman") %>%
    as.data.frame() %>%
    rownames_to_column("Variable") %>%
    slice(1) %>%  # take the first row only
    mutate(filter = "_all observations") %>%
    select(filter, everything(), -Variable)
  
  cor_list[["_all observations"]] <- cor_all
}

# ---- Per year ----
for (yr in year_list) {
  message("Processing year: ", yr)
  
  data_sub <- DIEM_FoodSecurity_HH_uniqueYears %>%
    filter(year == yr) %>%
    select(fcs:rcsi_score) %>%
    na.omit()
  
  # Skip if no data
  if (nrow(data_sub) == 0) next
  
  cor_sub <- cor(data_sub, method = "spearman") %>%
    as.data.frame() %>%
    rownames_to_column("Variable") %>%
    slice(1) %>%
    mutate(filter = as.character(yr)) %>%
    select(filter, everything(), -Variable)
  
  cor_list[[as.character(yr)]] <- cor_sub
}

# ---- Combine all correlation results ----
cor_spearman_byYear <- bind_rows(cor_list) %>%
  arrange(filter) %>%
  gt() %>%
  tab_header(
    title = "Spearman Correlation of FCS and Other Indicators — by Year"
  )

# View table
cor_spearman_byYear



# ## Simple correlations (pearson and normalized)

# ---- simpleCorrelationsPearson ----

variablesForCorrelation <- DIEM_FoodSecurity_HH %>% 
  mutate(id = paste(OBJECTID, survey_id)) %>% 
  select(id, fcs:rcsi_score)  %>%
    pivot_longer(
    cols = 2:last_col(), 
    names_to = "indicator", 
    values_to = "value"
  ) %>%
    group_by(indicator) %>%
  mutate(
    max_value = max(value, na.rm = TRUE),
    min_value = min(value, na.rm = TRUE)
  ) %>% ungroup() %>%
  mutate(value_normalized = case_when(
    indicator %in% c("lcsi", "hhs", "rcsi_score") ~ (value - min_value)/(max_value-min_value),
    indicator %in% c("fcs", "hdds_score") ~ (value - max_value)/(min_value-max_value),
    TRUE ~ -999999999)
  ) %>%
  select(id, indicator, value_normalized) %>%
  pivot_wider(
    names_from = indicator,
    values_from = value_normalized
  )  %>% select(-id)
  
variablesForCorrelation <- na.omit(variablesForCorrelation)
# Calculate pearson correlation matrix
cor_spearman <- cor(variablesForCorrelation, method = "pearson") %>%
   as.data.frame() %>%
  rownames_to_column("Variable") %>%
  gt() %>%
  fmt_number(columns = where(is.numeric), decimals = 2) %>%
    tab_header(
    title = md("**Pearson Correlation Matrix - all observations (DIEM hh) normalized values**")) %>%
  print()
  


# ## Correlations (DIEM district-level means) 

# This includes the entire DIAM dataset - so these are all district level values, not just those that are matched to IPC phase. This is the Sprearman rank correlation.
# ---- correlation2 ----

# Countries included in district-level correlation (Table6)
cat("Countries in district-level correlation (Table6):\n")
DIEM_FoodSecurityImported %>%
  select(iso3) %>% distinct() %>%
  mutate(country = countrycode(iso3, origin = "iso3c", destination = "country.name")) %>%
  arrange(country) %>% pull(country) %>% paste(collapse = ", ") %>% cat("\n")

variablesForCorrelation <- DIEM_FoodSecurityImported %>%
  select(fies_rawscore_wmean, #p_mod_wmean, 
         fcs_wmean, rcsi_score_wmean, hdds_score_wmean,hhs_3: hhs_6)  %>%
   rowwise() %>%
  mutate(
    hhs_3plusPercentage = sum(c_across(hhs_3:hhs_6), na.rm = TRUE)
  ) %>%
  ungroup() %>% 
  select(-(hhs_3: hhs_6))  %>%
    select(fcs_wmean, hhs_3plusPercentage, hdds_score_wmean, rcsi_score_wmean, fies_rawscore_wmean
         ) %>%
  rename(
    fiesRaw_wmean = fies_rawscore_wmean,
    #FIES_shareMod = p_mod_wmean,
         rcsi_wmean = rcsi_score_wmean,
         hdds_wmean = hdds_score_wmean
         )
variablesForCorrelation <- na.omit(variablesForCorrelation)
# Calculate Spearman correlation matrix
cor_spearman <- cor(variablesForCorrelation, method = "spearman")
print(cor_spearman) 

tableForPaper <- cor_spearman %>% as.data.frame() %>%
    rownames_to_column(var = "variable")

write_correlation_table(tableForPaper, file.path(outputVizInOutputFolder, "Table6_correlations_district.xlsx"))


# ## Correlations (DIEM district-level means post 2022) 

# These are the correlations of the district variables post 2022 to align with the hh version with FIEWS
# ---- correlation_post2022_district ----
variablesForCorrelation <- DIEM_FoodSecurityImported %>% 
  filter(coll_start_date> "2022-12-31" ) %>%
  select(fies_rawscore_wmean, #p_mod_wmean, 
         fcs_wmean, rcsi_score_wmean, hdds_score_wmean,hhs_3: hhs_6)  %>%
   rowwise() %>%
  mutate(
    hhs_3plusPercentage = sum(c_across(hhs_3:hhs_6), na.rm = TRUE)
  ) %>%
  ungroup() %>% 
  select(-(hhs_3: hhs_6))  %>%
  select(fcs_wmean, hhs_3plusPercentage, hdds_score_wmean, rcsi_score_wmean, fies_rawscore_wmean
         ) %>%
  rename(
    fiesRaw_wmean = fies_rawscore_wmean,
   # FIES_shareMod = p_mod_wmean,
         rcsi_wmean = rcsi_score_wmean,
         hdds_wmean = hdds_score_wmean
         )
variablesForCorrelation <- na.omit(variablesForCorrelation)
# Calculate Spearman correlation matrix
cor_spearman <- cor(variablesForCorrelation, method = "spearman")
print(cor_spearman) 

tableForPaper <- cor_spearman %>% as.data.frame() %>%
    rownames_to_column(var = "variable")

write_paper_table(tableForPaper, file.path(outputVizInOutputFolder, "table_correlations_district_post2022.xlsx"))





# ## Old versions
# Correlations among indic. - matched to IPC phase and including only phases 3+

# Here I look into correlation between indicators for districts that are in phase 3+
#     
# ---- correlation3 ----
variablesForCorrelation <- IPC_DIEM %>% 
    select(fies_rawscore_wmean,# p_mod_wmean, 
         fcs_wmean, rcsi_score_wmean, hdds_score_wmean, area_overall_phase, hhs_3: hhs_6) %>%
   rowwise() %>%
  mutate(
    hhs_3plusPercentage = sum(c_across(hhs_3:hhs_6), na.rm = TRUE)
  ) %>%
  ungroup() %>% 
  select(-(hhs_3: hhs_6))  %>%  
  filter(area_overall_phase %in% c(3,4)) %>% select(-area_overall_phase) %>%
    rename(
          fiesRaw_wmean = fies_rawscore_wmean,
         rcsi_wmean = rcsi_score_wmean,
         hdds_wmean = hdds_score_wmean
         )
variablesForCorrelation <- na.omit(variablesForCorrelation)
# Calculate Spearman correlation matrix
cor_spearman <- cor(variablesForCorrelation, method = "spearman")
print(cor_spearman)



# Correlations among indic. - w/ IPC phase
# Here I include IPC phase as a variable for the Spearman rank correlation (IPC phase = 1,2,3,4,5)

# ---- correlation4 ----
variablesForCorrelation <- IPC_DIEM %>%
    select(fies_rawscore_wmean,# p_mod_wmean, 
         fcs_wmean, rcsi_score_wmean, hdds_score_wmean, area_overall_phase, hhs_3: hhs_6) %>%
   rowwise() %>%
  mutate(
    hhs_3plusPercentage = sum(c_across(hhs_3:hhs_6), na.rm = TRUE)
  ) %>%
  ungroup() %>% 
  select(-(hhs_3: hhs_6))  %>%  
     rename(
       fiesRaw_wmean = fies_rawscore_wmean,
       rcsi_wmean = rcsi_score_wmean,
         hdds_wmean = hdds_score_wmean,
       IPCphase = area_overall_phase
         )
variablesForCorrelation <- na.omit(variablesForCorrelation)
# Calculate Spearman correlation matrix
cor_spearman <- cor(variablesForCorrelation, method = "spearman")
print(cor_spearman)




# Correlations among indic.  - w/ % IPC3+
# Here I include IPC phase as a variable for the Spearman rank correlation (share IPC 3 +) as well as the FGT value using our assumed gaps


#     
#     
# Then the share of population by phase is multiplied by these assumed avg deficits and summed across phases to get the one value. 

# ---- correlation5 ----
# District-level Spearman correlations including IPC 3+% and kcal gap index (single midpoint)
variablesForCorrelation <- IPC_DIEM %>%
    select(fies_rawscore_wmean, fcs_wmean, rcsi_score_wmean, hdds_score_wmean,
           hhs_3:hhs_6, area_p3plus_percentage, calGap_FGT) %>%
   rowwise() %>%
  mutate(
    hhs_3plusPercentage = sum(c_across(hhs_3:hhs_6), na.rm = TRUE)
  ) %>%
  ungroup() %>%
  select(fies_rawscore_wmean, fcs_wmean, rcsi_score_wmean, hdds_score_wmean,
         hhs_3plusPercentage, area_p3plus_percentage, calGap_FGT) %>%
  rename(
       "FIES raw score" = fies_rawscore_wmean,
       "Food consumption score" = fcs_wmean,
       "RCSI score" = rcsi_score_wmean,
       "HDDS score" = hdds_score_wmean,
       "HHS 3+ Population Share" = hhs_3plusPercentage,
       "Population share in phase 3+" = area_p3plus_percentage,
       "Kcal gap index" = calGap_FGT
       )
variablesForCorrelation <- na.omit(variablesForCorrelation)
# Calculate Spearman correlation matrix
cor_spearman <- cor(variablesForCorrelation, method = "spearman")
print(cor_spearman)

tableForPaper <- cor_spearman %>% as.data.frame() %>%
    rownames_to_column(var = "variable")
write_correlation_table(tableForPaper, file.path(finalTablesFolder, "Table5a_correlations_district_IPC3plus_kcalgap.xlsx"))





# <br>



# # ===================================================================================

# # Compare indicator distributions b/w DIEM hh and matched DIEM hh/IPC

# ## Summarize DIEM hh


# ---- microData_allHHdata ----

# summarize those variables

summarize_var <- function(df, var) {
  df %>%
    summarise(
      variable = var,
      mean = round(mean(.data[[var]], na.rm = TRUE), 2),
      sd = round(sd(.data[[var]], na.rm = TRUE), 2),
      min = round(min(.data[[var]], na.rm = TRUE), 2),
      max = round(max(.data[[var]], na.rm = TRUE),2 ),
      q25 = round(quantile(.data[[var]], 0.25, na.rm = TRUE),2),
      med = round(median(.data[[var]], na.rm = TRUE), 2),
      q75 = quantile(.data[[var]], 0.75, na.rm = TRUE)#,
      # pct_missing = round(sum(is.na(.data[[var]])) / n() * 100, 1)
      )
}

vars_to_summarize <- c("fcs", "hdds_score", "hhs", "rcsi_score")

dataToSummarize <- DIEM_FoodSecurity_HH %>%
  select(OBJECTID, fcs, hdds_score, hhs, rcsi_score) %>%
  
   rename(id = OBJECTID) %>%
  group_by(id) %>% slice(1) %>% ungroup() %>%
  pivot_longer(
    cols = 2:last_col(), 
    names_to = "indicator", 
    values_to = "value"
  ) %>%
  # mutate(value = case_when(
  #   value == 0 ~ NA_real_,
  #   TRUE ~ value
  # )) %>%
    group_by(indicator) %>%
  mutate(
    max_value = max(value, na.rm = TRUE),
    min_value = min(value, na.rm = TRUE)
  ) %>% ungroup() %>%
  mutate(value_normalized = case_when(
    indicator %in% c("lcsi", "hhs", "rcsi_score") ~ (value - min_value)/(max_value-min_value),
    indicator %in% c("fcs", "hdds_score") ~ (value - max_value)/(min_value-max_value),
    TRUE ~ -999999999)
  ) %>%
  select(id, indicator, value_normalized)  %>%
    pivot_wider(
    names_from = indicator,
    values_from = value_normalized
  )  %>% select(-id)
  

summary_table <- map_dfr(vars_to_summarize, ~summarize_var(dataToSummarize, .x)) 

summary_table

write_paper_table(summary_table,
           file.path(outputVizInOutputFolder, "table_indicatorMeansnormalized_descriptives_IPCDIEMhh.xlsx"))


# testing the max min normalization formulats
del_value <- 14
min_value <- 0
max_value <- 112

formula1 <- (del_value-min_value)/(max_value-min_value) 

#testing where higher is worse like rcsi
del_value <- 14
min_value <- 0
max_value <- 56

formula1 <- (min_value - del_value)/(min_value - max_value)

formula2 <- (del_value - max_value)/(min_value - max_value)






# ## Summarize DIEM hh IPC matched data

# ---- microData_1 ----

# summarize those variables

summarize_var <- function(df, var) {
  df %>%
    summarise(
      variable = var,
      mean = round(mean(.data[[var]], na.rm = TRUE), 1),
      sd = round(sd(.data[[var]], na.rm = TRUE), 1),
      min = round(min(.data[[var]], na.rm = TRUE), 1),
      max = round(max(.data[[var]], na.rm = TRUE),1 ),
      q25 = round(quantile(.data[[var]], 0.25, na.rm = TRUE),1),
      med = round(median(.data[[var]], na.rm = TRUE), 1),
      q75 = quantile(.data[[var]], 0.75, na.rm = TRUE),
      pct_missing = round(sum(is.na(.data[[var]])) / n() * 100, 1)
      )
}

vars_to_summarize <- c("fcs", "hdds_score", "hhs", "rcsi_score")

summary_table <- map_dfr(vars_to_summarize, ~summarize_var(IPCDIEM_hh, .x)) 

summary_table




# ## Summarize DIEM hh IPC matched data by phase

# ---- summarizeDIEMhhIPCIndicatorsByPhase ----

# summarize those variables

summarize_var <- function(df, var) {
  df %>%
    group_by(area_overall_phase)%>%
    summarise(
      variable = var,
      mean = round(mean(.data[[var]], na.rm = TRUE), 1),
      sd = round(sd(.data[[var]], na.rm = TRUE), 1)
      )
}

vars_to_summarize <- c("fcs", "hdds_score", "hhs", "rcsi_score")

summary_table <- map_dfr(vars_to_summarize, ~summarize_var(IPCDIEM_hh, .x))  %>%
  mutate(value = paste0(mean, " (", sd, ")")) %>% select(-c(mean, sd)) %>%
    pivot_wider(
    names_from = variable,
    values_from = value
  ) 

summary_table




# ## Appendix: Full DIEM vs matched IPC-DIEM sample comparison

# Addresses reviewer concern about representativeness of the matched subsample.
# Compares indicator distributions in the full DIEM household dataset against the
# matched IPC-DIEM subsample, by country. Similar means/SDs suggest the matching
# procedure does not systematically select atypical observations.
# Note: this comparison cannot establish that either sample is representative of
# the broader population in IPC-classified areas -- only that the matched subsample
# is not distorted relative to the full DIEM sample.

# ---- appendix_full_vs_matched ----

vars_compare <- c("fcs", "hdds_score", "hhs", "rcsi_score")

summarize_for_comparison <- function(df, group_label) {
  df %>%
    select(OBJECTID, adm0_name, all_of(vars_compare)) %>%
    group_by(adm0_name) %>%
    summarise(across(all_of(vars_compare),
      list(
        mean = ~round(mean(.x, na.rm = TRUE), 1),
        sd   = ~round(sd(.x, na.rm = TRUE), 1),
        n    = ~sum(!is.na(.x))
      ),
      .names = "{.col}_{.fn}"
    ), .groups = "drop") %>%
    mutate(sample = group_label)
}

full_summary    <- summarize_for_comparison(DIEM_FoodSecurity_HH, "Full DIEM")
matched_summary <- summarize_for_comparison(IPCDIEM_hh,           "Matched (IPC-DIEM)")

# Restrict to countries present in both samples
countries_in_both <- intersect(full_summary$adm0_name, matched_summary$adm0_name)
full_summary    <- full_summary    %>% filter(adm0_name %in% countries_in_both)
matched_summary <- matched_summary %>% filter(adm0_name %in% countries_in_both)

# Overall rows (pooled across all countries)
summarize_overall <- function(df, group_label) {
  df %>%
    select(OBJECTID, all_of(vars_compare)) %>%
    summarise(across(all_of(vars_compare),
      list(
        mean = ~round(mean(.x, na.rm = TRUE), 1),
        sd   = ~round(sd(.x, na.rm = TRUE), 1),
        n    = ~sum(!is.na(.x))
      ),
      .names = "{.col}_{.fn}"
    )) %>%
    mutate(adm0_name = "Overall", sample = group_label)
}

overall_full    <- summarize_overall(DIEM_FoodSecurity_HH %>% filter(adm0_name %in% countries_in_both), "Full DIEM")
overall_matched <- summarize_overall(IPCDIEM_hh           %>% filter(adm0_name %in% countries_in_both), "Matched (IPC-DIEM)")

appendix_comparison <- bind_rows(overall_full, overall_matched, full_summary, matched_summary) %>%
  arrange(adm0_name == "Overall", adm0_name, sample) %>%
  select(adm0_name, sample,
         fcs_mean, fcs_sd,
         hdds_score_mean, hdds_score_sd,
         hhs_mean, hhs_sd,
         rcsi_score_mean, rcsi_score_sd) %>%
  mutate(
    fcs_meansd        = fmt_mean_sd(fcs_mean,        fcs_sd),
    hdds_meansd       = fmt_mean_sd(hdds_score_mean, hdds_score_sd),
    hhs_meansd        = fmt_mean_sd(hhs_mean,        hhs_sd),
    rcsi_meansd       = fmt_mean_sd(rcsi_score_mean, rcsi_score_sd)
  ) %>%
  select(adm0_name, sample, fcs_meansd, hdds_meansd, hhs_meansd, rcsi_meansd) %>%
  pivot_wider(
    names_from  = sample,
    values_from = c(fcs_meansd, hdds_meansd, hhs_meansd, rcsi_meansd)
  ) %>%
  arrange(adm0_name == "Overall", adm0_name) %>%
  select(
    adm0_name,
    "fcs_meansd_Full DIEM",            "fcs_meansd_Matched (IPC-DIEM)",
    "hdds_meansd_Full DIEM",           "hdds_meansd_Matched (IPC-DIEM)",
    "hhs_meansd_Full DIEM",            "hhs_meansd_Matched (IPC-DIEM)",
    "rcsi_meansd_Full DIEM",           "rcsi_meansd_Matched (IPC-DIEM)"
  )

local({
  df <- appendix_comparison %>% rename(Country = adm0_name)
  wb <- createWorkbook()
  sh <- "Sheet1"
  addWorksheet(wb, sh)

  # Row 1: top-level indicator groups
  writeData(wb, sh, startRow = 1, startCol = 1, colNames = FALSE, x = data.frame(
    A = "Country",
    B = "FCS",  C = "",
    D = "HDDS", E = "",
    F = "HHS",  G = "",
    H = "rCSI", I = ""
  ))
  mergeCells(wb, sh, rows = 1, cols = 2:3)
  mergeCells(wb, sh, rows = 1, cols = 4:5)
  mergeCells(wb, sh, rows = 1, cols = 6:7)
  mergeCells(wb, sh, rows = 1, cols = 8:9)

  # Row 2: DIEM / matched sub-headers
  writeData(wb, sh, startRow = 2, startCol = 1, colNames = FALSE, x = data.frame(
    A = "Country",
    B = "FCS (DIEM)",   C = "FCS (matched)",
    D = "HDDS (DIEM)",  E = "HDDS (matched)",
    F = "HHS (DIEM)",   G = "HHS (matched)",
    H = "rCSI (DIEM)",  I = "rCSI (matched)"
  ))

  # Data
  writeData(wb, sh, x = df, startRow = 3, startCol = 1, colNames = FALSE)

  header_style <- createStyle(textDecoration = "bold", halign = "center", valign = "center",
                              wrapText = TRUE, fontName = "Times New Roman", fontSize = 9,
                              border = "TopBottomLeftRight", borderStyle = "thin", fgFill = "#BDD7EE")
  left_style   <- createStyle(halign = "left",   valign = "center",
                              fontName = "Times New Roman", fontSize = 9,
                              border = "TopBottomLeftRight", borderStyle = "thin")
  body_style   <- createStyle(halign = "center", valign = "center",
                              fontName = "Times New Roman", fontSize = 9,
                              border = "TopBottomLeftRight", borderStyle = "thin")

  addStyle(wb, sh, header_style, rows = 1:2,              cols = 1:9, gridExpand = TRUE)
  addStyle(wb, sh, left_style,   rows = 3:(nrow(df) + 2), cols = 1,   gridExpand = TRUE)
  addStyle(wb, sh, body_style,   rows = 3:(nrow(df) + 2), cols = 2:9, gridExpand = TRUE)

  fn_row <- nrow(df) + 4
  writeData(wb, sh, x = "Mean (SD).", startRow = fn_row, startCol = 1, colNames = FALSE)
  addStyle(wb, sh, createStyle(fontName = "Times New Roman", fontSize = 9,
                               textDecoration = "italic", halign = "left"),
           rows = fn_row, cols = 1)

  setColWidths(wb, sh, cols = 1,    widths = 20)
  setColWidths(wb, sh, cols = 2:9,  widths = 14)
  saveWorkbook(wb, file.path(finalTablesFolder, "TableA5_full_vs_matched_DIEM.xlsx"), overwrite = TRUE)
})


# ---- microData_2 ----
## Summarize micro data
# Then, the  household data from the FAO DIEM dataset is summarized below by country. This of course can by done by admin level 1 or 2 as well.

# summarize_var <- function(df, var) {
#   df %>%
#     group_by(adm0_name) %>%    summarise(
#       variable = var,
#       mean = round(mean(.data[[var]], na.rm = TRUE), 1),
#       sd = round(sd(.data[[var]], na.rm = TRUE), 1),
#       min = round(min(.data[[var]], na.rm = TRUE), 1),
#       max = round(max(.data[[var]], na.rm = TRUE),1 ),
#       q25 = round(quantile(.data[[var]], 0.25, na.rm = TRUE),1),
#       med = round(median(.data[[var]], na.rm = TRUE), 1),
#       q75 = quantile(.data[[var]], 0.75, na.rm = TRUE),
#       pct_missing = round(sum(is.na(.data[[var]])) / n() * 100, 1),
#       .groups = "drop"    )
# }
# 
# vars_to_summarize <- c("fcs", "hdds_score", "hhs", "lcsi", "rcsi_score")
# 
# summary_table <- map_dfr(vars_to_summarize, ~summarize_var(IPCDIEM_hh, .x)) %>%
#   arrange(adm0_name)
# 
# 
# DT::datatable(summary_table) 




# ##Summarize DIEM hh by country

# ---- descriptives_indicators_hhDIEM ----

# summarize those variables

vars_to_summarize <- c("fcs", "hdds_score", "hhs", "rcsi_score")

dataToSummarize <- DIEM_FoodSecurity_HH %>%
  select(OBJECTID, adm0_name, fcs, hdds_score, hhs, rcsi_score) %>%
   rename(id = OBJECTID) %>%
  group_by(id) %>% slice(1) %>% ungroup() %>%
  pivot_longer(
    cols = 3:last_col(), 
    names_to = "indicator", 
    values_to = "value"
  ) %>%
  # mutate(value = case_when(
  #   value == 0 ~ NA_real_,
  #   TRUE ~ value
  # )) %>%
    group_by(indicator) %>%
  mutate(
    max_value = max(value, na.rm = TRUE),
    min_value = min(value, na.rm = TRUE)
  ) %>% ungroup() %>%
  mutate(value_normalized = case_when(
    indicator %in% c("lcsi", "hhs", "rcsi_score") ~ (value - min_value)/(max_value-min_value),
    indicator %in% c("fcs", "hdds_score") ~ (value - max_value)/(min_value-max_value),
    TRUE ~ -999999999)
  ) %>%
  select(id, adm0_name, indicator, value_normalized)  %>%
  select(-id) %>%
  group_by(adm0_name, indicator) %>%
  summarize(
    mean= mean(value_normalized, na.rm = TRUE),
    sd = sd(value_normalized, na.rm = TRUE)
  ) %>% ungroup() %>%
  mutate(
    mean = round(mean, 2),
    sd = round(sd, 2)
  ) %>%
  mutate(
    value = paste0(mean, "(",sd,")")) %>% 
  select(-c(mean, sd)) %>%
  pivot_wider(
    names_from = indicator,
    values_from = value
  ) 






# # Calculating gaps 
# ## FCS gap
# Then, using the household data from the FAO DIEM dataset, I look into the share of households under FCS 35 (FGT0) and the depth of that gap (FGT1). The first is across all observations and the second is by admin 1, which one we have the latest data we can match to IPC and generate gaps by phase. The cutoff line for FCS is 35. 
# ---- microData_fcs ----

library(patchwork) 

microData_FCS <- IPCDIEM_hh %>%
 # select(`Admin 0 name`, `Admin 1 name`, survey_date, fcs) %>%
  mutate(cutoff = line_fcs) %>%
    mutate(
    gap = case_when(
      is.na(fcs) ~ NA_integer_,
      fcs < cutoff ~ (cutoff - fcs) / cutoff,
      TRUE ~ 0
    )
  )   

# poverty gap measure for fcs

FGT_summary_allObs <- microData_FCS %>%
   summarize(
    FGT0 = mean(gap > 0, na.rm = TRUE),  # headcount ratio
    FGT1 = mean(gap, na.rm = TRUE)      # poverty gap
  )

FGT_summary_allObs_FCS <- FGT_summary_allObs %>%
  mutate(indicator = "FCS") %>% select(indicator, everything())

FGT_summary_byPhase <- microData_FCS %>%
  group_by(area_overall_phase) %>%
 summarize(
    FGT0 = mean(gap > 0, na.rm = TRUE),  # headcount ratio
    FGT1 = mean(gap, na.rm = TRUE)      # poverty gap
  ) %>% ungroup() 

byPhaseGap_FCS <- FGT_summary_byPhase %>%
  rename(ipc_phase = area_overall_phase,
         FCS_FGT0 = FGT0,
         FCS_FGT1 = FGT1) %>%
  mutate(FCS_avg_gap = FCS_FGT1/FCS_FGT0) %>%
  relocate(FCS_avg_gap, .after = FCS_FGT0)
  

FGT_summary_byPhase %>% print()

# ---- FGT by country (Admin 0 name) by phase-----------------------------
FGT_summary_byPhase <- microData_FCS %>%
  group_by(adm0_name,area_overall_phase) %>%
 summarize(
    FGT0 = mean(gap > 0, na.rm = TRUE),  # headcount ratio
    FGT1 = mean(gap, na.rm = TRUE)      # poverty gap
  ) %>% ungroup() %>% # summarize(
  mutate(FGT0 = round(FGT0,2),
         FGT1 = round(FGT1, 2)) %>%
  mutate(indicator = "FCS")

gap_FCS_byPhase <- FGT_summary_byPhase

FGT_summary_byPhase %>%
  mutate(gap = paste0("FGT0: ",FGT0, "  |  FGT1: ", FGT1)) %>% select(-c(FGT0, FGT1)) %>%
  pivot_wider(
    names_from = area_overall_phase,
    values_from = gap,
      names_prefix = "IPC_"
  ) %>% relocate(IPC_1, .before = IPC_2)  %>% print()


# ---- FGT by country (Admin 0 name) across phase-----------------------------
FGT_summary_byCountry <- microData_FCS %>%
  group_by(adm0_name) %>%
 summarize(
    FGT0 = mean(gap > 0, na.rm = TRUE),  # headcount ratio
    FGT1 = mean(gap, na.rm = TRUE)      # poverty gap
  )  

FGT_summary_byCountry 

fcs_gap <- FGT_summary_byCountry %>% rename(
  FCS_FGT0 = FGT0,
  FCS_FGT1 = FGT1
  )

#############################################################################
# show the distribution of the gap by phase
ggplot(microData_FCS %>% filter(gap>0), aes(x = gap, fill = factor(area_overall_phase))) +
  geom_density(alpha = 0.5) +
  labs(x = "FCS gap (distance) from 35", y = "Density", title = "Distribution of FCS Gap by IPC Phase", fill = "IPC Phase") +
  theme_minimal()

# v2
summary_gap <- microData_FCS %>%
  mutate(below_threshold = gap > 0) %>%
  group_by(area_overall_phase) %>%
  summarize(
    pct_below = mean(below_threshold, na.rm = TRUE) * 100
  )

p1 <- ggplot(summary_gap, aes(x = factor(area_overall_phase), y = pct_below, fill = factor(area_overall_phase))) +
  geom_col() +
  geom_text(aes(label = sprintf("%.1f%%", pct_below)), vjust = -0.5) +
  scale_y_continuous(
    limits = c(0, 100),
    labels = function(x) paste0(x, "%")  # adds % to axis labels
  ) +
  labs(
    x = "", y = "% below threshold",
    title = ""
  ) +
  theme_minimal() +
  theme(legend.position = "none")

p2 <- ggplot(IPCDIEM_hh, aes(x = factor(area_overall_phase), y = fcs, fill = factor(area_overall_phase))) +
  geom_boxplot(alpha = 0.6) +
  labs(
    x = "IPC Phase", y = "FCS score"
  ) +
  theme_minimal() +
  theme(legend.position = "none")

# Combine vertically (sharing the same x-axis)
combined_plot <- p1 / p2 +
  plot_layout(heights = c(1, 1.2)) +
  plot_annotation(title = "Food Consumption Score",
                  theme = theme(plot.title = element_text(size = 10, hjust = 0.5)))

# Display it
combined_plot

ggsave(
  filename = file.path(finalFiguresFolder, "gapbyIPCphase_combined_plot_FCS.png"),
  plot = combined_plot,
  width = 3,
  height = 5,
  dpi = 300
)



# ## RCSI gap
# RCSI with the cutoff at 19. 
# ---- microdata_rCSI ----

microData_RCSI <- IPCDIEM_hh %>%
 # select(`Admin 0 name`, `Admin 1 name`, survey_date, fcs) %>%
  mutate(cutoff = line_rcsi) %>%
# poverty gap measure 
    mutate(
    gap = case_when(
      is.na(rcsi_score) ~ NA_integer_,
      rcsi_score > cutoff ~ (rcsi_score - cutoff) / cutoff,
      TRUE ~ 0
    )
  ) 

microData_RCSI %>% filter(area_overall_phase ==4) %>% distinct(rcsi_score)


FGT_summary_allObs <- microData_RCSI %>%
   summarize(
    FGT0 = mean(gap > 0, na.rm = TRUE),  # headcount ratio
    FGT1 = mean(gap, na.rm = TRUE)      # poverty gap
  )

FGT_summary_allObs_RCSI <- FGT_summary_allObs %>%
  mutate(indicator = "RCSI") %>% select(indicator, everything())

# FGT by phase only ------------------------------------------------------
FGT_summary_byPhase <- microData_RCSI %>%
  group_by(area_overall_phase) %>%
 summarize(
    FGT0 = mean(gap > 0, na.rm = TRUE),  # headcount ratio
    FGT1 = mean(gap, na.rm = TRUE)      # poverty gap
  ) %>% ungroup() 

byPhaseGap_RCSI <- FGT_summary_byPhase %>%
  rename(ipc_phase = area_overall_phase,
         RCSI_FGT0 = FGT0,
         RCSI_FGT1 = FGT1) %>%
  mutate(RCSI_avg_gap = RCSI_FGT1/RCSI_FGT0) %>%
  relocate(RCSI_avg_gap, .after = RCSI_FGT0)

# ---- FGT by country (Admin 0 name) by phase-----------------------------
FGT_summary_byPhase <- microData_RCSI %>%
  group_by(adm0_name,area_overall_phase) %>%
    summarize(
    FGT0 = mean(gap > 0, na.rm = TRUE),  # headcount ratio
    FGT1 = mean(gap, na.rm = TRUE)      # poverty gap
  ) %>%  ungroup() %>% 
  mutate(FGT0 = round(FGT0,2),
         FGT1 = round(FGT1, 2)) %>%
    mutate(indicator = "rcsi")

FGT_summary_byPhase %>%
  mutate(gap = paste0("FGT0: ",FGT0, "  |  FGT1: ", FGT1)) %>% select(-c(FGT0, FGT1)) %>%
  pivot_wider(
    names_from = area_overall_phase,
    values_from = gap,
      names_prefix = "IPC_"
  ) %>% relocate(IPC_1, .before = IPC_2)  %>%
  print()

gap_RCSI_byPhase <- FGT_summary_byPhase


# ---- FGT by country (Admin 0 name) across phase-----------------------------
FGT_summary_byCountry <- microData_RCSI %>%
  group_by(adm0_name) %>%
   summarize(
    FGT0 = mean(gap > 0, na.rm = TRUE),  # headcount ratio
    FGT1 = mean(gap, na.rm = TRUE)      # poverty gap
  ) %>%
  select(adm0_name, FGT0, FGT1)

FGT_summary_byCountry

rcsi_gap <- FGT_summary_byCountry %>% rename(
  RCSI_FGT0 = FGT0,
  RCSI_FGT1 = FGT1
  )


#############################################################################
summary_gap <- microData_RCSI %>%
  mutate(below_threshold = gap > 0) %>%
  group_by(area_overall_phase) %>%
  summarize(
    pct_below = mean(below_threshold, na.rm = TRUE) * 100
  )

p1 <- ggplot(summary_gap, aes(x = factor(area_overall_phase), y = pct_below, fill = factor(area_overall_phase))) +
  geom_col() +
  geom_text(aes(label = sprintf("%.1f%%", pct_below)), vjust = -0.5) +
   scale_y_continuous(
    limits = c(0, 100),
    labels = function(x) paste0(x, "%")  # adds % to axis labels
  ) +
  labs(
    x = "", y = "% below threshold",
    title = ""
  ) +
  theme_minimal() +
  theme(legend.position = "none")

p2 <- ggplot(IPCDIEM_hh, aes(x = factor(area_overall_phase), y = rcsi_score, fill = factor(area_overall_phase))) +
  geom_boxplot(alpha = 0.6) +
  labs(
    x = "IPC Phase", y = "rCSI score"
  ) +
  theme_minimal() +
  theme(legend.position = "none")

# Combine vertically (sharing the same x-axis)
combined_plot <- p1 / p2 +
  plot_layout(heights = c(1, 1.2)) +
  plot_annotation(title = "rCSI",
                  theme = theme(plot.title = element_text(size = 10, hjust = 0.5)))

# Display it
combined_plot

ggsave(
  filename = file.path(finalFiguresFolder, "gapbyIPCphase_combined_plot_RCSI.png"),
  plot = combined_plot,
  width = 3,
  height = 5,
  dpi = 300
)





# ## hdds gap
# Cutoff at 5
# ---- microdata_hdds ----

microData_hdds <- IPCDIEM_hh %>%
 # select(`Admin 0 name`, `Admin 1 name`, survey_date, fcs) %>%
  mutate(cutoff = line_hdds) %>%
# poverty gap measure 
    mutate(
    gap = case_when(
      is.na(hdds_score) ~ NA_integer_,
      hdds_score < cutoff ~ (cutoff - hdds_score) / cutoff,
      TRUE ~ 0
    )
  )   # mutate(
  #   underCutoff = case_when(
  #     is.na(hdds_score) ~ NA_integer_,
  #     hdds_score < cutoff ~ 1,
  #     TRUE ~ 0)
  #   ) %>%
  # mutate(
  #   gap = case_when(
  #     underCutoff == 1 ~ cutoff - hdds_score,
  #     TRUE ~ 0)
  # )

# poverty gap measure 

FGT_summary_allObs <- microData_hdds %>%
      summarize(
    FGT0 = mean(gap > 0, na.rm = TRUE),  # headcount ratio
    FGT1 = mean(gap, na.rm = TRUE)      # poverty gap
  ) 

FGT_summary_allObs_HDDS <- FGT_summary_allObs %>%
  mutate(indicator = "HDDS") %>% select(indicator, everything())

  # summarize(
  #   FGT0 = mean(underCutoff, na.rm = TRUE),  # Headcount ratio
  #   average_underHDDSLine = mean(hdds_score[underCutoff == 1], na.rm = TRUE),  # Average FCS of poor
  #   FGT1 = FGT0 * (cutoff - average_underHDDSLine) / cutoff  # Poverty gap index
  # ) %>% select(FGT0, FGT1) %>% slice(1)

FGT_summary_byPhase <- microData_hdds %>%
  group_by(area_overall_phase) %>%
    summarize(
    FGT0 = mean(gap > 0, na.rm = TRUE),  # headcount ratio
    FGT1 = mean(gap, na.rm = TRUE)      # poverty gap
  ) %>%  # summarize(
  #   FGT0 = mean(underCutoff, na.rm = TRUE),  # Headcount ratio
  #   average_underHDDSLine = mean(hdds_score[underCutoff == 1], na.rm = TRUE),  # Average FCS of poor
  #   FGT1 = FGT0 * (cutoff - average_underHDDSLine) / cutoff  # Poverty gap index
  # ) %>% select(FGT0, FGT1) %>% slice(1) %>% 
  ungroup() %>% print()

# FGT by phase only ------------------------------------------------------
FGT_summary_byPhase <- microData_hdds %>%
  group_by(area_overall_phase) %>%
 summarize(
    FGT0 = mean(gap > 0, na.rm = TRUE),  # headcount ratio
    FGT1 = mean(gap, na.rm = TRUE)      # poverty gap
  ) %>% ungroup() 

byPhaseGap_HDDS <- FGT_summary_byPhase %>%
  rename(ipc_phase = area_overall_phase,
         HDDS_FGT0 = FGT0,
         HDDS_FGT1 = FGT1) %>%
  mutate(HDDS_avg_gap = HDDS_FGT1/HDDS_FGT0) %>%
  relocate(HDDS_avg_gap, .after = HDDS_FGT0)


# ---- FGT by country (Admin 0 name) by phase-----------------------------
FGT_summary_byPhase <- microData_hdds %>%
  group_by(adm0_name,area_overall_phase) %>%
    summarize(
    FGT0 = mean(gap > 0, na.rm = TRUE),  # headcount ratio
    FGT1 = mean(gap, na.rm = TRUE)      # poverty gap
  ) %>% ungroup() %>%  # summarize(
  #   FGT0 = mean(underCutoff, na.rm = TRUE),  # Headcount ratio
  #   average_underHDDSLine = mean(hdds_score[underCutoff == 1], na.rm = TRUE),  # Average FCS of poor
  #   FGT1 = FGT0 * (cutoff - average_underHDDSLine) / cutoff  # Poverty gap index
  # ) %>% select(FGT0, FGT1) %>% slice(1) %>% ungroup() %>% 
  mutate(FGT0 = round(FGT0,2),
         FGT1 = round(FGT1, 2))  %>%
  mutate(indicator = "hdds") 

FGT_summary_byPhase %>%
  mutate(gap = paste0("FGT0: ",FGT0, "  |  FGT1: ", FGT1)) %>% select(-c(FGT0, FGT1)) %>%
  pivot_wider(
    names_from = area_overall_phase,
    values_from = gap,
      names_prefix = "IPC_"
  ) %>% relocate(IPC_1, .before = IPC_2)  %>%
  print()

gap_hdds_byPhase <- FGT_summary_byPhase

# ---- FGT by country (Admin 0 name) across phase-----------------------------
FGT_summary_byCountry <- microData_hdds %>%
  group_by(adm0_name) %>%
    summarize(
    FGT0 = mean(gap > 0, na.rm = TRUE),  # headcount ratio
    FGT1 = mean(gap, na.rm = TRUE)      # poverty gap
  ) %>% ungroup()  # summarize(
  #   FGT0 = mean(underCutoff, na.rm = TRUE),  # Headcount ratio
  #   average_underHDDSLine = mean(hdds_score[underCutoff == 1], na.rm = TRUE),  # Mean FCS of poor
  #   cutoff = mean(cutoff, na.rm = TRUE),  # Include cutoff for reference
  #   FGT1 = FGT0 * (cutoff - average_underHDDSLine) / cutoff  # Poverty gap index
  # ) %>%
  # select(adm0_name, FGT0, FGT1)

FGT_summary_byCountry

HDDS_gap <- FGT_summary_byCountry %>% 
  rename(
  hdds_FGT0 = FGT0,
  hdds_FGT1 = FGT1
  )

#############################################################################
# show the distribution of the gap by phase
ggplot(microData_hdds %>% filter(gap>0), aes(x = gap, fill = factor(area_overall_phase))) +
  geom_density(alpha = 0.5) +
  labs(x = "RCSI gap (distance) from 35", y = "Density", title = "Distribution of FCS Gap by IPC Phase", fill = "IPC Phase") +
  theme_minimal()



summary_gap <- microData_hdds %>%
  mutate(below_threshold = gap > 0) %>%
  group_by(area_overall_phase) %>%
  summarize(
    pct_below = mean(below_threshold, na.rm = TRUE) * 100
  )

p1 <- ggplot(summary_gap, aes(x = factor(area_overall_phase), y = pct_below, fill = factor(area_overall_phase))) +
  geom_col() +
  geom_text(aes(label = sprintf("%.1f%%", pct_below)), vjust = -0.5) +
   scale_y_continuous(
    limits = c(0, 100),
    labels = function(x) paste0(x, "%")  # adds % to axis labels
  ) +
  labs(
    x = "", y = "% below threshold",
    title = ""
  ) +
  theme_minimal() +
  theme(legend.position = "none")

p2 <- ggplot(IPCDIEM_hh, aes(x = factor(area_overall_phase), y = hdds_score, fill = factor(area_overall_phase))) +
  geom_boxplot(alpha = 0.6) +
  labs(
    x = "IPC Phase", y = "HDDS score"
  ) +
  theme_minimal() +
  theme(legend.position = "none")

# Combine vertically (sharing the same x-axis)
combined_plot <- p1 / p2 +
  plot_layout(heights = c(1, 1.2)) +
  plot_annotation(title = "HDDS",
                  theme = theme(plot.title = element_text(size = 10, hjust = 0.5)))

# Display it
combined_plot

ggsave(
  filename = file.path(finalFiguresFolder, "gapbyIPCphase_combined_plot_hdds.png"),
  plot = combined_plot,
  width = 3,
  height = 5,
  dpi = 300
)




# ## HHS gap
# cutoff at 2
# ---- microdata_hhs ----

microData_hhs <- IPCDIEM_hh %>%
 # select(`Admin 0 name`, `Admin 1 name`, survey_date, fcs) %>%
  mutate(cutoff = line_hhs) %>%
    mutate(
    gap = case_when(
      is.na(hhs) ~ NA_integer_,
      hhs > cutoff ~ (hhs - cutoff) / cutoff,
      TRUE ~ 0
    )
  )   # mutate(
  #   underCutoff = case_when(
  #     is.na(hhs) ~ NA_integer_,
  #     hhs > cutoff ~ 1,
  #     TRUE ~ 0)
  #   ) %>%
  # mutate(
  #   gap = case_when(
  #     underCutoff == 1 ~ hhs - cutoff,
  #     TRUE ~ 0)
  # )

# poverty gap measure for fcs

FGT_summary_allObs <- microData_hhs %>%
    summarize(
    FGT0 = mean(gap > 0, na.rm = TRUE),  # headcount ratio
    FGT1 = mean(gap, na.rm = TRUE)      # poverty gap
  ) %>%  ungroup()  

FGT_summary_allObs_HHS <- FGT_summary_allObs %>%
  mutate(indicator = "HHS") %>% select(indicator, everything())

# summarize(
  #   FGT0 = mean(underCutoff, na.rm = TRUE),  # Headcount ratio
  #   average_underHHSline = mean(hhs[underCutoff == 1], na.rm = TRUE),  # Average FCS of poor
  #   FGT1 = FGT0 * (average_underHHSline/cutoff) / cutoff  # Poverty gap index
  # ) %>% select(FGT0, FGT1) %>% slice(1)

FGT_summary_byPhase <- microData_hhs %>%
  group_by(area_overall_phase) %>%
    summarize(
    FGT0 = mean(gap > 0, na.rm = TRUE),  # headcount ratio
    FGT1 = mean(gap, na.rm = TRUE)      # poverty gap
  ) %>%  ungroup() %>% print()  # summarize(
  #   FGT0 = mean(underCutoff, na.rm = TRUE),  # Headcount ratio
  #   average_underHHSline = mean(hhs[underCutoff == 1], na.rm = TRUE),  # Average FCS of poor
  #   FGT1 = FGT0 * (average_underHHSline - cutoff) / cutoff  # Poverty gap index
  # ) %>% select(FGT0, FGT1) %>% slice(1) %>% ungroup() %>% print()

# FGT by phase only ------------------------------------------------------
FGT_summary_byPhase <- microData_hhs %>%
  group_by(area_overall_phase) %>%
 summarize(
    FGT0 = mean(gap > 0, na.rm = TRUE),  # headcount ratio
    FGT1 = mean(gap, na.rm = TRUE)      # poverty gap
  ) %>% ungroup() 

byPhaseGap_HHS <- FGT_summary_byPhase %>%
  rename(ipc_phase = area_overall_phase,
         HHS_FGT0 = FGT0,
         HHS_FGT1 = FGT1) %>%
  mutate(HHS_avg_gap = HHS_FGT1/HHS_FGT0) %>%
  relocate(HHS_avg_gap, .after = HHS_FGT0)



# ---- FGT by country (Admin 0 name) by phase-----------------------------
FGT_summary_byPhase <- microData_hhs %>%
  group_by(adm0_name,area_overall_phase) %>%
  # summarize(
  #   FGT0 = mean(underCutoff, na.rm = TRUE),  # Headcount ratio
  #   average_underHHSline = mean(hhs[underCutoff == 1], na.rm = TRUE),  # Average FCS of poor
  #   FGT1 = FGT0 * (cutoff - average_underHHSline) / cutoff  # Poverty gap index
  # ) %>% select(FGT0, FGT1) %>% slice(1) %>% ungroup() %>% 
  summarize(
    FGT0 = mean(gap > 0, na.rm = TRUE),  # headcount ratio
    FGT1 = mean(gap, na.rm = TRUE)      # poverty gap
  ) %>%  ungroup() %>% 
  mutate(FGT0 = round(FGT0,2),
         FGT1 = round(FGT1, 2))%>%
    mutate(indicator = "hhs")

FGT_summary_byPhase %>%
  mutate(gap = paste0("FGT0: ",FGT0, "  |  FGT1: ", FGT1)) %>% select(-c(FGT0, FGT1)) %>%
  pivot_wider(
    names_from = area_overall_phase,
    values_from = gap,
      names_prefix = "IPC_"
  ) %>% relocate(IPC_1, .before = IPC_2)  %>%
  print()

gap_hhs_byPhase <- FGT_summary_byPhase


# ---- FGT by country (Admin 0 name) across phase-----------------------------
FGT_summary_byCountry <- microData_hhs %>%
  group_by(adm0_name) %>%
      summarize(
    FGT0 = mean(gap > 0, na.rm = TRUE),  # headcount ratio
    FGT1 = mean(gap, na.rm = TRUE)      # poverty gap
  ) %>%  ungroup() 
  # summarize(
  #   FGT0 = mean(underCutoff, na.rm = TRUE),  # Headcount ratio
  #   average_underHHSline = mean(hhs[underCutoff == 1], na.rm = TRUE),  # Mean FCS of poor
  #   cutoff = mean(cutoff, na.rm = TRUE),  # Include cutoff for reference
  #   FGT1 = FGT0 * (cutoff - average_underHHSline) / cutoff  # Poverty gap index
  # ) %>%
  # select(adm0_name, FGT0, FGT1)

FGT_summary_byCountry

hhs_gap <- FGT_summary_byCountry %>% rename(
  hhs_FGT0 = FGT0,
  hhs_FGT1 = FGT1
  )




#########################################################

summary_gap <- microData_hhs %>%
  mutate(below_threshold = gap > 0) %>%
  group_by(area_overall_phase) %>%
  summarize(
    pct_below = mean(below_threshold, na.rm = TRUE) * 100
  )

p1 <- ggplot(summary_gap, aes(x = factor(area_overall_phase), y = pct_below, fill = factor(area_overall_phase))) +
  geom_col() +
  geom_text(aes(label = sprintf("%.1f%%", pct_below)), vjust = -0.5) +
   scale_y_continuous(
    limits = c(0, 100),
    labels = function(x) paste0(x, "%")  # adds % to axis labels
  ) +
  labs(
    x = "", y = "% below threshold",
    title = ""
  ) +
  theme_minimal() +
  theme(legend.position = "none")

p2 <- ggplot(IPCDIEM_hh, aes(x = factor(area_overall_phase), y = hhs, fill = factor(area_overall_phase))) +
  geom_boxplot(alpha = 0.6) +
  labs(
    x = "IPC Phase", y = "HHS score"
  ) +
  theme_minimal() +
  theme(legend.position = "none")

# Combine vertically (sharing the same x-axis)
combined_plot <- p1 / p2 +
  plot_layout(heights = c(1, 1.2)) +
  plot_annotation(title = "HHS",
                  theme = theme(plot.title = element_text(size = 10, hjust = 0.5)))

# Display it
combined_plot

ggsave(
  filename = file.path(finalFiguresFolder, "gapbyIPCphase_combined_plot_hhs.png"),
  plot = combined_plot,
  width = 3,
  height = 5,
  dpi = 300
)



# # Prep

# ## by indicator 
# ---- combineIndicatorGaps_summarizing ----

indicatorGapsByIndicatorOnly <- bind_rows(FGT_summary_allObs_FCS, FGT_summary_allObs_RCSI,
                             FGT_summary_allObs_HDDS,    FGT_summary_allObs_HHS      ) %>%
  mutate(avg_gap = FGT1/FGT0) %>%
  relocate(avg_gap, .after = FGT0) %>%
  mutate(ipc_phase = "overall") %>%
    pivot_wider(
    names_from = indicator,
    values_from = c(FGT0, avg_gap, FGT1),
    names_glue = "{indicator}_{.value}"
  ) %>%
    select(
    ipc_phase,
    FCS_FGT0,  FCS_avg_gap,  FCS_FGT1,
    RCSI_FGT0, RCSI_avg_gap, RCSI_FGT1,
    HDDS_FGT0, HDDS_avg_gap, HDDS_FGT1,
    HHS_FGT0,  HHS_avg_gap,  HHS_FGT1
  ) %>%
  relocate(RCSI_FGT0:RCSI_FGT1, .after =HHS_FGT1 )




# ## by phase 
# ---- combineIndicatorGaps_by phasevers ----

indicatorGapsByPhaseOnly <- byPhaseGap_FCS %>%
  left_join(byPhaseGap_RCSI) %>%    left_join(byPhaseGap_HDDS) %>% 
  left_join(byPhaseGap_HHS) %>%
  relocate(RCSI_FGT0:RCSI_FGT1, .after = HHS_FGT1) %>%
  mutate(ipc_phase = as.character(ipc_phase)) %>%
  bind_rows(indicatorGapsByIndicatorOnly)


local({
  df <- indicatorGapsByPhaseOnly %>%
    mutate(
      ipc_phase = case_when(
        ipc_phase == "overall" ~ "Overall",
        TRUE ~ paste0("IPC ", ipc_phase)
      ),
      across(where(is.numeric), ~ round(.x, 2))
    ) %>%
    rename("IPC Phase" = ipc_phase)

  wb <- createWorkbook()
  sh <- "Sheet1"
  addWorksheet(wb, sh)

  # Row 1: top-level indicator groups
  writeData(wb, sh, startRow = 1, startCol = 1, colNames = FALSE, x = data.frame(
    A = "IPC Phase",
    B = "FCS",  C = "", D = "",
    E = "HDDS", F = "", G = "",
    H = "HHS",  I = "", J = "",
    K = "rCSI", L = "", M = ""
  ))
  mergeCells(wb, sh, rows = 1, cols = 2:4)
  mergeCells(wb, sh, rows = 1, cols = 5:7)
  mergeCells(wb, sh, rows = 1, cols = 8:10)
  mergeCells(wb, sh, rows = 1, cols = 11:13)

  # Row 2: sub-headers
  writeData(wb, sh, startRow = 2, startCol = 1, colNames = FALSE, x = data.frame(
    A = "IPC Phase",
    B = "FGT0", C = "Avg Gap", D = "FGT1",
    E = "FGT0", F = "Avg Gap", G = "FGT1",
    H = "FGT0", I = "Avg Gap", J = "FGT1",
    K = "FGT0", L = "Avg Gap", M = "FGT1"
  ))

  # Data
  writeData(wb, sh, x = df, startRow = 3, startCol = 1, colNames = FALSE)

  header_style <- createStyle(textDecoration = "bold", halign = "center", valign = "center",
                              wrapText = TRUE, fontName = "Times New Roman", fontSize = 9,
                              border = "TopBottomLeftRight", borderStyle = "thin", fgFill = "#BDD7EE")
  left_style   <- createStyle(halign = "left",   valign = "center",
                              fontName = "Times New Roman", fontSize = 9,
                              border = "TopBottomLeftRight", borderStyle = "thin")
  body_style   <- createStyle(halign = "center", valign = "center",
                              fontName = "Times New Roman", fontSize = 9,
                              border = "TopBottomLeftRight", borderStyle = "thin")

  addStyle(wb, sh, header_style, rows = 1:2,              cols = 1:13, gridExpand = TRUE)
  addStyle(wb, sh, left_style,   rows = 3:(nrow(df) + 2), cols = 1,    gridExpand = TRUE)
  addStyle(wb, sh, body_style,   rows = 3:(nrow(df) + 2), cols = 2:13, gridExpand = TRUE)

  setColWidths(wb, sh, cols = 1,     widths = 12)
  setColWidths(wb, sh, cols = 2:13,  widths = 9)
  saveWorkbook(wb, file.path(finalTablesFolder, "Table7_FGT_indices_by_phase.xlsx"), overwrite = TRUE)
})




# ## by country/phase. 

# ### Combine indicator gaps by phase
# ---- combineIndicatorGaps ----
indicatorGapsByPhase <- bind_rows(gap_FCS_byPhase, gap_RCSI_byPhase,gap_hdds_byPhase,gap_hhs_byPhase) %>%
      mutate(iso3 = countrycode(adm0_name, origin = "country.name", destination = "iso3c")) %>% 
    rename(ipcphase = area_overall_phase) %>%
  select(iso3, ipcphase, indicator, FGT1) %>%
    pivot_wider(
    id_cols = c(iso3, ipcphase),       
    names_from = indicator,            
    values_from = FGT1,               
    #names_sep = "_" ,
    names_prefix = "fgt1_"
  )


# ### prepare IPC data for indicator gaps and join with indicator gaps
# ---- ipcDataPrep ----

IPCdata_forIndicatorGaps <- IPCdataImported %>%
  select(iso3: country_phase5_percentage) %>%
    mutate(country_name = countrycode(iso3, origin = "iso3c", destination = "country.name")) %>%
  select(country_name, everything()) %>% select(-iso3)  %>%
  mutate(countryAnalysis = paste( country_name, " - ", country_title)) %>%
  select(countryAnalysis, everything()) %>% select(-c(country_title)) %>%
  distinct() %>%
  # now create total population covered column so that I can select the analysis with the highest coverage (by year) %>%
  mutate(totalPopulationCovered = country_phase1_population + country_phase2_population+country_phase3_population+country_phase4_population+country_phase5_population) %>%
  mutate(year = year(country_analysis_date)) %>% relocate(year, .after = country_analysis_date) %>%
    group_by(country_name, year) %>%
  slice_max(totalPopulationCovered, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
    select( -contains("percentage") ) %>%
    mutate(iso3 = countrycode(country_name, origin = "country.name", destination = "iso3c")) %>% 
  select(countryAnalysis, iso3, country_name, year, country_phase1_population: country_phase5_population) %>%
  #now pivot longer to make it matchable
    pivot_longer(
    cols = starts_with("country_phase"),  # all columns with population per phase
    names_to = "ipcphase",                # new column name for phase
    values_to = "population"              # new column for population
  ) %>%
  filter(population >=0) %>%
  mutate(ipcphase = case_when(
    ipcphase == "country_phase1_population" ~ 1,
    ipcphase == "country_phase2_population" ~ 2,
    ipcphase == "country_phase3_population" ~ 3,
    ipcphase == "country_phase4_population" ~ 4,
    ipcphase == "country_phase5_population" ~ 5,
    TRUE ~ -9999999
  )) 

IPCdata_forIndicatorGaps2<- IPCdata_forIndicatorGaps %>%
  left_join(indicatorGapsByPhase) %>%
  #now add cost per meal per day column
  mutate(
    costPerWFPration_USD = .5,
    costPerWFPrationPerYear_USD = costPerWFPration_USD * 365
    ) %>%
  select(country_name, year, ipcphase: last_col()) %>%
  #remove ipc1
  filter(ipcphase != 1)

IPCdata_forIndicatorGaps <- IPCdata_forIndicatorGaps2




# ## Table - IPC table with FCS gaps
# ---- IPC table with FCS gaps ----
million <- 1000000
gaps_Table_1 <- IPCdata_forIndicatorGaps %>%
  mutate(
    cost_annual_millionsUSD_usingFCSgaps = population*fgt1_FCS *costPerWFPrationPerYear_USD/million,
    cost_annual_millionsUSD_usingRCSIgaps = population*fgt1_rcsi *costPerWFPrationPerYear_USD/million,
    cost_annual_millionsUSD_usingHDDSgaps = population*fgt1_hdds *costPerWFPrationPerYear_USD/million,
    cost_annual_millionsUSD_usingHHSgaps = population*fgt1_hhs *costPerWFPrationPerYear_USD/million

  )%>%
 # select(country_name, year, ipcphase, population, fgt1_FCS, cost_annual_millionsUSD)%>%
  
  group_by(country_name) %>%
  filter(year %in% sort(unique(year), decreasing = TRUE)[1]) %>%  # keep latest year
  ungroup() %>%
  
  #now make it only for phases 3 and 4
  filter(ipcphase %in% c(3,4)) %>%
  
  group_by(country_name, year) %>%
  mutate(
    total_cost_annual_millionsUSD_usingFCSgaps = sum(cost_annual_millionsUSD_usingFCSgaps, na.rm = TRUE),
    total_cost_annual_millionsUSD_usingRCSIgaps = sum(cost_annual_millionsUSD_usingRCSIgaps, na.rm = TRUE),
    total_cost_annual_millionsUSD_usingHDDSgaps = sum(cost_annual_millionsUSD_usingHDDSgaps, na.rm = TRUE),
    total_cost_annual_millionsUSD_usingHHSgaps = sum(cost_annual_millionsUSD_usingHHSgaps, na.rm = TRUE)
        ) %>%
  filter(!all(is.na(fgt1_FCS))) %>%
  ungroup() 

# Table 9: FCS gap by country with grouped headers (IPC 3 / IPC 4)
gaps_Table_fcs <- gaps_Table_1 %>%
  select(country_name, year, ipcphase, population, fgt1_FCS,
         cost_annual_millionsUSD_usingFCSgaps, total_cost_annual_millionsUSD_usingFCSgaps) %>%
  pivot_wider(
    id_cols = c(country_name, year, total_cost_annual_millionsUSD_usingFCSgaps),
    names_from = ipcphase,
    values_from = c(population, fgt1_FCS, cost_annual_millionsUSD_usingFCSgaps),
    names_glue = "{.value}_phase{ipcphase}"
  ) %>%
  select(country_name, year,
         population_phase3, fgt1_FCS_phase3, cost_annual_millionsUSD_usingFCSgaps_phase3,
         population_phase4, fgt1_FCS_phase4, cost_annual_millionsUSD_usingFCSgaps_phase4,
         total_cost_annual_millionsUSD_usingFCSgaps)

local({
  df <- gaps_Table_fcs
  wb <- createWorkbook()
  sh <- "Sheet1"
  addWorksheet(wb, sh)

  # Row 1: group headers
  writeData(wb, sh, startRow = 1, startCol = 1, colNames = FALSE, x = data.frame(
    A = "Country", B = "Year",
    C = "FCS gap IPC 3", D = "", E = "",
    F = "FCS gap IPC 4", G = "", H = "",
    I = "Total cost"
  ))
  mergeCells(wb, sh, rows = 1, cols = 3:5)
  mergeCells(wb, sh, rows = 1, cols = 6:8)

  # Row 2: sub-headers
  writeData(wb, sh, startRow = 2, startCol = 1, colNames = FALSE, x = data.frame(
    A = "Country", B = "Year",
    C = "Population", D = "FGT1", E = "Cost*",
    F = "Population", G = "FGT1", H = "Cost*",
    I = "Total cost*"
  ))

  # Data
  writeData(wb, sh, x = df, startRow = 3, startCol = 1, colNames = FALSE)

  header_style <- createStyle(textDecoration = "bold", halign = "center", valign = "center",
                              wrapText = TRUE, fontName = "Times New Roman", fontSize = 9,
                              border = "TopBottomLeftRight", borderStyle = "thin", fgFill = "#BDD7EE")
  left_style   <- createStyle(halign = "left",   valign = "center",
                              fontName = "Times New Roman", fontSize = 9,
                              border = "TopBottomLeftRight", borderStyle = "thin")
  body_style   <- createStyle(halign = "center", valign = "center",
                              fontName = "Times New Roman", fontSize = 9,
                              border = "TopBottomLeftRight", borderStyle = "thin")

  addStyle(wb, sh, header_style, rows = 1:2,              cols = 1:9, gridExpand = TRUE)
  addStyle(wb, sh, left_style,   rows = 3:(nrow(df) + 2), cols = 1,   gridExpand = TRUE)
  addStyle(wb, sh, body_style,   rows = 3:(nrow(df) + 2), cols = 2:9, gridExpand = TRUE)

  # Footnote
  fn_row <- nrow(df) + 4
  writeData(wb, sh, x = "* Cost in millions USD (annual, based on $0.50/ration/day).",
            startRow = fn_row, startCol = 1, colNames = FALSE)
  addStyle(wb, sh, createStyle(fontName = "Times New Roman", fontSize = 9,
                               textDecoration = "italic", halign = "left"),
           rows = fn_row, cols = 1)

  setColWidths(wb, sh, cols = 1:9, widths = c(20, 8, 14, 8, 10, 14, 8, 10, 12))
  saveWorkbook(wb, file.path(finalTablesFolder, "Table9_FCS_cost_by_country.xlsx"), overwrite = TRUE)
})

# now on to the RCSI table------------------------------------------------------------------
gaps_Table_rcsi <- gaps_Table_1 %>%
  mutate(
    byPhaseValue = paste0("Pop: ", population, " | RCSI gap: ", fgt1_rcsi, " | Cost annual mill USD: ", round(cost_annual_millionsUSD_usingRCSIgaps, 1))
  ) %>%
  
  select(country_name, year, ipcphase, byPhaseValue, total_cost_annual_millionsUSD_usingRCSIgaps) %>%
  
   pivot_wider(
    id_cols = c(country_name, year, total_cost_annual_millionsUSD_usingRCSIgaps),       
    names_from = ipcphase,            
    values_from = byPhaseValue,
    names_prefix = "IPC phase "
    ) 

# now on to the HDDS table------------------------------------------------------------------
gaps_Table_hdds <- gaps_Table_1 %>%
  mutate(
    byPhaseValue = paste0("Pop: ", population, " | HDDS gap: ", fgt1_hdds, " | Cost annual mill USD: ", round(cost_annual_millionsUSD_usingHDDSgaps, 1))
  ) %>%
  
  select(country_name, year, ipcphase, byPhaseValue, total_cost_annual_millionsUSD_usingHDDSgaps) %>%
  
   pivot_wider(
    id_cols = c(country_name, year, total_cost_annual_millionsUSD_usingHDDSgaps),       
    names_from = ipcphase,            
    values_from = byPhaseValue,
    names_prefix = "IPC phase "
    ) 

# now on to the HHS table------------------------------------------------------------------
gaps_Table_hhs <- gaps_Table_1 %>%
  mutate(
    byPhaseValue = paste0("Pop: ", population, " | HHS gap: ", fgt1_hhs, " | Cost annual mill USD: ", round(cost_annual_millionsUSD_usingHHSgaps, 1))
  ) %>%
  
  select(country_name, year, ipcphase, byPhaseValue, total_cost_annual_millionsUSD_usingHHSgaps) %>%
  
   pivot_wider(
    id_cols = c(country_name, year, total_cost_annual_millionsUSD_usingHHSgaps),       
    names_from = ipcphase,            
    values_from = byPhaseValue,
    names_prefix = "IPC phase "
    ) 

# Now table with only the total cost columns---------------------------------------------

gapsTableTotalsUSDByCountry <- gaps_Table_1 %>%
  select(country_name, year, total_cost_annual_millionsUSD_usingFCSgaps:total_cost_annual_millionsUSD_usingHHSgaps) %>%
  group_by(country_name, year) %>% slice(1) %>% ungroup()
  
gapsTableTotalsUSDByCountry <- gapsTableTotalsUSDByCountry %>%
  rename(
    Country = country_name,
    Year    = year,
    "Cost using FCS gaps (mill. USD)"  = total_cost_annual_millionsUSD_usingFCSgaps,
    "Cost using RCSI gaps (mill. USD)" = total_cost_annual_millionsUSD_usingRCSIgaps,
    "Cost using HDDS gaps (mill. USD)" = total_cost_annual_millionsUSD_usingHDDSgaps,
    "Cost using HHS gaps (mill. USD)"  = total_cost_annual_millionsUSD_usingHHSgaps
  )

write_paper_table(gapsTableTotalsUSDByCountry, file.path(finalTablesFolder, "Table10_all_indicator_costs.xlsx"))
  





# ## Table - indicator gaps by phase
# ---- combinegaps ----

countries_fgtgaps <- IPCDIEM_hh %>%
  select(adm0_name) %>% distinct() %>% arrange(adm0_name) %>%
  left_join(fcs_gap) %>%
  left_join(rcsi_gap)%>%
  left_join(HDDS_gap) %>%
  left_join(hhs_gap)


# export to excel — nested headers (FCS / HDDS / rCSI / HHS × FGT0/FGT1)
local({
  df <- countries_fgtgaps %>%
    select(adm0_name,
           FCS_FGT0,  FCS_FGT1,
           hdds_FGT0, hdds_FGT1,
           RCSI_FGT0, RCSI_FGT1,
           hhs_FGT0,  hhs_FGT1) %>%
    rename(Country = adm0_name) %>%
    mutate(across(where(is.numeric), ~round(.x, 2)))

  wb <- createWorkbook()
  sh <- "Sheet1"
  addWorksheet(wb, sh)

  # Row 1: top-level indicator groups
  writeData(wb, sh, startRow = 1, startCol = 1, colNames = FALSE, x = data.frame(
    A = "Country",
    B = "FCS",  C = "",
    D = "HDDS", E = "",
    F = "rCSI", G = "",
    H = "HHS",  I = ""
  ))
  mergeCells(wb, sh, rows = 1, cols = 2:3)
  mergeCells(wb, sh, rows = 1, cols = 4:5)
  mergeCells(wb, sh, rows = 1, cols = 6:7)
  mergeCells(wb, sh, rows = 1, cols = 8:9)

  # Row 2: sub-headers
  writeData(wb, sh, startRow = 2, startCol = 1, colNames = FALSE, x = data.frame(
    A = "Country",
    B = "FGT0", C = "FGT1",
    D = "FGT0", E = "FGT1",
    F = "FGT0", G = "FGT1",
    H = "FGT0", I = "FGT1"
  ))

  # Data
  writeData(wb, sh, x = df, startRow = 3, startCol = 1, colNames = FALSE)

  header_style <- createStyle(textDecoration = "bold", halign = "center", valign = "center",
                              wrapText = TRUE, fontName = "Times New Roman", fontSize = 9,
                              border = "TopBottomLeftRight", borderStyle = "thin", fgFill = "#BDD7EE")
  left_style   <- createStyle(halign = "left",   valign = "center",
                              fontName = "Times New Roman", fontSize = 9,
                              border = "TopBottomLeftRight", borderStyle = "thin")
  body_style   <- createStyle(halign = "center", valign = "center",
                              fontName = "Times New Roman", fontSize = 9,
                              border = "TopBottomLeftRight", borderStyle = "thin")

  addStyle(wb, sh, header_style, rows = 1:2,              cols = 1:9, gridExpand = TRUE)
  addStyle(wb, sh, left_style,   rows = 3:(nrow(df) + 2), cols = 1,   gridExpand = TRUE)
  addStyle(wb, sh, body_style,   rows = 3:(nrow(df) + 2), cols = 2:9, gridExpand = TRUE)

  setColWidths(wb, sh, cols = 1,    widths = 20)
  setColWidths(wb, sh, cols = 2:9,  widths = 10)

  saveWorkbook(wb, file.path(outputVizInOutputFolder, "table_fgtIndicatorGaps_by country.xlsx"), overwrite = TRUE)
  saveWorkbook(wb, file.path(finalTablesFolder, "TableA3_FGT_by_country.xlsx"),                 overwrite = TRUE)
})




# ## Table - Combine indicator gaps by country and phase
# ---- combinegaps_countryPhase ----

indicatorGapsByPhase <- bind_rows(gap_FCS_byPhase, gap_RCSI_byPhase,gap_hdds_byPhase,gap_hhs_byPhase) %>%
    rename(ipcphase = area_overall_phase) %>%
  select(adm0_name, ipcphase, indicator, FGT0,FGT1) %>%
  pivot_wider(
    id_cols = c(adm0_name, ipcphase),
    names_from = indicator,
    values_from = c(FGT0, FGT1),
    names_glue = "{indicator}_{.value}"
  ) %>%
    relocate(matches("^FCS_"), .after = ipcphase) %>%
  relocate(matches("^rcsi_"), .after = last_col()) %>%
  relocate(matches("^hdds_"), .after = last_col()) %>%
  relocate(matches("^hhs_"), .after = last_col()) %>%
    pivot_wider(
    id_cols = adm0_name,
    names_from = ipcphase,
    values_from = c(FCS_FGT0, FCS_FGT1,
                    rcsi_FGT0, rcsi_FGT1,
                    hdds_FGT0, hdds_FGT1,
                    hhs_FGT0,  hhs_FGT1),
    names_glue = "{.value}_phase{ipcphase}"
  )

# Table 8: FCS FGT by country, IPC phases 3 and 4 only, with grouped column headers
indicatorGapsByPhase_fcs <- indicatorGapsByPhase %>%
  select(adm0_name,
    FCS_FGT0_phase3, FCS_FGT1_phase3,
    FCS_FGT0_phase4, FCS_FGT1_phase4
  ) %>%
  filter(!if_all(c(FCS_FGT0_phase3, FCS_FGT1_phase3, FCS_FGT0_phase4, FCS_FGT1_phase4), is.na)) %>%
  rename(Country = adm0_name)

local({
  df <- indicatorGapsByPhase_fcs
  wb <- createWorkbook()
  sh <- "Sheet1"
  addWorksheet(wb, sh)

  # Group header row
  writeData(wb, sh, x = data.frame(A="Country", B="FCS gap IPC 3", C="", D="FCS gap IPC 4", E=""),
            startRow = 1, startCol = 1, colNames = FALSE)
  mergeCells(wb, sh, rows = 1, cols = 2:3)
  mergeCells(wb, sh, rows = 1, cols = 4:5)

  # Sub-header row
  writeData(wb, sh, x = data.frame(A="Country", B="FGT0", C="FGT1", D="FGT0", E="FGT1"),
            startRow = 2, startCol = 1, colNames = FALSE)

  # Data
  df <- df %>% mutate(across(where(is.numeric), ~round(., 1)))
  writeData(wb, sh, x = df, startRow = 3, startCol = 1, colNames = FALSE)

  header_style <- createStyle(textDecoration = "bold", halign = "center", valign = "center",
                              fontName = "Times New Roman", fontSize = 9, border = "TopBottomLeftRight", borderStyle = "thin", fgFill = "#BDD7EE")
  body_style   <- createStyle(halign = "center", valign = "center", fontName = "Times New Roman", fontSize = 9,
                              border = "TopBottomLeftRight", borderStyle = "thin")
  left_style   <- createStyle(halign = "left",   valign = "center", fontName = "Times New Roman", fontSize = 9,
                              border = "TopBottomLeftRight", borderStyle = "thin")

  addStyle(wb, sh, header_style, rows = 1:2,              cols = 1:5, gridExpand = TRUE)
  addStyle(wb, sh, left_style,   rows = 3:(nrow(df) + 2), cols = 1,   gridExpand = TRUE)
  addStyle(wb, sh, body_style,   rows = 3:(nrow(df) + 2), cols = 2:5, gridExpand = TRUE)

  setColWidths(wb, sh, cols = 1:5, widths = c(20, 10, 10, 10, 10))
  saveWorkbook(wb, file.path(finalTablesFolder, "Table8_FCS_FGT_by_country_phase.xlsx"), overwrite = TRUE)
})


# AppendixA3.2: All-indicator FGT by country × phase (phases 3 and 4), separate columns
AppendixA3_2 <- indicatorGapsByPhase %>%
  select(adm0_name,
    FCS_FGT0_phase3,  FCS_FGT1_phase3,  FCS_FGT0_phase4,  FCS_FGT1_phase4,
    hdds_FGT0_phase3, hdds_FGT1_phase3, hdds_FGT0_phase4, hdds_FGT1_phase4,
    rcsi_FGT0_phase3, rcsi_FGT1_phase3, rcsi_FGT0_phase4, rcsi_FGT1_phase4,
    hhs_FGT0_phase3,  hhs_FGT1_phase3,  hhs_FGT0_phase4,  hhs_FGT1_phase4
  )

local({
  df <- AppendixA3_2 %>%
    rename(Country = adm0_name) %>%
    mutate(across(where(is.numeric), ~round(., 1)))

  wb <- createWorkbook()
  sh <- "Sheet1"
  addWorksheet(wb, sh)

  # Row 1: top-level indicator groups (FCS cols 2-5, HDDS 6-9, rCSI 10-13, HHS 14-17)
  writeData(wb, sh, startRow = 1, startCol = 1, colNames = FALSE, x = data.frame(
    A="Country", B="FCS", C="", D="", E="",
    F="HDDS",    G="", H="", I="",
    J="rCSI",    K="", L="", M="",
    N="HHS",     O="", P="", Q=""
  ))
  mergeCells(wb, sh, rows = 1, cols = 2:5)
  mergeCells(wb, sh, rows = 1, cols = 6:9)
  mergeCells(wb, sh, rows = 1, cols = 10:13)
  mergeCells(wb, sh, rows = 1, cols = 14:17)

  # Row 2: phase groups within each indicator
  writeData(wb, sh, startRow = 2, startCol = 1, colNames = FALSE, x = data.frame(
    A="Country",
    B="FCS gap IPC 3",  C="",  D="FCS gap IPC 4",  E="",
    F="HDDS gap IPC 3", G="",  H="HDDS gap IPC 4",  I="",
    J="rCSI gap IPC 3", K="",  L="rCSI gap IPC 4",  M="",
    N="HHS gap IPC 3",  O="",  P="HHS gap IPC 4",   Q=""
  ))
  for (start_col in c(2, 4, 6, 8, 10, 12, 14, 16)) {
    mergeCells(wb, sh, rows = 2, cols = start_col:(start_col + 1))
  }

  # Row 3: FGT0 / FGT1 sub-headers
  writeData(wb, sh, startRow = 3, startCol = 1, colNames = FALSE, x = data.frame(
    A="Country",
    B="FGT0", C="FGT1", D="FGT0", E="FGT1",
    F="FGT0", G="FGT1", H="FGT0", I="FGT1",
    J="FGT0", K="FGT1", L="FGT0", M="FGT1",
    N="FGT0", O="FGT1", P="FGT0", Q="FGT1"
  ))

  # Data
  writeData(wb, sh, x = df, startRow = 4, startCol = 1, colNames = FALSE)

  header_style <- createStyle(textDecoration = "bold", halign = "center", valign = "center",
                              wrapText = TRUE, fontName = "Times New Roman", fontSize = 9,
                              border = "TopBottomLeftRight", borderStyle = "thin", fgFill = "#BDD7EE")
  left_style   <- createStyle(halign = "left",   valign = "center",
                              fontName = "Times New Roman", fontSize = 9,
                              border = "TopBottomLeftRight", borderStyle = "thin")
  body_style   <- createStyle(halign = "center", valign = "center",
                              fontName = "Times New Roman", fontSize = 9,
                              border = "TopBottomLeftRight", borderStyle = "thin")

  addStyle(wb, sh, header_style, rows = 1:3,              cols = 1:17, gridExpand = TRUE)
  addStyle(wb, sh, left_style,   rows = 4:(nrow(df) + 3), cols = 1,    gridExpand = TRUE)
  addStyle(wb, sh, body_style,   rows = 4:(nrow(df) + 3), cols = 2:17, gridExpand = TRUE)

  setColWidths(wb, sh, cols = 1,     widths = 20)
  setColWidths(wb, sh, cols = 2:17,  widths = 8)
  saveWorkbook(wb, file.path(finalTablesFolder, "TableA4_FGT_by_country_phase.xlsx"), overwrite = TRUE)
})







# # ==========================================
# # DEFICITS BY PHASE

# ## setting the per phase gaps
# ---- perPhaseGaps ----
# IPC1_calDef through IPC5_calDef defined earlier in script (before dataMaching section)

fullAmt <- 2100




# ## base table
# ---- createbasetableForPaper ----
baseTable <- data.frame(
  IPC_phase = c("IPC1", "IPC2", "IPC3", "IPC4", "IPC5"),
  assumedCalorieDeficit = c("0%", "0%", "10.5%", "35.5%", "50%")
  )


#create table of thresholds
IPCthresholds <- data.frame(
  IPC_phase = c("IPC1", "IPC2", "IPC3", "IPC4", "IPC5"),
  IPC_calDef = c(IPC1_calDef, IPC2_calDef, IPC3_calDef, IPC4_calDef, IPC5_calDef)
) %>%
  mutate(
    calDef_amt = fullAmt * IPC_calDef,
    kcal_per_person_per_day = fullAmt - calDef_amt,
    cerealkgDeficit = round(calDef_amt/3790, 2)
  )


tableForPaper <- IPCthresholds %>%
  left_join(baseTable) %>%
  select(IPC_phase, assumedCalorieDeficit, calDef_amt, kcal_per_person_per_day, cerealkgDeficit) %>%
  rename(
    "IPC Phase" = IPC_phase,
    "Assumed caloric deficit (%)" = assumedCalorieDeficit,
    "Assumed caloric deficit in KCal pp/pd" = calDef_amt,
    "Assumed average consumption in KCal pp/pd" = kcal_per_person_per_day,
    "Assumed average deficit in cereals kg/pp/pd" = cerealkgDeficit
  ) %>%
  slice(1:5)


write_paper_table(tableForPaper, file.path(finalTablesFolder, "Table3_caloric_deficits_by_phase.xlsx"))





# ## applying to IPC data
# ---- IPCdata ----

IPCcalculations <- IPCdataImported %>% 
  mutate(country_name = countrycode(iso3, origin = "iso3c", destination = "country.name")) %>% select(country_name, everything()) %>%
  #remove labonon because of stage duplications
  filter(country_name != "Lebanon") %>%
  select(-iso3) %>%
  mutate(country_title = paste(country_name, " - ", country_title)) %>%
  # keep country_name until after peak-analysis selection below
  # for the merging
  rename(IPC_phase = area_overall_phase) %>%
  mutate(IPC_phase = case_when(
    IPC_phase == 1~ "IPC1",
    IPC_phase == 2~ "IPC2",
    IPC_phase == 3~ "IPC3",
    IPC_phase == 4~ "IPC4",
    IPC_phase == 5~ "IPC5")
  ) %>%
  #making it longer
  select(-c(country_current_period_dates, IPC_phase,area_p3plus_percentage, adm_name: last_col())) %>%
  group_by(country_title) %>% slice(1) %>% ungroup() %>%
  # select the analysis with the highest total population coverage per country
  mutate(totalPopulationCovered = country_phase1_population + country_phase2_population +
           country_phase3_population + country_phase4_population + country_phase5_population) %>%
  group_by(country_name) %>%
  slice_max(totalPopulationCovered, n = 1, with_ties = FALSE) %>%
  ungroup() %>%
  select(-country_name, -totalPopulationCovered) %>%

#IPCcalculations %>% group_by(id) %>% count() %>% filter(n>1)
  pivot_longer(
    cols = country_phase1_population:country_phase5_percentage,  
    names_to = "indicator",                               
    values_to = "value"                                  
  ) %>%
      separate(indicator, into = c("area", "phase", "metric"), sep = "_", remove = TRUE) %>% select(-area) %>%

    pivot_wider(
    names_from = metric,
    values_from = value,
    names_glue = "{metric}InPhase"
  ) %>%
  rename(
    percentage_inPhase = percentageInPhase,
    population_inPhase = populationInPhase
  ) %>%
  rename( IPC_phase = phase) %>%
  mutate(IPC_phase = case_when(
    IPC_phase == "phase1" ~ "IPC1",
    IPC_phase == "phase2" ~ "IPC2",
    IPC_phase == "phase3" ~ "IPC3",
    IPC_phase == "phase4" ~ "IPC4",
    IPC_phase == "phase5" ~ "IPC5",

  )) %>%
  mutate(
    percentage_inPhase = as.numeric(percentage_inPhase),
    population_inPhase = as.numeric(population_inPhase)
  ) %>%
  left_join(IPCthresholds) %>%
  
  
   # FGT index by phase
  mutate(
    calGap_FGT_byphase = IPC_calDef * percentage_inPhase) %>%
  group_by(country_title) %>%
  mutate(
    calGap_FGT_acrossAnalysis = sum(calGap_FGT_byphase, na.rm = TRUE)
  ) %>% ungroup() %>%

  # total kcal gap
  mutate(
    gap_inKcal_byPhase_acrossPopulation = population_inPhase * calDef_amt
  ) %>%
  group_by(country_title) %>%
  mutate(
    totalGap_inKcal_byAnalysis = sum(gap_inKcal_byPhase_acrossPopulation)
  ) %>% ungroup() %>%

  # cereal gap in MT
  mutate(
    gap_cerealKG_byPhase_acrossPopulation = population_inPhase * cerealkgDeficit
  ) %>%
  group_by(country_title) %>%
  mutate(
    gap_cerealKG_byAnalysis_acrossPopulation = sum(gap_cerealKG_byPhase_acrossPopulation, na.rm = TRUE)
  ) %>% ungroup() %>%
  mutate(
    byPhaseGap_MTCereal = gap_cerealKG_byPhase_acrossPopulation / 1000,
    totalGap_MTCereal   = gap_cerealKG_byAnalysis_acrossPopulation / 1000
  ) %>%
  select(-c(gap_cerealKG_byPhase_acrossPopulation, gap_cerealKG_byAnalysis_acrossPopulation))




# ## tables with ranges

# ---- IPCdataImportPrep_3 ----

tablePrep <- IPCcalculations %>%
  mutate(
    MillKcalNeeds_byPhase    = gap_inKcal_byPhase_acrossPopulation / 1000000,
    totalGap_inmillKCal      = totalGap_inKcal_byAnalysis / 1000000,
    population_inPhase       = scales::comma_format(accuracy = 1)(population_inPhase),
    byPhaseGap_MTCereal      = scales::comma_format(accuracy = 0.1)(byPhaseGap_MTCereal),
    totalGap_MTCereal        = scales::comma_format(accuracy = 0.1)(totalGap_MTCereal),
    MillKcalNeeds_byPhase    = scales::comma_format(accuracy = 0.1)(MillKcalNeeds_byPhase),
    totalGap_inmillKCal      = scales::comma_format(accuracy = 0.1)(totalGap_inmillKCal)
  )

tableWithRanges <- tablePrep %>%
  mutate(country_title = str_remove(country_title, "Acute Food Insecurity")) %>%
  mutate(country_title = str_remove(country_title, "Cadre Harmonisé")) %>%
  mutate(country_title = str_remove(country_title, "CH Analysis")) %>%
  filter(!str_detect(country_title, "displaced")) %>%
  # peak-analysis selection is now done in IPCcalculations; just drop the date column
  select(-country_analysis_date) %>%
  rename(
    "Gap mill. kcal"                  = MillKcalNeeds_byPhase,
    "Total gap mill. kcal"            = totalGap_inmillKCal,
    "Calorie gap by phase (FGT index)"= calGap_FGT_byphase,
    "Calorie gap (FGT index)"         = calGap_FGT_acrossAnalysis,
    "Gap MT cereal"                   = byPhaseGap_MTCereal,
    "Total gap MT cereal"             = totalGap_MTCereal
  ) %>%
  select(
    country_title, IPC_phase, population_inPhase,
    `Gap mill. kcal`, `Total gap mill. kcal`,
    `Calorie gap by phase (FGT index)`, `Calorie gap (FGT index)`,
    `Gap MT cereal`, `Total gap MT cereal`
  )

# export to excel final file..............................................
dataForExcel <- tableWithRanges %>%
 select(country_title, IPC_phase, population_inPhase, 
         `Gap mill. kcal`,  `Calorie gap by phase (FGT index)`, `Gap MT cereal`) %>%
  rename(
    Country = country_title,
    Phase = IPC_phase,
    "No. people" = population_inPhase
  ) 

dataForExcel <- tableWithRanges %>%
  select(country_title, IPC_phase, population_inPhase,
         `Gap mill. kcal`, `Calorie gap by phase (FGT index)`, `Gap MT cereal`) %>%
  mutate(population_numeric = parse_number(as.character(population_inPhase))) %>%
  filter(population_numeric > 0) %>%
  select(-population_numeric) %>%
  rename(
    "Name of IPC analysis" = country_title,
    Phase        = IPC_phase,
    "No. people" = population_inPhase
  )

write_paper_table(dataForExcel, file.path(finalTablesFolder, "TableA2_deficits_by_country_phase.xlsx"))


#=====================================================================================================
#table 2 - food assistance for matched countries only

# iso3 codes of countries in the matched IPC-DIEM dataset
matched_iso3s <- unique(IPCDIEM_hh$iso3)

dataForExcel <- tableWithRanges %>%
  select(country_title, IPC_phase, population_inPhase,
         `Total gap mill. kcal`, `Calorie gap (FGT index)`, `Total gap MT cereal`) %>%
  mutate(
    country_name_clean = str_extract(country_title, "^[^-]+") %>% str_trim(),
    iso3_temp = countrycode(country_name_clean, origin = "country.name", destination = "iso3c")
  ) %>%
  filter(iso3_temp %in% matched_iso3s) %>%
  select(-country_name_clean, -iso3_temp) %>%
  group_by(country_title) %>% slice(1) %>% ungroup() %>% select(-IPC_phase) %>%
  mutate(population_numeric = parse_number(as.character(population_inPhase))) %>%
  filter(population_numeric > 0) %>%
  select(-population_numeric) %>%
  rename(
    "Name of IPC analysis" = country_title,
    "No. people"           = population_inPhase
  )
# export to excel final file..............................................


write_paper_table(dataForExcel, file.path(finalTablesFolder, "Table4_food_assistance_by_country.xlsx"))


#=============================================================================
#calculating total needs. 

# now to excel .............
# Define path
# excel_file <- file.path(outputVizInOutputFolder, "Table3.xlsx")
# 
# # Create workbook and worksheet
# wb <- createWorkbook()
# addWorksheet(wb, "table")
# 
# dataForExcel <- tablePrep %>%
#   # create variable that is the number is IPC 3+ 
#   mutate(
#     population_inPhase_numerica = parse_number(population_inPhase)
#     )%>%
#   mutate(no3Plus_intermed = case_when(
#     IPC_phase %in% c("IPC3", "IPC4", "IPC5") ~ population_inPhase_numerica, 
#     TRUE ~0 
#   )) %>%
#   group_by(country_title) %>% mutate(no3Plus = sum(no3Plus_intermed, na.rm = TRUE)) %>% ungroup() %>% select(-no3Plus_intermed) %>%
#   select(country_title, IPC_phase, population_inPhase, no3Plus, 
#          `Total gap mill. kcal`, `Total gap MT cereal`) %>%
#   group_by(country_title) %>% slice(1) %>% ungroup() %>% select(-IPC_phase) %>%
#   rename(
#     Country = country_title,
#     "No. people" = population_inPhase
#   ) 
# 
# # Write plain data
# writeData(
#   wb,
#   sheet = "table",
#   x = dataForExcel,
#   startCol = 1,
#   startRow = 1,
#   colNames = TRUE,
#   rowNames = FALSE
# )
# 
# # Header style: bold, centered, wrapped
# header_style <- createStyle(
#   textDecoration = "bold",
#   halign = "center",
#   valign = "center",
#   wrapText = TRUE,
#   fontName = "Times New Roman", fontSize = 9
# )
# addStyle(
#   wb,
#   sheet = "table",
#   style = header_style,
#   rows = 1,
#   cols = 1:ncol(tableForPaper),
#   gridExpand = TRUE
# )
# 
# # Body style: center-align
# body_style <- createStyle(
#   halign = "center",
#   valign = "center"
# )
# addStyle(
#   wb,
#   sheet = "table",
#   style = body_style,
#   rows = 2:(nrow(dataForExcel) + 1),
#   cols = 1:ncol(dataForExcel),
#   gridExpand = TRUE
# )
# 
# # 🔲 Border style: thin border around all cells (including headers)
# border_style <- createStyle(
#   border = "TopBottomLeftRight",
#   borderStyle = "thin"
# )
# addStyle(
#   wb,
#   sheet = "table",
#   style = border_style,
#   rows = 1:(nrow(dataForExcel) + 1),
#   cols = 1:ncol(dataForExcel),
#   gridExpand = TRUE,
#   stack = TRUE  # Preserve previous styles
# )
# 
# # Set compact column widths
# setColWidths(wb, sheet = "table", cols = 1:ncol(dataForExcel), widths = 15)
# 
# # Save the workbook
# saveWorkbook(wb, excel_file, overwrite = TRUE)
# 
# 





# # ==========================================

# # PCA (old)
# ## id/desc pc

# ---- pca ----
dataForPCA <- IPC_DIEM %>%
  select(fies_rawscore_wmean,# p_mod_wmean, 
         fcs_wmean, rcsi_score_wmean, hdds_score_wmean, area_p3plus_percentage, area_overall_phase) %>%
  na.omit() %>%
  filter(area_overall_phase == 4) %>% select(-area_overall_phase)

# Scale the variables so they are comparable
pca_result <- princomp(dataForPCA %>% select(-area_p3plus_percentage), cor = TRUE)

# View a summary of the PCA
summary(pca_result)

# Show loadings for the first two principal components
pca_result$loadings[, 1:2]

# visualize=====================
fviz_eig(pca_result, addlabels = TRUE)

fviz_pca_var(pca_result, col.var = "black",repel = TRUE)

# contribution of each variable
fviz_cos2(pca_result, choice = "var", axes = 1:2)

# contribution with the directions
fviz_pca_var(pca_result, col.var = "cos2",
            gradient.cols = c("black", "orange", "green"),
            repel = TRUE)


# getting first principal component scores
pc1_scores <- pca_result$scores[,1]
pc2_scores <- pca_result$scores[,2]


# creating a new data frame with PC1 and outcome
analysis_df <- dataForPCA %>%
  mutate(
    PC1 = pc1_scores,
    PC2 = pc2_scores
    )
# fitting a regression model with PC1 predicting share in IPC 3+
model <- lm(area_p3plus_percentage ~ PC1, data = analysis_df)
summary(model)

# ## regress IPC3+ on the three variables and the two principal components

# ## regress on principal components
# ---- regressionpca ----

# fitting a regression model with PC1 predicting share in IPC 3+
model <- lm(area_p3plus_percentage ~ PC1, data = analysis_df)
summary(model)

model <- lm(area_p3plus_percentage ~ PC2, data = analysis_df)
summary(model)



# ## regress on three individual indicators
# ---- regression1 ----
model_direct <- lm(area_p3plus_percentage ~ fies_rawscore_wmean,
                   data = dataForPCA)
summary(model_direct)

model_direct <- lm(area_p3plus_percentage ~ fcs_wmean,
                   data = dataForPCA)
summary(model_direct)

model_direct <- lm(area_p3plus_percentage ~  rcsi_score_wmean,
                   data = dataForPCA)
summary(model_direct)






