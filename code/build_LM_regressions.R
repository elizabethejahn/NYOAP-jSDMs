here::i_am("code/build_LM_regressions.R")
#'  @title build_LM
#'  @description
#'  This function is used to build length-mass regressions for species to convert different species length measurements to mass for the calculation of individual mass and total species or community biomass.
#'  @param spn species common name. This must match a species 
#'
#'
build_LM = function(specName = NULL, df = bioTab){
  require(rstan)
  # tests #
  ## check that spn is in data
  if(!any(specName %in% bioTab$spn)) stop("Error: The 'spn' is not found in the data frame")
  
  # end tests
  # guts of function #
  # subset the species
  spnDf = bioTab %>%
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
  
  x = brms::brm(log(weight)~log(tlength), data = spnLWDf)
  
  stanList = list(N = nrow(spnLWDf),
                  W_obs = spnLWDf$weight,
                  L = spnLWDf$tlength,
                  censored = spnLWDf$censored)
  
  fit = stan(
    file = here("code/LW-measure-error.stan"),
    data = stanList,
    iter = 2000,
    warmup = 1000,
    chains = 3)
  
  # extract generated quantities for posterior check
  post = rstan::extract(fit)
  Wobs_posts = post$W_pred %>% 
    as.data.frame %>% 
    mutate(id = 1:n()) %>% 
    pivot_longer(cols = -id, names_to = 'iter', values_to = 'W_obs') %>% 
    select(-iter)
  
  ggplot(as.data.frame(stanList$W_obs))+
    geom_histogram(aes(x = stanList$W_obs))+
    geom_density(data = Wobs_posts %>% dplyr::filter(id %in% sample(unique(Wobs_posts$id), 30)), aes(x = W_obs, group = id))

}