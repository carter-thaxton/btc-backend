
source('./dbi.R')
if(!require("plyr")){
	install.packages("plyr", repos="http://ftp.osuosl.org/pub/cran/")
	library("plyr")
}

if(!require("rjson")){
	install.packages("rjson", repos="http://ftp.osuosl.org/pub/cran/")
	library("rjson")
}

ERRORLOGFILENAME="affiliationScrapeErrorlog.txt"


# committeefolder = "raw_committee_data"
# dbname = "hack_oregon"
# comTabName = "raw_committees_scraped"
bulkLoadScrapedCommitteeData<-function(committeefolder, dbname, comTabName){
	allfiles = dir(committeefolder)
	scrapeFiles = allfiles[grepl(pattern="^[0-9]+(.txt)$", x=allfiles)]
	if(length(scrapeFiles)){
		comids = as.integer(gsub(pattern=".txt$", replacement="", x=scrapeFiles))
		cat("Found",length(comids)," download files with likely committee IDs.\n")
		rawScrapeDat = rawScrapeToTable(committeeNumbers=comids, rawdir=committeefolder, 
																		attemptRetry=F, 
																		moveErrantScrapes=T)
		cat("Loaded scrape data for",nrow(rawScrapeDat),"committees.\n")
		sendCommitteesToDb( comtab=rawScrapeDat, dbname=dbname, comTabName=comTabName )
		updateWorkingCommitteesTableWithScraped(dbname=dbname)
	}else{
		if(!file.exists(committeefolder)) dir.create(committeefolder)
		message("No scraped committee files found in folder\n'",committeefolder,"'")
	}
	cat("\n..\n")
}


ccidsInComms<-function(){
	q = "select distinct \"Committee_Id\" from comms where \"Committee_Type\" = 'CC'"
	res = dbiRead(query=q, dbname="contributions")
	cuids = unique(res[,1])
	return(cuids)
}

idsInFins<-function(){
	q="select distinct \"Filer_Id\" from fins"
	res1 = dbiRead(query=q, dbname="contributions")
	
	q1 = "select distinct \"Contributor_Payee_Committee_ID\" from fins"
	res2 =  dbiRead(query=q1, dbname="contributions")
	uids = unique(c(res1[,1], res2[,1]))
	return(uids)
}

affiliationsFromFilings<-function(){
	
	q3 = "select * from afcomms" #where \"Party_Descr\" is null;"
	res3 =  dbiRead(query=q3, dbname="contributions")
	return(res3)
}

orestarConnect<-function(commID = 2752){
	
	nodeString = "/Users/samhiggins2001_worldperks/local/bin/node"
	if( !file.exists(nodeString) ) nodeString = "/usr/local/bin/node"
	if( !file.exists(nodeString) ) nodeString = "/usr/bin/nodejs"
	
	sysReq = paste0(nodeString," ./orestar_scrape_committees/scraper ",commID)
	sres = system(command=sysReq, intern=TRUE)
	return(sres)
}

cleanRes<-function(sres){
	gsr = gsub(pattern="[{}']|\\\\n|(\\s)+",replacement=" ", x=sres, perl=TRUE)
	gsr = gsub(pattern="(\\s)+",replacement=" ", x=gsr, perl=TRUE)
	gsr = gsub(pattern=":\\s:\\s",replacement=" : ", x=gsr, perl=TRUE)
	spres  = strsplit(x=gsr, split=" : ")
	i = 2
	vout = rep("", times=length(spres))
	for(i in 1:length(spres)){
		crow = spres[[i]]
		cur = gsub(pattern="^\\s|\\s,$", replacement="", x=crow)
		vout[i] = cur[2]
		names(vout)[i] = cur[1]
	}
	
	vout = vout[!is.na(vout)]
	vout = vout[!vout==","]
	return(vout)
}

cleanRes2<-function(sres){
	library("rjson")
	gsr = gsub(pattern="[']|\\\\n|(\\s)+",replacement=" ", x=sres, perl=TRUE)
	gsr = gsub(pattern="(\\s)+",replacement=" ", x=gsr, perl=TRUE)
	gsr = gsub(pattern=":\\s:\\s",replacement=" : ", x=gsr, perl=TRUE)
	spres  = strsplit(x=gsr, split=" : ")
	i = 2
	vout = rep("", times=length(spres))
	for(i in 1:length(spres)){
		crow = spres[[i]]
		cur = gsub(pattern="^\\s|\\s,$", replacement="", x=crow)
		vout[i] = cur[2]
		names(vout)[i] = cur[1]
	}
	
	vout = vout[!is.na(vout)]
	vout = vout[!vout==","]
	return(vout)
}

