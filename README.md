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
* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) (version >= 1.9)
* [kops](https://github.com/kubernetes/kops) (version >= 1.9)
* [jq](https://stedolan.github.io/jq/)
* [httpie](https://httpie.org/)
* [VirtualBox](https://www.virtualbox.org/)

## Usage

The single entry point to the scripts is the `Makefile`.

It is self-documenting, run `make` to see a list of the available commands.

### Getting started

1. **Start all services**

   Run `make start` to start all services inside minikube. See [troubleshooting](#troubleshooting) if it fails at first.

2. **Update your hosts file**

   OTA CE running in kubernetes has a single ingress point; it routes traffic to the appropriate pod/microservice based on the host name. That means that you need to either set up a DNS server pointing to the right place, or just edit your hosts file. We suggest going with the hosts file initially. Run `make print-hosts` to print a list of entries to add to your `/etc/hosts` file.

3. **Visit the Admin User Interface**

   The OTA Community Edition Admin UI should now be available to view in your browser at http://app.ota.local (by default).

4. (optional) **Forward ports in VirtualBox to make OTA CE accessible outside of localhost**

   Unless you're just testing on your local machine, you'll probably want to access OTA CE from somewhere else on your network. Assuming your minikube is using virtualbox as the backend (this is the default setup), you can use virtualbox to forward the relevant ports. To allow devices to connect, you'll need to forward port 30443, and to expose the Admin UI you'll need to forward port 80. You can do this from the command line:

```
# For the clients
vboxmanage controlvm "minikube" natpf1 "client_forwarding_rule,tcp,,30443,,30443"
# To access the UI
vboxmanage controlvm "minikube" natpf1 "adminui_forwarding_rule,tcp,,80,,80"
```

You will also need to modify the hosts file on any other computer that you want to use the Admin UI from. Note that the IP you give it won't be the minikube IP (normally 192.168.99.100); it will be the external IP address of the machine you are running minikube on. For example:

```
export OTA_CE_IP=external_ip_of_ota_machine
sudo cat <<EOF >> /etc/hosts
${OTA_CE_IP} app.ota.local
${OTA_CE_IP} gateway.ota.local
${OTA_CE_IP} treehub.ota.local
${OTA_CE_IP} tuf-reposerver.ota.local
${OTA_CE_IP} web-events.ota.local
EOF
```

### Admin interface

Run `minikube dashboard` to open minikube's admin interface in your browser, which will be at http://192.168.99.100:30000 by default.

## Create and connect a client

Clients can be built with Yocto. A complete guide to building a Yocto client is out of scope here, but you can follow the instructions for HERE OTA Connect to build a [QEMU](https://docs.atsgarage.com/quickstarts/qemuvirtualbox.html) or [Raspberry Pi](https://docs.atsgarage.com/quickstarts/raspberry-pi.html) client.

However, OTA Community Edition supports only [**implicit provisioning**](https://github.com/advancedtelematic/aktualizr/blob/master/docs/implicit-provisioning.adoc) of devices, instead of automatic provisioning as available in HERE OTA Connect/ATS Garage. In an implicit provisioning process, the device must be pre-loaded with provisioning credentials signed by a root CA that OTA CE trusts. As a part of the setup performed by `make start` (specifically, the `new_server` function), this root CA is generated and stored in the `ota.ce` directory. Additionally, a **credentials.zip** file is created. You will find it in `ota-community-edition/generated/ota.ce/credentials.zip` after running `make start`.

You must supply your yocto build with the credentials.zip, and specify that you want to use implicit provisioning. Add the following lines to the `local.conf` of your Yocto build:

    SOTA_CLIENT_PROV = "aktualizr-implicit-prov"
    SOTA_PACKED_CREDENTIALS = "/path/to/ota.ce/generated/credentials.zip"

Note that, if your build machine is different from the machine where minikube is running, you'll need to forward ports on the minikube machine and modify the build machine's hosts file as described above.

Once your build is complete and the device (virtual or real) is running, you can generate device credentials, register them, and copy them to the device with `make new-client`. You'll need to specify a device name, the IP and SSH port of the device, and the IP address of the OTA CE instance. For example, if your OTA CE machine is running at 192.168.1.99 and you've built a Raspberry Pi image that's running at 192.168.1.50, you could do the following:

```
export DEVICE_ID=raspberrypi_1
export DEVICE_ADDR=192.168.1.50
export DEVICE_PORT=22
export GATEWAY_ADDR=192.168.1.99
make new-client
```

This will also modify the hosts file on the client so it's able to connect.

## Troubleshooting

Try re-running `make start` if you receive any of the following errors:

* `Unable to connect to the server: dial tcp 192.168.99.100:8443: getsockopt: operation timed out`
* `Error initializing Vault: Put http://127.0.0.1:8200/v1/sys/init: dial tcp 127.0.0.1:8200: getsockopt: connection refused`
* `ERROR 2002 (HY000): Can't connect to local MySQL server through socket '/var/run/mysqld/mysqld.sock' (2)`
* `error on line 12 of ota-community-edition/scripts/server.cnf
140680409176832:error:0EFFF068:configuration file routines:CRYPTO_internal:variable has no valu
e:conf/conf_def.c:563:line 12
error: error reading ota.ce/server.chain.pem: no such file or directory`

If your device isn't connecting, verify that the virtualbox port forwarding of port 30443 is set up correctly.

## License

This code is licensed under the [Mozilla Public License 2.0](LICENSE), a copy of which can be found in this repository. All code is copyright [ATS Advanced Telematic Systems GmbH](https://www.advancedtelematic.com), 2016-2018.
