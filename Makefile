SHELL=/bin/bash

export DATAPREP_VERSION := $(shell cat projects/deces-dataprep/recipes/deces_dataprep.yml projects/deces-dataprep/datasets/deces_index.yml  | sha1sum | awk '{print $1}' | cut -c-8)
export APP=deces-dataprep
export PWD := $(shell pwd)
export APP_PATH=${PWD}
export GIT = $(shell which git)
export GITROOT = https://github.com/matchid-project
export GIT_BRANCH = master
export GIT_BACKEND = backend
export GIT_TOOLS = tools
export MAKEBIN = $(shell which make)
export MAKE = ${MAKEBIN} --no-print-directory -s
export ES_NODES=1
export ES_MEM=1024m
export ERR_MAX=20
export ES_PRELOAD=[]
export CHUNK_SIZE=10000
export RECIPE = deces_dataprep
export RECIPE_THREADS = 4
export RECIPE_QUEUE = 1
export ES_THREADS = 2
export TIMEOUT = 2520
export DATAGOUV_API = https://www.data.gouv.fr/api/1/datasets
export DATAGOUV_DATASET = fichier-des-personnes-decedees
export STORAGE_BUCKET=${DATAGOUV_DATASET}
export DATA_DIR=${PWD}/data
export BACKUP_DIR = ${PWD}/${GIT_BACKEND}/backup
export DATA_TAG=${PWD}/data-tag
export BACKUP_CHECK=${PWD}/backup-check
# files to sync:
export FILES_TO_SYNC=deces-.*.txt(.gz)?
# files to process:
export FILES_TO_PROCESS=deces-([0-9]{4}|2020-m[0-9]{2}).txt.gz
export SSHID=matchid@matchid.project.gmail.com
export SSHKEY_PRIVATE = ${HOME}/.ssh/id_rsa_${APP}
export SSHKEY = ${SSHKEY_PRIVATE}.pub
export SSHKEYNAME = ${APP}
export OS_TIMEOUT = 60
export SCW_SERVER_FILE_ID=scw.id
SCW_TIMEOUT= 180
EC2_PROFILE=default
EC2=ec2 ${EC2_ENDPOINT_OPTION} --profile ${EC2_PROFILE}
EC2_SERVER_FILE_ID=${PWD}/ec2.id
EC2_TIMEOUT= 120
CLOUD=SCW
SSHOPTS=-o "StrictHostKeyChecking no" -i ${SSHKEY} ${CLOUD_SSHOPTS}

dummy               := $(shell touch artifacts)
include ./artifacts

config: ${GIT_BACKEND}
	@echo checking system prerequisites
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND} config && \
	echo "prerequisites installed" > config

datagouv-to-storage: config
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} datagouv-to-storage \
		DATAGOUV_DATASET=${DATAGOUV_DATASET} STORAGE_BUCKET=${STORAGE_BUCKET}\
		FILES_PATTERN='${FILES_TO_SYNC}' &&\
	touch datagouv-to-storage

${DATA_TAG}: config
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} catalog-tag CATALOG_TAG=${DATA_TAG}\
		DATAGOUV_DATASET=${DATAGOUV_DATASET} STORAGE_BUCKET=${STORAGE_BUCKET}\
		FILES_PATTERN='${FILES_TO_PROCESS}' > /dev/null 2>&1

data-tag: ${DATA_TAG}

${BACKUP_CHECK}: data-tag
	@${MAKE} -s -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} get-catalog CATALOG=${BACKUP_CHECK}\
		DATAGOUV_DATASET=${DATAGOUV_DATASET} STORAGE_BUCKET=${STORAGE_BUCKET}\
		FILES_PATTERN=esdata_${DATAPREP_VERSION}_$$(cat ${PWD}/data-tag).tar &&\
	if [ -s ${BACKUP_CHECK} ]; then\
		echo backup already exist on remote storage;\
	else\
		echo no previous backup found;\
	fi

backup-check: ${BACKUP_CHECK}

backup-pull: data-tag
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} storage-pull\
		STORAGE_BUCKET=${STORAGE_BUCKET} STORAGE_ACCESS_KEY=${STORAGE_ACCESS_KEY} STORAGE_SECRET_KEY=${STORAGE_SECRET_KEY}\
		FILE=esdata_${DATAPREP_VERSION}_$$(cat data.tag).tar &&\
	touch backup-pull

${GIT_BACKEND}:
	@echo configuring matchID
	@${GIT} clone -q ${GITROOT}/${GIT_BACKEND}
	@cp artifacts ${GIT_BACKEND}/artifacts
	@cp docker-compose-local.yml ${GIT_BACKEND}/docker-compose-local.yml
	@echo "export ES_NODES=${ES_NODES}" >> ${GIT_BACKEND}/artifacts
	@echo "export PROJECTS=${PWD}/projects" >> ${GIT_BACKEND}/artifacts
	@echo "export STORAGE_BUCKET=${STORAGE_BUCKET}" >> ${GIT_BACKEND}/artifacts

