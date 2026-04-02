# Script bringing in imported IPC data and the DIEM data to match
# 2025_03_20

#### Library ####
library(tidyverse)
library(RMySQL)

library(countrycode)
library(lubridate)

#### Global folders ####

dataFolder <- "C:/Users/BRICE/IFPRI Dropbox/Brendan Rice/DIEM_IPC_analysis/Data"
outputFolder <- "C:/Users/BRICE/IFPRI Dropbox/Brendan Rice/DIEM_IPC_analysis/Output"

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

#### Aggregated data ####

DIEM_FoodSecurityImported<- read_csv(file.path(dataFolder, "DIEM_household_surveys_aggregated_data_(food_security_thematic_area)_-5236016848326234343.csv")) %>%
  rename(iso3 = adm0_iso3) %>%
  mutate(coll_start_date = mdy_hms(coll_start_date))

del <- DIEM_FoodSecurityImported %>% 
  select(contains("hhs")) %>%  colnames() %>% as.data.frame() 

DIEM_IncomeImported<- read_csv(file.path(dataFolder, "DIEM_household_surveys_aggregated_data_(income_shocks_and_needs_thematic_areas)_-8295228611698009492.csv")) %>%
  rename(iso3 = adm0_iso3)

IPCdataImported <- readRDS(file.path(dataFolder, "IPCdata_imported.rds")) %>%
  select(country_ISO2Code:country_current_period_dates, area_name, area_overall_phase) %>%
  mutate(iso3 = countrycode::countrycode(country_ISO2Code, origin = "iso2c", destination = "iso3c")) %>%
  relocate(iso3, .after = country_ISO2Code) %>% select(-country_ISO2Code) %>%
  mutate(country_analysis_date = as.Date(country_analysis_date)) %>%
  rename(adm_name = area_name)

# creating date overlapping
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
         hdds_class_1: hdds_class_3,
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

# checking which were matched 
IPC_DIEM_matched <- DIEM_FoodSecurity %>%
  left_join(IPCdata, c("adm_name", "iso3")) #%>%
 # select(adm_name) %>% distinct() %>% arrange() %>% pull()
  

# joining based on admin2
IPC_DIEM <- DIEM_FoodSecurity %>%
  left_join(IPCdata, c("adm_name", "iso3")) %>%
  filter(
    start_dateForMatching_IPC <= end_dateForMatching_DIEM &
      end_dateForMatching_IPC >= start_dateForMatching_DIEM
  ) %>%
  select(iso3, adm_name, coll_start_date, 
         # the indicators wanted here 
         fcs_median, fcs_wmean,  hhs_0: hhs_6,rcsi_score_median, rcsi_score_wmean,
          country_title, country_analysis_date, country_current_period_dates,  area_overall_phase) %>%
  rename(DIEM_startDate=coll_start_date,
         IPC_country_title = country_title,
         IPC_analysis_date = country_analysis_date,
         IPC_current_period_dates = country_current_period_dates)


# now summarize the indicators by phase 

### FCS median by IPC phase

#Seeing which countries to focus on
#common_areaName <-  as.vector(intersect(DIEM_FS_SOM$adm_name, IPCdata_SOM$area_name))


#### Household level data ####
del <- read_csv(file.path(dataFolder, "DIEM Household surveys microdata_20251003155124.csv")) %>%
  select(contains("hhs")) %>%  colnames() %>% as.data.frame() 

DIEM_FoodSecurity_HH_Imported<- read_csv(file.path(dataFolder, "DIEM Household surveys microdata_20251003155124.csv")) 
DIEM_FoodSecurity_HH <- DIEM_FoodSecurity_HH_Imported %>%
  select(2:14, 
        # fies_rawscore, 
         fcs, hhs, lcsi, hdds_score, rcsi_score, 
         weight_final, last_col()) %>%
  select(-c(adm0_m49))


del <- DIEM_FoodSecurity_HH_Imported %>%
  filter(adm0_name == "Sierra Leone")
del <- DIEM_FoodSecurity_HH_Imported %>%
  filter(survey_date < "2023-01-01")


