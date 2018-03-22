#!/bin/sh -e

# ensure we execute from this directory
cd $(dirname $(readlink -f $0))

docker build -t otace-client .
