#!/bin/sh -e

echo "Install gcloud and kubectl"
mkdir -p /opt && cd /opt
curl https://dl.google.com/dl/cloudsdk/channels/rapid/google-cloud-sdk.zip >sdk.zip
unzip sdk.zip && rm sdk.zip
google-cloud-sdk/install.sh --additional-components alpha beta gsutil kubectl

ln -s /opt/google-cloud-sdk/bin/gcloud /usr/local/bin/
ln -s /opt/google-cloud-sdk/bin/kubectl /usr/local/bin/
ln -s /root/.config/gcloud/kube-config /root/.kube


echo "Installing kops"
cd /tmp
curl -LO https://github.com/kubernetes/kops/releases/download/$(curl -s https://api.github.com/repos/kubernetes/kops/releases/latest | grep tag_name | cut -d '"' -f 4)/kops-linux-amd64
chmod +x kops-linux-amd64
mv kops-linux-amd64 /usr/local/bin/kops
