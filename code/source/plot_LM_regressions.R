
plot_LM_PPC = function(model_path, df = NULL){
  W_obs = df$weight
# extract generated quantities for posterior check
fit = readRDS(model_path)
post = rstan::extract(fit)
Wpred_posts = post$W_pred %>% 
  as.data.frame %>% 
  mutate(id = 1:n()) %>% 
  pivot_longer(cols = -id, names_to = 'iter', values_to = 'W_pred') %>% 
  select(-iter)

return(
ggplot()+
  geom_density(aes(x = W_obs), color = 'blue', linewidth = 2)+
  geom_density(data = Wpred_posts %>% dplyr::filter(id %in% sample(unique(Wpred_posts$id), 100)), aes(x = W_pred, group = id), color = 'grey', linewidth = 1, alpha = 0.8)
)
}