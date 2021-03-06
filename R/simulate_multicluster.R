#' Simulate multicluster counts with time dependent association from a Dirichlet-Multinomial distribution
#'
#' @param counts the reference counts data set, either a matrix with rows as cluster and colums as samples or
#'               a \code{\link[SummarizedExperiment]{SummarizedExperiment-class}} object as generated from \code{\link{calcCounts}}.
#' @param nr_diff number of clusters where an association should be introduced. Has to be an even number. 
#' @param nr_samples number of samples in output data. If NULL will set to same as input data.
#' @param alphas alpha parameter of Dirichlet-Multinomial distribution. If 'NULL' will be estimated from 'counts'.
#' @param theta correlation parameter. If 'NULL' will be estimated from 'counts'.
#' @param sizes total sizes for each sample
#' @param covariate covariates, one for each sample. Default Null means random draws from an exponential distribution with rate = 1.
#' @param slope negative double. Coefficients corresponding to the covariate for the DA clusters. One for each pair of DA clusters. 
#'   To ensure correctness of the final distribution use only negative values. Alternatively can be a list of length 'nr_diff'/2, 
#'   where each elements indicates the proportion of the cluster size at the maximum covariate relative to the mean. E.g. 0.1 means
#'   that the cluster proportion at the maximum covariate is 0.1 times smaller than the mean.
#' @param group either Null (no group effect), double between 0 and 1 (proportion of samples with group effect), 
#'   integer (total number of samples with group effect), vector of 0 and 1 (indicating which samples have a group effect)
#'   or TRUE (effect with even group size).
#' @param group_slope regression coefficient of second covariate 'group'. If Null will choose a value automatically.
#'  Alternatively can be a list of length 'nr_diff'/2, where each elements indicates the proportion of the cluster 
#'  size at the maximum covariate relative to the mean. E.g. 0.1 means that the cluster proportion at the maximum 
#'  covariate is 0.1 times smaller than the mean.
#' @param diff_cluster Logical. Should the clusters be choosen random (TRUE) or according to a minimal distance of
#'                              of mean cluster sizes (FALSE). Alternatively a list of length 'nr_diff' with each element
#'                              a vector of length 2 indicating the paired clusters can be given. Default is FALSE.
#' @param enforce_sum_alpha Logical. Should the total sum of alphas be kept constant to ensure randomness of
#'                          non association clusters. The drawback is that one of the two paired clusters with an association
#'                          will not follow a GLMM (binomial link function) exactly any more. Default is TRUE.
#' @param return_summarized_experiment logical. Should the counts returned as a \code{\link[SummarizedExperiment]{SummarizedExperiment-class}}
#'   object. Default is FALSE.
#'
#' @return returns a list with elements counts (either matrix or SummarizedExperiment object, depending on input),
#'   row_data (data per cluster: regression coefficients used), col_data (data per sample: covariates), 
#'   alphas (matrix of alpha parameters used), theta (theta parameter), 
#'   var_counts (covariance matrix of a DM distribution with the given alphas and sizes).
#' @export
#' @importFrom stats rexp
#'
#' @examples
#' # without data reference:
#' alphas <- runif(20,10,100)
#' sizes <- runif(10,1e4,1e5)
#' output <- simulate_multicluster(alphas=alphas,sizes=sizes)
#' # counts:
#' counts <- output$counts
#' 
#' # with data reference:
#' # first simulate reference data set (normally this would be a real data set):
#' data <- t(dirmult::simPop(n=runif(10,1e4,1e5),theta=0.001)$data)
#' # then generate new data set based on original one but if DA clusters
#' output <- simulate_multicluster(data)
#' 
#' # specify number of differential clusters (has to be an even number):
#' output <- simulate_multicluster(alphas=alphas,sizes=sizes,nr_diff = 4)
#' 
#' # specify which clusters should be differential:
#' output <- simulate_multicluster(alphas=alphas,
#'                                 sizes=sizes,
#'                                 nr_diff = 4, 
#'                                 diff_cluster = list(c(2,9),c(6,7)))
#' 
#' # with second covariate (group):
#' output <- simulate_multicluster(alphas=alphas,sizes=sizes, group = TRUE)
#' 
#' # with second covariate (group), specify group proportion:
#' output <- simulate_multicluster(alphas=alphas,sizes=sizes, group = 0.5)
#' 
#' # with second covariate (group), specify id of group memberships for one group:
#' output <- simulate_multicluster(alphas=alphas,sizes=sizes, group = 3:7)
simulate_multicluster <-
  function(counts = NULL,
           nr_diff = 2,
           nr_samples = NULL,
           alphas = NULL,
           theta = NULL,
           sizes = NULL,
           covariate = NULL,
           slope = NULL,
           group = NULL,
           group_slope = NULL,
           diff_cluster = FALSE,
           enforce_sum_alpha = FALSE,
           return_summarized_experiment = FALSE) {
  # either reference or parameters needs to be given
  stopifnot(!is.null(counts) | (!is.null(alphas) & !is.null(sizes)))
    
  # stop if any slope is positive
  if(!is.null(slope) & any(slope >= 0) & !is.list(slope)){
    stop("Slopes should be negative",call. = FALSE)
  # if factor is given make sure length is right
  } else if (is.list(slope) & length(slope)==1){
    slope <- lapply(seq_len(nr_diff/2),function(x) slope[[1]])
  }
  if (is.list(slope) & any(slope >= 1 | slope < 0 )){
    stop("elements in 'slope' (if list) have to be between 0 and 1",call. = FALSE)
  }
  # stop if any group_slope is positive
  if(!is.null(group_slope) & any(group_slope >= 0) & !is.list(group_slope)){
    stop("Slopes should be negative",call. = FALSE)
    # if factor is given make sure length is right
  } else if (is.list(group_slope) & length(group_slope)==1){
    group_slope <- lapply(seq_len(nr_diff/2),function(x) group_slope[[1]])
  }
  if (is.list(group_slope) & any(group_slope >= 1 | group_slope < 0 )){
    stop("elements in 'group_slope' (if list) have to be between 0 and 1",call. = FALSE)
  }
    
  if(nr_diff%%2!=0){
    stop("'nr_diff' has to be an even number.",call. = FALSE)
  }
  # in case group is set to 'FALSE', set it to NULL
  if (!is.null(group)){
    if (is.logical(group) & all(!group)){
      group <- NULL
    }
  }
  if (is(counts, "SummarizedExperiment")){
    counts_inv <- t(SummarizedExperiment::assay(counts))
  } else if (!is.null(counts)){
    counts_inv <- t(counts)
  }
  if (is.null(nr_samples)){
    if (is.null(counts)){
      nr_samples <- length(sizes)
    } else if(!is.null(counts)){
      nr_samples <- dim(counts_inv)[1]
      if (is.null(rownames(counts_inv))){
        sample_names <- seq_len(nr_samples)
      } else {
        sample_names <- rownames(counts_inv)
      }
    }
  }

  if(!exists("sample_names")){
    sample_names <- paste0("sample_",seq_len(nr_samples))
  }
    
  if (is.null(counts)){
    stopifnot(nr_samples==length(sizes))
    n_clu <- length(alphas)
    cluster_names <- as.character(seq_len(n_clu))
  } else{
    n_clu <- dim(counts_inv)[2]
    if (is.null(colnames(counts_inv))){
      cluster_names <- seq_len(n_clu)
    } else {
      cluster_names <- colnames(counts_inv)
    }
    # estimate alphas and theta from data
    if(is.null(alphas)){
      # fit dirichlet multinomial on counts
      dir_out <- dirmult::dirmult(counts_inv)
      if (is.null(theta)){
        theta <- dir_out$theta
      }
      alphas <- dir_out$gamma
    }
  }
    if (is.null(theta)){
      theta <- 1/(1+sum(alphas))
    }
    if (is.null(sizes)){
      sizes <- apply(counts_inv, 1, sum)
      if (nr_samples>dim(counts_inv)[1]){
        random_sizes <- runif(nr_samples-dim(counts_inv)[1],min(sizes),max(sizes))
        sizes <- c(sizes,random_sizes)
      }
    }
  # group memberships
  if (!is.null(group)){
    if (is.numeric(group)){
      if (length(group)== 1){
        if (group<1){
          group_size <- round(group*nr_samples)
        } else{
          group_size <- round(group)
        }
        group_id <- sample(seq_len(nr_samples),group_size,replace = FALSE)
      } else {
        group_id <- group
      }
    } else {
      group_id <- sample(seq_len(nr_samples),round(nr_samples/2),replace = FALSE)
    }
    group_covariate <- matrix(rep(0,nr_samples),nrow=1)
    group_covariate[group_id] <- 1
    }
  # matrix of alphas
  alphas_inv <- matrix(alphas,nrow=nr_samples,ncol=n_clu,byrow = TRUE, dimnames =  list(sample_names,cluster_names))
  
  # all availabe non DA clusters 
  cluster_pool <- seq_len(n_clu)
  # beta matrix to be filled
  if (is.null(group)){
    betas <- matrix(NA,nrow=2,ncol=nr_diff,dimnames = list(c("b0","b1"),rep(NA,nr_diff)))
  } else{
    betas <- matrix(NA,nrow=3,ncol=nr_diff,dimnames = list(c("b0","b1","b2"),rep(NA,nr_diff)))
  }
  
  # simulate covariate if null
  if (is.null(covariate)){
    covariate <- matrix(rexp(nr_samples),nrow=1)
  } else if (!is.matrix(covariate)){
    covariate <- matrix(covariate,nrow=1)
  }
  colnames(covariate) <- rownames(alphas_inv)
  # maximal observed covariate value used for inferring b1
  zmax <- max(covariate)
  
  # loop through pairs of DA clusters
  for (i in seq_len(nr_diff/2)) {
    if (is.list(diff_cluster)){
      stopifnot(length(unlist(diff_cluster)) == length(unique(unlist(diff_cluster))))
      clu_ind <- diff_cluster[[i]]
    } else if(diff_cluster){
      # choose two random clusters
      clu_ind <- sample(cluster_pool,2, replace = FALSE)
    } else{
      # choose two clusters with minimum distance of alphas
      dis_mat <- abs(matrix(alphas[cluster_pool],nrow=length(cluster_pool),ncol=length(cluster_pool),byrow = TRUE)-alphas[cluster_pool])
      diag(dis_mat) <- Inf
      clu_ind <- cluster_pool[arrayInd(which.min(dis_mat), dim(dis_mat))]
    }
    # update availabe non DA clusters
    cluster_pool <- cluster_pool[!(cluster_pool %in% clu_ind)]
    
    # pi0: pi at z=0; as mean(x)
    pi0 <- alphas[clu_ind]/sum(alphas)
    
    if (enforce_sum_alpha){
      pi0_order <- seq_along(pi0)
    } else{
      pi0_order <- order(pi0)
    }
    pi0 <- pi0[pi0_order]
    
    # if z=0 b0=logit(pi0)
    b0 <- log(pi0/(1-pi0))
    
    # if slope is given as a factor
    if (is.list(slope)){
      slope_factor <- slope[[i]]
    } else {
      slope_factor <- 0.7
    }
    # max proportion at z=zmax
    pimax <- c(pi0[1]-pi0[1]*slope_factor, pi0[2]+pi0[1]*slope_factor)
    # logit(pimax) = b0+b1*zmax, solve for b1
    b1 <- matrix((log(pimax/(1-pimax))-b0)/zmax,ncol=1,dimnames = list(names(b0)))
    
    # if a slope is given, overwrite the calculated one
    if (!is.null(slope) & !is.list(slope)){
      b1[1,1] <- slope[i]
    }
    
    # add calculated betas to matrix
    betas[1,c((2*i-1):(2*i))] <- b0
    betas[2,c((2*i-1):(2*i))] <- c(b1)
    colnames(betas)[c((2*i-1):(2*i))] <- clu_ind[pi0_order]
    # calculate pi for all covariate values
    pi <- t(1/(1+exp(-(b0+b1%*%covariate))))
    
    # if second covariate is present
    if (!is.null(group)){
      # if group slope is given as a factor
      if (is.list(group_slope)){
        group_slope_factor <- group_slope[[i]]
      } else {
        group_slope_factor <- 0.2
      }
      pi02 <- c(pi0[1]-pi0[1]*group_slope_factor, pi0[2]+pi0[1]*group_slope_factor)
      # logit(pi0) = b0+b2, at z=0 and group=1
      b2 <- matrix(log(pi02/(1-pi02))-b0,ncol=1,dimnames = list(names(b0)))
      # if a group_slope is given, overwrite the calculated one
      if (!is.null(group_slope) & !is.list(group_slope)){
        b2[1,1] <- group_slope[i]
      }
      betas[3,c((2*i-1):(2*i))] <- c(b2)
      # calculate pi for all covariate values
      pi <- t(1/(1+exp(-(b0+b1%*%covariate+b2%*%group_covariate))))
    }
    
    if (enforce_sum_alpha){
      # adapt proportions of second cluster so that total sum of alphas will stay the same
      pi[,2] <- pi0[2]-(pi[,1]-pi0[1])
    }
    pi <- pi[,pi0_order]
    alphas_inv[,clu_ind] <- pi*sum(alphas)
  }
  # all clusters with an association
  diff_clus <- seq_len(n_clu)[!(seq_len(n_clu) %in% cluster_pool)]
  
  # create row data
  probs_tmp <- alphas/sum(alphas)
  if (is.null(group)){
    row_data_df <- data.frame(cluster_id = cluster_names, b0 = log(probs_tmp/(1-probs_tmp)),b1=0,paired=NA)
    diff_clu_betas <- as.integer(colnames(betas))
    row_data_df[diff_clu_betas,c("b0","b1")] <- t(betas)
  }else {
    row_data_df <- data.frame(cluster_id = cluster_names, b0 = log(probs_tmp/(1-probs_tmp)),b1=0,b2=0,paired=NA, stringsAsFactors = FALSE)
    diff_clu_betas <- as.integer(colnames(betas))
    row_data_df[diff_clu_betas,c("b0","b1","b2")] <- t(betas)
  }
  for (i in seq_len(nr_diff/2)) {
    row_data_df[diff_clu_betas[c((2*i-1):(2*i))],"paired"] <- i
  }
  # create col data
  if (is.null(group)){
    col_data_df <- data.frame(sample = sample_names, covariate = c(covariate))
  }else {
    col_data_df <- data.frame(sample = sample_names, covariate = c(covariate), group_covariate=c(group_covariate))
  }
    
  # calculate covariance matrices
  var_counts <- purrr::map(seq_len(nr_samples), function(i){var_dirichlet_multinomial(t(alphas_inv)[,i],seq_len(n_clu),sizes[i])}) %>% 
    purrr::reduce(rbind)
  # mean proportions
  probs_compl <- t(apply(alphas_inv,1,function(x) x/sum(x)))
  # simulate data
  out_data <- purrr::map(seq_len(nr_samples), function(i) {
    dirmult::simPop(J=1,n=sizes[i],pi=probs_compl[i,],theta=theta)$data %>% t()
  }) %>% purrr::reduce(cbind)
  
  colnames(out_data) <- sample_names
  rownames(out_data) <- cluster_names
  # adjust output format
  if (is(counts, "SummarizedExperiment")){
    out_data_se <- counts
    SummarizedExperiment::assay(out_data_se) <- out_data
    SummarizedExperiment::rowData(out_data_se) <- cbind(SummarizedExperiment::rowData(out_data_se),row_data_df)
    SummarizedExperiment::colData(out_data_se) <- cbind(SummarizedExperiment::colData(out_data_se),col_data_df)
    out_data <- out_data_se
  } 
  if (return_summarized_experiment){
    out_data <- SummarizedExperiment::SummarizedExperiment(
      assays = list(counts=out_data),
      rowData = row_data_df,
      colData = col_data_df)
  }
  return(list(counts=out_data,
              row_data=row_data_df, 
              col_data = col_data_df,
              alphas=t(alphas_inv),
              theta=theta,
              var_counts=var_counts))
}


var_dirichlet_multinomial <- function(alphas,ind,size){
  sum_alphas <- sum(alphas)
  prop_alphas <- alphas[ind]/sum_alphas
  return(size*prop_alphas*(1-prop_alphas)*((size+sum_alphas)/(1+sum_alphas)))
}

