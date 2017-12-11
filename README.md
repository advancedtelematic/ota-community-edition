# OTA Community Edition

## Requirements

The following tools are required:

* [minikube](https://github.com/kubernetes/minikube)
* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) (version >= 1.8)
* [kops](https://github.com/kubernetes/kops) (version >= 1.8)

## Getting started

### Start all services

Run `make start` to start all services on minikube, as well as creating all databases and unsealing vault.

### Update your hosts file

Run `make hosts` next to print a list of services to add to your `/etc/hosts` file.

### Visit OTA Community Edition Garage

The OTA Community Edition Garage should now be available to view in your browser at http://app.ota.local (by default).

### Admin interface

Run `minikube dashboard` to open the admin interface in your browser, which will be at http://192.168.99.100:30000 by default.

## Command line interface

Run `make` to see a list of the available Makefile commands, which are:

command | description
---|---
help | Print this message and exit.
start | Start minikube and all services.
start-minikube | Start local minikube environment.
start-services | Apply the generated config to the k8s cluster.
create-databases | Create all database tables and users.
unseal-vault | Automatically unseal the vault.
hosts | Print the service mappings for /etc/hosts
