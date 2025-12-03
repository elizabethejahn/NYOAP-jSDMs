// This model is to estimate length-weight regression parameters for fish species
// while taking into acount the measurement uncertainty in mass and the lower
// measurement limit of 0.01 for weight

data {
  int<lower=0> N;
  vector[N] W_obs;
  vector[N] L;
  
  //censored data vector
  vector[N] censored;
}

parameters {
  real loga;
  real b;
  real<lower=0> Wsigma;
  real logW[N];
}

model {
  // core
  // priors
  b ~ normal(3, 0.5);
  loga ~ normal(-10, 1);
  Wsigma ~ normal(0, 0.05);
  
  // for(i in 1:N){
  logW ~ normal(loga + b * log(L), Wsigma);
  // }
  //likelihood with the censoring 
  target += sum(
    censored .* normal_lccdf(log(0.01) | logW, Wsigma) +
    (1- censored) .* normal_lpdf(log(W_obs) | logW, Wsigma));
  
}

generated quantities {
  real W_pred[N];
  for (i in 1:N) {
    W_pred[i] = exp(logW[i]);
  }
}
