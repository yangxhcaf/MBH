#' inclMBH
#'
#' This calculates the probability of inclusion of new data into a calculated hypervolume
#'
#' @param hv Fitted MBH model
#' @param newdat New data to test probability of inclusion in the hypervolume
#' @param ndraws Number of draws from multivariate distribution against which to test new data. Defaults to 999
#' @return Returns newdat with an additional column corresponding to probability of inclusion in the hypervolume
#' @export

inclMBH <- function(hv, newdat, ndraws = 999){


  #extract volume

  vol1 <- hv$volume

  #simulate points from each hypervolume

  #calculate means

  if(is.null(hv$group_means)){
    mean1 <- colMeans(hv$means)

  }else{mean1 <- colMeans(apply(hv$means, 3, rbind))}


  #extract covariance

  cov1 <- hv$covariance

  #extract variable names
  varnames1 <- hv$dimensions

  #extract correct vars from newdat
  newvars <- newdat[,varnames1]

  #generate random points from hypervolume
  pnts_hv <- mvtnorm::rmvnorm(max(round(vol1),ndraws), mean1, cov1, method = "eigen")

  pb <- utils::txtProgressBar(min = 0, max = nrow(newvars), style = 3)

  #test inclusion of new points
  totestall <- newvars
  prob <- vector()
  mean.test.p <- vector()
  for(k in 1:nrow(totestall)){
    totest <- as.numeric(totestall[k,])
    test.p <- vector()
    tau <- cov1
    #colnames(tau) <- rownames(tau)
    mu <- mean1
    #test new point against distribution
    prob <- min(mvtnorm::pmvnorm(upper = totest,sigma = tau, mean = mu),mvtnorm::pmvnorm(lower = totest,sigma = tau, mean = mu)*2)

    #simulate ndraws draws from multivariate dist (for speed)
    rsims <- pnts_hv[sample(nrow(pnts_hv), ndraws, replace = FALSE), ]
    #calculate p values for each simulation
    sim.prob <- vector()
    for (j in 1:nrow(rsims)){
      sim.prob[j] <- min(mvtnorm::pmvnorm(upper = rsims[j,],sigma = tau, mean = mu),mvtnorm::pmvnorm(lower = rsims[j,],sigma = tau, mean = mu*2))
    }
    #calc probability of inclusion
    all.prob <- c(sim.prob,prob)
    prob.df <- stats::ecdf(all.prob)
    #plot
    #plot(prob.df); abline(v=prob[i])
    test.p <- prob.df(prob)
    mean.test.p[k] <- mean(test.p)
    utils::setTxtProgressBar(pb, k)
  }

  p.out <- cbind(totestall, mean.test.p)

  return(p.out)



}
