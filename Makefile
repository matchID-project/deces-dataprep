SHELL=/bin/bash

export DATAPREP_VERSION := $(shell cat Makefile projects/deces-dataprep/recipes/deces_dataprep.yml projects/deces-dataprep/datasets/deces_index.yml  | sha1sum | awk '{print $1}' | cut -c-8)
export APP=deces-dataprep
export APP_GROUP=matchID
export PWD := $(shell pwd)
export APP_PATH=${PWD}
export GIT = $(shell which git)
export GITROOT = https://github.com/matchid-project
export GIT_BRANCH = master
export GIT_BACKEND = backend
export GIT_TOOLS = tools
export MAKEBIN = $(shell which make)
export MAKE = ${MAKEBIN} --no-print-directory -s
export ES_INDEX=deces
export ES_NODES=1
export ES_MEM=1024m
export ES_VERSION = 8.6.1
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
export DATAGOUV_CONNECTOR = s3
export STORAGE_BUCKET=${DATAGOUV_DATASET}
export REPOSITORY_BUCKET=${DATAGOUV_DATASET}-elasticsearch
export DATA_DIR=${PWD}/data
export BACKUP_DIR = ${PWD}/${GIT_BACKEND}/backup
export DATA_TAG=${PWD}/data-tag
export BACKUP_METHOD=repository
export BACKUP_CHECK=${PWD}/backup-check
export REPOSITORY_CHECK=${PWD}/repository-check
# files to sync:
export FILES_TO_SYNC=fichier-opposition-deces.csv(.gz)?|deces-.*.txt(.gz)?
export FILES_TO_SYNC_FORCE=fichier-opposition-deces.csv(.gz)?
# files to process:
export FILES_TO_PROCESS=deces-([0-9]{4}|2023-m[0-9]{2}).txt.gz
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
RCLONE_OPTS=--s3-acl=public-read
export SCW_FLAVOR=PRO2-M
export SCW_VOLUME_TYPE=b_ssd
export SCW_VOLUME_SIZE=50000000000
export SCW_IMAGE_ID=3043c0c8-d413-4d2e-b9c5-1dbb02fbdcb5

dummy               := $(shell touch artifacts)
include ./artifacts

config: ${GIT_BACKEND}
	@echo checking system prerequisites
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND} config && \
	echo "prerequisites installed" > config

datagouv-to-storage: config
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} datagouv-to-storage \
		DATAGOUV_DATASET=${DATAGOUV_DATASET} STORAGE_BUCKET=${STORAGE_BUCKET}\
		FILES_PATTERN='${FILES_TO_SYNC}' FILES_PATTERN_FORCE='${FILES_TO_SYNC_FORCE}' &&\
	touch datagouv-to-storage

datagouv-to-s3: datagouv-to-storage
	touch datagouv-to-s3

datagouv-to-upload:
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} datagouv-get-files \
		DATAGOUV_DATASET=${DATAGOUV_DATASET} DATA_DIR=${APP_PATH}/${GIT_BACKEND}/upload\
		FILES_PATTERN='${FILES_TO_SYNC}' FILES_PATTERN_FORCE='${FILES_TO_SYNC_FORCE}' &&\
	touch datagouv-to-upload

${DATA_TAG}: config
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} catalog-tag CATALOG_TAG=${DATA_TAG}\
		DATAGOUV_DATASET=${DATAGOUV_DATASET} STORAGE_BUCKET=${STORAGE_BUCKET}\
		FILES_PATTERN='${FILES_TO_PROCESS}' > /dev/null 2>&1

data-tag: ${DATA_TAG}

dataprep-version:
	@echo ${DATAPREP_VERSION}

${BACKUP_CHECK}: data-tag
	${MAKE} -s -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} get-catalog CATALOG=${BACKUP_CHECK}\
		DATAGOUV_DATASET=${DATAGOUV_DATASET} STORAGE_BUCKET=${STORAGE_BUCKET}\
		FILES_PATTERN=esdata_${DATAPREP_VERSION}_$$(cat ${PWD}/data-tag).tar &&\
	if [ -s "${BACKUP_CHECK}" ]; then\
		echo classic backup already exist on remote storage;\
	else\
		rm -f "${BACKUP_CHECK}";\
		echo no previous classic backup found;\
	fi;\

backup-check: ${BACKUP_CHECK}