convertToJSON<-function(sres){
	gsr00 = gsub(pattern="\"", replacement="", x=sres)
	gsr0 = gsub(pattern="\\\\n|(\\s)+",replacement=" ", x=gsr00, perl=TRUE)
	gsr1=gsub(pattern="'",replace="\"",x=gsr0)
	gsr2 = paste0(gsr1, collapse=" ")
	gsr3 = gsub(pattern="(\\s)+", replacement=" ", x=gsr2 )
	jsl = fromJSON(json_str=gsr3)
}

flattenList<-function(jsl2){
	#first see if some slot names are repeated
	snames=c()
	for(nm in names(jsl2)) snames = c(snames, names(jsl2[[nm]]))
	ntab=table(snames)
	mergers = names(ntab)[ntab>1]
	flattened = c()
	jsl3 = jsl2
	for(nm in names(jsl2)){
		
		tomerge = names(jsl2[[nm]])[names(jsl2[[nm]])%in%mergers]
		merged = paste(nm, tomerge)
		names(jsl3[[nm]])[names(jsl3[[nm]])%in%mergers] = merged
		flattened = c(flattened, jsl3[[nm]])
	}
	return(unlist(flattened))
}

scrubConvertedJson<-function(jsl){
	
	names(jsl) <- gsub( pattern="Information$", replacement="", x=names(jsl) )
	names(jsl) <- rmWhiteSpace(strin=names(jsl))
	names(jsl) <- gsub(pattern=":$", replacement="", x=names(jsl))
	jsout = list()
	for(i in 1:length(jsl)){
		nms = names(jsl)[i]
		subl <- jsl[[nms]] 
		if( ( !is.null(subl) | !nms%in%c(" ","") ) & length(subl) ){ #removes blank slots & assures the list isn't empty
			if( class(subl)=="list" ){
				subl <- scrubConvertedJson(jsl=subl)
			} else {
				subl <- rmWhiteSpace(subl)
			}
			jsout[[nms]] = subl
		} 
	}
	return(jsout)
}

test.rmWhiteSpace<-function(){
	
	rmres = rmWhiteSpace(strin="   test   two   ")
	checkEquals(target="test two", current=rmres)
}

rmWhiteSpace<-function(strin){
	strout <- gsub( pattern="(^[ ]+)|[ ]+$", replacement="", x=strin )
	strout <- gsub( pattern="[ ]+", replacement=" ", x=strout )
	return(strout)
}

tabulateRecs<-function(lout){
	
	ukeys = c()
	
	for(i in names(lout)){
		cur = lout[[i]]
		ukeys = c(ukeys, names(cur))
	}
	ukeys=unique(ukeys)
	omat = matrix(nrow=length(lout), ncol=length(ukeys), dimnames= list( names(lout), ukeys ))
	for(i in names(lout)){
		cur = lout[[i]]
		omat[i,names(cur)] = cur
	}
	omat[,"ID"] = gsub(pattern="[^0-9]", replacement="", x=omat[,"ID"])
	return(omat)
}

scrapeTheseCommittees<-function(committeeNumbers, commfold = "raw_committee_data", forceRedownload=F){
	
	if( !file.exists(commfold) ) dir.create(path=commfold)
	
	for(cn in committeeNumbers){
		cat("\nCandidate committee ID:",cn,"\n")
		rawCommfile = paste0(commfold,"/", cn, ".txt")
		if( !file.exists(rawCommfile) | forceRedownload ){
			r1 = orestarConnect(commID=cn)
			if( grepl(pattern="Committee", x=r1[1], ignore.case=TRUE) ){
				write.table(x=r1, file=rawCommfile )
			}else{
				Sys.sleep(time=sample(x=5:20, size=1))
				r1 = orestarConnect(commID=cn)
				if(!grepl(pattern="Committee", x=r1[1], ignore.case=TRUE)) logError(err=paste("No committee data returned for committee",cn))
				write.table(x=r1, file=rawCommfile )
			}
			cat("Catnap...\n")
			Sys.sleep(time=sample(x=5:20, size=1))
		}else{
			cat("Record already downloaded\n")
		}
		# 	cleanRecs = cleanRes(sres=r1)
		# 	lout[[as.character(cn)]] = cleanRecs
	}
}


