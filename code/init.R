here::i_am("code/init.R")
library(here)
library(junkR)
library(RODBC)
library(magrittr)
library(dplyr)
library(EML)
library(ggplot2)
library(tidyr)
library(rstan)
library(lubridate)
library(terra)
library(geosphere)
library(purrr)
library(furrr)
library(readr)
library(tibble)
library(viridis)
library(ncdf4)
library(Hmsc)
'%ni%' <- Negate('%in%')
options(mc.cores = parallel::detectCores())
rstan::rstan_options(auto_write = TRUE)


# setup the environment to run python and estimate the NAO at designated time steps
source(here('code/init_python.R'))
theme_set(theme_minimal())

## check that an ignore folder exists
if(!file.exists(here('ignore'))){
  print("Warning: The ignore folder does not exist.")
} 

# check that the Nearshore Survery database is present
if(!file.exists(here('ignore/Nearshore Survey.accdb'))){
  print("Warning: The database, Nearshore Survey.accdb, does not exist in the `ignore` folder.")
}

# check that the ignore folder is present in .gitignore
if(!any(grepl("ignore/",readLines(here(".gitignore"))))){
  print("Warning: `ignore` is not set to be ignored in .gitignore. Set this by adding 'ignore/' to the .gitignore file.")
}

# setup the access database connection
conn <<- odbcConnectAccess2007(here("ignore/Nearshore Survey.accdb"))
# sqlTables(db)


# setup dataset variables
## spatial coordinates for environmental variables
NYSbbox <<- c(-74.262999, -71.389711, 39.803091, 41.431287)

## temporal boundaries for the data set.
bioHindStart <<- "2017-11-01"
bioStart <<- "2022-06-01" # this is the beginning of the data product for SST
bioEnd <<- "2024-12-31"

# should we update data each time
update_data = FALSE

# run data forecast procedures
rerun_forecasts = FALSE

if(rerun_forecasts){

source(here('code/nao_gfs_workflow.R'))
}
