# IPC from db to Rdata/rds file
# 2025_03_19
#### Library ####
library(tidyverse)
library(RMySQL)

dataFolder <- "C:/Users/BRICE/IFPRI Dropbox/Brendan Rice/DIEM_IPC_analysis/Data"



# Load the database connection details from the RData file
load(file = file.path(dataFolder, "connection.RData"))

# Establish MySQL connection
mysqlconnection <- dbConnect(RMySQL::MySQL(),
                             dbname = connection$dbname,
                             host = connection$host,
                             port = connection$port,
                             user = connection$user,
                             password = connection$password
)

# Close db connection after function call exits
on.exit(dbDisconnect(mysqlconnection))

# Import data from IPC table
IPC_imported <- dbSendQuery(mysqlconnection, "select * from IPC") 
IPCdata_imported <- fetch(IPC_imported, n = -1)

del <- IPCdata_imported %>% 
  filter(area_overall_phase %in% c(-1,6 ))

# Clean and manipulate the data
IPCdata <- IPCdata_imported %>%
  mutate(country_analysis_date = lubridate::dmy(paste0("01 ", country_analysis_date))) %>%
  mutate(country_current_period_dates = case_when(
    country_current_period_dates == "" ~ "No range provided",
    TRUE ~ country_current_period_dates
  )) %>%
  select(country_ISO2Code, country_title, country_analysis_date, country_current_period_dates, country_phase1_population:country_phase5_percentage,
         area_ID, area_name, area_overall_phase, area_population, area_p3plus, area_p3plus_percentage, 
         area_estimated_population:area_phase5_percentage) %>%
  filter(!area_overall_phase %in% c(-1,6))

# Save the cleaned data to an RDS file
saveRDS(IPCdata, file.path(dataFolder, "IPCdata_imported.rds"))