repository-config: config
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND} elasticsearch-repository-config\
		REPOSITORY_BUCKET=${REPOSITORY_BUCKET} STORAGE_ACCESS_KEY=${STORAGE_ACCESS_KEY} STORAGE_SECRET_KEY=${STORAGE_SECRET_KEY}\
		${MAKEOVERRIDES} && touch repository-config

${REPOSITORY_CHECK}: repository-config data-tag
	@ES_BACKUP_NAME=esdata_${DATAPREP_VERSION}_$$(cat ${DATA_TAG});\
	${MAKE} -C ${APP_PATH}/${GIT_BACKEND} elasticsearch-repository-check\
		REPOSITORY_BUCKET=${REPOSITORY_BUCKET} STORAGE_ACCESS_KEY=${STORAGE_ACCESS_KEY} STORAGE_SECRET_KEY=${STORAGE_SECRET_KEY}\
		${MAKEOVERRIDES} ES_BACKUP_NAME=$${ES_BACKUP_NAME} \
		| egrep -q "^snapshot found"\
		&& echo "snapshot found for or $${ES_BACKUP_NAME} in elasticsearch repository" && (echo "$${ES_BACKUP_NAME}" > "${REPOSITORY_CHECK}") \
		|| (echo "no snapshot found for $${ES_BACKUP_NAME} elasticsearch repository")

repository-check: ${REPOSITORY_CHECK}

check-s3: ${BACKUP_METHOD}-check
	touch check-s3

check-upload:
	@touch check-upload

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
	@sed -i -E "s/export API_SECRET_KEY:=(.*)/export API_SECRET_KEY:=1234/"  backend/Makefile
	@sed -i -E "s/export ADMIN_PASSWORD:=(.*)/export ADMIN_PASSWORD:=1234ABC/"  backend/Makefile
	@sed -i -E "s/id(.*):=(.*)/id:=myid/"  backend/Makefile

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
		echo running recipe on data FILES_TO_PROCESS="${FILES_TO_PROCESS}" $$(cat ${DATA_TAG}), dataprep ${DATAPREP_VERSION};\
		${MAKE} -C ${APP_PATH}/${GIT_BACKEND} version;\
		${MAKE} -C ${APP_PATH}/${GIT_BACKEND} recipe-run \
			CHUNK_SIZE=${CHUNK_SIZE} RECIPE=${RECIPE} RECIPE_THREADS=${RECIPE_THREADS} RECIPE_QUEUE=${RECIPE_QUEUE} \
			ES_PRELOAD='${ES_PRELOAD}' ES_THREADS=${ES_THREADS} \
			STORAGE_BUCKET=${STORAGE_BUCKET} STORAGE_ACCESS_KEY=${STORAGE_ACCESS_KEY} STORAGE_SECRET_KEY=${STORAGE_SECRET_KEY}\
			${MAKEOVERRIDES} \
			APP=backend APP_VERSION=$(shell cd ${APP_PATH}/${GIT_BACKEND} && make version | awk '{print $$NF}') \
			&&\
		touch recipe-run s3-pull &&\
		(echo esdata_${DATAPREP_VERSION}_$$(cat ${DATA_TAG}).tar > elasticsearch-restore);\
	fi

full-check: datagouv-to-${DATAGOUV_CONNECTOR} check-${DATAGOUV_CONNECTOR}
	@if [ -s ${BACKUP_METHOD}-check -a -z "${NO_CHECK}"]; then\
		echo recipe has already been runned on full and saved on remote storage;\
		touch recipe-run watch-run backup backup-push repository-push no-remote;\
	fi

full: full-check recipe-run
	@echo Total records in index: `docker exec -it matchid-elasticsearch curl localhost:9200/_cat/indices | awk '{printf $$7}'`
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

backup-restore: backup-pull
	@if [ ! -f "elasticsearch-restore" ];then\
		${MAKE} -C ${APP_PATH}/${GIT_BACKEND} elasticsearch-restore ES_BACKUP_FILE=esdata_${DATAPREP_VERSION}_$$(cat ${DATA_TAG}).tar \
			&& (echo esdata_${DATAPREP_VERSION}_$$(cat ${DATA_TAG}).tar > elasticsearch-restore);\
	fi

