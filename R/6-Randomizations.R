### Hyena Network Randomizations ====
# Alec Robitaille
# Started: March 01 2019


### Packages ----
libs <- c('data.table', 'spatsoc', 'asnipe', 'igraph', 'foreach')
lapply(libs, require, character.only = TRUE)

### Import data ----
derived <- 'data/derived-data/'
der <- dir(derived, full.names = TRUE)

# Life stages
life <- readRDS(der[grepl('ego-life', der)])

# Association
asso <- readRDS(der[grepl('prep-asso', der)])

# Aggression
aggr <- readRDS(der[grepl('prep-aggr', der)])

# Affiliation
affil <- readRDS(der[grepl('prep-affil', der)])

## Set column names
groupCol <- 'group'
idCol <- 'ID'

## Iterations
set.seed(53)
iterations <- 1000


### Count edges ----
# Count the number of affiliations (edges) in each session
affil[, countAffil := .N, session]
affil[, sessiondatecopy := sessiondate]

# Count the number of individuals associating in each session
asso[, countAsso := .N, session]
asso[, sessiondatecopy := sessiondate]

# Count the number of aggressions (edges) in each session
aggr[, countAggr := .N, session]
aggr[, sessiondatecopy := sessiondate]

### Randomize affiliation networks ----
# Set up parallel with doParallel and foreach
doParallel::registerDoParallel()


life[, ID := ego]

# Include an affil and aggression index to resolve the dup rows in merge with association
affil[, affilIndex := .I]
aggr[, aggrIndex := .I]

# In case of error
# options(error = recover)


# Randomization --------------------------------------------------
# Set na action to exlude to ensure NAs in res are padded
options(na.action = "na.exclude")

range01 <- function(x) {
	(x - min(x)) / (max(x) - min(x))
}

affilnms <- c('ll_receiver', 'll_solicitor')
aggrnms <- c('aggressor', 'recip')

seqlife <- seq.int(length.out = nrow(life))

