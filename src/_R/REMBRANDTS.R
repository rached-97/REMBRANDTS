library(gplots)

########### Identify the input arguments

args <- commandArgs(trailingOnly = TRUE)
jobID <- args[1]
stringency <- as.numeric(args[2])
fitMode <- args[3]

tempFolder <- paste("./tmp/",jobID,sep="")
outputFolder <- paste("./out/",jobID,sep="")

########### read the exon and intron centered normalized reads, and the total read counts

exon <- read.csv(paste(tempFolder,"/vsd_normalized.exonic.all.centered.mx.txt",sep=""),sep="\t")
nSample <- ncol(exon)-1
exonRawCounts <- read.csv(paste(tempFolder,"/vsd_normalized.exonic.all.mx.txt",sep=""),sep="\t")
if( nSample != ncol(exonRawCounts)-1 )
  print("Error: unequal sample numbers")
intron <- read.csv(paste(tempFolder,"/vsd_normalized.intronic.all.centered.mx.txt",sep=""),sep="\t")
if( nSample != ncol(intron)-1 )
  print("Error: unequal sample numbers")
intronRawCounts <- read.csv(paste(tempFolder,"/vsd_normalized.intronic.all.mx.txt",sep=""),sep="\t")
if( nSample != ncol(intronRawCounts)-1 )
  print("Error: unequal sample numbers")

########### calculate the median counts, and merge all relevant data

exonRawCounts$MedianExon <- apply(exonRawCounts[,2:ncol(exonRawCounts)],1,median)
intronRawCounts$MedianIntron <- apply(intronRawCounts[,2:ncol(intronRawCounts)],1,median)

merged <- merge(exon,intron,by="GeneID", suffixes = c('.exon', '.intron'))
merged <- merge( merged, exonRawCounts[,c(1,ncol(exonRawCounts))],by="GeneID")
merged <- merge( merged, intronRawCounts[,c(1,ncol(intronRawCounts))],by="GeneID")

########### optimize the total read count threshold so as to maximize correlation between exon and intron fold-changes

print( paste( "Optimizing read count cutoff at stringency ", stringency, " ...", sep="" ) )
correl_all <- cor(
	unlist(merged[ , 2:(nSample+1)]),
	unlist(merged[ , (nSample+2):(2*nSample+1)]) )
print( paste( "Total correlation is ", correl_all, sep="" ) )
print( paste( "Total number of genes is ", nrow(merged), sep="" ) )

correl_max <- -10
cutoff_table <- data.frame(matrix(c(Inf,0,NA),nrow=1,ncol=3,dimnames=list("",c("Threshold","NumGenes","Correlation"))))
cutoffs <- quantile( c(merged$MedianIntron, merged$MedianExon), probs = seq( 1, 0, -0.01 ) )
for( i in cutoffs )
	if( sum(merged$MedianIntron > i & merged$MedianExon > i) > 2000 )
	{
		correl <- cor(
			unlist(merged[ merged$MedianIntron > i & merged$MedianExon > i , 2:(nSample+1)]),
			unlist(merged[ merged$MedianIntron > i & merged$MedianExon > i, (nSample+2):(2*nSample+1)]) )

		if( correl_max < correl )
			correl_max <- correl

		if( correl >= (correl_max-correl_all)*stringency + correl_all )
			threshold <- i

		cutoff_table <- rbind( cutoff_table, c( i, sum( merged$MedianIntron > i & merged$MedianExon > i), correl ) );
	}

print( paste( "Maximum correlation is ", correl_max, sep="" ) )
print( paste( "Selected threshold is ", threshold, sep="" ) )
print( paste( "Number of remaining genes is ", sum(merged$MedianIntron > threshold & merged$MedianExon > threshold), sep="" ) )

########### Filter the data to include only genes that pass the read count cutoff, and create a scatterplot

# the filtered exon counts
y <- unlist(merged[ merged$MedianIntron > threshold & merged$MedianExon > threshold, 2:(nSample+1)])
# the filtered intron counts
x <- unlist(merged[ merged$MedianIntron > threshold & merged$MedianExon > threshold, (nSample+2):(2*nSample+1)])

jpeg(file=paste(outputFolder,"/scatterplot.jpg",sep=""),
	width=300,height=350)
