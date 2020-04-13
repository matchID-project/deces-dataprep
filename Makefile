SHELL=/bin/bash

export DATAPREP_VERSION := $(shell cat projects/deces-dataprep/recipes/deces_dataprep.yml projects/deces-dataprep/datasets/deces_index.yml  | sha1sum | awk '{print $1}' | cut -c-8)
export APP=deces-dataprep
export PWD := $(shell pwd)
export GIT = $(shell which git)
export GITROOT = https://github.com/matchid-project
export GIT_BACKEND = backend
export MAKEBIN = $(shell which make)
export MAKE = ${MAKEBIN} --no-print-directory -s
export RECIPE = deces_dataprep
export RECIPE_THREADS = 4
export RECIPE_QUEUE = 1
export TIMEOUT = 2520
export DATAGOUV_API = https://www.data.gouv.fr/api/1/datasets
export DATAGOUV_DATASET = fichier-des-personnes-decedees
export DATA_DIR=${PWD}/data
export BACKUP_DIR = ${PWD}/${GIT_BACKEND}/backup
export TOOLS = ${PWD}/${GIT_BACKEND}/tools
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
	@${MAKE} -C ${GIT_BACKEND} config && \
	echo "prerequisites installed" > config

datagouv-to-storage: config
	@${MAKE} -C ${TOOLS} datagouv-to-storage \
		DATAGOUV_DATASET=${DATAGOUV_DATASET} BUCKET=${DATAGOUV_DATASET}\
		FILES_PATTERN='${FILES_TO_SYNC}' &&\
	touch datagouv-to-storage

${DATA_TAG}: config
	@${MAKE} -C ${TOOLS} catalog-tag CATALOG_TAG=${DATA_TAG}\
		DATAGOUV_DATASET=${DATAGOUV_DATASET} BUCKET=${DATAGOUV_DATASET}\
		FILES_PATTERN=${FILES_TO_PROCESS} > /dev/null 2>&1

data-tag: ${DATA_TAG}

${BACKUP_CHECK}: data-tag
	@${MAKE} -s -C ${TOOLS} get-catalog CATALOG=${BACKUP_CHECK}\
		DATAGOUV_DATASET=${DATAGOUV_DATASET} BUCKET=${DATAGOUV_DATASET}\
		FILES_PATTERN=esdata_${DATAPREP_VERSION}_$$(cat ${PWD}/data-tag).tar &&\
	if [ -s ${BACKUP_CHECK} ]; then\
		echo backup already exist on remote storage;\
	else\
		echo no previous backup found;\
	fi

backup-check: ${BACKUP_CHECK}

backup-pull: data-tag
	@${MAKE} -C ${TOOLS} storage-pull\
		BUCKET=${DATAGOUV_DATASET}\
		FILE=esdata_${DATAPREP_VERSION}_$$(cat data.tag).tar &&\
	touch backup-pull

${GIT_BACKEND}:
	@echo configuring matchID
	@${GIT} clone -q ${GITROOT}/${GIT_BACKEND}
	@cp artifacts ${GIT_BACKEND}/artifacts
	@cp docker-compose-local.yml ${GIT_BACKEND}/docker-compose-local.yml
	@echo "export ES_NODES=1" >> ${GIT_BACKEND}/artifacts
	@echo "export PROJECTS=${PWD}/projects" >> ${GIT_BACKEND}/artifacts
	@echo "export S3_BUCKET=${DATAGOUV_DATASET}" >> ${GIT_BACKEND}/artifacts

dev: config
	@${MAKE} -C ${GIT_BACKEND} elasticsearch backend frontend && matchID started, go to http://localhost:8081

dev-stop:
	if [ -f config ]; then\
		${MAKE} -C ${GIT_BACKEND} frontend-stop backend-stop elasticsearch-stop;
	fi

up:
	@${MAKE} -C ${GIT_BACKEND} elasticsearch backend && echo matchID backend services started

recipe-run: data-tag
	@if [ ! -f recipe-run ];then\
		${MAKE} -C ${GIT_BACKEND} elasticsearch ${MAKEOVERRIDES};\
		echo running recipe on full data;\
		${MAKE} -C ${GIT_BACKEND} recipe-run RECIPE=${RECIPE} RECIPE_THREADS=${RECIPE_THREADS} RECIPE_QUEUE=${RECIPE_QUEUE} &&\
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

