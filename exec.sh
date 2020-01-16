#!/usr/bin/env bash

started=$((docker inspect -f '{{.State.Running}}' matchid-tools > /dev/null 2>&1) || echo false)
if [ "$started" == "false" ];then \
	docker run --rm -d\
		--name matchid-tools\
		-v "$(pwd):/tools/data" \
		-v "$HOME/.aws/:/root/.aws"\
		matchid/tools;\
fi
if [ -p /dev/stdin ];then \
	cat /dev/stdin | docker exec -i matchid-tools "$@";\
else\
	docker exec -i matchid-tools "$@";
fi