smoothScatter( x, y, colramp=colorRampPalette(c( "white", "red", "black" ) ), nbin=400, nrpoints=0, xlab="Log2 fold-change of intronic reads", ylab="Log2 fold-change of exonic reads" )
lines( c(-10,+10), c(0,0), lty=3 )
lines( c(0,0), c(-10,+10), lty=3 )

########### Now perform bias removal

# The intron counts represent the effect of transcriptional changes
# The exon counts represent the combined effect of transcriptional and post-transcriptional changes
# Model the exon-intron counts as a function of intron counts, so that by subtracting the fitted values
# only the effect of post-transcriptional regulation remains

# create a copy of exon counts
exon.counts <- merged[ merged$MedianIntron > threshold & merged$MedianExon > threshold, 1:(nSample+1)]
# plot the similarity heatmap for exon counts
sim <- cor(as.matrix(exon.counts[,2:(nSample+1)]))
width  <- ncol(sim) * 36.9 + 231
height <- nrow(sim) * 36.9 + 231
jpeg(file=paste(outputFolder,"/exonic.filtered.correl.heatmap.jpg",sep=""),
	width=width,height=height)
exonHeatmap <- heatmap.2(sim, distfun=function(x) as.dist(1-x), trace="none", margin=c(10, 10),symm=T,revC=T,breaks=seq(-1,1,length.out=256),col=colorRampPalette(c("blue","white","red"))(255), key.title=NA, key.xlab="Pearson correlation", density.info="none", key.ylab=NA, keysize=0.85)

# create a copy of intron counts
intron.counts <- merged[ merged$MedianIntron > threshold & merged$MedianExon > threshold, c(1,(nSample+2):(2*nSample+1))]
intron.counts.MedianIntron <- merged[ merged$MedianIntron > threshold & merged$MedianExon > threshold, 'MedianIntron'] # need this to estimate bias using neighborhood method
# plot the similarity heatmap for intron counts
sim <- cor(as.matrix(intron.counts[,2:(nSample+1)]))
width  <- ncol(sim) * 36.9 + 231
height <- nrow(sim) * 36.9 + 231
jpeg(file=paste(outputFolder,"/intronic.filtered.correl.heatmap.jpg",sep=""),
	width=width,height=height)
heatmap.2(sim, Rowv=exonHeatmap$rowDendrogram, Colv=exonHeatmap$colDendrogram, distfun=function(x) as.dist(1-x), trace="none", margin=c(10, 10),symm=T,revC=F,breaks=seq(-1,1,length.out=256),col=colorRampPalette(c("blue","white","red"))(255), key.title=NA, key.xlab="Pearson correlation", density.info="none", key.ylab=NA, keysize=0.85)

# gene-by-gene, deconvolute the PTR effect
intron.counts.sd <- apply(intron.counts[ , -1], 1, sd) # gene variation in transcription
diffTxIdx <- which(intron.counts.sd > quantile(intron.counts.sd, 0.25)) # diff transcribed gene indices

ptr <- ptr2 <- exon.counts
colnames(ptr) <- colnames(ptr2) <- gsub('\\.exon$', '', colnames(ptr))
nGenes <- nrow(exon.counts)
biast <- biast2 <- rep(NA_real_, nGenes)
for( i in 1:nGenes )
{
    # adjust bias using information from gene i
    yi <- unlist(exon.counts[i,2:(nSample+1)] - intron.counts[i,2:(nSample+1)])
    xi <- unlist(intron.counts[i,2:(nSample+1)])
    if( fitMode == "linear" )
        lfit <- glm( yi ~ xi )
    else
    {
        print("ERROR: Fit mode not recognized.")
        quit(status=1)
    }

    ptr[i,2:(nSample+1)] = yi - fitted(lfit)
    biast[i] <- coef(lfit)['xi']

    # adjust bias using information from neighbourhood of gene i
    # useful for experimental designs with less biological heterogeneity
    # assumes most genes are not diff stabilized
    gene.neighbours <- order(
        abs(intron.counts.MedianIntron[i] - intron.counts.MedianIntron),
        decreasing = F
    )

    gene.neighbours <- head(gene.neighbours[gene.neighbours %in% diffTxIdx], 100) # use 100 nearest genes based on median abundance

    y <- unlist(exon.counts[gene.neighbours,2:(nSample+1)] - intron.counts[gene.neighbours,2:(nSample+1)])
    x <- unlist(intron.counts[gene.neighbours,2:(nSample+1)])
    if( fitMode == "linear" )
        lfit <- glm( y ~ x )
    else
    {
        print("ERROR: Fit mode not recognized.")
        quit(status=1)
    }

    ptr2[i,2:(nSample+1)] = yi - predict(lfit, newdata = data.frame(x = xi), type = 'response')
    biast2[i] <- coef(lfit)['x']

    #	print(i)
}