ls:
	@echo iiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiiii
	@ls | grep watch-run || true
	@echo yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy

watch-run:
	@timeout=${TIMEOUT} ; ret=1 ; \
		until [ "$$timeout" -le 0 -o "$$ret" -eq "0"  ] ; do \
			f=$$(find ${GIT_BACKEND}/log/ -iname '*${RECIPE}*' | sort | tail -1);\
			((tail $$f | grep "end of all" > /dev/null) || exit 1) ; \
			ret=$$? ; \
			if [ "$$ret" -ne "0" ] ; then \
				echo "waiting for end of job $$timeout" ; \
				grep wrote $$f |awk 'BEGIN{s=0}{t=$$4;s+=$$12}END{print t " wrote " s}' ;\
				sleep 10 ;\
			fi ; ((timeout--)); done ; exit $$ret
	@find ${GIT_BACKEND}/log/ -iname '*dataprep_personnes-dedecees_search*' | sort | tail -1 | xargs tail

elasticsearch-restore: backup-pull
	@if [ ! -f "elasticsearch-restore" ];then\
		${MAKE} -C ${GIT_BACKEND} elasticsearch-restore ES_BACKUP_FILE=esdata_${DATAPREP_VERSION}_$$(cat ${DATA_TAG}).tar \
			&& (echo esdata_${DATAPREP_VERSION}_$$(cat ${DATA_TAG}).tar > elasticsearch-restore);\
	fi

backup-dir:
	mkdir -p ${BACKUP_DIR}

backup: data-tag
	@if [ ! -f backup ];then\
		ES_BACKUP_FILE=esdata_${DATAPREP_VERSION}_$$(cat ${DATA_TAG}).tar;\
		ES_BACKUP_FILE_SNAR=esdata_${DATAPREP_VERSION}_$$(cat ${DATA_TAG}).snar;\
		if [ ! -f "${BACKUP_DIR}/$$ES_BACKUP_FILE" ];then\
			${MAKE} -C ${GIT_BACKEND} elasticsearch-backup \
				ES_BACKUP_FILE=$$ES_BACKUP_FILE\
				ES_BACKUP_FILE_SNAR=$$ES_BACKUP_FILE_SNAR;\
		fi;\
		touch backup;\
	fi

backup-push: data-tag backup
	@if [ ! -f backup-push ];then\
		ES_BACKUP_FILE_ROOT=esdata_${DATAPREP_VERSION}_$$(cat ${DATA_TAG});\
		${MAKE} -C ${GIT_BACKEND} elasticsearch-storage-push\
			BUCKET=fichier-des-personnes-decedees\
			ES_BACKUP_FILE=$$ES_BACKUP_FILE_ROOT.tar\
			ES_BACKUP_FILE_SNAR=$$ES_BACKUP_FILE_ROOT.snar &&\
			touch backup-push &&\
			SIZE=`cd ${BACKUP_DIR}; du -sh $$ES_BACKUP_FILE_ROOT.tar`;\
			echo pushed $$SIZE to storage ${DATAGOUV_DATASET};\
	fi

${SSHKEY}:
	@echo ssh keygen
	@ssh-keygen -t rsa -b 4096 -C "${SSHID}" -f ${SSHKEY_PRIVATE} -q -N "${SSH_PASSPHRASE}"

