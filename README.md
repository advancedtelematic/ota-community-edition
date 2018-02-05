# OTA Community Edition

The OTA Community Edition is open-source server software to allow
over-the-air (OTA) updates of compatible clients (see the
[Aktualizr](https://github.com/advancedtelematic/aktualizr)
open-source example client). It is comprised of a number of services
which together make up the OTA system. The source code for the servers
is available on [Github](https://github.com/advancedtelematic) and is
licensed under the MPL2.0 (as is the code in this repository, see
below). Docker container images of the latest build are available on
[Docker Hub](https://hub.docker.com/u/advancedtelematic).

This repository contains scripts to launch the open-source OTA
Community Edition software under the
[Kubernetes](https://kubernetes.io/) orchestration system on a single
machine (minikube).

Note that the OTA Community Edition doesn't use authentication nor any
other security provision needed for a production system. It is meant
to run locally/inside of a firewall.

## Requirements

OTA needs at least 8GB of RAM to run.

The following software tools are required to run the scripts in the
current repository:

* [minikube](https://github.com/kubernetes/minikube)
* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) (version >= 1.8)
* [helm](https://github.com/kubernetes/helm/blob/master/docs/install.md) (version >= 2.8.0)
* [kops](https://github.com/kubernetes/kops) (version >= 1.8)
* [jq](https://stedolan.github.io/jq/)
* [httpie](https://httpie.org/)
* [VirtualBox](https://www.virtualbox.org/)

## Usage

The single entry point to the scripts is the `Makefile`.

It is self-documenting, run `make` to see a list of the available commands.

### Getting started

1. **Start all services**

   Run `make start` to start all services inside minikube.

2. **Update your hosts file**

   Run `make print-hosts` to print a list of entries to add to your `/etc/hosts` file.

3. **Visit the Admin User Interface**

   The Community Edition Admin UI should now be available to view in your browser at http://app.ota.local (by default).

### Admin interface

Run `minikube dashboard` to open the admin interface in your browser, which will be at http://192.168.99.100:30000 by default.

## Troubleshooting

Try re-running `make start` if you receive any of the following errors:

* `Unable to connect to the server: dial tcp 192.168.99.100:8443: getsockopt: operation timed out`
* `Error initializing Vault: Put http://127.0.0.1:8200/v1/sys/init: dial tcp 127.0.0.1:8200: getsockopt: connection refused`
* `ERROR 2002 (HY000): Can't connect to local MySQL server through socket '/var/run/mysqld/mysqld.sock' (2)`
* `error on line 12 of ota-community-edition/scripts/server.cnf
140680409176832:error:0EFFF068:configuration file routines:CRYPTO_internal:variable has no valu
e:conf/conf_def.c:563:line 12
error: error reading ota.ce/server.chain.pem: no such file or directory`

## License

This code is licensed under the [Mozilla Public License 2.0](LICENSE), a copy of which can be found in this repository. All code is copyright [ATS Advanced Telematic Systems GmbH](https://www.advancedtelematic.com), 2016-2018.
