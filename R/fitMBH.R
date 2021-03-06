#' fitMBH
#'
#' This function fits modelled based or empirical hypervolumes to multivariate data
#'
#' @param x Data to fit hypervolume to
#' @param vars  Names of variables in x to use for hypervolume construction
#' @param groups Name of the grouping variable in x. Use NULL if no groups present or to  ignore grouping structure and fit an empirical hypervolume
#' @param nc Number of MCMC chains
#' @param ni Number of MCMC iterations (default 100000)
#' @param nb Length of burnin
#' @param nt Thinning paramter
#' @return means - Estimated means of each variable
#' @return covariance - Estimated covariance structure
#' @return volume - Estimated hypervolume size
#' @return group_means - Estimated group means
#' @return group_variances - Estimated between-group variances for each variable
#' @return samples - The output from the jags.samples function
#' @details To use the coda package for mcmc diagnostics, you first need to convert the samples to mcmc.list format. This can be completed with the as.mcmc.list function from the mcmcr package. To inspect the mcmc chains for the estimated covariance matrix use plot(as.mcmc.list(m3$samples$tau))
#' @export



fitMBH <- function(x, vars = c("V1", "V2", "V3"), groups = "Group", nc = 3, ni = 100000, nb = 20000, nt = 20){


  if(any(!vars %in% colnames(x))){stop("Variable names not found in data")}

  #get dimensions and covariance matrix
  ndims <- length(vars)

  covm <- stats::cov(x[,vars])

  if(any(!stats::complete.cases(x))){stop("Missing data found, check all cases are complete before fitting model")}




  ##MCMC parameters
  nc = nc # number of chains
  ni = ni # number of iterations
  nb = nb #burnin length
  nt = nt # thinning parameter


  #set initial values
  inits <- function() {list(tau = structure(.Data = diag(0.1, ncol = ndims, nrow = ndims), .Dim = c(ndims,ndims)))}



  ########no group model###########


  if(is.null(groups)){

    message("No grouping variable supplied, empirical hypervolume calculated")

    nobv <- nrow(x)
    Y2 <- as.matrix(x[,vars])
    cov2 <- covm

    #non-nested model


    sink("mod_empirical.txt")
    cat("model
        {
        #start loop over observations
        for (i in 1:N){
        #each observation has J variables and comes from a multivariate normal described by mu and tau
        Y2[i,1:J] ~ dmnorm(mu[i,1:ndims], tau[ 1:ndims,1:ndims ])

        #start loop over variables
        for (j in 1:J){
        #the mean of each variable comes from an independent normal distribution (this allows means to vary between variables)
        mu[i,j] ~ dnorm(0,0.0001)
        }}


        #the covariance matrix (used to calculate the hypervolume) gets an informative prior based on the covariance matrix calculated from the data
        tau[1 : ndims,1 : ndims] ~ dwish(R[ , ], ndims + 1)
        for (i in 1:ndims){
        for (j in 1:ndims){
        R[i,j] <- cov2[i,j]*(ndims + 1)
        }
        }

        }
        ")
    sink()

    #specify data
    dat <- list(N = nobv, J = ndims, ndims = ndims,
                Y2 = structure(
                  .Data = as.numeric(Y2),
                  .Dim = c(nobv,ndims)),
                cov2 = structure(
                  .Data = as.numeric(cov2),
                  .Dim = c(ndims,ndims))
    )

    #specify parameters to return
    params <- c("tau", "mu")

    jm <- rjags::jags.model("mod_empirical.txt", data = dat, inits = inits, n.chains = nc, quiet = TRUE)

    #burnin
    stats::update(jm, n.iter = nb, progress.bar = "none")

    #iterations to use

    zj <- rjags::jags.samples(jm, variable.names = params, n.iter = ni, thin = nt, progress.bar = "text")

    tau <- solve(summary(zj$tau, FUN = mean)$stat)
    mu <- summary(zj$mu, FUN = mean)$stat

    ##calculate volume of hypervolume

    eig <- eigen(tau)

    sf <- stats::qchisq(0.95,df = ndims)

    ax <- vector()
    for (k in 1:ndims){
      ax[k] <- sqrt(sf*eig$values[k])
    }

    volume <- 2/ndims * (pi^(ndims/2))/factorial((ndims/2)-1) * prod(ax)


    outlist <- list("means" = mu, "covariance" = tau, "volume" = volume, "Y" = Y2, "dimensions" = vars)

  }



 ######## group model #######



  if(!is.null(groups)){

    if(!groups %in% colnames(x)){stop("Grouping variable not found in data")}

    #nested model
    ngroups <- length(unique(x[,groups]))

    #change groups to numeric - ordered alphabetically
    x[,groups] <- as.numeric(as.factor((x[,groups])))


    nobv <- vector()

    for(i in 1:ngroups){
      nobv[i] <- length(x[,groups][x[,groups] == i])
    }
    #observations per group

    maxobv <- max(nobv)

    #make x into array

    xarray <- array(NA, dim = c(maxobv, ngroups, ndims))

    for (j in 1:ndims){
      for (k in 1:ngroups){
      xarray[,k,j] <- c(x[x[,groups]==k, vars[j]], rep(NA, length(xarray[,k,j]) - length(x[x[,groups]==k, vars[j]])))
      }
    }

    Y <- xarray


    ##model with random effect

    sink("mod_modelbased.txt")
    cat("model
        {
        #add new loop over sites 1:K
        for (k in 1:K){
        #loop over observations
        for (i in 1:N){

        Y[i,k,1:J] ~ dmnorm(mu[i,k,1:ndims], tau[ 1:ndims,1:ndims ])

        #Now allow means to vary by variable and group - note this additional step is required to define mu1 (which varies between groups and variables but not individuals). Tau.1 allows the individual means (cf fitted values) to vary around group means with a different value for each variable. However, in all simulations tau.1 is returned as a very small variance (high precision) indicating all variability in the data is captured in tau (inverse of sigma) and in the group and variable level means.
        for (j in 1:J){
        mu[i,k,j] ~ dnorm(mu1[k,j], tau.1[j])
        }

        }
        #loop over variables
        for (j in 1:J){
        #each mean comes from an uninformative normal distribution with epsilion given a small precision to place an uninformative prior on means.
        mu1[k,j] ~ dnorm(0, 0.0001)
        }

        }

        #informative prior on covariance matrix for observations
        tau[1 : ndims,1 : ndims] ~ dwish(R[ , ], ndims + 1)
        for (i in 1:ndims){
        for (j in 1:ndims){
        R[i,j] <- covm[i,j]*(ndims + 1)
        }
        }

        #uninformative prior on variances for random group effect
        for (j in 1:ndims){
        tau.1[j] <- 1/pow(sigma.1[j],2)
        sigma.1[j] ~ dunif(0,1)
        }

        }
        ")
    sink()

    #specify data required, Y is now a 3d array
    dat <- list(N = maxobv, J = ndims, K = ngroups, ndims = ndims,
                Y = structure(
                  .Data = as.numeric(Y),
                  .Dim = c(maxobv, ngroups ,ndims)),
                covm = structure(
                  .Data = as.numeric(covm),
                  .Dim = c(ndims,ndims))
    )

    #specify parameters to return
    params <- c("mu","tau", "tau.1", "mu1")

    jm <- rjags::jags.model("mod_modelbased.txt", data = dat, inits = inits, n.chains = nc, quiet = TRUE)

    #burnin
    stats::update(jm, n.iter = nb, progress.bar = "none")

    #iterations to use
    rjags::load.module("dic")

    zj <- rjags::jags.samples(jm, variable.names = params, n.iter = ni, thin = nt, progress.bar = "text")

    tau <- solve(summary(zj$tau, FUN = mean)$stat)
    mu <- summary(zj$mu, FUN = mean)$stat
    tau1 <-  1/summary(zj$tau.1, FUN = mean)$stat
    mu1 <- summary(zj$mu1, FUN = mean)$stat


    ##calculate volume of hypervolume

    eig <- eigen(tau)

    sf <- stats::qchisq(0.95,df = ndims)

    ax <- vector()
    for (k in 1:ndims){
      ax[k] <- sqrt(sf*eig$values[k])
    }

    volume <- 2/ndims * (pi^(ndims/2))/factorial((ndims/2)-1) * prod(ax)


    outlist <- list("means" = mu, "covariance" = tau, "volume" = volume, "group_means" = mu1, "group_variances" = tau1, "Y" = Y, "dimensions" = vars, "samples" = zj)



    }

  return(outlist)
}






































