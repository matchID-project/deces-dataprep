SHELL=/bin/bash

APP=personnes-decedees_search
PWD := $(shell pwd)
GIT = $(shell which git)
GITROOT = https://github.com/matchid-project
GITBACKEND = backend
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
SSHID=matchid@matchid.project.gmail.com
SSHKEY_PRIVATE = ~/.ssh/id_rsa_${APP}
SSHKEY = ${SSHKEY_PRIVATE}.pub
SSHKEYNAME = ${APP}
SSHOPTS=-o "StrictHostKeyChecking no"
OS_TIMEOUT = 120

dummy               := $(shell touch artifacts)
include ./artifacts

config:
	@echo checking system prerequisites
	@${MAKE} -C ${GITBACKEND} install-prerequisites install-aws-cli
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

${GITBACKEND}:
	@echo configuring matchID
	@${GIT} clone ${GITROOT}/${GITBACKEND}
	@cp artifacts ${GITBACKEND}/artifacts
	@cp docker-compose-local.yml ${GITBACKEND}/docker-compose-local.yml
	@echo "export ES_NODES=1" >> ${GITBACKEND}/artifacts
	@echo "export PROJECTS=${PWD}/projects" >> ${GITBACKEND}/artifacts
	@echo "export S3_BUCKET=${S3_BUCKET}" >> ${GITBACKEND}/artifacts

dev: config backend
	${MAKE} -C ${GITBACKEND} frontend-build backend elasticsearch frontend

up:
	${MAKE} -C ${GITBACKEND} backend elasticsearch wait-backend wait-elasticsearch

recipe-run:
	${MAKE} -C ${GITBACKEND} recipe-run RECIPE=${RECIPE}

watch-run:
	@timeout=${TIMEOUT} ; ret=1 ; \
		until [ "$$timeout" -le 0 -o "$$ret" -eq "0"  ] ; do \
			f=$$(find ${GITBACKEND}/log/ -iname '*dataprep_personnes-dedecees_search*' | sort | tail -1);\
		((tail $$f | grep "end of all" > /dev/null) || exit 1) ; \
		ret=$$? ; \
		if [ "$$ret" -ne "0" ] ; then \
			echo "waiting for end of job $$timeout" ; \
			grep wrote $$f |awk 'BEGIN{s=0}{t=$$4;s+=$$12}END{print t " wrote " s}' ;\
			sleep 10 ;\
		fi ; ((timeout--)); done ; exit $$ret
	@find ${GITBACKEND}/log/ -iname '*dataprep_personnes-dedecees_search*' | sort | tail -1 | xargs tail

s3.tag:
	@aws s3 ls fichier-des-personnes-decedees | egrep '${FILES_TO_PROCESS}' | awk '{print $NF}' | sort | sha1sum | awk '{print $1}' | cut -c-8 > s3.tag

backup: s3.tag
	echo "export ES_BACKUP_FILE=esdata_${DATAPREP_VERSION}_$$(cat s3.tag).tar" >> ${GITBACKEND}/artifacts
	${MAKE} -C ${GITBACKEND} elasticsearch-backup

s3-push:
	${MAKE} -C ${GITBACKEND} elasticsearch-s3-push S3_BUCKET=fichier-des-personnes-decedees

${SSHKEY}:
	@echo ssh keygen
	@ssh-keygen -t rsa -b 4096 -C "${SSHID}" -f ${SSHKEY_PRIVATE} -q -N "${SSH_PASSPHRASE}"

os-add-sshkey: ${SSHKEY}
	@(\
		(nova keypair-list | sed 's/|//g' | egrep -v '\-\-\-|Name' | (egrep '^\s*${SSHKEYNAME}\s' > /dev/null) &&\
		 echo "ssh key already deployed" ) \
	  || \
		(nova keypair-add --pub-key ${SSHKEY} ${SSHKEYNAME} &&\
		 nova keypair-list | sed 's/|//g' | egrep -v '\-\-\-|Name' | (egrep '^\s*${SSHKEYNAME}\s' > /dev/null) &&\
		 echo "ssh key deployed with success" ) \
	  )

os-instance-order:
	@(\
		(nova list | sed 's/|//g' | egrep -v '\-\-\-|Name' | (egrep '\s${APP}\s' > /dev/null) && \
		echo "openstack instance already ordered")\
	 || \
		(nova boot --key-name ${SSHKEYNAME} --flavor ${OS_FLAVOR_ID} --image ${OS_IMAGE_ID} ${APP} && \
	 		echo "openstack intance ordered with success") || echo "openstance instance order failed"\
	)

os-instance-wait: os-instance-order
	@timeout=${OS_TIMEOUT} ; ret=1 ; until [ "$$timeout" -le 0 -o "$$ret" -eq "0"  ] ; do\
	  nova list | sed 's/|//g' | egrep -v '\-\-\-|Name' | (egrep '\s${APP}\s.*Running' > /dev/null) ;\
	  ret=$$? ; \
	  if [ "$$ret" -ne "0" ] ; then echo "waiting for openstack instance to start $$timeout" ; fi ;\
	  ((timeout--)); sleep 1 ; \
	done ; exit $$ret

os-instance-delete:
	nova delete ${APP}

down:
	${MAKE} -C ${GITBACKEND} backend-stop elasticsearch-stop frontend-stop

clean: down
	sudo rm -rf ${GITBACKEND} frontend ${DATA_DIR}

# launch all locally
# configure
all-step0: ${GITBACKEND} config

# first step should be 4 to 10 hours
all-step1: up s3.tag recipe-run

# second step is backup and <5 minutes
all-step2: down backup s3-push clean

all: config all-step1 watch-run all-step2
	@echo ended with succes !!!

# launch remote
remote-config: os-instance-wait
	@OS_HOST=$$(nova list | sed 's/|//g' | egrep -v '\-\-\-|Name' | egrep '\s${APP}\s.*Running' | sed 's/.*Ext-Net=//;s/,.*//') ;\
		ssh ${SSHOPTS} ${OS_SSHUSER}@$$OS_HOST git clone ${GITROOT}/${APP};\
		ssh ${SSHOPTS} ${OS_SSHUSER}@$$OS_HOST sudo apt-get update -y;\
		ssh ${SSHOPTS} ${OS_SSHUSER}@$$OS_HOST sudo apt-get install -y make;\
		ssh ${SSHOPTS} ${OS_SSHUSER}@$$OS_HOST make -C ${APP} all-step0;

remote-step1:
	@OS_HOST=$$(nova list | sed 's/|//g' | egrep -v '\-\-\-|Name' | egrep '\s${APP}\s.*Running' | sed 's/.*Ext-Net=//;s/,.*//');\
		ssh ${SSHOPTS} ${OS_SSHUSER}@$$OS_HOST make -C ${APP} all-step1;

remote-status:
	@OS_HOST=$$(nova list | sed 's/|//g' | egrep -v '\-\-\-|Name' | egrep '\s${APP}\s.*Running' | sed 's/.*Ext-Net=//;s/,.*//');\
		ssh ${SSHOPTS} ${OS_SSHUSER}@$$OS_HOST make -C ${APP} watch-run;

remote-step2:
	@OS_HOST=$$(nova list | sed 's/|//g' | egrep -v '\-\-\-|Name' | egrep '\s${APP}\s.*Running' | sed 's/.*Ext-Net=//;s/,.*//');\
		ssh ${SSHOPTS} ${OS_SSHUSER}@$$OS_HOST make -C ${APP} step2;

remote-clean: os-instance-delete
