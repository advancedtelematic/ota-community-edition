# OTA Community Edition

## Requirements

The following tools are required:

* [minikube](https://github.com/kubernetes/minikube)
* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) (version >= 1.8)
* [kops](https://github.com/kubernetes/kops) (version >= 1.8)

## Usage

Run `make` to see a list of the available Makefile commands.

### Getting started

0. **Until all images are public...**

   Set the `DOCKER_USER` and `DOCKER_PASS` environment variables for pulling the private ATS images.

1. **Start all services**

   Run `make start` to start all services inside minikube. *n.b. you will need 8GB of free RAM*

2. **Update your hosts file**

   Run `make hosts` to print a list of entries to add to your `/etc/hosts` file.

3. **Visit the garage**

   The Community Edition Garage should now be available to view in your browser at http://app.ota.local (by default).

### Admin interface

Run `minikube dashboard` to open the admin interface in your browser, which will be at http://192.168.99.100:30000 by default.

## Troubleshooting

Try re-running `make start` if you receive any of the following errors:

* `Unable to connect to the server: dial tcp 192.168.99.100:8443: getsockopt: operation timed out`
