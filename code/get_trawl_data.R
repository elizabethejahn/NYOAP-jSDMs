here::i_am("code/get_trawl_data.R")
#'  @title get_trawl_data()
#'  @description
#'  This function extracts and cleans the trawl data. With this function 
#'  1) metadata for each sampling event is merged across multiple sheets,
#'  2) a full long-format data object is created
#'  3) metadata are connected to this data file and output as xml, and
#'  4) a community matrix of biological data is created for further analysis
#'  @param conn a database connection to the trawl Access database
#'
#'
get_trawl_data(conn = NULL){
  # tests #
  ## check that the db connection is good
  if(!grepl("RODBC", class(conn))) stop("Error: `conn` must be a valid RODBC connection.")
  if(!grepl("Nearshore Survey.accdb", attr(conn, "connection.string"))) stop("Error: `conn` should point to the 'Nearshore Survey' database.")
  # end tests #
  
  #extract the Biological Samples table and clean columns
  bioTab <- sqlFetch(conn, 'Biological Samples') %>% 
    # make all names lowercase
    rename_with(tolower) %>% 
    mutate(towdate = as.Date(towdate, format = "%Y-%m-%d")) %>% 
    select(cno, towdate, station, spn, tlength, flength, weight) %>% 
    # filter out 'Rod & Reel'
    dplyr::filter(station != 'Rod & Reel')
  
  towTab <- sqlFetch(conn, 'Tow') %>% 
    #make all lowercase
    rename_with(tolower) %>% 
    dplyr::mutate(towdate = as.Date(towdate, format = "%Y-%m-%d")) %>% 
    dplyr::select(cno, towdate, station, latds, latms, londs, lonms, latde, latme, londe, lonme) 
  
  #data checks for bad coords
  # if()
  latmsBad = any(na.omit(unlist(towTab$latms)) > 60)
  latmeBad = any(na.omit(unlist(towTab$latme)) > 60)
  lonmsBad = any(na.omit(unlist(towTab$lonms)) > 60)
  lonmeBad = any(na.omit(unlist(towTab$lonme)) > 60)
  
  
  %>% 
    mutate(latStart_dd = latds+(latms/60),
           lonStart_dd = londs+(lonms/60),
           latEnd_dd = latde+(latme/60),
           lonEnd_dd = londe+(lonme/60))
  
  # merge test
  bioTab$cno[bioTab$cno %ni% towTab$cno]
  bioTab$station[bioTab$station %ni% towTab$station]
  bioTab$towdate[bioTab$towdate %ni% towTab$towdate]
  bioTowTab <- merge(bioTab, towTab, by = c("cno","station","towdate"))
  
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