jpeg(file=paste(outputFolder,"/perGene_bias_vs_accrossGenes_(experimental).jpg",sep=""),
     width=300,height=350)
smoothScatter( biast, biast2, colramp=colorRampPalette(c( "white", "red", "black" ) ), nbin=400, nrpoints=0, xlab="per gene", ylab="across genes" )
lines( c(-1,+1), c(0,0), lty=3 )
lines( c(0,0), c(-1,+1), lty=3 )
dev.off()
# save.image('~/Documents/book_chapter/remb.RData')

# draw the sample-specific scatterplots
for( i in 2:(nSample+1) )
{
	jpeg(file=paste(outputFolder,"/sampleScatterplots/scatterplot.",colnames(exon.counts)[i],".jpg",sep=""),
		width=700,height=400)
	par(mfrow=c(1,2))

	xlim <- quantile( intron.counts[,i], probs=c(0.005,0.995) )
	ylim <- quantile( exon.counts[,i]-intron.counts[,i], probs=c(0.005,0.995) )
	# draw the scatterplot for exon-intron vs. intron
	smoothScatter( intron.counts[,i], exon.counts[,i]-intron.counts[,i], nbin=400, nrpoints=0, xlim=xlim,ylim=ylim, xlab="Δintron", ylab="Δexon–Δintron" )
	sorting <- order(intron.counts[,i])
	lines(xlim,c(0,0),col="blue")
	lines(c(0,0),ylim,col="blue")
	lfit <- loess( exon.counts[,i]-intron.counts[,i] ~ intron.counts[,i], family="gaussian", span=1, degree=1 )
	#lines(intron.counts[sorting,i],lfit$fitted[sorting],col="black")

	# draw the scatterplot for bias-removed ptr vs. intron
	smoothScatter( intron.counts[,i], ptr[,i], nbin=400, nrpoints=0, xlim=xlim,ylim=ylim, xlab="Δintron", ylab="unbiased Δexon–Δintron" )
	lines(xlim,c(0,0),col="blue")
	lines(c(0,0),ylim,col="blue")
	lfit <- loess( ptr[,i] ~ intron.counts[,i], family="gaussian", span=1, degree=1 )
	#lines(intron.counts[sorting,i],lfit$fitted[sorting],col="black")

	dev.off()
}

# plot the similarity heatmap for deconvoluted PTR matrix
sim <- cor(as.matrix(ptr[,2:(nSample+1)]))
width  <- ncol(sim) * 36.9 + 231
height <- nrow(sim) * 36.9 + 231
jpeg(file=paste(outputFolder,"/stability.filtered.correl.heatmap.jpg",sep=""),
	width=width,height=height)
heatmap.2(sim, Rowv=exonHeatmap$rowDendrogram, Colv=exonHeatmap$colDendrogram, distfun=function(x) as.dist(1-x), trace="none", margin=c(10, 10),symm=T,revC=F,breaks=seq(-1,1,length.out=256),col=colorRampPalette(c("blue","white","red"))(255), key.title=NA, key.xlab="Pearson correlation", density.info="none", key.ylab=NA, keysize=0.85)

# write the tables
write.table(cutoff_table,paste(outputFolder,"/cutoff.txt",sep=""),sep="\t",quote=F,row.names=F)
write.table(exon.counts,paste(outputFolder,"/exonic.filtered.mx.txt",sep=""),sep="\t",quote=F,row.names=F)
write.table(intron.counts,paste(outputFolder,"/intronic.filtered.mx.txt",sep=""),sep="\t",quote=F,row.names=F)
write.table(ptr,paste(outputFolder,"/stability.filtered.mx.txt",sep=""),sep="\t",quote=F,row.names=F)
write.table(ptr2,paste(outputFolder,"/stability.filtered.mx_(experimental).txt",sep=""),sep="\t",quote=F,row.names=F)
