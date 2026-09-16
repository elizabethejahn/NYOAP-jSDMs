here::i_am("code/source/get_trawl_data.R")
#'  @title get_trawl_data()
#'  @description
#'  This function extracts and cleans the trawl data. With this function 
#'  1) metadata for each sampling event is merged across multiple sheets,
#'  2) a full long-format data object is created
#'  3) metadata are connected to this data file and output as xml, and
#'  4) a community matrix of biological data is created for further analysis
#'  @param conn a database connection to the trawl Access database
#'  @param update logical. Should the data procedure update for new data (TRUE) or upload saved object (FALSE)
#'

get_trawl_data = function(conn = NULL, update = FALSE){
  # tests #
  ## check that the db connection is good
  if(!grepl("RODBC", class(conn))) stop("Error: `conn` must be a valid RODBC connection.")
  if(!grepl("Nearshore Survey.accdb", attr(conn, "connection.string"))) stop("Error: `conn` should point to the 'Nearshore Survey' database.")
  # end tests #
  if(update){
  #extract the Biological Samples table and clean columns
  bioTab <- sqlFetch(conn, 'Biological Samples') %>% 
    # make all names lowercase
    rename_with(tolower) %>% 
    # filter out Striped Bass Surveys
    dplyr::filter(cno != "2017001") %>% 
    mutate(towDate = as.Date(towdate, format = "%Y-%m-%d")) %>% 
    select(cno, towDate, station, spn, tlength, flength, weight) %>% 
    # filter out 'Rod & Reel'
    dplyr::filter(station != 'Rod & Reel')
  
  catchTab <- sqlFetch(conn, 'WEIGHT') %>%
    # make all names lowercase
    rename_with(tolower) %>%
    # select relevant columns
    dplyr::select(cno, station, spn, seq, wtype, subweight, disweight, tweight) %>%
    dplyr::summarise(totWeight = sum(subweight, disweight, na.rm = TRUE), .by = c(cno, station, spn,tweight)) %>% 
    dplyr::mutate(biomass_kg = case_when(is.na(tweight) | tweight == 0 ~ totWeight,
                                         totWeight == 0 ~ tweight,
                                         .default = tweight)) %>% 
    dplyr::select(cno, station, spn, biomass_kg)
  
  towTab <- sqlFetch(conn, 'Tow') %>% 
    #make all lowercase
    rename_with(tolower) %>% 
    # filter out Striped Bass Surveys
    dplyr::filter(cno != "2017001") %>% 
    dplyr::mutate(towDate = as.Date(towdate, format = "%Y-%m-%d")) %>% 
    dplyr::select(cno, towDate, station, towID = tow, latds, latms, londs, lonms, latde, latme, londe, lonme) 
  
  
  # read in cleaned tow data
  towFile = readxl::read_xlsx(here('ignore/Annual Tow Information.xlsx')) %>% 
    dplyr::rename_with(tolower) %>% 
    dplyr::select(cno = 'cruise #', station = 'station #', towID = 'tow #', towDate = 'date',
                  duration = 'tow duration (min)', latStart_dd = 'start lat dd', lonStart_dd = 'start long dd',
                  latEnd_dd = 'end lat dd', lonEnd_dd = 'end long dd', temp_c = 'water temp (°c)',
                  sal_psu = 'salinity (psu)', do_mgL = 'do (mg/l)', ph) %>% 
    dplyr::mutate(cno = as.numeric(gsub("[[:punct:]]","",cno)),
                  towDate = as.Date(towDate)) %>%
    dplyr::mutate(across(where(is.character), trimws)) %>% 
    rowwise %>% 
    dplyr::mutate(trawlDist_tow = geosphere::distm(c(lonStart_dd,latStart_dd), c(lonEnd_dd, latEnd_dd), fun = distHaversine)[,1]) %>% 
    ungroup
  
  
  #data checks for bad coords
  # if()
  latmsBad = any(na.omit(unlist(towTab$latms)) > 60)
  latmeBad = any(na.omit(unlist(towTab$latme)) > 60)
  lonmsBad = any(na.omit(unlist(towTab$lonms)) > 60)
  lonmeBad = any(na.omit(unlist(towTab$lonme)) > 60)
  if(any(latmsBad,latmeBad,lonmsBad, lonmeBad)) warning("Warning: some tow coordinates are incorrect (i.e. greater than 60). They cannot be converted to decimal degrees.")
  
  towTab = towTab  %>% 
    dplyr::mutate(bad_coords_tow = case_when(
      is.na(latms) | is.na(latme) | is.na(lonms) | is.na(lonme) |
      latms > 60 |
      latme > 60 |
      lonms > 60 |
      lonme > 60 ~ TRUE,
    .default = FALSE)) %>% 
    dplyr::mutate(latStart_dd_tow = latds+(latms/60),
           lonStart_dd_tow = londs-(lonms/60),
           latEnd_dd_tow = latde+(latme/60),
           lonEnd_dd_tow = londe-(lonme/60)) %>% 
    rowwise %>% 
    dplyr::mutate(trawlDist_tow = geosphere::distm(c(lonStart_dd_tow,latStart_dd_tow), c(lonEnd_dd_tow, latEnd_dd_tow), fun = distHaversine)[,1])
  
  
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
  towEnvFile = merge(towFile, ctdTab, by = c('cno','station','towID','towDate','duration'), all = TRUE) %>% 
    dplyr::mutate(dist_agree = case_when(round(trawlDist_tow,3) == round(trawlDist_ctd,3) ~TRUE,
                                         .default = FALSE))#,
                  # coords_agree = case_when(latStart_dd_tow == latStart_dd_ctd &
                  #                            lonStart_dd_tow == lonStart_dd_ctd &
                  #                            latEnd_dd_tow == latEnd_dd_ctd &
                  #                            lonEnd_dd_tow == lonEnd_dd_ctd ~ TRUE,
                  #                          .default = FALSE))
                                             # 'temp_c','sal_psu','do_mgL', 'ph'), all = TRUE)
  
  
  towEnvTab = merge(towTab, ctdTab, by = c('cno','station','towID','towDate'), all = TRUE) %>% 
    dplyr::mutate(dist_agree = case_when(round(trawlDist_tow,4) == round(trawlDist_ctd,4) ~TRUE,
                                        .default = FALSE),
                  coords_agree = case_when(latStart_dd_tow == latStart_dd_ctd &
                                             lonStart_dd_tow == lonStart_dd_ctd &
                                             latEnd_dd_tow == latEnd_dd_ctd &
                                             lonEnd_dd_tow == lonEnd_dd_ctd ~ TRUE,
                                           .default = FALSE)) %>% 
    dplyr::select(-latds,-latms,-londs,-lonms,-latde, -latme, -londe,-lonme) %>% 
    dplyr::select(cno, station, towID, towDate, duration, latStart_dd_tow,latStart_dd_ctd, lonStart_dd_tow,lonStart_dd_ctd,
                  latEnd_dd_tow,latEnd_dd_ctd, lonEnd_dd_tow,lonEnd_dd_ctd, bad_coords_tow,coords_agree, dist_agree, trawlDist_tow, trawlDist_ctd, everything() ) %>% 
    dplyr::mutate(trawlDist_tow = case_when(trawlDist_tow > 6000 ~ NA_real_,
                                            trawlDist_tow == 0 ~ NA_real_,
                                            .default = trawlDist_tow),
                  trawlDist_ctd = case_when(trawlDist_ctd > 6000 ~ NA_real_,
                                            trawlDist_ctd == 0 ~ NA_real_,
                                            .default = trawlDist_ctd)) %>% 
    dplyr::mutate(across(matches("\\w+_dd_tow"), ~if_else(bad_coords_tow == TRUE, NA_real_, .x))) %>% 
    dplyr::mutate(latStart_dd = case_when(bad_coords_tow ~ latStart_dd_ctd,
                                         dist_agree & is.na(latStart_dd_ctd) & !is.na(latStart_dd_tow) ~ latStart_dd_tow,
                                         is.na(latStart_dd_ctd) & !is.na(latStart_dd_tow) ~ latStart_dd_tow,
                                         is.na(trawlDist_ctd) & !is.na(latStart_dd_ctd) ~ latStart_dd_tow,
                                         dist_agree & !is.na(latStart_dd_ctd) ~ latStart_dd_ctd,
                                         is.na(trawlDist_tow) & !is.na(latStart_dd_ctd) ~ latStart_dd_ctd,
                                         .default = NA_real_),
                  lonStart_dd = case_when(bad_coords_tow ~ lonStart_dd_ctd,
                                          dist_agree & is.na(lonStart_dd_ctd) & !is.na(lonStart_dd_tow) ~ lonStart_dd_tow,
                                          is.na(lonStart_dd_ctd) & !is.na(lonStart_dd_tow) ~ lonStart_dd_tow,
                                          is.na(trawlDist_ctd) & !is.na(lonStart_dd_ctd) ~ lonStart_dd_tow,
                                          dist_agree & !is.na(lonStart_dd_ctd) ~ lonStart_dd_ctd,
                                          is.na(trawlDist_tow) & !is.na(lonStart_dd_ctd) ~ lonStart_dd_ctd,
                                          .default = NA_real_),
                  latEnd_dd = case_when(bad_coords_tow ~ latEnd_dd_ctd,
                                        dist_agree & is.na(latEnd_dd_ctd) & !is.na(latEnd_dd_tow) ~ latEnd_dd_tow,
                                        is.na(latEnd_dd_ctd) & !is.na(latEnd_dd_tow) ~ latEnd_dd_tow,
                                        is.na(trawlDist_ctd) & !is.na(latEnd_dd_ctd) ~ latEnd_dd_tow,
                                        dist_agree & !is.na(latEnd_dd_ctd) ~ latEnd_dd_ctd,
                                        is.na(trawlDist_tow) & !is.na(latEnd_dd_ctd) ~ latEnd_dd_ctd,
                                        .default = NA_real_),
                  lonEnd_dd = case_when(bad_coords_tow ~ lonEnd_dd_ctd,
                                        dist_agree & is.na(lonEnd_dd_ctd) & !is.na(lonEnd_dd_tow) ~ lonEnd_dd_tow,
                                        is.na(lonEnd_dd_ctd) & !is.na(lonEnd_dd_tow) ~ lonEnd_dd_tow,
                                        is.na(trawlDist_ctd) & !is.na(lonEnd_dd_ctd) ~ lonEnd_dd_tow,
                                        dist_agree & !is.na(lonEnd_dd_ctd) ~ lonEnd_dd_ctd,
                                        is.na(trawlDist_tow) & !is.na(lonEnd_dd_ctd) ~ lonEnd_dd_ctd,
                                        .default = NA_real_),
                  trawlDist_m = case_when(dist_agree ~ trawlDist_ctd,
                                          is.na(trawlDist_ctd) & !is.na(trawlDist_tow) ~ trawlDist_tow,
                                          is.na(trawlDist_tow) & !is.na(trawlDist_ctd) ~ trawlDist_ctd,
                                          .default = NA_real_)) %>% 
    dplyr::select(-matches("\\w+_dd_tow"), -matches("\\w+_dd_ctd"), -trawlDist_ctd,
                  -trawlDist_tow, -bad_coords_tow, -coords_agree, -dist_agree) %>% 
    dplyr::select(cno, station, towID, towDate, duration, ctdDateTime = towDateTime, matches("\\w+_dd"), trawlDist_m, everything()  )
  
  
  # merge test
  ## test for cruise numbers (cno) in bioTab but not towTab
  bioTab$cno[bioTab$cno %ni% towEnvTab$cno]
  if(length(bioTab$cno[bioTab$cno %ni% towEnvTab$cno]) > 0) warning("Warning: There are cruises (cno) in bioTab not in towTab")
  ## test for stations in bioTab but not towTab
  bioTab$station[bioTab$station %ni% towEnvTab$station]
  if(length(bioTab$station[bioTab$station %ni% towEnvTab$station]) > 0 ) warning(paste0("Warning: There are stations in bioTab not present in towTab. \n Stations not in towTab are:",bioTab$station[bioTab$station %ni% towTab$station]))
  ## test for towdates in bioTab but not towTab
  unique(bioTab$towdate[bioTab$towdate %ni% towEnvTab$towdate])
  if(length(bioTab$towdate[bioTab$towdate %ni% towEnvTab$towdate]) > 0 ) warning(paste0("Warning: There are towdates present in bioTab not in towTab. \n Dates not present in towTab are:",unique(bioTab$towdate[bioTab$towdate %ni% towTab$towdate])))
  ## merge the bio and tow tabs by cno, station, and towdate
  bioTowTab <-left_join(bioTab, towEnvTab, by = c("cno","station","towDate"))
  saveRDS(bioTowTab, here('data/derived-data/bioTowTab.rds'))
  }
  bioTowTab = readRDS(here('data/derived-data/bioTowTab.rds'))
   assign("bioTowTab", readRDS(here('data/derived-data/bioTowTab.rds')), envir = .GlobalEnv)
   print("Trawl data imported")

  
  #write the eml file to export 
  # jim <- list(individualName = list(givenName = 'James', surName = 'Junker'))
  
#   # set trawl dataset attributes
#   trawl_attributes <- data.frame(
#     attributeName = list("cno",#1
#                          "towdate",#2
#                          "station",#3
#                          "spc",#4
#                          "spn",#5
#                          "seq",#6
#                          "tlength",#7
#                          "flength",#8
#                          "weight",#9
#                          "agestructure",#10
#                          "tag",#11
#                          "sex",#12
#                          "mat",#13
#                          "eggs",#14
#                          "dec#",#15
#                          "cmts"),#16
#     attributeDefinition = list("cruise number. Year and campaign number. e.g., YYYYCCC",#cno
#                                "Date of tow. e.g., YYYY-MM-DD",#towdate
#                                "station identifier code",#station
#                                "species code",#spc
#                                "species common name",#spn
#                                "sequence",#seq
#                                "total length",#tlength
#                                "fork length",#flength
#                                "individual mass",#weight
#                                "type of sample taken for aging",#agestruc
#                                "tag identifier, if applicable",#tag
#                                "organism sex. male (M), female (F), or unknown (U)",#sex
#                                "mat??",#mat
#                                "eggs. B, N, O, Y",#eggs
#                                "Department of Environmental Conservation code",#dec#
#                                "comments"),#cmts
#     formatString = list(NA,#cno
#                         "YYYY-MM-DD",#towdate
#                         NA,#station
#                         NA,#spc
#                         NA,#spn
#                         NA,#seq
#                         NA,#tlength
#                         NA,#flength
#                         NA,#weight
#                         NA,#agestruc
#                         NA,#tag
#                         NA,#sex
#                         NA,#mat
#                         NA,#eggs
#                         NA,#dec#
#                         NA #cmts
#                         ),
#     definition = list("which cruise number",#cno
#                       NA,#towdate
#                       NA,#station
#                       NA,#spc
#                       "species common name",#spn
#                       NA,#seq
#                       NA,#tlength
#                       NA,#flength
#                       NA,#weight
#                       NA,#agestruc
#                       NA,#tag
#                       NA,#sex
#                       NA,#mat
#                       NA,#eggs
#                       "DEC code",#dec#
#                       "comments" #cmts
#                       ),
#     unit = list(NA,#cno
#                 NA,#towdate
#                 NA,#station
#                 NA,#spc
#                 NA,#spn
#                 NA,#seq
#                 "cm",#tlength
#                 "cm",#flength
#                 "kg",#weight
#                 NA,#agestruc
#                 NA,#tag
#                 NA,#sex
#                 NA,#mat
#                 NA,#eggs
#                 NA,#dec#
#                 NA #cmts
#                 ),
#     numberType = list("integer",#cno
#                       NA,#towdate
#                       NA,#station
#                       "integer",#spc
#                       NA,#spn
#                       "integer",#seq
#                       "real",#tlength
#                       "real",#flength
#                       "real",#weight
#                       NA,#agestruc
#                       "integer",#tag
#                       NA,#sex
#                       NA,#mat
#                       NA,#eggs
#                       NA,#dec#
#                       NA #cmts
#                       )
#   )
#   
#   # define the factors in the dataset
#   stations = list()
#   agestructures = list()
#   sexes = list(M = 'male',
#                F = 'female',
#                U = 'unknown')
#   mat = list()#??
#   eggs = list(B = ,
#               N = ,
#               O = ,
#               Y = )
#   
#   
#   trawl_eml <- eml$eml(
#     dataset = eml$dataset(
#       title = "Defining foraging hotspots of finfish and sharks in the New York Bight: linking
# trophic dynamics with spatiotemporal trends in species distributions",
#       abstract = abstract,
#       keywordSet = trawl_keywordSet,
#       coverage = trawl_coverage,
#       contact = trawl_contact,
#       methods = trawl_methods,
#       
#       
#     )
#   )
}