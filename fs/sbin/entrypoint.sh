#! /usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
source /sbin/hdfs-lib.sh
source /sbin/accumulo-lib.sh

# Run in all cases
sed -i.bak "s/{HADOOP_MASTER_ADDRESS}/${HADOOP_MASTER_ADDRESS}/g" ${HADOOP_CONF_DIR}/core-site.xml
sed -i.bak \
  -e "s/{HADOOP_MASTER_ADDRESS}/${HADOOP_MASTER_ADDRESS}/g" \
  -e "s/{ACCUMULO_ZOOKEEPERS}/${ACCUMULO_ZOOKEEPERS}/g" \
  -e "s/{ACCUMULO_SECRET}/${ACCUMULO_SECRET}/g" \
  -e "s/{ACCUMULO_PASSWORD}/${ACCUMULO_PASSWORD}/g" \
  ${ACCUMULO_CONF_DIR}/accumulo-site.xml

# The first argument determines this container's role in the accumulo cluster
ROLE=${1:-}
if [ -z $ROLE ]; then
  echo "Select the role for this container with the docker cmd 'master', 'monitor', 'gc', 'tracer', or 'tserver'"
  exit 1
else
  case $ROLE in
    "master" | "tserver" | "monitor" | "gc" | "tracer")
      ATTEMPTS=7 # ~2 min before timeout failure
      wait_until_port_open ${ACCUMULO_ZOOKEEPERS} 2181 || exit 1
      wait_until_port_open ${HADOOP_MASTER_ADDRESS} 8020 || exit 1
      wait_until_hdfs_is_available || exit 1

      USER=${USER:-root}
      ensure_user $USER
      echo "Running as $USER"

      if [[ ($ROLE = "master") && (${2:-} = "--auto-init")]]; then
        set +e
        accumulo info
        if [[ $? != 0 ]]; then
          echo "Initilizing accumulo instance ${INSTANCE_NAME} at hdfs://${HADOOP_MASTER_ADDRESS}/accumulo ..."
          runuser -p -u $USER hdfs -- dfs -mkdir -p /accumulo-classpath
          runuser -p -u $USER accumulo -- init --instance-name ${INSTANCE_NAME} --password ${ACCUMULO_PASSWORD}
        else
          echo "Found accumulo instance at hdfs://${HADOOP_MASTER_ADDRESS}/accumulo ..."
        fi
        set -e
      else
        with_backoff hdfs dfs -test -d /accumulo
        if [ $? != 0 ]; then
          echo "Accumulo not initilized before timeout. Exiting ..."
          exit 1
        fi
      fi
      exec runuser -p -u $USER accumulo -- $ROLE ;;
    *)
      exec "$@"
  esac
fi