# del2 <- DIEM_FoodSecurity_HH__2021to22 %>%
#   filter(adm0_name == "Sierra Leone")

DIEM_FoodSecurity_HH__2021to22_Imported<- read_csv(file.path(dataFolder, "Household_Surveys_Microdata_6215924197953569388.csv")) 
del <- colnames(DIEM_FoodSecurity_HH__2021to22_Imported)
fies_cols <- str_subset(del, regex("fies", ignore_case = TRUE))
DIEM_FoodSecurity_HH__2021to22 <- DIEM_FoodSecurity_HH__2021to22_Imported %>%
  select(1:12, 
         #there's no FIES, 
         fcs, hhs, lcsi, hdds_score, rcsi_score, 
         weight_final, last_col()) %>%
  rename(
    adm0_name = `Admin 0 name`,
    adm0_iso3 = `Admin 0 ISO3`,
    adm1_pcode = `Admin 1 PCODE`,
    adm1_name = `Admin 1 name`,
    adm2_pcode = `Admin 2 PCODE`,
    adm2_name = `Admin 2 name`,
    adm3_pcode = `Admin 3 PCODE`,
    adm3_name = `Admin 3 name`
  ) %>%
  mutate(survey_date = mdy_hms(survey_date))

DIEM_hh_combined <- bind_rows(
  DIEM_FoodSecurity_HH, DIEM_FoodSecurity_HH__2021to22
) %>%
  rename(iso3 = adm0_iso3) %>%
  # create time window for matching
  mutate(start_dateForMatching_DIEM = survey_date %m-% months(5),
         end_dateForMatching_DIEM = survey_date %m+% months(5)) %>%
  relocate(c(start_dateForMatching_DIEM, end_dateForMatching_DIEM), .before =survey_date ) %>%
  # determine  the admin level for matching to IPC
  rename(
    adm_name = adm2_name
  ) %>%
  mutate(
    adm0_name = case_when(
      adm0_name == "Democratic Republic of Congo" ~ 	"Democratic Republic of the Congo",
      TRUE ~ adm0_name)) %>%
  filter(survey_date > "2020-12-31")

del <- DIEM_hh_combined %>% select(adm0_name) %>% distinct() %>% arrange(adm0_name)

del <- DIEM_hh_combined %>% mutate(year = year(survey_date)) %>%
  group_by(year) %>% count()

##### clean variables/indicators with obvious errors #####
indicators_checkingOutliers <- DIEM_hh_combined %>%
  select(fcs:rcsi_score) %>%
  pivot_longer(
    cols = everything(), 
    names_to = "indicator", 
    values_to = "value"
  ) %>%  
  group_by(indicator) %>%
  summarize(
    min = min(value, na.rm = TRUE),
    q01 = quantile(value, 0.01, na.rm = TRUE),
    q02 = quantile(value, 0.02, na.rm = TRUE),
    median = median(value, na.rm = TRUE),
    q97 = quantile(value, 0.97, na.rm = TRUE),
    q98 = quantile(value, 0.98, na.rm = TRUE),
    q99 = quantile(value, 0.99, na.rm = TRUE),
    "q99.5" = quantile(value, 0.995, na.rm = TRUE),
    highest6th = sort(value, decreasing = TRUE)[6],
    highest5th = sort(value, decreasing = TRUE)[5],
    highest4th = sort(value, decreasing = TRUE)[4],
    highest3rd = sort(value, decreasing = TRUE)[3],
    highest2nd = sort(value, decreasing = TRUE)[2],
    max = max(value, na.rm = TRUE)
  )


DIEM_hh_combined_clean <- DIEM_hh_combined %>%
  #clean fcs
  mutate(
    #first the fcs - there were some very high values 99th percentile was 101 so I winsorize here. 
    fcs = case_when(
      fcs>112 ~ 112,
      TRUE ~ fcs)
  ) %>%
  #clean RCSI extreme values
  mutate(
    rcsi_score = case_when(
      rcsi_score < 0 ~ NA_integer_,
      rcsi_score >56 ~ 56,
      TRUE ~ rcsi_score
    )
  )

DIEM_hh_combined <- DIEM_hh_combined_clean