#'@description Open each scrped file and join all the results into a table. 
makeTableFromScrape<-function(committeeNumbers, rawdir=""){
	
	lout = list()
	for(cn in committeeNumbers){
		comfile = paste0(rawdir,"/",cn,".txt")
		# 	r1 = orestarConnect(commID=cn)
		if( file.exists(comfile) ){
			cat("..found:",cn,"..")
			r2 = read.table(file=comfile,stringsAsFactors=F)[,1]
			cleanRecs = cleanRes(sres=r2)
			lout[[as.character(cn)]] = cleanRecs
		}else{
			cat("..comm id not found:",cn,"..")
		}
	}
	rectab = tabulateRecs(lout=lout)
	return(rectab)
	
}

vectorFromRecord<-function(sres){
	listFromJson = convertToJSON(sres=sres)
	cleanList = scrubConvertedJson(jsl=listFromJson)
	recordVector = flattenList(jsl2=cleanList)
}


addScrapedToWorkingCommitteesTable<-function(dbname){
	
	q1="insert into working_committees
			(select id as committee_id, committee_name, 
			committee_type, pac_type as committee_subtype, 
			party_affiliation, election_office, candidate_name, 
			candidate_email_address, candidate_work_phone_home_phone_fax, 
			candidate_address, treasurer_name, treasurer_work_phone_home_phone_fax, 
			treasurer_mailing_address
			from raw_committees_scraped);"
	dbCall(sql=q1, dbname=dbname)
}

updateWorkingCommitteesTableWithScraped<-function(dbname){
	

	q0 = "delete from working_committees where committee_id in 
	(select id from raw_committees_scraped)"
	dbCall(sql=q0, dbname=dbname)
	
	q1="insert into working_committees
	(select id as committee_id, committee_name, 
	committee_type, pac_type as committee_subtype, 
	party_affiliation, election_office, candidate_name, 
	candidate_email_address, candidate_work_phone_home_phone_fax, 
	candidate_address, treasurer_name, treasurer_work_phone_home_phone_fax, 
	treasurer_mailing_address
	from raw_committees_scraped);"
	dbCall(sql=q1, dbname=dbname)
}