randMets <- lapply(seq(0, iterations), function(iter) {
	# Within ego stages, randomize association data
	subLs <- foreach(i = seqlife) %do% {
		# Sub association data to ego stage
		sub <- asso[life[i],
								on = .(sessiondate >= period_start,
											 sessiondate < period_end)]

		# If iteration != 0, randomize association IDs
		if (iter == 0) {
			sub[, ID := hyena]
		} else {
			sub[, ID := sample(hyena)]
		}
	}

	## Count sessions ----------------------------------------------
	nseshLs <- rbindlist(foreach(i = seqlife) %do% {
		sub <- subLs[[i]]
		ego <- sub$ego[[i]]
		period <- sub$period[[i]]

		uasso <- unique(sub[, .(ID, session)])
		uasso[, nSession := .N, session]
		nsesh <- uasso[, .(nSession = .N, nAlone = sum(nSession == 1), period),
									 by = ID]
		return(nsesh[ID == ego])
	})


	## Affiliation -------------------------------------------------
	# Randomize affiliations
	randAffilLs <- foreach(i = seqlife) %do% {
		# Sub affiliations w/i ego period
		subAffil <- affil[life[i],
											on = .(sessiondate >= period_start,
														 sessiondate < period_end)]

		# Collect all the individuals * sessiondate
		iddate <- subLs[[i]][, .(ID = unique(ID)), sessiondatecopy]

		# Randomize affiliation data using only IDs from each session date
		# TODO: check if replace = TRUE
		if (iter == 0) {
			subAffil
		} else {
			subAffil[, (affilnms) :=
							 	{
							 		ids <- iddate[sessiondatecopy == .BY[[1]]]$ID

							 		if (length(ids) > .N) {
							 			l <- sample(ids, size = .N, replace = TRUE)
							 			r <- sample(ids, size = .N, replace = TRUE)

							 			while (any(l == r)) {
							 				l <- sample(ids, size = .N, replace = TRUE)
							 				r <- sample(ids, size = .N, replace = TRUE)
							 			}
						 			list(l, r)
							 		}
							 	}, by = sessiondatecopy]
		}
	}

	# Count matching edges
	countLs <- foreach(i = seqlife) %do% {
		focal <- randAffilLs[[i]]
		focal[, N := .N, by = .(ll_receiver, ll_solicitor)]
		unique(focal[, .(ll_receiver,
										 ll_solicitor,
										 period_length,
										 N,
										 affilRate = N / period_length)])
	}

	## Aggression -------------------------------------------------
	# Randomize aggressions
	randAggrLs <- foreach(i = seqlife) %do% {
		# Sub aggressions w/i ego period
		subAggr <- aggr[life[i],
											on = .(sessiondate >= period_start,
														 sessiondate < period_end)]

		# Collect all the individuals * sessiondate
		iddate <- subLs[[i]][, .(ID = unique(ID)), sessiondatecopy]

		# Randomize aggression data using only IDs from each session date
		# TODO: check if replace = TRUE
		if (iter == 0) {
			subAggr
		} else {
			subAggr[, (aggrnms) :=
							 	{
							 		ids <- iddate[sessiondatecopy == .BY[[1]]]$ID

							 		if (length(ids) > .N) {
							 			l <- sample(ids, size = .N, replace = TRUE)
							 			r <- sample(ids, size = .N, replace = TRUE)

							 			while (any(l == r)) {
							 				l <- sample(ids, size = .N, replace = TRUE)
							 				r <- sample(ids, size = .N, replace = TRUE)
							 			}
							 			list(l, r)
							 		}
							 	}, by = sessiondatecopy]
		}
	}

	# Average of behavior1 during period
	# TODO: do we need aggrIndex?
	avgLs <- foreach(i = seqlife) %do% {
		focal <- randAggrLs[[i]]
		focal[, .(avgB1 = mean(behavior1),
							avgB1Len = mean(behavior1) / period_length,
							period_length = period_length[[1]]),
					by = .(aggressor, recip)]
	}

	## Association -------------------------------------------------
	# Generate a GBI for each ego's life stage
	gbiLs <- foreach(i = seqlife) %do% {
		sub <- subLs[[i]]

		# Filter out < 10
		get_gbi(sub[get(idCol) %chin% sub[, .N, idCol][N > 10, get(idCol)]],
						groupCol, idCol)
	}

	# Calculate SRI
	sriLs <- foreach(g = gbiLs) %do% {
		get_network(g, 'GBI', 'SRI')
	}

	## Combine edges, make graphs  -------------------------------------
	# Associations
	assoGraphs <- foreach(i = seqlife) %do% {
		graph.adjacency(sriLs[[i]], 'undirected',
										diag = FALSE, weighted = TRUE)
	}

	# Affiliations
	# TODO: loop to check range of y var
	affilGraphs <- foreach(i = seqlife) %do% {
		# Melt SRI matrix to a three column data.table
		melted <- melt(as.data.table(sriLs[[i]], keep.rownames = 'id1'), id.vars = 'id1')

		melted[, c('id1', 'variable') := lapply(.SD, as.character), .SDcols = c(1, 2)]

		# Setnames
		setnames(melted, c('id1', 'variable', 'value'), c('ll_receiver', 'll_solicitor', 'sri'))

		# Merge SRI onto affiliation data
		sub <- merge(countLs[[i]], melted, by = c('ll_receiver', 'll_solicitor'), all.x = TRUE)[sri != 0]
		# Calculate residuals from affiliation rate ~ SRI
		sub[, res := residuals(glm(affilRate ~ sri), family = 'binomial',
													 type = 'deviance')]

		sub[, res01 := range01(res)]

		# Generate the graph
		g <- graph_from_data_frame(sub[, .(ll_solicitor, ll_receiver)],
															 directed = TRUE)

		# Set edge weight to residuals
		w <- sub$res01
		E(g)$weight <- w

		return(g)
	}

	# Aggressions
	aggrGraphs <- foreach(i = seqlife) %do% {
		# Melt SRI matrix to a three column data.table
		melted <- melt(as.data.table(sriLs[[i]], keep.rownames = 'id1'), id.vars = 'id1')

		melted[, c('id1', 'variable') := lapply(.SD, as.character), .SDcols = c(1, 2)]

		# Setnames
		setnames(melted, c('id1', 'variable', 'value'), c('aggressor', 'recip', 'sri'))

		# Merge SRI onto aggression data
		sub <- merge(avgLs[[i]], melted, by = c('aggressor', 'recip'), all.x = TRUE)[
			sri != 0 & (sri / avgB1) != 0]

		# Calculate residuals from average of behavior1 during period ~ SRI
		sub[, res := residuals(glm(avgB1Len ~ sri, family = 'binomial'),
													 type = 'deviance')]

		sub[, res01 := range01(res)]

		# Generate the graph
		g <- graph_from_data_frame(sub[, .(aggressor, recip)],
															 directed = TRUE)

		# Set edge weight to residuals
		w <- sub$res01
		E(g)$weight <- w

		return(g)
	}

	## Return network metrics ---------------------------------
	mets <- foreach(i = seqlife) %do% {
		affilG <- affilGraphs[[i]]
		aggrG <- aggrGraphs[[i]]
		assoG <- assoGraphs[[i]]

		ego <- life$ego[[i]]

		w <- E(assoG)$weight

		assoMets <- data.table(
			sri_degree = degree(assoG),
			sri_strength = strength(assoG),
			sri_betweenness = betweenness(assoG, directed = FALSE, weights = 1/w),
			ID = names(degree(assoG))
		)[ID == ego]

		w <- E(affilG)$weight
		affilMets <- data.table(
			affil_degree = degree(affilG, mode = 'total'),
			affil_outdegree = degree(affilG, mode = 'out'),
			affil_indegree = degree(affilG, mode = 'in'),
			affil_strength = strength(affilG, mode = 'total' ,weights = w),
			affil_outstrength = strength(affilG, mode = 'out', weights = w),
			affil_instrength = strength(affilG, mode = 'in', weights = w),
			affil_betweenness = betweenness(affilG, directed = TRUE, weights = 1/w),
			ID = names(degree(affilG))
		)[ID == ego]

		w <- E(aggrG)$weight
		aggrMets <- data.table(
			aggr_degree = degree(aggrG, mode = 'total'),
			aggr_outdegree = degree(aggrG, mode = 'out'),
			aggr_indegree = degree(aggrG, mode = 'in'),
			aggr_strength = strength(aggrG, mode = 'total', weights = w),
			aggr_outstrength = strength(aggrG, mode = 'out', weights = w),
			aggr_instrength = strength(aggrG, mode = 'in', weights = w),
			aggr_betweenness = betweenness(aggrG, directed = TRUE, weights = 1/w),
			ID = names(degree(aggrG))
		)[ID == ego]


		# If no rows, fill columns with NA
		if (nrow(assoMets) == 0) {
			assoMets <- assoMets[NA]
		}

		if (nrow(affilMets) == 0) {
			affilMets <- affilMets[NA]
		}

		if (nrow(aggrMets) == 0) {
			aggrMets <- aggrMets[NA]
		}
		ls <- list(life[i], assoMets, affilMets, aggrMets)
		Reduce(function(x, y) merge(x, y, by = 'ID', all = TRUE), ls)
	}
	rbindlist(mets)[nseshLs, on = c('ID', 'period'), all = TRUE][, iteration := iter]
})

out <- rbindlist(randMets)

out[iteration == 0, observed := TRUE]
out[iteration != 0, observed := FALSE]

### Output ----
# saveRDS(out, paste0(derived, 'observed-random-metrics.Rds'))
