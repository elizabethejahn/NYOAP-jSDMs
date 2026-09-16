library(here)
library(dplyr)
library(magrittr)
library(RODBC)
library(geosphere)
# setup the access database connection
conn <<- odbcConnectAccess2007(here("ignore/Nearshore Survey.accdb"))

towTab <- sqlFetch(conn, 'Tow') %>% 
  #make all lowercase
  rename_with(tolower) %>% 
  # filter out Striped Bass Surveys
  dplyr::filter(cno != "2017001") %>% 
  dplyr::mutate(towDate = as.Date(towdate, format = "%Y-%m-%d")) %>% 
  dplyr::mutate(towmonth = as.Date( paste0( lubridate::year(towDate), "-",
                                            lubridate::month(towDate) ,"-01" ),
                                    format = "%Y-%m-%d")) %>% 
  dplyr::select(cno, towDate, towmonth, station, towID = tow, latds, latms, londs, lonms, latde, latme, londe, lonme) %>% 
  # convert from decimal minutes to decimal degrees
  dplyr::mutate(latStart_dm_dd = latms/60,
              lonStart_dm_dd = -lonms/60,
              latEnd_dm_dd = latme/60,
              lonEnd_dm_dd = -lonme/60) %>% 
  dplyr::mutate(latStart_dd_tow = latds + latStart_dm_dd,
                lonStart_dd_tow = londs+lonStart_dm_dd,
                latEnd_dd_tow = latde+latEnd_dm_dd,
                lonEnd_dd_tow = londe+lonEnd_dm_dd) %>% 
  rowwise %>% 
  dplyr::mutate(trawlDist_tow = geosphere::distm(c(lonStart_dd_tow,latStart_dd_tow), c(lonEnd_dd_tow, latEnd_dd_tow), fun = distHaversine)[,1])

#data checks for bad coords
latmsBad = any(na.omit(unlist(towTab$latms)) > 60)
latmeBad = any(na.omit(unlist(towTab$latme)) > 60)
lonmsBad = any(na.omit(unlist(towTab$lonms)) > 60)
lonmeBad = any(na.omit(unlist(towTab$lonme)) > 60)

towTab_badCoords = towTab %>% 
  dplyr::filter(if_any(c(latms, latme, lonms , lonme), ~. > 60) | !between(trawlDist_tow, 100, 6000) | is.na(trawlDist_tow))

towTab_good = towTab %>% 
  dplyr::filter(if_any(c(latms, latme, lonms , lonme), ~. < 60) & between(trawlDist_tow, 100, 6000))


# pull CTD information
ctdTab <- sqlFetch(conn, 'CTD') %>% 
  # make all lower case
  rename_with(tolower, everything()) %>% 
  dplyr::select(cno = 'cruise #',
                station = 'station #',
                towID = 'tow #',
                towDate = 'date ',
                towTime = 'time',
                duration = 'tow duration (min)',
                latStart_dd_ctd = 'start lat dd',
                lonStart_dd_ctd = 'start long dd',
                latEnd_dd_ctd = 'end lat dd',
                lonEnd_dd_ctd = 'end long dd',
                ctd_depth_m = 'depth (ctd, m)',
                temp_c = 'temp (°c)',
                sal_psu = 'salinity (psu)',
                do_mgL = 'do (mg/l)',
                ph) %>% 
  # filter out Striped Bass Surveys
  dplyr::filter(cno != "2017001") %>% 
  dplyr::mutate(towTime = as.character(towTime)) %>% 
  dplyr::mutate(towDate = as.Date(towDate, format = '%Y-%m-%d'),
                towTime = gsub("\\d{4}-\\d{2}-\\d{2}\\s(\\d{2}:\\d{2}:\\d{2}$)","\\1",towTime),
                towDateTime = as.POSIXct(paste(towDate,towTime, sep = " "), format = "%Y-%m-%d %H:%M:%S")) %>% 
  dplyr::select(-towTime) %>% 
  rowwise %>% 
  dplyr::mutate(trawlDist_ctd = geosphere::distm(c(lonStart_dd_ctd,latStart_dd_ctd), c(lonEnd_dd_ctd, latEnd_dd_ctd), fun = distHaversine)[,1])