repository-restore: repository-check
	@if [ ! -f "elasticsearch-restore" ];then\
		${MAKE} -C ${APP_PATH}/${GIT_BACKEND} elasticsearch-repository-restore\
			REPOSITORY_BUCKET=${REPOSITORY_BUCKET} STORAGE_ACCESS_KEY=${STORAGE_ACCESS_KEY} STORAGE_SECRET_KEY=${STORAGE_SECRET_KEY}\
			ES_INDEX=${ES_INDEX} ES_BACKUP_NAME=esdata_${DATAPREP_VERSION}_$$(cat ${DATA_TAG})\
			&& (echo esdata_${DATAPREP_VERSION}_$$(cat ${DATA_TAG}) > elasticsearch-restore);\
	fi

elasticsearch-restore: ${BACKUP_METHOD}-restore

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

repository-push: data-tag
	@if [ ! -f repository-push ];then\
		${MAKE} -C ${APP_PATH}/${GIT_BACKEND} elasticsearch-repository-backup\
			REPOSITORY_BUCKET=${REPOSITORY_BUCKET} STORAGE_ACCESS_KEY=${STORAGE_ACCESS_KEY} STORAGE_SECRET_KEY=${STORAGE_SECRET_KEY}\
			ES_INDEX=${ES_INDEX} ES_BACKUP_NAME=esdata_${DATAPREP_VERSION}_$$(cat ${DATA_TAG}) && touch repository-push;\
		fi

repository-backup-tmp: data-tag
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND} elasticsearch-repository-backup-async\
		REPOSITORY_BUCKET=${REPOSITORY_BUCKET} STORAGE_ACCESS_KEY=${STORAGE_ACCESS_KEY} STORAGE_SECRET_KEY=${STORAGE_SECRET_KEY}\
		ES_INDEX=${ES_INDEX} ES_BACKUP_NAME=esdata_tmp_${DATAPREP_VERSION}_$$(cat ${DATA_TAG})

respository-cleanse:
	@(${MAKE} -C ${APP_PATH}/${GIT_BACKEND} elasticsearch-repository-delete\
		REPOSITORY_BUCKET=${REPOSITORY_BUCKET} STORAGE_ACCESS_KEY=${STORAGE_ACCESS_KEY} STORAGE_SECRET_KEY=${STORAGE_SECRET_KEY}\
		ES_INDEX=${ES_INDEX} ES_BACKUP_NAME=esdata_tmp_${DATAPREP_VERSION}_$$(cat ${DATA_TAG}) > /dev/null 2>&1) || exit 0

down:
	@if [ -f config ]; then\
		(${MAKE} -C ${APP_PATH}/${GIT_BACKEND} backend-stop elasticsearch-stop frontend-stop || true);\
	fi

clean: down
	@sudo rm -rf ${GIT_BACKEND} frontend ${DATA_DIR} data-tag config \
		recipe-run backup-check datagouv-to-* check-* elasticsearch-restore watch-run full\
		backup backup-pull backup-push repository-push repository-config repository-check no-remote

# launch all locally
# configure
all-step0: ${GIT_BACKEND} config

# first step should be 1h30 to 10 hours if not already runned (can't be travis-ed)
all-step1: full

# second step is backup
all-step2: ${BACKUP_METHOD}-push

all: all-step0 all-step1 watch-run all-step2
	@echo ended with succes !!!

# launch remote

remote-config: config data-tag
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} remote-config\
		APP=${APP} APP_VERSION=${DATAPREP_VERSION} CLOUD_TAG=data:$$(cat ${DATA_TAG})-prep:${DATAPREP_VERSION}\
		REPOSITORY_BUCKET=${REPOSITORY_BUCKET} STORAGE_BUCKET=${STORAGE_BUCKET} STORAGE_ACCESS_KEY=${STORAGE_ACCESS_KEY} STORAGE_SECRET_KEY=${STORAGE_SECRET_KEY}\
        SCW_IMAGE_ID=${SCW_IMAGE_ID} SCW_FLAVOR=${SCW_FLAVOR} SCW_VOLUME_SIZE=${SCW_VOLUME_SIZE} SCW_VOLUME_TYPE=${SCW_VOLUME_TYPE} \
		GIT_BRANCH=${GIT_BRANCH} ${MAKEOVERRIDES}

remote-deploy:
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} remote-deploy\
		APP=${APP} APP_VERSION=${DATAPREP_VERSION} GIT_BRANCH=${GIT_BRANCH} \
		REPOSITORY_BUCKET=${REPOSITORY_BUCKET} STORAGE_BUCKET=${STORAGE_BUCKET} STORAGE_ACCESS_KEY=${STORAGE_ACCESS_KEY} STORAGE_SECRET_KEY=${STORAGE_SECRET_KEY}\
		${MAKEOVERRIDES}