dev: config
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND} elasticsearch backend frontend &&\
		echo matchID started, go to http://localhost:8081

dev-stop:
	@if [ -f config ]; then\
		${MAKE} -C ${APP_PATH}/${GIT_BACKEND} frontend-stop backend-stop elasticsearch-stop;\
	fi

up:
	@unset APP;unset APP_VERSION;\
	${MAKE} -C ${APP_PATH}/${GIT_BACKEND} elasticsearch backend && echo matchID backend services started

recipe-run: data-tag
	@if [ ! -f recipe-run ];then\
		${MAKE} -C ${APP_PATH}/${GIT_BACKEND} elasticsearch ES_NODES=${ES_NODES} ES_MEM=${ES_MEM} ${MAKEOVERRIDES};\
		echo running recipe on full data;\
		${MAKE} -C ${APP_PATH}/${GIT_BACKEND} recipe-run \
			RECIPE=${RECIPE} RECIPE_THREADS=${RECIPE_THREADS} RECIPE_QUEUE=${RECIPE_QUEUE}\
			ES_PRELOAD='${ES_PRELOAD}' ES_THREADS=${ES_THREADS} \
			STORAGE_BUCKET=${STORAGE_BUCKET} STORAGE_ACCESS_KEY=${STORAGE_ACCESS_KEY} STORAGE_SECRET_KEY=${STORAGE_SECRET_KEY}\
			${MAKEOVERRIDES} \
			APP=backend APP_VERSION=$(shell cd ${APP_PATH}/${GIT_BACKEND} && make version | awk '{print $$NF}') \
			&&\
		touch recipe-run s3-pull &&\
		(echo esdata_${DATAPREP_VERSION}_$$(cat ${DATA_TAG}).tar > elasticsearch-restore);\
	fi

full-check: datagouv-to-storage backup-check
	@if [ -s backup-check ]; then\
		echo recipe has already been runned on full and saved on remote storage;\
		touch recipe-run watch-run backup backup-push no-remote;\
	fi

full: full-check recipe-run
	@touch full


