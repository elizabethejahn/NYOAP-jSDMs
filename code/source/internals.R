#'
#'
#'

monthly_aggregate_ln = function(mu = NULL, sd = NULL, month_var = NULL, nsims = 1e3){
  sims = purrr::map2(mu, sd, \(x,y){
    sim = rlnorm(nsims, meanlog = x, sdlog = y)
    sim
  }) %>% setNames(., month_var) %>% 
    split(., names(.)) %>% 
    map(data.frame) %>% 
    map(~apply(.x,1,mean, na.rm = TRUE))
  
  
  return(data.frame(mean = unlist(lapply(sims, mean, na.rm = TRUE)),
                    ci_l = unlist(lapply(sims, function(x) quantile(x, 0.025, na.rm = TRUE))),
                    ci_u = unlist(lapply(sims, function(x) quantile(x, 0.975, na.rm = TRUE)))))
}