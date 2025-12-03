here::i_am("code/init.R")
library(here)
library(RODBC)
library(magrittr)
library(dplyr)
library(EML)
library(ggplot2)
library(tidyr)
library(rstan)
library(reticulate)
library(copernicusR)
library(terra)
library(geosphere)

'%ni%' <- Negate('%in%')
options(mc.cores = parallel::detectCores())
rstan::rstan_options(auto_write = TRUE)

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

# setup the access databased connection
conn <- odbcConnectAccess2007(here("ignore/Nearshore Survey.accdb"))
# sqlTables(db)

# setup copernicusR environment to download environmental data
setup_copernicus(username = Sys.getenv("COPERNICUS_USERNAME"), password = Sys.getenv("COPERNICUS_PASSWORD"))

# setup dataset variables
## spatial coordinates for environmental variables
NYSbbox = c(-74.262999, -71.389711, 39.803091, 41.431287)

## temporal boundaries for the data set.
bioHindStart = "2017-11-01"
bioStart = "2022-06-01" # this is the beginning of the data product for SST
bioEnd = "2024-12-31"
