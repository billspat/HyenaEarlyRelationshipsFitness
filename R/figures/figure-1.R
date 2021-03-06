### Figure 1 - Flowchart
# Alec Robitaille

### Packages ----
pkgs <- c(
	'data.table',
	'ggplot2',
	'asnipe',
	'patchwork',
	'ggthemes',
	'spatsoc',
	'igraph',
	'ggnetwork',
	'gridExtra',
	'foreach',
	'rphylopic',
	'grid',
	'png',
	'magick'
)
p <- lapply(pkgs, library, character.only = TRUE)

### Import data ----
derived <- dir('data/derived-data', full.names = TRUE)

# Associations
asso <- readRDS(derived[grepl('prep-asso', derived)])

# Life stages
life <- readRDS(derived[grepl('ego-life', derived)])

# Aggression
aggr <- readRDS(derived[grepl('prep-aggr', derived)])

# Affiliation
affil <- readRDS(derived[grepl('prep-affil', derived)])


# Set column names
groupCol <- 'group'
idCol <- 'hyena'

# Set focal individual
selfocal <- 'mono'
selfocaltitle <- 'Monopoly'

### Set theme ----
pal <- c('#E69F00', '#56B4E9', '#009E73', '#F0E442')

theme_set(theme_classic())
theme_update(
	axis.text = element_blank(),
	axis.title = element_blank(),
	axis.ticks = element_blank(),
	aspect.ratio = 1,
	line = element_blank()
)

fontSize <- 24
gridTheme <- gridExtra::ttheme_default(base_size = fontSize)

focal <- life[ego == selfocal]


### Association networks ----
## Make networks for each life stage
# To avoid the merge dropping out sessiondate to sessiondate and sessiondate.i (matching period start and end), we'll add it as an extra column and disregard those later
asso[, idate := sessiondate]

# Generate a GBI for each life stage
gbiLs <- foreach(i = seq(1, nrow(focal))) %do% {
	sub <- asso[focal[i],
							on = .(sessiondate >= period_start,
										 sessiondate < period_end)]

	# Filter out < 10
	get_gbi(sub[hyena %chin% sub[, .N, idCol][N > 10, get(idCol)]],
					groupCol, idCol)
}

# Calculate SRI
sriLs <- foreach(g = gbiLs) %do% {
	get_network(g, 'GBI', 'SRI')
}

# Generate graph and calculate network metrics
assonets <- foreach(n = seq_along(sriLs)) %do% {
	g <- graph.adjacency(sriLs[[n]], 'undirected',
											 diag = FALSE, weighted = TRUE)

	w <- E(g)$weight
	g
}
names(assonets) <- paste0('association-', focal$period)


### Aggression networks ----
## Make networks for each ego*life stage
# To avoid the merge dropping out sessiondate to sessiondate and sessiondate.i (matching period start and end), we'll add it as an extra column and disregard those later
aggr[, idate := sessiondate]

#  average of behavior1 during period
avgLs <- foreach(i = seq(1, nrow(focal))) %do% {
	f <- aggr[focal[i],
						on = .(sessiondate >= period_start,
									 sessiondate < period_end)]
	f[, .(avgB1 = mean(behavior1)), by = .(aggressor, recip)]
}

# Create edge list
edgeLs <- foreach(i = seq(1, nrow(focal))) %do% {
	sri <- data.table(melt(sriLs[[i]]), stringsAsFactors = FALSE)
	sri[, c('Var1', 'Var2') := lapply(.SD, as.character), .SDcols = c(1, 2)]
	merge(
		avgLs[[i]],
		sri,
		by.x = c('aggressor', 'recip'),
		by.y = c('Var1', 'Var2'),
		all.x = TRUE
	)
}

# Generate graph and calculate network metrics
aggrnets <- foreach(i = seq_along(edgeLs)) %do% {
	sub <- edgeLs[[i]][value != 0 & (value / avgB1) != 0]
	g <- graph_from_data_frame(sub[, .(aggressor, recip)],
														 directed = TRUE)

	# average of behavior1 during period/AI during period
	w <- sub[, avgB1 / value]
	E(g)$weight <- w

	g
}
names(aggrnets) <- paste0('aggr-', focal$period)


### Affiliation networks ----
# To avoid the merge dropping out sessiondate to sessiondate and sessiondate.i (matching period start and end), we'll add it as an extra column and disregard those later
affil[, idate := sessiondate]

# Count number of (directed) affiliations between individuals
countLs <- foreach(i = seq(1, nrow(focal))) %do% {
	f <- affil[focal[i],
						 on = .(sessiondate >= period_start,
						 			 sessiondate < period_end)]
	f[, .N, .(ll_receiver, ll_solicitor)]
}

