functions {
  // Convolve a pdf and case vector using matrix multiplication
  vector convolve(vector cases, vector pdf) {
    int t = num_elements(cases);
    matrix[t, t] delay_mat = rep_matrix(0, t, t);
    int max_pdf = num_elements(pdf);
    row_vector[max_pdf] row_pdf = to_row_vector(pdf);
    vector[t] convolved_cases;
    
    for (s in 1:t) {
      int max_length = min(s, max_pdf);
      delay_mat[s, (s - max_length + 1):s] = row_pdf[(max_pdf - max_length + 1):max_pdf];
    }
  
   convolved_cases = delay_mat * to_vector(cases);

   return convolved_cases;
  }

  real discretised_lognormal_pmf(int y, real mu, real sigma) {
    return(lognormal_cdf(y, mu, sigma) -
           lognormal_cdf(y - 1, mu, sigma));
  }

}


data {
  int t; // number of time steps
  int d; 
  int inc; 
  int samples;
  int day_of_week[t];
  int <lower = 0> cases[t];
  vector<lower = 0>[t] shifted_cases; 
  real inc_mean_sd;                  // prior sd of mean incubation period
  real inc_mean_mean;                // prior mean of mean incubation period
  real inc_sd_mean;                  // prior sd of sd of incubation period
  real inc_sd_sd;                    // prior sd of sd of incubation period
  real rep_mean_mean;                // prior mean of mean reporting delay
  real rep_mean_sd;                  // prior sd of mean reporting delay
  real rep_sd_mean;                  // prior mean of sd of reporting delay
  real rep_sd_sd;                    // prior sd of sd of reporting delay
  int model_type; //Type of model: 1 = Poisson otherwise negative binomial
}

parameters{
  vector<lower = 0>[t] noise;
  real <lower = 0> inc_mean;         // mean of incubation period
  real <lower = 0> inc_sd;           // sd of incubation period
  real <lower = 0> rep_mean;         // mean of reporting delay
  real <lower = 0> rep_sd;           // sd of incubation period
  real<lower = 0> phi; 
  vector[6] day_of_week_eff_raw;
}

transformed parameters {
  vector[d] rev_delay;
  vector[inc] rev_incubation;
  vector<lower = 0>[t] infections;
  vector<lower = 0>[t] onsets;
  vector<lower = 0>[t] reports;
  vector[7] day_of_week_eff;
  
  //Constrain day of week to sum to 0
  day_of_week_eff = 1 + append_row(day_of_week_eff_raw, -sum(day_of_week_eff_raw));
  
  //Reverse the distributions to allow vectorised access
    for (j in 1:d) {
      rev_delay[j] =
        discretised_lognormal_pmf(d - j + 1, inc_mean, inc_sd);
        }
   
    for (j in 1:inc) {
      rev_incubation[j] =
        discretised_lognormal_pmf(inc - j + 1, rep_mean, rep_sd);
    }

  //Generation infections from median shifted cases and non-parameteric noise
  infections = shifted_cases .* noise;

  
     // Onsets from infections
     onsets = convolve(infections, rev_incubation);
     
     // Reports from onsets
     reports = convolve(onsets, rev_delay);
     
  // Add reporting effects
    for (s in 1:t) {
       reports[s] = reports[s] + day_of_week_eff[day_of_week[s]];
    }
}

model {
  // Week effect
  for (j in 1:6) {
      day_of_week_eff_raw[j] ~ normal(0, 0.1) T[-1,];
  }

  // Reporting overdispersion
  phi ~ exponential(1);

  // Noise on median shift
  for (i in 1:t) {
    noise[i] ~ normal(1, 0.2) T[0,];
  }
  
  for (h in 1:samples) {
    // Log likelihood of reports
     if (model_type == 1) {
       target +=  poisson_lpmf(cases | reports[h]);
     }else{
       target += neg_binomial_2_lpmf(cases | reports[h], phi);
     }
  }


  // penalised priors
  target += sum(cases) * normal_lpdf(inc_mean | inc_mean_mean, inc_mean_sd);
  target += sum(cases) * normal_lpdf(inc_sd | inc_sd_mean, inc_sd_sd);
  target += sum(cases) * normal_lpdf(rep_mean | rep_mean_mean, rep_mean_sd);
  target += sum(cases) * normal_lpdf(rep_sd | rep_sd_mean, rep_sd_sd);

}
  
generated quantities {
  int imputed_infections[t];
  imputed_infections = poisson_rng(infections);
}