fillMissingWorkingCommitteesTableWithScraped<-function(dbname){
	
	q1="insert into working_committees
	(select id as committee_id, committee_name, 
	committee_type, pac_type as committee_subtype, 
	party_affiliation, election_office, candidate_name, 
	candidate_email_address, candidate_work_phone_home_phone_fax, 
	candidate_address, treasurer_name, 
	treasurer_work_phone_home_phone_fax, 
	treasurer_mailing_address
	from raw_committees_scraped
	where id not in (select distinct committee_id from working_committees);"
	dbCall(sql=q1, dbname=dbname)
	
}


rawScrapeToTable<-function(committeeNumbers, rawdir="", attemptRetry=T, moveErrantScrapes=T){

	lout = list()
	notDownloaded = c()
	for(cn in committeeNumbers){
		comfile = paste0(rawdir,"/",cn,".txt")
		# 	r1 = orestarConnect(commID=cn)
		if( file.exists(comfile) ){
			cat("..found:",cn,"..")
			r2 = read.table(file=comfile,stringsAsFactors=F)[,1]
			if( !grepl(pattern="Committee", x=r2[1], ignore.case=TRUE) ){#r2[1]=="x"){ #if the scraper did not find anything, x will be returned. 
				logError(err=paste("The scraper failed to download data for the committee,",cn,"\n"))
				notDownloaded = c(notDownloaded, cn)
				cat("Error in import, 'Committee' not found. See",ERRORLOGFILENAME,"..")
			}else{
				recvec = try(expr=vectorFromRecord(sres=r2), silent=TRUE)
				if( grepl(pattern="error", x=class(recvec)) ){
					logError(err=recvec, additionalData=paste("committee download file:",comfile) )
					cat("Error in conversion of record to JSON, see",ERRORLOGFILENAME,"..")
				}else{
					lout[[as.character(cn)]] = recvec
				}
			}
		}else{
			notDownloaded = c(notDownloaded, cn)
			message("..comm id not found by rawScrapeToTable() function!!:",cn,"..\n")
			warning("..comm id not found by rawScrapeToTable() function!!:",cn,"..\n")
		}
	}
	notDownloaded = unique(notDownloaded)
	rectab = tabulateRecs(lout=lout)
	
	if( length(notDownloaded)&attemptRetry ){
		cat("\n\nData for these committees was not correctly downloaded on the first attempt:\n", 
				paste(notDownloaded, collapse=", "),
				"\nTrying again..\n")
		scrapeTheseCommittees(committeeNumbers=notDownloaded, commfold="raw_committee_data", forceRedownload=TRUE)
		logWarnings(warnings())
		rectab2 = rawScrapeToTable(committeeNumbers=notDownloaded, rawdir="raw_committee_data", attemptRetry=F, moveErrantScrapes=F)
		rectab = rbind.fill.matrix(rectab, rectab2)
	}
	
	if(moveErrantScrapes) moveErrantScrapesFun(rectab=rectab, rawdir=rawdir)
	
	rectab = unique(rectab)
	
	return(rectab)
	
}

moveErrantScrapesFun<-function(rectab, rawdir){
	cat("\nDimensions of raw committee data from scrape:\n", dim(rectab), "\n")
	#determine which of the committeeNumbers cannot be found in the
	#rectab but can be found as dl file names

	#get the committee numbers from the file names
	allfnms = dir(rawdir)
	comfnms = allfnms[grep(pattern=".txt$", x=allfnms)]
	committeeNumbers = as.integer(gsub(pattern=".txt$",replacement="", x=comfnms))
	
	notInrectab = setdiff(committeeNumbers, as.integer(rectab[,"ID"]) )
	
	if(length(notInrectab)){
		cat("\nThe import failed for these committees:\n")
		print(notInrectab)
		toMove = notInrectab[file.exists(paste0(rawdir,"/" ,notInrectab, ".txt"))]
		if(length(toMove)){
			cat("\nThese corresponding files will be moved to the failedScrapes folder:\n")
			print(paste0(rawdir,"/",toMove,".txt"))
			dir.create(paste0(rawdir,"/failedScrapes/"), showWarnings=FALSE)
			for(fi in toMove) file.rename(to=paste0(rawdir,"/failedScrapes/",fi,".txt"), 
																					 from=paste0(rawdir,"/",fi,".txt") )
		}
	}
}

logError<-function(err,additionalData=""){
	mess = paste(as.character(Sys.time())," ",additionalData,"\n",as.character(err))
	message("Errors found in committee data import, see error log: ",ERRORLOGFILENAME)
	print(mess)
	warning("Errors found in committee data import, see error log: ",ERRORLOGFILENAME)
	write.table(file=ERRORLOGFILENAME, x=mess, 
							append=TRUE, 
							col.names=FALSE, 
							row.names=FALSE, 
							quote=FALSE)
	cat("\nError log written to file '",ERRORLOGFILENAME,"'\n")
}

# 
# #the first block
# q1 = "select * from neededComms"
# res1 = dbiRead(query=q1, dbname="contributions")
# committeeNumbers=res1$Committee_Id#c(2752,16461, 12519, 13866)
# 
# scrapeTheseCommittees(committeeNumbers=committeeNumbers)
# rectab = makeTableFromScrape(committeeNumbers=committeeNumbers)
# View(rectab)
# rectab = as.data.frame(rectab, stringsAsFactors=F)
# 
# #the second block
# cuids = ccidsInComms()
# uids = idsInFins()
# CcInFins = intersect(cuids, uids)
# fromFilings = affiliationsFromFilings()
# ffNoAffil = fromFilings[is.na(fromFilings$Party_Descr),]
# ffNoAffilIds = ffNoAffil$Committee_Id
# 
# affilationTested = rownames(rectab)
# stillNeeded = setdiff(ffNoAffilIds, affilationTested)
# 
# 
# scrapeTheseCommittees(committeeNumbers=stillNeeded)
# tout2 = makeTableFromScrape(committeeNumbers=stillNeeded)
# 
# 
# tout3 = makeTableFromScrape(committeeNumbers=c(stillNeeded,committeeNumbers))
# tout3 = as.data.frame(tout3)
# 
# table(tout3$"Party Affiliation")
# 
# knownComms = fromFilings[!is.na(fromFilings$Party_Descr),c("Committee_Id","Party_Descr")]
# colnames(knownComms)<-c("id","party")
# 
# numAndAffil = tout3[,c("ID","Party Affiliation")]
# numAndAffil$id <-as.character(numAndAffil$id)
# colnames(numAndAffil)<-c("id","party")
# numAndAffil[is.na(numAndAffil$id),"id"]<-rownames(numAndAffil)[is.na(numAndAffil$id)]
# 
# withAffil=rbind.data.frame(knownComms, numAndAffil)
# 
# duprows = withAffil[duplicated(withAffil$id)|duplicated(withAffil$id, fromLast=T),]
# duprows = duprows[order(duprows$id, decreasing=T),]
# 
# library(ggplot2)
# ggplot(data=withAffil, aes(x=party))+geom_bar()
# 
# 