# Create edge list
edgeLs <- foreach(i = seq(1, nrow(focal))) %do% {
	sri <- data.table(melt(sriLs[[i]]), stringsAsFactors = FALSE)
	sri[, c('Var1', 'Var2') := lapply(.SD, as.character), .SDcols = c(1, 2)]
	merge(
		countLs[[i]],
		sri,
		by.x = c('ll_receiver', 'll_solicitor'),
		by.y = c('Var1', 'Var2'),
		all.x = TRUE
	)
}

# Generate graph and calculate network metrics
affilnets <- foreach(i = seq_along(edgeLs)) %do% {
	sub <- edgeLs[[i]][value != 0]
	g <- graph_from_data_frame(sub[, .(ll_solicitor, ll_receiver)],
														 directed = TRUE)
	w <- sub[, N / value]
	E(g)$weight <- w

	g
}
names(affilnets) <- paste0('affil-', focal$period)


### Plot nets
nets <- rbindlist(lapply(c(assonets, aggrnets, affilnets),
												 ggnetwork),
									idcol = 'nm',
									fill = TRUE)
nets[, label := ifelse(name == selfocal, selfocal, ' ')]

nets[, c('type', 'period') := tstrsplit(nm, '-')]

nets[period == 'cd', period := 'CD']
nets[period == 'postgrad', period := 'DI']
nets[period == 'adult', period := 'Adult']

nets[type == 'affil', type := 'Affiliation']
nets[type == 'association', type := 'Association']
nets[type == 'aggr', type := 'Aggression']

nets[, type := factor(type, levels = c('Association', 'Aggression', 'Affiliation'))]

nets[, period := factor(period, levels = c('CD', 'DI', 'Adult'))]

nets[, weightCut := cut(weight, breaks = 4), type]
nets[type == 'Association', weightCut := cut(weight * 100, breaks = 4)]

# for aesthetic
# nets[vertex.names == 'mono', c('x', 'y') := .(0.5, 0.5)]

(
	gnets <- ggplot(nets,
									aes(
										x = x,
										y = y,
										xend = xend,
										yend = yend
									)) +
		geom_edges(aes(alpha = weightCut),
							 data = nets[type == 'Aggression']) +
		geom_edges(aes(alpha = weightCut),
							 data = nets[type == 'Affiliation']) +
		geom_edges(aes(alpha = weightCut),
							 data = nets[type == 'Association']) +
		geom_nodes() +
		geom_nodes(
			color = ifelse(selfocal == 'mono', '#1b9e77', '#7570b3'),
			shape = 19,
			size = 4,
			data = nets[name == selfocal]
		) +
		theme_blank() +
		facet_grid(type ~ period, switch = 'y') +
		guides(alpha = FALSE)
)


### Timeline ----
focal[period == 'cd', period := 'CD']
focal[period == 'postgrad', period := 'DI']
focal[period == 'adult', period := 'Adult']

(
	tmln <- ggplot(focal,
								 aes(x = period_start)) +
		geom_hline(
			yintercept = 0,
			color = 'black',
			size = 0.3
		) +
		geom_segment(
			aes(x = period_start, xend = period_end, color = period),
			linetype = 1,
			size = 6,
			y = 0,
			alpha = 0.8,
			yend = 0
		) +
		geom_text(aes(
			x = period_start - 20 + (period_end - period_start) / 2,
			y = 0.1,
			label = period
		)) +
		geom_text(aes(
			x = period_end,
			y = -.1,
			label = period_end
		), data = focal[period != 'CD']) +
		geom_text(aes(
			x = period_start,
			y = -.1,
			label = period_start
		)) +
		guides(color = FALSE) +
		scale_color_tableau(palette = 'Color Blind') +
		scale_y_continuous(expand = c(0, 0.1)) +
		scale_x_date(expand = c(0.1, 0)) +
		theme(aspect.ratio = 0.13) +
		geom_point(aes(period_start, 0)) +
		geom_point(aes(period_end, 0))
)


### Silhouette ----
img <- rphylopic::image_data('f1b665ae-8fe9-42e4-b03a-4e9ae8213244', 512)[[1]]

(gimg <- ggplot() +
		add_phylopic(img, 1, color = ifelse(selfocal == 'mono', '#1b9e77', '#7570b3')) +
		labs(caption = selfocaltitle)  +
		theme(plot.caption = element_text(hjust = 0.5, size = 15)))


### Patchwork ----
layout <- '
#BBB
#CCC
ACCC
#CCC
'

(fig <- gimg + tmln + gnets  +
		plot_layout(
			design = layout,
			ncol = 2,
			widths = c(1, 3)
		))


### Output ---
w <- 220
h <- 0.66 * w
ggsave(
	filename = paste0('graphics/flowchart-', selfocal, '.png'),
	plot = fig,
	width = w,
	height = h,
	units = 'mm'
)


# Combine
mono <- image_read('graphics/flowchart-mono.png')
gui <- image_read('graphics/flowchart-gui.png')
img <- c(mono, gui)

image_write(image_append(img, stack = TRUE),
						path = 'graphics/figure-1.pdf',
						format = 'pdf')
