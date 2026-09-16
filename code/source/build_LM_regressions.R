here::i_am("code/source/build_LM_regressions.R")
#'  @title build_LM
#'  @description
#'  This function is used to build length-mass regressions for species to convert different species length measurements to mass for the calculation of individual mass and total species or community biomass.
#'  @param spn species common name. This must match a species 
#'
#'
build_LM = function(specName = NULL, df = NULL, rerun = FALSE){
  require(rstan)
  # tests #
  ## check that spn is in data
  if(!any(specName %in% df$spn)) stop("Error: The 'spn' is not found in the data frame")
  
  # end tests
  # guts of function #
  model_name = paste0(here(),"/ignore/models/",specName,"_LM_censored.rds")
  ## don't rerun if existing models if rerun is false and the model exists
  if(all(!rerun & file.exists(model_name))){
   print("Warning: Model already exists. To rerun, set `rerun=TRUE`.")
  return(NULL) 
  }
  # subset the species
  spnDf = df %>%
    dplyr::filter(spn == specName)
  
  # build the list object for modeling W~aL^b
  # model formula is log(W)~ log(a) + b * log(L)
  # using tlength because it is more available
  # isolate the tlength and weights and remove NAs
  spnLWDf = spnDf %>% 
    select(tlength, weight) %>% 
    na.omit %>% 
    # create a vector of censored measurements
    mutate(censored = ifelse(weight == 0.01, 1,0))
  # 
  # if(!any(as.logical(spnLWDf$censored))){
  # 
  # fit = brms::brm(log(weight)~log(tlength), data = spnLWDf)
  # 
  # post = brms::conditional_effects(fit)
  # 
  # } else{
    stanList = list(N = nrow(spnLWDf),
                  W_obs = spnLWDf$weight,
                  L = spnLWDf$tlength,
                  censored = spnLWDf$censored)
  
  fit = stan(
    file = here("code/source/LW-measure-error.stan"),
    data = stanList,
    iter = 2000,
    warmup = 1000,
    chains = 4,
    seed = 1312,
    refresh = 0
    )
  # save the model 
  saveRDS(fit, model_name)
 
}