EC2-add-sshkey:
	@(\
		((${AWS} ${EC2} describe-key-pairs --key-name ${SSHKEYNAME}  > /dev/null 2>&1) &&\
			echo "ssh key already deployed to EC2") \
	|| \
		((${AWS} ${EC2} import-key-pair --key-name ${SSHKEYNAME} --public-key-material file://${SSHKEY} > /dev/null 2>&1) &&\
			echo "ssh key deployed with success to EC2") \
	)

${EC2_SERVER_FILE_ID}:
	@((${AWS} ${EC2} run-instances --key-name ${SSHKEYNAME} \
		 	--image-id ${EC2_IMAGE_ID} --instance-type ${EC2_FLAVOR_TYPE} \
			--tag-specifications "Tags=[{Key=Name,Value=${APP}}]" | jq -r '.Instances[0].InstanceId' > ${EC2_SERVER_FILE_ID} 2>&1 \
		 ) &&\
			echo "EC2 instance ordered with success")

EC2-instance-order: EC2-add-sshkey ${EC2_SERVER_FILE_ID}



EC2-instance-wait-running: EC2-instance-order
	@EC2_SERVER_ID=$$(cat ${EC2_SERVER_FILE_ID});\
	timeout=${EC2_TIMEOUT} ; ret=1 ; until [ "$$timeout" -le 0 -o "$$ret" -eq "0"  ] ; do\
	  ${AWS} ${EC2} describe-instances --instance-ids $$EC2_SERVER_ID | jq -c '.Reservations[].Instances[].State.Name' | (grep running > /dev/null);\
	  ret=$$? ; \
	  if [ "$$ret" -ne "0" ] ; then echo "waiting for EC2 instance $$EC2_SERVER_ID to start $$timeout" ; fi ;\
	  ((timeout--)); sleep 1 ; \
    done ; exit $$ret

EC2-instance-wait-ssh: EC2-instance-wait-running
	@EC2_SERVER_ID=$$(cat ${EC2_SERVER_FILE_ID});\
	HOST=$$(${AWS} ${EC2} describe-instances --instance-ids $$EC2_SERVER_ID |\
		jq -r ".Reservations[].Instances[].${EC2_IP}");\
	(ssh-keygen -R $$HOST > /dev/null 2>&1) || true;\
	timeout=${EC2_TIMEOUT} ; ret=1 ; until [ "$$timeout" -le 0 -o "$$ret" -eq "0"  ] ; do\
	  ((ssh ${SSHOPTS} ${EC2_SSHUSER}@$$HOST sleep 1) > /dev/null 2>&1);\
	  ret=$$? ; \
	  if [ "$$ret" -ne "0" ] ; then echo "waiting for ssh service on EC2 instance $$EC2_SERVER_ID - $$timeout" ; fi ;\
	  ((timeout--)); sleep 1 ; \
    done ; exit $$ret

EC2-instance-wait: EC2-instance-wait-ssh

EC2-instance-delete:
	@if [ -f "${EC2_SERVER_FILE_ID}" ];then\
		EC2_SERVER_ID=$$(cat ${EC2_SERVER_FILE_ID});\
		${AWS} ${EC2} terminate-instances --instance-ids $$EC2_SERVER_ID |\
			jq -r '.TerminatingInstances[0].CurrentState.Name' | sed 's/$$/ EC2 instance/';\
	fi
	@rm ${EC2_SERVER_FILE_ID} > /dev/null 2>&1 | true;

OS-add-sshkey: ${SSHKEY}
	@(\
		(nova keypair-list | sed 's/|//g' | egrep -v '\-\-\-|Name' | (egrep '^\s*${SSHKEYNAME}\s' > /dev/null) &&\
		 echo "ssh key already deployed to openstack" ) \
	  || \
		(nova keypair-add --pub-key ${SSHKEY} ${SSHKEYNAME} &&\
		 nova keypair-list | sed 's/|//g' | egrep -v '\-\-\-|Name' | (egrep '^\s*${SSHKEYNAME}\s' > /dev/null) &&\
		 echo "ssh key deployed with success to openstack" ) \
	  )

OS-instance-order: OS-add-sshkey
	@(\
		(nova list | sed 's/|//g' | egrep -v '\-\-\-|Name' | (egrep '\s${APP}\s' > /dev/null) && \
		echo "openstack instance already ordered")\
	 || \
		(nova boot --key-name ${SSHKEYNAME} --flavor ${OS_FLAVOR_ID} --image ${OS_IMAGE_ID} ${APP} && \
	 		echo "openstack intance ordered with success") || echo "openstance instance order failed"\
	)

OS-instance-wait-running: OS-instance-order
	@timeout=${OS_TIMEOUT} ; ret=1 ; until [ "$$timeout" -le 0 -o "$$ret" -eq "0"  ] ; do\
	  nova list | sed 's/|//g' | egrep -v '\-\-\-|Name' | (egrep '\s${APP}\s.*Running' > /dev/null) ;\
	  ret=$$? ; \
	  if [ "$$ret" -ne "0" ] ; then echo "waiting for openstack instance to start $$timeout" ; fi ;\
	  ((timeout--)); sleep 1 ; \
	done ; exit $$ret

OS-instance-wait-ssh: OS-instance-wait-running
	@HOST=$$(nova list | sed 's/|//g' | egrep -v '\-\-\-|Name' | egrep '\s${APP}\s.*Running' | sed 's/.*Ext-Net=//;s/,.*//') ;\
		(ssh-keygen -R $$HOST > /dev/null 2>&1) || true;\
		SSHUSER=${OS_SSHUSER};\
	timeout=${OS_TIMEOUT} ; ret=1 ; until [ "$$timeout" -le 0 -o "$$ret" -eq "0"  ] ; do\
	  ((ssh ${SSHOPTS} $$SSHUSER@$$HOST sleep 1) > /dev/null 2>&1);\
	  ret=$$? ; \
	  if [ "$$ret" -ne "0" ] ; then echo "waiting for ssh service on openstack instance $$SCW_SERVER_ID - $$timeout" ; fi ;\
	  ((timeout--)); sleep 1 ; \
    done ; exit $$ret

OS-instance-wait: OS-instance-wait-ssh

OS-instance-delete:
	nova delete ${APP}

${SCW_SERVER_FILE_ID}:
	@curl -s ${SCW_API}/servers -H "X-Auth-Token: ${SCW_SECRET_TOKEN}" \
		-H "Content-Type: application/json" \
		-d '{"name": "${APP}", "image": "${SCW_IMAGE_ID}", "commercial_type": "${SCW_FLAVOR}", "organization": "${SCW_ORGANIZATION_ID}"}' | jq -r '.server.id' > ${SCW_SERVER_FILE_ID}

SCW-instance-start: ${SCW_SERVER_FILE_ID}
	@SCW_SERVER_ID=$$(cat ${SCW_SERVER_FILE_ID});\
		(curl -s ${SCW_API}/servers -H "X-Auth-Token: ${SCW_SECRET_TOKEN}" | jq -cr  ".servers[] | select (.id == \"$$SCW_SERVER_ID\") | .state" | (grep running > /dev/null) && \
		echo scaleway instance already running)\
		|| \
	 	(\
			(\
				(curl -s --fail ${SCW_API}/servers/$$SCW_SERVER_ID/action -H "X-Auth-Token: ${SCW_SECRET_TOKEN}" \
					-H "Content-Type: application/json" -d '{"action": "poweron"}' > /dev/null) &&\
				echo scaleway instance starting\
			) || echo scaleway instance still starting\
		)

SCW-instance-wait-running: SCW-instance-start
	@SCW_SERVER_ID=$$(cat ${SCW_SERVER_FILE_ID});\
	timeout=${SCW_TIMEOUT} ; ret=1 ; until [ "$$timeout" -le 0 -o "$$ret" -eq "0"  ] ; do\
	  curl -s ${SCW_API}/servers -H "X-Auth-Token: ${SCW_SECRET_TOKEN}" | jq -cr  ".servers[] | select (.id == \"$$SCW_SERVER_ID\") | .state" | (grep running > /dev/null);\
	  ret=$$? ; \
	  if [ "$$ret" -ne "0" ] ; then echo "waiting for scaleway instance $$SCW_SERVER_ID to start $$timeout" ; fi ;\
	  ((timeout--)); sleep 1 ; \
    done ; exit $$ret

SCW-instance-wait-ssh: SCW-instance-wait-running
	@SCW_SERVER_ID=$$(cat ${SCW_SERVER_FILE_ID});\
	HOST=$$(curl -s ${SCW_API}/servers -H "X-Auth-Token: ${SCW_SECRET_TOKEN}" | jq -cr  ".servers[] | select (.id == \"$$SCW_SERVER_ID\") | .${SCW_IP}" ) ;\
	(ssh-keygen -R $$HOST > /dev/null 2>&1) || true;\
	timeout=${SCW_TIMEOUT} ; ret=1 ; until [ "$$timeout" -le 0 -o "$$ret" -eq "0"  ] ; do\
	  ((ssh ${SSHOPTS} root@$$HOST sleep 1) > /dev/null 2>&1);\
	  ret=$$? ; \
	  if [ "$$ret" -ne "0" ] ; then echo "waiting for ssh service on scaleway instance $$SCW_SERVER_ID - $$timeout" ; fi ;\
	  ((timeout--)); sleep 1 ; \
    done ; exit $$ret

SCW-instance-wait: SCW-instance-wait-ssh


SCW-instance-delete:
	@if [ -f "${SCW_SERVER_FILE_ID}" ];then\
		SCW_SERVER_ID=$$(cat ${SCW_SERVER_FILE_ID});\
		((curl -s --fail ${SCW_API}/servers/$$SCW_SERVER_ID/action -H "X-Auth-Token: ${SCW_SECRET_TOKEN}" \
			-H "Content-Type: application/json" -d '{"action": "terminate"}' > /dev/null) && \
			echo scaleway server terminating) ||\
		echo scaleway error while terminating server;\
		rm ${SCW_SERVER_FILE_ID};\
	else\
		echo no scw.id for deletion;\
	fi

down:
	@if [ -f config ]; then\
		(${MAKE} -C ${GIT_BACKEND} backend-stop elasticsearch-stop frontend-stop || true);\
	fi

clean: down
	@sudo rm -rf ${GIT_BACKEND} frontend ${DATA_DIR} data-tag config \
		recipe-run backup-check elasticsearch-restore watch-run full\
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

remote-config: ${CLOUD}-instance-wait
	@if [ "${CLOUD}" == "OS" ];then\
		HOST=$$(nova list | sed 's/|//g' | egrep -v '\-\-\-|Name' | egrep '\s${APP}\s.*Running' | sed 's/.*Ext-Net=//;s/,.*//') ;\
		(ssh-keygen -R $$HOST > /dev/null 2>&1) || true;\
		SSHUSER=${OS_SSHUSER};\
	elif [ "${CLOUD}" == "EC2" ];then\
		EC2_SERVER_ID=$$(cat ${EC2_SERVER_FILE_ID});\
		HOST=$$(${AWS} ${EC2} describe-instances --instance-ids $$EC2_SERVER_ID |\
				jq -r ".Reservations[].Instances[].${EC2_IP}");\
		(ssh-keygen -R $$HOST > /dev/null 2>&1) || true;\
		SSHUSER=${EC2_SSHUSER};\
	else\
		SCW_SERVER_ID=$$(cat ${SCW_SERVER_FILE_ID});\
		HOST=$$(curl -s ${SCW_API}/servers -H "X-Auth-Token: ${SCW_SECRET_TOKEN}" | jq -cr  ".servers[] | select (.id == \"$$SCW_SERVER_ID\") | .${SCW_IP}" ) ;\
		(ssh-keygen -R $$HOST > /dev/null 2>&1) || true;\
		SSHUSER=${SCW_SSHUSER};\
		ssh ${SSHOPTS} root@$$HOST apt-get install -o Dpkg::Options::="--force-confold" -yq sudo;\
	fi;\
		ssh ${SSHOPTS} $$SSHUSER@$$HOST git clone ${GITROOT}/${APP};\
		ssh ${SSHOPTS} $$SSHUSER@$$HOST sudo apt-get update -y;\
		ssh ${SSHOPTS} $$SSHUSER@$$HOST sudo apt-get install -y make;\
		ssh ${SSHOPTS} $$SSHUSER@$$HOST ${MAKE} -C ${APP} all-step0 ${MAKEOVERRIDES};

remote-step1:
	@if [ "${CLOUD}" == "OS" ];then\
		HOST=$$(nova list | sed 's/|//g' | egrep -v '\-\-\-|Name' | egrep '\s${APP}\s.*Running' | sed 's/.*Ext-Net=//;s/,.*//') ;\
		SSHUSER=${OS_SSHUSER};\
	elif [ "${CLOUD}" == "EC2" ];then\
		EC2_SERVER_ID=$$(cat ${EC2_SERVER_FILE_ID});\
		HOST=$$(${AWS} ${EC2} describe-instances --instance-ids $$EC2_SERVER_ID |\
				jq -r ".Reservations[].Instances[].${EC2_IP}");\
		SSHUSER=${EC2_SSHUSER};\
	else\
		SCW_SERVER_ID=$$(cat ${SCW_SERVER_FILE_ID});\
		HOST=$$(curl -s ${SCW_API}/servers -H "X-Auth-Token: ${SCW_SECRET_TOKEN}" | jq -cr  ".servers[] | select (.id == \"$$SCW_SERVER_ID\") | .${SCW_IP}" ) ;\
		SSHUSER=${SCW_SSHUSER};\
	fi;\
		ssh ${SSHOPTS} $$SSHUSER@$$HOST 'echo "export FILES_TO_PROCESS=${FILES_TO_PROCESS}" > ${APP}/artifacts';\
		ssh ${SSHOPTS} $$SSHUSER@$$HOST mkdir -p .aws;\
		cat ${S3_CONFIG} | ${REMOTE_HOST} ssh ${SSHOPTS} $$SSHUSER@$$HOST "cat > .aws/config";\
		echo -e "[default]\naws_access_key_id=${aws_access_key_id}\naws_secret_access_key=${aws_secret_access_key}\n" |\
			ssh ${SSHOPTS} $$SSHUSER@$$HOST 'cat > .aws/credentials';\
		ssh ${SSHOPTS} $$SSHUSER@$$HOST ${MAKE} -C ${APP} all-step1 aws_access_key_id=${aws_access_key_id} aws_secret_access_key=${aws_secret_access_key} ${MAKEOVERRIDES};

remote-watch:
	@if [ "${CLOUD}" == "OS" ];then\
		HOST=$$(nova list | sed 's/|//g' | egrep -v '\-\-\-|Name' | egrep '\s${APP}\s.*Running' | sed 's/.*Ext-Net=//;s/,.*//') ;\
		SSHUSER=${OS_SSHUSER};\
	elif [ "${CLOUD}" == "EC2" ];then\
		EC2_SERVER_ID=$$(cat ${EC2_SERVER_FILE_ID});\
		HOST=$$(${AWS} ${EC2} describe-instances --instance-ids $$EC2_SERVER_ID |\
				jq -r ".Reservations[].Instances[].${EC2_IP}");\
		SSHUSER=${EC2_SSHUSER};\
	else\
		SCW_SERVER_ID=$$(cat ${SCW_SERVER_FILE_ID});\
		HOST=$$(curl -s ${SCW_API}/servers -H "X-Auth-Token: ${SCW_SECRET_TOKEN}" | jq -cr  ".servers[] | select (.id == \"$$SCW_SERVER_ID\") | .${SCW_IP}" ) ;\
		SSHUSER=${SCW_SSHUSER};\
	fi;\
		ssh ${SSHOPTS} $$SSHUSER@$$HOST make -C ${APP} watch-run ${MAKEOVERRIDES};

remote-step2: remote-watch
	@if [ "${CLOUD}" == "OS" ];then\
		HOST=$$(nova list | sed 's/|//g' | egrep -v '\-\-\-|Name' | egrep '\s${APP}\s.*Running' | sed 's/.*Ext-Net=//;s/,.*//') ;\
		SSHUSER=${OS_SSHUSER};\
	elif [ "${CLOUD}" == "EC2" ];then\
		EC2_SERVER_ID=$$(cat ${EC2_SERVER_FILE_ID});\
		HOST=$$(${AWS} ${EC2} describe-instances --instance-ids $$EC2_SERVER_ID |\
				jq -r ".Reservations[].Instances[].${EC2_IP}");\
		SSHUSER=${EC2_SSHUSER};\
	else\
		SCW_SERVER_ID=$$(cat ${SCW_SERVER_FILE_ID});\
		HOST=$$(curl -s ${SCW_API}/servers -H "X-Auth-Token: ${SCW_SECRET_TOKEN}" | jq -cr  ".servers[] | select (.id == \"$$SCW_SERVER_ID\") | .${SCW_IP}" ) ;\
		SSHUSER=${SCW_SSHUSER};\
	fi;\
		ssh ${SSHOPTS} $$SSHUSER@$$HOST ${MAKE} -C ${APP} all-step2 aws_access_key_id=${aws_access_key_id} aws_secret_access_key=${aws_secret_access_key} ${MAKEOVERRIDES};\
		ssh ${SSHOPTS} $$SSHUSER@$$HOST rm .aws/credentials;

remote-clean: ${CLOUD}-instance-delete

remote-all: full-check
	@if [ ! -f "no-remote" ];then\
		${MAKE} remote-config remote-step1 remote-watch remote-step2 remote-clean;\
	fi

