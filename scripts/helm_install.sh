#!/usr/bin/env bash

set -euo pipefail

declare HELM_VERSION='v2.8.0'
declare HELM_BIN='/usr/local/bin/helm'
declare ERR_HELM_DOWNLOAD="Error: Couldn't fetch HELM package"
declare ERR_HELM_EXTRACT="Error: Couldn't extract HELM package under /tmp"
declare ERR_HELM_VERIFY="Error: Couldn't verify 'helm version'"

function get_arch()
{
  ARCH=`arch`
  if [ $ARCH == 'x86_64' ]
  then
    HELM_ARCH='linux-amd64'
  fi
}

function get_helm()
{
  curl --silent --output /tmp/helm.tgz https://storage.googleapis.com/kubernetes-helm/helm-${HELM_VERSION}-${HELM_ARCH}.tar.gz
  if [ $? != 0 ]; then
    echo ${ERR_HELM_DOWNLOAD} && exit 1;
  fi
}

function extract_helm()
{
  mkdir -p /tmp/helm && tar -xzf /tmp/helm.tgz -C /tmp/helm && \
        sudo cp /tmp/helm/${HELM_ARCH}/helm ${HELM_BIN}
  if [ $? != 0 ]; then
    echo ${ERR_HELM_EXTRACT} && exit 1;
  fi
}

function verify_helm()
{
  ${HELM_BIN} version > /dev/null 2>&1
  if [ $? != 0 ]; then
    echo ${ERR_HELM_VERIFY} && exit 1;
  fi
}

get_arch && get_helm && verify_helm