distributionAfterCleaning <- DIEM_hh_combined %>%
  select(fcs:rcsi_score) %>%
  pivot_longer(
    cols = everything(), 
    names_to = "indicator", 
    values_to = "value"
  ) %>%  
  group_by(indicator) %>%
  group_by(indicator) %>%
  summarize(
    min = min(value, na.rm = TRUE),
    q01 = quantile(value, 0.01, na.rm = TRUE),
    q02 = quantile(value, 0.02, na.rm = TRUE),
    median = median(value, na.rm = TRUE),
    q97 = quantile(value, 0.97, na.rm = TRUE),
    q98 = quantile(value, 0.98, na.rm = TRUE),
    q99 = quantile(value, 0.99, na.rm = TRUE),
    "q99.5" = quantile(value, 0.995, na.rm = TRUE),
    highest6th = sort(value, decreasing = TRUE)[6],
    highest5th = sort(value, decreasing = TRUE)[5],
    highest4th = sort(value, decreasing = TRUE)[4],
    highest3rd = sort(value, decreasing = TRUE)[3],
    highest2nd = sort(value, decreasing = TRUE)[2],
    max = max(value, na.rm = TRUE)
  )
  
# now just the 2023+ data so there's fies 
DIEM_hh_post2022 <- DIEM_FoodSecurity_HH_Imported %>%
  select(2:14, 
          fies_rawscore, 
         fcs, hhs, lcsi, hdds_score, rcsi_score, 
         weight_final, last_col()) %>%
  select(-c(adm0_m49)) %>% 
  #clean in same way
  #clean fcs
  mutate(
    #first the fcs - there were some very high values 99th percentile was 101 so I winsorize here. 
    fcs = case_when(
      fcs>112 ~ 112,
      TRUE ~ fcs)
  ) %>%
  #clean RCSI extreme values
  mutate(
    rcsi_score = case_when(
      rcsi_score < 0 ~ NA_integer_,
      rcsi_score >56 ~ 56,
      TRUE ~ rcsi_score
    )
  ) %>%
  #then there wwere a few observations from 2027 for some reason
  filter(survey_date > "2022-12-31")

##### save household DIEM data ####
saveRDS(DIEM_hh_combined, file.path(dataFolder, "DIEM_hh_joinedAndClean.rds"))
saveRDS(DIEM_hh_post2022, file.path(dataFolder, "DIEM_hhpost2022AndClean.rds"))


#### import IPC and combine w/ DIEMhh ####
IPCdataImported <- readRDS(file.path(dataFolder, "IPCdata_imported.rds")) %>%
  filter(area_overall_phase != -1) %>%
  select(country_ISO2Code:country_current_period_dates, area_name, area_overall_phase) %>%
  mutate(iso3 = countrycode::countrycode(country_ISO2Code, origin = "iso2c", destination = "iso3c")) %>%
  relocate(iso3, .after = country_ISO2Code) %>% select(-country_ISO2Code) %>%
  mutate(country_analysis_date = as.Date(country_analysis_date)) %>%
  rename(adm_name = area_name) %>%
  # creating date overlapping
  mutate(start_dateForMatching_IPC = country_analysis_date %m-% months(5),
         end_dateForMatching_IPC = country_analysis_date %m+% months(5)) %>%
  relocate(c(start_dateForMatching_IPC, end_dateForMatching_IPC), .before = country_analysis_date )

del <- IPCdataImported %>%
  filter(area_overall_phase == -1)
# checking which were matched 
IPC_DIEM_hh_matched <- DIEM_hh_combined %>%
  left_join(IPCdataImported, c("adm_name", "iso3"))  %>%
  filter(
    start_dateForMatching_IPC <= end_dateForMatching_DIEM &
      end_dateForMatching_IPC >= start_dateForMatching_DIEM
  ) %>%
  # add thresholds
  mutate(
    line_fcs = 35,
    line_rcsi = 18,
    line_hdds = 5,
    line_hhs = 2
  )

#### Export ####
saveRDS(IPC_DIEM_hh_matched, file.path(dataFolder, "IPC_DIEM_hh_joinedAndClean.rds"))