## tow and ctd merge test
towEnvTab = merge(towTab, ctdTab, by = c('cno','station','towID','towDate'), all = TRUE) %>% 
  dplyr::mutate(dist_agree = case_when(round(trawlDist_tow,4) == round(trawlDist_ctd,4) ~TRUE,
                                       .default = FALSE),
                coords_agree = case_when(latStart_dd_tow == latStart_dd_ctd &
                                           lonStart_dd_tow == lonStart_dd_ctd &
                                           latEnd_dd_tow == latEnd_dd_ctd &
                                           lonEnd_dd_tow == lonEnd_dd_ctd ~ TRUE,
                                         .default = FALSE),
                bad_coords_tow = case_when(latms > 60 | latme > 60 | lonms > 60 | lonme > 60 ~ TRUE,
                                           .default = FALSE)) %>% 
  dplyr::select(-latds,-latms,-londs,-lonms,-latde, -latme, -londe,-lonme) %>% 
  dplyr::select(cno, station, towID, towDate, duration, latStart_dd_tow,latStart_dd_ctd, lonStart_dd_tow,lonStart_dd_ctd,
                latEnd_dd_tow,latEnd_dd_ctd, lonEnd_dd_tow,lonEnd_dd_ctd, bad_coords_tow,coords_agree, dist_agree, trawlDist_tow, trawlDist_ctd, everything() )# %>% 
  # dplyr::mutate(trawlDist_tow = case_when(trawlDist_tow > 6000 ~ NA_real_,
  #                                         trawlDist_tow == 0 ~ NA_real_,
  #                                         .default = trawlDist_tow),
  #               trawlDist_ctd = case_when(trawlDist_ctd > 6000 ~ NA_real_,
  #                                         trawlDist_ctd == 0 ~ NA_real_,
  #                                         .default = trawlDist_ctd)) %>% 
  # dplyr::mutate(across(matches("\\w+_dd_tow"), ~if_else(bad_coords_tow == TRUE, NA_real_, .x))) %>% 
  # dplyr::mutate(latStart_dd = case_when(bad_coords_tow ~ latStart_dd_ctd,
  #                                       dist_agree & is.na(latStart_dd_ctd) & !is.na(latStart_dd_tow) ~ latStart_dd_tow,
  #                                       is.na(latStart_dd_ctd) & !is.na(latStart_dd_tow) ~ latStart_dd_tow,
  #                                       is.na(trawlDist_ctd) & !is.na(latStart_dd_ctd) ~ latStart_dd_tow,
  #                                       dist_agree & !is.na(latStart_dd_ctd) ~ latStart_dd_ctd,
  #                                       is.na(trawlDist_tow) & !is.na(latStart_dd_ctd) ~ latStart_dd_ctd,
  #                                       .default = NA_real_),
  #               lonStart_dd = case_when(bad_coords_tow ~ lonStart_dd_ctd,
  #                                       dist_agree & is.na(lonStart_dd_ctd) & !is.na(lonStart_dd_tow) ~ lonStart_dd_tow,
  #                                       is.na(lonStart_dd_ctd) & !is.na(lonStart_dd_tow) ~ lonStart_dd_tow,
  #                                       is.na(trawlDist_ctd) & !is.na(lonStart_dd_ctd) ~ lonStart_dd_tow,
  #                                       dist_agree & !is.na(lonStart_dd_ctd) ~ lonStart_dd_ctd,
  #                                       is.na(trawlDist_tow) & !is.na(lonStart_dd_ctd) ~ lonStart_dd_ctd,
  #                                       .default = NA_real_),
  #               latEnd_dd = case_when(bad_coords_tow ~ latEnd_dd_ctd,
  #                                     dist_agree & is.na(latEnd_dd_ctd) & !is.na(latEnd_dd_tow) ~ latEnd_dd_tow,
  #                                     is.na(latEnd_dd_ctd) & !is.na(latEnd_dd_tow) ~ latEnd_dd_tow,
  #                                     is.na(trawlDist_ctd) & !is.na(latEnd_dd_ctd) ~ latEnd_dd_tow,
  #                                     dist_agree & !is.na(latEnd_dd_ctd) ~ latEnd_dd_ctd,
  #                                     is.na(trawlDist_tow) & !is.na(latEnd_dd_ctd) ~ latEnd_dd_ctd,
  #                                     .default = NA_real_),
  #               lonEnd_dd = case_when(bad_coords_tow ~ lonEnd_dd_ctd,
  #                                     dist_agree & is.na(lonEnd_dd_ctd) & !is.na(lonEnd_dd_tow) ~ lonEnd_dd_tow,
  #                                     is.na(lonEnd_dd_ctd) & !is.na(lonEnd_dd_tow) ~ lonEnd_dd_tow,
  #                                     is.na(trawlDist_ctd) & !is.na(lonEnd_dd_ctd) ~ lonEnd_dd_tow,
  #                                     dist_agree & !is.na(lonEnd_dd_ctd) ~ lonEnd_dd_ctd,
  #                                     is.na(trawlDist_tow) & !is.na(lonEnd_dd_ctd) ~ lonEnd_dd_ctd,
  #                                     .default = NA_real_),
  #               trawlDist_m = case_when(dist_agree ~ trawlDist_ctd,
  #                                       is.na(trawlDist_ctd) & !is.na(trawlDist_tow) ~ trawlDist_tow,
  #                                       is.na(trawlDist_tow) & !is.na(trawlDist_ctd) ~ trawlDist_ctd,
  #                                       .default = NA_real_)) %>% 
  # dplyr::select(-matches("\\w+_dd_tow"), -matches("\\w+_dd_ctd"), -trawlDist_ctd,
  #               -trawlDist_tow, -bad_coords_tow, -coords_agree, -dist_agree) %>% 
  # dplyr::select(cno, station, towID, towDate, duration, ctdDateTime = towDateTime, matches("\\w+_dd"), trawlDist_m, everything()  )
  # 

write.csv(towEnvTab, "./towEnvTab.csv", quote = FALSE, row.names = FALSE)