remote-step1:
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} remote-actions\
		APP=${APP} APP_VERSION=${DATAPREP_VERSION} GIT_BRANCH=${GIT_BRANCH} \
		ACTIONS="all-step1"\
		REPOSITORY_BUCKET=${REPOSITORY_BUCKET} STORAGE_BUCKET=${STORAGE_BUCKET} STORAGE_ACCESS_KEY=${STORAGE_ACCESS_KEY} STORAGE_SECRET_KEY=${STORAGE_SECRET_KEY}\
		CHUNK_SIZE=${CHUNK_SIZE} ES_THREADS=${ES_THREADS} RECIPE_THREADS=${RECIPE_THREADS} ES_MEM=${ES_MEM} RECIPE_QUEUE=${RECIPE_QUEUE} \
		BACKUP_METHOD=${BACKUP_METHOD} ${MAKEOVERRIDES}

remote-watch:
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} remote-actions\
		APP=${APP} APP_VERSION=${DATAPREP_VERSION} GIT_BRANCH=${GIT_BRANCH} \
		ACTIONS="watch-run"\
		${MAKEOVERRIDES}

remote-step2:
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} remote-actions\
		APP=${APP} APP_VERSION=${DATAPREP_VERSION} GIT_BRANCH=${GIT_BRANCH} \
		ACTIONS="all-step2"\
		REPOSITORY_BUCKET=${REPOSITORY_BUCKET} STORAGE_BUCKET=${STORAGE_BUCKET} STORAGE_ACCESS_KEY=${STORAGE_ACCESS_KEY} STORAGE_SECRET_KEY=${STORAGE_SECRET_KEY}\
		BACKUP_METHOD=${BACKUP_METHOD} ${MAKEOVERRIDES}

remote-clean:
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} remote-clean\
		APP=${APP} APP_VERSION=${DATAPREP_VERSION} GIT_BRANCH=${GIT_BRANCH} \
		${MAKEOVERRIDES}
	@rm ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS}/configured/*.deployed > /dev/null 2>&1

remote-all:
	@if [ ! -f "no-remote" ];then\
		${MAKE} remote-config remote-deploy remote-step1 remote-watch remote-step2 remote-clean ${MAKEOVERRIDES};\
	fi


# optimize delays
remote-docker-pull-base: config remote-config remote-deploy
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} remote-docker-pull DOCKER_IMAGE=python:3.9-slim-bullseye
	@${MAKE} -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} remote-docker-pull DOCKER_IMAGE=docker.elastic.co/elasticsearch/elasticsearch:${ES_VERSION}

update-base-image: config remote-config remote-deploy remote-docker-pull-base
	@\
	APP_VERSION=$$(cd ${APP_PATH}/${GIT_BACKEND} && make version | awk '{print $$NF}');\
	${MAKE} -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} remote-cmd REMOTE_CMD="sudo apt upgrade -y"; \
	${MAKE} -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} remote-cmd REMOTE_CMD="sync"; \
	${MAKE} -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} remote-cmd REMOTE_CMD="rm -rf ${APP_GROUP}"; \
	sleep 5;\
	${MAKE} -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} SCW-instance-snapshot \
		GIT_BRANCH=${GIT_BRANCH} APP=${APP} APP_VERSION=$${APP_VERSION} CLOUD_TAG=data:$$(cat ${DATA_TAG})-prep:${DATAPREP_VERSION}\
		CLOUD_APP=deces-dataprep;\
	${MAKE} -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} SCW-instance-image \
		CLOUD_APP=deces-dataprep;\
	SCW_IMAGE_ID=$$(cat ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS}/cloud/SCW.image.id)/;\
	cat ${APP_PATH}/Makefile | sed "s/^export SCW_IMAGE_ID=.*/export SCW_IMAGE_ID=$${SCW_IMAGE_ID}" \
		> ${APP_PATH}/Makefile.tmp && mv ${APP_PATH}/Makefile.tmp ${APP_PATH}/Makefile;\
	${MAKE} -C ${APP_PATH}/${GIT_BACKEND}/${GIT_TOOLS} remote-clean;\
	git add Makefile && git commit -m '⬆️  update SCW_IMAGE_ID'