backend-clean-logs:
	rm -f ${PWD}/${GIT_BACKEND}/log/*${RECIPE}*log

watch-run:
	@LOG_FILE=$(shell find ${GIT_BACKEND}/log/ -iname '*${RECIPE}*' | sort | tail -1);\
	timeout=${TIMEOUT} ; ret=1 ; \
		until [ "$$timeout" -le 0 -o "$$ret" -eq "0"  ] ; do \
			((tail $$LOG_FILE | grep "end of all" > /dev/null) || exit 1) ; \
			ret=$$? ; \
			if [ "$$ret" -ne "0" ] ; then \
				grep inserted $$LOG_FILE |awk 'BEGIN{s=0}{t=$$4;s+=$$14}END{printf("\rwrote %d in %s",s,t)}' ;\
				grep -i Ooops $$LOG_FILE | wc -l | awk '($$1>${ERR_MAX}){exit 1}' || exit 0;\
				sleep 10 ;\
			fi ; ((timeout--)); done ;
	@LOG_FILE=$(shell find ${GIT_BACKEND}/log/ -iname '*${RECIPE}*' | sort | tail -1);\
	((egrep -i 'end : run|Ooops' $$LOG_FILE | tail -5) && exit 1) || \
	egrep 'end : run.*successfully' $$LOG_FILE

elasticsearch-restore: backup-pull
	@if [ ! -f "elasticsearch-restore" ];then\
		${MAKE} -C ${APP_PATH}/${GIT_BACKEND} elasticsearch-restore ES_BACKUP_FILE=esdata_${DATAPREP_VERSION}_$$(cat ${DATA_TAG}).tar \
			&& (echo esdata_${DATAPREP_VERSION}_$$(cat ${DATA_TAG}).tar > elasticsearch-restore);\
	fi

backup-dir:
	mkdir -p ${BACKUP_DIR}

backup: data-tag
	@if [ ! -f backup ];then\
		ES_BACKUP_FILE=esdata_${DATAPREP_VERSION}_$$(cat ${DATA_TAG}).tar;\
		ES_BACKUP_FILE_SNAR=esdata_${DATAPREP_VERSION}_$$(cat ${DATA_TAG}).snar;\
		if [ ! -f "${BACKUP_DIR}/$$ES_BACKUP_FILE" ];then\
			${MAKE} -C ${APP_PATH}/${GIT_BACKEND} elasticsearch-backup \
				ES_BACKUP_FILE=$$ES_BACKUP_FILE\
				ES_BACKUP_FILE_SNAR=$$ES_BACKUP_FILE_SNAR;\
		fi;\
		touch backup;\
	fi

backup-push: data-tag backup
	@if [ ! -f backup-push ];then\
		ES_BACKUP_FILE_ROOT=esdata_${DATAPREP_VERSION}_$$(cat ${DATA_TAG});\
		${MAKE} -C ${APP_PATH}/${GIT_BACKEND} elasticsearch-storage-push\
			STORAGE_BUCKET=${STORAGE_BUCKET} STORAGE_ACCESS_KEY=${STORAGE_ACCESS_KEY} STORAGE_SECRET_KEY=${STORAGE_SECRET_KEY}\
			ES_BACKUP_FILE=$$ES_BACKUP_FILE_ROOT.tar\
			ES_BACKUP_FILE_SNAR=$$ES_BACKUP_FILE_ROOT.snar &&\
			touch backup-push &&\
			SIZE=`cd ${BACKUP_DIR}; du -sh $$ES_BACKUP_FILE_ROOT.tar`;\
			echo pushed $$SIZE to storage ${DATAGOUV_DATASET};\
	fi

down:
	@if [ -f config ]; then\
		(${MAKE} -C ${APP_PATH}/${GIT_BACKEND} backend-stop elasticsearch-stop frontend-stop || true);\
	fi

clean: down
	@sudo rm -rf ${GIT_BACKEND} frontend ${DATA_DIR} data-tag config \
		recipe-run backup-check datagouv-to-storage elasticsearch-restore watch-run full\
		backup backup-pull backup-push no-remote

# launch all locally
# configure
all-step0: ${GIT_BACKEND} config

# first step should be 1h30 to 10 hours if not already runned (can't be travis-ed)
all-step1: full

# second step is backup
all-step2: backup-push

all: all-step0 all-step1 watch-run all-step2
	@echo ended with succes !!!

# launch remote

remote-config: config data-tag
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} remote-config\
		APP=${APP} APP_VERSION=${DATAPREP_VERSION} CLOUD_TAG=data:$$(cat ${DATA_TAG})-prep:${DATAPREP_VERSION}\
		STORAGE_BUCKET=${STORAGE_BUCKET} STORAGE_ACCESS_KEY=${STORAGE_ACCESS_KEY} STORAGE_SECRET_KEY=${STORAGE_SECRET_KEY}\
		GIT_BRANCH=${GIT_BRANCH} ${MAKEOVERRIDES}

remote-deploy:
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} remote-deploy\
		APP=${APP} APP_VERSION=${DATAPREP_VERSION} GIT_BRANCH=${GIT_BRANCH} \
		STORAGE_BUCKET=${STORAGE_BUCKET} STORAGE_ACCESS_KEY=${STORAGE_ACCESS_KEY} STORAGE_SECRET_KEY=${STORAGE_SECRET_KEY}\
		${MAKEOVERRIDES}

remote-step1:
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} remote-actions\
		APP=${APP} APP_VERSION=${DATAPREP_VERSION} GIT_BRANCH=${GIT_BRANCH} \
		ACTIONS="all-step1"\
		STORAGE_BUCKET=${STORAGE_BUCKET} STORAGE_ACCESS_KEY=${STORAGE_ACCESS_KEY} STORAGE_SECRET_KEY=${STORAGE_SECRET_KEY}\
		${MAKEOVERRIDES}

remote-watch:
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} remote-actions\
		APP=${APP} APP_VERSION=${DATAPREP_VERSION} GIT_BRANCH=${GIT_BRANCH} \
		ACTIONS="watch-run"\
		STORAGE_BUCKET=${STORAGE_BUCKET} STORAGE_ACCESS_KEY=${STORAGE_ACCESS_KEY} STORAGE_SECRET_KEY=${STORAGE_SECRET_KEY}\
		${MAKEOVERRIDES}

remote-step2:
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} remote-actions\
		APP=${APP} APP_VERSION=${DATAPREP_VERSION} GIT_BRANCH=${GIT_BRANCH} \
		ACTIONS="all-step2"\
		STORAGE_BUCKET=${STORAGE_BUCKET} STORAGE_ACCESS_KEY=${STORAGE_ACCESS_KEY} STORAGE_SECRET_KEY=${STORAGE_SECRET_KEY}\
		${MAKEOVERRIDES}

remote-clean:
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} remote-clean\
		APP=${APP} APP_VERSION=${DATAPREP_VERSION} GIT_BRANCH=${GIT_BRANCH} \
		${MAKEOVERRIDES}
	@rm ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS}/configured/*.deployed > /dev/null 2>&1

remote-all: full-check
	@if [ ! -f "no-remote" ];then\
		${MAKE} remote-config remote-deploy remote-step1 remote-watch remote-step2 remote-clean;\
	fi

