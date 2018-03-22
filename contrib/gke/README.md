# OTA Community Edition In Google Kubernetes Engine

## Build container

~~~
  ./contrib/gke/docker-build.sh
~~~

## Initialze gcloud Environment

A few commands need to be run to set up gcloud credentials:
~~~
 EXTRA_ARGS="-it" ./contrib/gke/gcloud auth login

 ./contrib/gke/gcloud config set project <YOUR PROJECT>
 ./contrib/gke/gcloud config set compute/zone us-central1-c
~~~

## Create Cluster

Create the k8s cluster with:
~~~
 ./contrib/gke/gcloud container clusters create ota-ce --machine-type n1-standard-2
 ./contrib/gke/gcloud container clusters get-credentials ota-ce
~~~

## Cleaning Up
The setup can be completed removed with:
~~~
  # delete the cluster
  ./contrib/gke/gcloud container clusters delete ota-ce --quiet
~~~
