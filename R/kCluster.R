# modification on git from copied files
kCluster <-

    function(cD, maxK = 100, matrixFile = NULL, replicates = NULL, algorithm = "Lloyd", B = 1000, sdm = 1)
{

    kstats <- function(k, x, cx) {
        if(k > length(unique(x))) return(rep(NA, 3))
        if(k == length(x)) {
                                        #if(is.null(replicates) || length(replicates) == length(unique(replicates))) {
            clustK <- list(centers = x, cluster = seq_along(x))
                                        #} else return(c(NA, NA))
        } else {
            clustK <- suppressWarnings(kmeans(x, k, iter.max = 1000, nstart = 100, algorithm = algorithm))
            if(any(is.na(clustK$centers))) clustK <- suppressWarnings(kmeans(x, k, iter.max = 1000, nstart = 100, algorithm = algorithm))
                                        #store the clustering and orderings as a string
            
                                        # the match bit makes sure that identical clusterings have identical numberings
                                        #if(forceReplicates && any(sapply(lapply(split(clustK$cluster, replicates), unique), length) > 1)) return(rep(NA, 2))                
        }
        if(forceReplicates) cluster <- clustK$cluster[match(replicates, levels(replicates))] else cluster <- clustK$cluster
        
        clusterings <- paste(match(cluster, (unique(cluster))), collapse = ":")
        orderings <- paste(order(clustK$centers[unique(cluster)]), collapse = "<")
        clusterOrder <- paste(clusterings, orderings, sep = "-")
                                        # statistic gets stored as a string too, with marginal loss of precision. Could fix it, but who cares
                                        #            stat <- max(sapply(seq_len(k), function(kk) {
                                        #                mx <- suppressWarnings(max(abs(split(cx, factor(cluster, levels = seq_len(k)))[[kk]] - clustK$centers[kk]))#
                                        #                mx
                                        #            }))
        
        stat = max(sapply(split(cx, factor(cluster, levels = seq_len(k))), function(kx) diff(range(kx))))
                                        #wss <- sum(sapply(split(cx, factor(cluster, levels = seq_len(k))), function(kx) sum((kx - mean(kx))^2)))
        
                                        #if(k > 1) dstat <- stat / min(diff(sort(clustK$centers))) else dstat <- NA
                                        #W <- sum(clustK$withinss)
        dstat <- stat / diff(range(cx))
        c(clusterOrder, stat, dstat)
    }
    
    
    if(inherits(cD, "countData")) {
        dat <- cD@data
        dat[dat == 0] <- 1
        dat <- log2(t(t(dat) / as.vector(libsizes(cD)) * mean(libsizes(cD))))
        replicates <- cD@replicates        
    } else dat <- as.matrix(cD)
    if(is.null(replicates)) {
        forceReplicates <- FALSE
    } else {
        if(!is.factor(replicates)) replicates <- as.factor(replicates)
        forceReplicates <- TRUE
        mdat <- do.call("cbind", lapply(levels(replicates), function(rep) apply(dat[,replicates == rep], 1, median)))
        if(length(replicates) != ncol(cD)) stop("If replicates are provided, there must be the same number of elements in the 'replicates' vector as there are columns in the 'cD' object.")
    }
    #print(forceReplicates)

    # this looks like it's something like Tibshirani's gap statistic - simulate data on a uniform distribution
    mx <- matrix(runif(n = B * ncol(dat), min = 0, max = 1), ncol = ncol(dat))
    if(forceReplicates) mxx <- t(apply(mx, 1, function(mxx) sapply(split(mxx, replicates), median))) else mxx <- mx
    
    mpK <- min(ncol(mxx), maxK)

    # calculate kstats based on that uniform distribution
    message("Bootstrapping distributions...", appendLF = TRUE) 
    pseudoW <- do.call("rbind", bplapply(seq_len(nrow(mx)), function(kk) 
        do.call("cbind", lapply(seq_len(mpK), kstats, x = mxx[kk,], cx = mx[kk,]))[2,]))
                                       #, BPPARAM = BP(workers = as.integer(cores), progressbar = TRUE)))
    message("done!")
    
    message("K-means processing...", appendLF = FALSE)

    koverk <- function(ii, maxK, forceReplicates, replicates) {
        if(forceReplicates) x <- mdat[ii,] else x <- dat[ii,]
        cx <- dat[ii,]
        
        genestats <- sapply(seq_len(min(length(x), maxK)), kstats, x = x, cx = cx)
        
        bootExp <- function(x, cx, replicates, forceReplicates) {
            rx <- range(cx)
            if(diff(rx) == 0) return(1)
            # uniform distribution gets rescaled here to range of data
            lWs <- split(log(as.numeric(pseudoW) * diff(rx)), rep(seq_len(mpK), each = B))
            elWk <- sapply(lWs, mean)
            lW <- log(as.numeric(genestats[2,seq_len(mpK)]))
            gap <- elWk - lW
            sdk <- sqrt(1 + 1/B) * sapply(lWs, sd)
            suppressWarnings(clustNum <- min(which(gap[-length(gap)] > gap[-1] - sdm * sdk[-1])))
                                        #mono <- gap[-length(gap)] > gap[-1] - sdm * sdk[-1]
            clustNum
        }

        clustNum <- bootExp(x, cx, replicates = replicates, forceReplicates = forceReplicates)
        clustNumM <- bootExp(x, x, replicates = NULL, forceReplicates = FALSE)
        
        list(gs = genestats, clustNum, clustNumM)
    }
                                       # this bit does all possible clusterings, parallelised
    kgene <- do.call("cbind", bplapply(seq_len(nrow(dat)), koverk, maxK = maxK, forceReplicates = forceReplicates, replicates = replicates))#, BPPARAM = BP(workers = as.integer(cores), progressbar = TRUE)))

    message(".done!")

    monos <- unlist(kgene[2,]) == 1
    
                                        # fix dimensions of matrix 
    kgeneS <- do.call("cbind", kgene[1,])
    
 
                                        # separate out clusterings and stats
    clusterings <- matrix(kgeneS[1,], ncol = nrow(dat))
    clusterings[is.na(clusterings)] <- FALSE
    stats <- matrix(as.numeric(kgeneS[3,]), ncol = nrow(dat))

    stats <- round(stats, 3)

                                        #temporary matrix prototype
    infmat <- matrix(1, nrow = nrow(stats), ncol = ncol(stats))

    stats[1,monos] <- 0
#    stats[seq.int(2,nrow(stats)),monos] <- Inf

    if(!is.null(matrixFile)) {
        if(substr(matrixFile, nchar(matrixFile) -2, nchar(matrixFile)) != ".gz") {
            message("Matrix file will be gzipped; appending '.gz' to filename supplied")
            matrixFile <- paste(matrixFile, ".gz", sep = "")
        }
        if(file.exists(matrixFile)) file.remove(matrixFile)
        gzfile <- gzfile(matrixFile, "w")
    }



                                        # write one by one the stats for each gene. Can't trivially parallelise this bit or you will have multiple threads writing to same file. Could parallelise with writes to separate files followed by cat and sort but this would take it out of pure R.


    message("Comparing clusterings...", appendLF = FALSE)

    if(!is.null(matrixFile)) {
        lapplyFun <- lapply
        writeLines(paste(c("", rownames(dat)), collapse = "\t"), gzfile)
    } else lapplyFun <- bplapply
    kAM <- do.call("rbind", lapplyFun(seq_len(ncol(clusterings)), function(ii) {
            if(sample(seq_len(100), 1) == 1) message(".", appendLF = FALSE)
                                          # fill in temporary matrix with valid statistics for each comparison
            tmat <- infmat; tmat[(clusterings[,ii] == clusterings)] <- stats[clusterings[,ii] == clusterings]
                                        # update temporary matrix with stats from current gene (if bigger)
            tmat <- apply(cbind(stats[,ii], tmat), 1, function(x) pmax(x[-1], x[1]))
            
                                        # select minimum statistic from each column of temporary matrix and write

            minstats <- do.call(pmin, c(lapply(seq_len(ncol(tmat)), function(i)tmat[,i]), list(na.rm = TRUE)))
            if(!is.null(matrixFile))
                writeLines(paste(rownames(dat)[ii], paste(minstats, collapse = "\t"), sep = "\t"), gzfile)
            minstats[seq_len(ii)] <- 1
            c(id = ii, pair.id = which.min(minstats), stat = min(minstats))
        }))#, BPPARAM = BP(workers = as.integer(cores), progressbar = TRUE)))

    if(!is.null(matrixFile)) close(gzfile)
    message(".done!")
    kAM
}

