SHELL=/bin/bash

PWD := $(shell pwd)
GIT = $(shell which git)
MAKE = $(shell which make)
RECIPE = dataprep_personnes-dedecees_search
TIMEOUT = 2520
DATAGOUV_API = https://www.data.gouv.fr/api/1/datasets
DATAGOUV_DATASET = fichier-des-personnes-decedees
DATA_DIR = ${PWD}/data
# files to sync:
FILES_TO_SYNC=(^|\s)deces-.*.txt(.gz)?($$|\s)
# files to process:
FILES_TO_PROCESS=deces-[0-9]{4}(|-m\d.*).txt.gz
DATAGOUV_CATALOG = ${DATA_DIR}/${DATAGOUV_DATASET}.datagouv.list
S3_BUCKET = ${DATAGOUV_DATASET}
S3_CATALOG = ${DATA_DIR}/${DATAGOUV_DATASET}.s3.list
DATAPREP_VERSION := $(shell cat projects/personnes-decedees_search/recipes/dataprep_personnes-dedecees_search.yml projects/personnes-decedees_search/datasets/personnes-decedees_index.yml  | sha1sum | awk '{print $1}' | cut -c-8)

dummy               := $(shell touch artifacts)
include ./artifacts

config:
	@echo checking system prerequisites
	@${MAKE} -C backend install-prerequisites install-aws-cli
	@if [ ! -f "/usr/bin/curl" ]; then sudo apt-get install -y curl;fi
	@if [ ! -f "/usr/bin/jq" ]; then sudo apt-get install -y jq;fi
	@echo "prerequisites installed" > config

${DATA_DIR}:
	@if [ ! -d "${DATA_DIR}" ]; then mkdir -p ${DATA_DIR};fi

${DATAGOUV_CATALOG}: config ${DATA_DIR}
	@echo getting ${DATAGOUV_DATASET} catalog from data.gouv API ${DATAGOUV_API}
	@curl -s --fail ${DATAGOUV_API}/${DATAGOUV_DATASET}/ | \
		jq  -cr '.resources[] | .title + " " +.checksum.value + " " + .url' | sort > ${DATAGOUV_CATALOG}

datagouv-get-catalog: ${DATAGOUV_CATALOG}

datagouv-get-files: ${DATAGOUV_CATALOG}
	@if [ -f "${S3_CATALOG}" ]; then\
		(echo egrep -v $$(cat ${S3_CATALOG} | tr '\n' '|' | sed 's/.gz//g;s/^/"(/;s/|$$/)"/') ${DATAGOUV_CATALOG} | sh > ${DATA_DIR}/tmp.list) || true;\
	else\
		cp ${DATAGOUV_CATALOG} ${DATA_DIR}/tmp.list;\
	fi

	@if [ -s "${DATA_DIR}/tmp.list" ]; then\
		i=0;\
		for file in $$(awk '{print $$1}' ${DATA_DIR}/tmp.list); do\
			if [ ! -f ${DATA_DIR}/$$file.gz.sha1 ]; then\
				echo getting $$file ;\
				grep $$file ${DATA_DIR}/tmp.list | awk '{print $$3}' | xargs curl -s > ${DATA_DIR}/$$file; \
				grep $$file ${DATA_DIR}/tmp.list | awk '{print $$2}' > ${DATA_DIR}/$$file.sha1.src; \
				sha1sum < ${DATA_DIR}/$$file | awk '{print $$1}' > ${DATA_DIR}/$$file.sha1.dst; \
				((diff ${DATA_DIR}/$$file.sha1.src ${DATA_DIR}/$$file.sha1.dst > /dev/null) || echo error downloading $$file); \
				gzip ${DATA_DIR}/$$file; \
				sha1sum ${DATA_DIR}/$$file.gz > ${DATA_DIR}/$$file.gz.sha1; \
				((i++));\
			fi;\
		done;\
		if [ "$$i" == "0" ]; then\
			echo no new file downloaded from datagouv;\
		else\
			echo "$$i file(s) donwloaded from datagouv";\
		fi;\
	else\
		echo no new file downloaded from datagouv;\
	fi

${S3_CATALOG}: config ${DATA_DIR}
	@echo getting ${S3_BUCKET} catalog from s3 API
	@aws s3 ls ${S3_BUCKET} | awk '{print $$NF}' | egrep '${FILES_TO_SYNC}' | sort > ${S3_CATALOG}

s3-get-catalog: ${S3_CATALOG}

datagouv-to-s3: s3-get-catalog datagouv-get-files
	@for file in $$(ls ${DATA_DIR} | egrep '${FILES_TO_SYNC}');do\
		aws s3 cp ${DATA_DIR}/$$file s3://${S3_BUCKET}/$$file;\
		aws s3api put-object-acl --acl public-read --bucket ${S3_BUCKET} --key $$file && echo $$file acl set to public;\
	done

backend:
	@echo configuring matchID
	@${GIT} clone https://github.com/matchid-project/backend backend
	@cp artifacts backend/artifacts
	@cp docker-compose-local.yml backend/docker-compose-local.yml
	@echo "export ES_NODES=1" >> backend/artifacts
	@echo "export PROJECTS=${PWD}/projects" >> backend/artifacts
	@echo "export S3_BUCKET=${S3_BUCKET}" >> backend/artifacts

dev: config backend
	${MAKE} -C backend frontend-build backend elasticsearch frontend

up:
	${MAKE} -C backend backend elasticsearch wait-backend wait-elasticsearch

recipe-run:
	${MAKE} -C backend recipe-run RECIPE=${RECIPE}

watch-run:
	@timeout=${TIMEOUT} ; ret=1 ; \
		until [ "$$timeout" -le 0 -o "$$ret" -eq "0"  ] ; do \
			f=$$(find backend/log/ -iname '*dataprep_personnes-dedecees_search*' | sort | tail -1);\
		((tail $$f | grep "end of all" > /dev/null) || exit 1) ; \
		ret=$$? ; \
		if [ "$$ret" -ne "0" ] ; then \
			echo "waiting for end of job $$timeout" ; \
			grep wrote $$f |awk 'BEGIN{s=0}{t=$$4;s+=$$12}END{print t " wrote " s}' ;\
			sleep 10 ;\
		fi ; ((timeout--)); done ; exit $$ret
	@find backend/log/ -iname '*dataprep_personnes-dedecees_search*' | sort | tail -1 | xargs tail

s3.tag:
	@aws s3 ls fichier-des-personnes-decedees | egrep '${FILES_TO_PROCESS}' | awk '{print $NF}' | sort | sha1sum | awk '{print $1}' | cut -c-8 > s3.tag

backup: s3.tag
	echo "export ES_BACKUP_FILE=esdata_${DATAPREP_VERSION}_$$(cat s3.tag).tar" >> backend/artifacts
	${MAKE} -C backend elasticsearch-backup

s3-push:
	${MAKE} -C backend elasticsearch-s3-push S3_BUCKET=fichier-des-personnes-decedees

down:
	${MAKE} -C backend backend-stop elasticsearch-stop frontend-stop

clean: down
	sudo rm -rf backend frontend ${DATA_DIR}

all: config backend up s3.tag recipe-run watch-run down backup s3-push clean
	@echo ended with succes !!!
