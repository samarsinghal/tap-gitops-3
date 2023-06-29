#!/bin/bash

# Get the Kubernetes server version
SERVER_VERSION=$(kubectl version --short | awk -Fv '/Server Version: /{print substr($3,0,4)}')

#check if kubernetes version is retrieved.
if [ -z "$SERVER_VERSION" ]; then
  echo "Error: Failed to retrieve Kubernetes server version"
  exit 1
fi

# Check if the server version is less than 1.24
if (( $(echo "$SERVER_VERSION < 1.24" | bc -l) )); then
  echo "Kubernetes server version is less than 1.24"
  echo "For TAP1.5, you must have minimum k8s 1.24"
  exit 1
fi

# age
if ! command -v age >/dev/null 2>&1 ; then
  echo "age not installed. Use below to install"
  echo "brew install age"
  echo "or"
  echo "wget https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz && tar -xvf age-v1.1.1-linux-amd64.tar.gz && cp age/age /usr/local/bin/age && cp age/age-keygen /usr/local/bin/age-keygen"
  echo "Exiting...."
  exit 1
fi


# sops
if ! command -v sops >/dev/null 2>&1 ; then
  echo "sops not installed. Use below to install"
  echo "brew install sops"
  echo "or"
  echo "wget https://github.com/mozilla/sops/releases/download/v3.7.3/sops-v3.7.3.linux.amd64 && chmod +x sops-v3.7.3.linux.amd64 && mv sops-v3.7.3.linux.amd64 sops && cp sops /usr/local/bin/sops"
  echo "Exiting...."
  exit 1
fi

# pivnet
if ! command -v pivnet >/dev/null 2>&1 ; then
  echo "pivnet not installed. Use below to install"
  echo "uname -s| grep Darwin && wget https://github.com/pivotal-cf/pivnet-cli/releases/download/v3.0.1/pivnet-darwin-amd64-3.0.1 && chmod +x pivnet-darwin-amd64-3.0.1 && mv pivnet-darwin-amd64-3.0.1 pivnet && cp pivnet /usr/local/bin/pivnet"
  echo "uname -s| grep Linux && wget https://github.com/pivotal-cf/pivnet-cli/releases/download/v3.0.1/pivnet-linux-amd64-3.0.1 && chmod +x pivnet-linux-amd64-3.0.1 && mv pivnet-linux-amd64-3.0.1 pivnet && cp pivnet /usr/local/bin/pivnet"
  echo "pivnet login --api-token xyz"
  echo "Exiting...."
  exit 1
fi

# kapp
if ! command -v kapp >/dev/null 2>&1 ; then
  echo "kapp not installed. Use below to install"
  echo "uname -s| grep Darwin && wget https://github.com/carvel-dev/kapp/releases/download/v0.55.0/kapp-darwin-amd64 && chmod +x kapp-darwin-amd64 && mv kapp-darwin-amd64 kapp && cp kapp /usr/local/bin/kapp"
  echo "uname -s| grep Linux && wget https://github.com/carvel-dev/kapp/releases/download/v0.55.0/kapp-linux-amd64 && chmod +x kapp-linux-amd64 && mv kapp-linux-amd64 kapp && cp kapp /usr/local/bin/kapp"
  echo "Exiting...."
  exit 1

fi

# imgpkg
if ! command -v imgpkg >/dev/null 2>&1 ; then
  echo "imgpkg not installed. Use below to install"
  echo "uname -s| grep Darwin && wget https://github.com/carvel-dev/imgpkg/releases/download/v0.31.3/imgpkg-darwin-amd64 && chmod +x imgpkg-darwin-amd64 && cp imgpkg-darwin-amd64 /usr/local/bin/imgpkg"
  echo "uname -s| grep Linux && wget https://github.com/carvel-dev/imgpkg/releases/download/v0.31.3/imgpkg-linux-amd64 && chmod +x imgpkg-linux-amd64 && cp imgpkg-linux-amd64 /usr/local/bin/imgpkg"
  echo "Exiting...."
  exit 1
fi

# minio mc client
if ! command -v mc >/dev/null 2>&1 ; then
  echo "mc not installed. Use below to install"
  echo "uname -s| grep Darwin && wget https://dl.min.io/client/mc/release/darwin-amd64/mc && chmod +x mc && cp mc /usr/local/bin/mc"
  echo "uname -s| grep Linux && wget https://dl.min.io/client/mc/release/linux-amd64/mc && chmod +x mc && cp mc /usr/local/bin/mc"
  echo "Exiting...."
  exit 1
fi

if [ -f tanzu-gitops-ri-*.tgz ] && [ -f gorkem/values.yaml ]; then
    echo "required files exist, continuing."
else
    echo "check tanzu-gitops-ri-*.tgz and/or gorkem/values.yaml do not exist."
    exit 1
fi


rm -rf .git
rm -rf .catalog
rm -rf clusters
rm -rf setup-repo.sh

# GitOps Ref. Implementation
tar -xvf tanzu-gitops-ri-*.tgz
./setup-repo.sh full-profile sops

#cp ./gorkem/templates/values-template.yaml ./gorkem/values.yaml

kubectl create clusterrolebinding default-tkg-admin-privileged-binding --clusterrole=psp:vmware-system-privileged --group=system:authenticated

export AIRGAPPED=$(yq eval '.airgapped' gorkem/values.yaml)

export KAPP_NS=$(kubectl get pods --all-namespaces -l app=kapp-controller -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.status.phase}{"\n"}{end}'|awk '{print $1}')
export KAPP_POD=$(kubectl get pods --all-namespaces -l app=kapp-controller -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'|awk '{print $1}')

if [ -n "$KAPP_NS" ]; then
    echo "kapp is running"
else
    echo "kapp is not running, therefore installing."
    export INSTALL_BUNDLE=registry.tanzu.vmware.com/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:79abddbc3b49b44fc368fede0dab93c266ff7c1fe305e2d555ed52d00361b446
    export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
    export INSTALL_REGISTRY_USERNAME=$(yq eval '.tanzuNet_username' gorkem/values.yaml)
    export INSTALL_REGISTRY_PASSWORD=$(yq eval '.tanzuNet_password' gorkem/values.yaml)
    
    cd gorkem/tanzu-cluster-essentials
    ./install.sh --yes
    cd ../..
fi

# setup sops key
sops_age_file="./gorkem/tmp-enc/key.txt"

if [ -e "$sops_age_file" ]; then
  echo "The file '$sops_age_file' exists. Continuing"
else
  echo "The file '$sops_age_file' does not exist."
  mkdir -p ./gorkem/tmp-enc
  chmod 700 ./gorkem/tmp-enc
  age-keygen -o ./gorkem/tmp-enc/key.txt
fi

export SOPS_AGE_RECIPIENTS=$(cat ./gorkem/tmp-enc/key.txt | grep "# public key: " | sed 's/# public key: //')
export HARBOR_USERNAME=$(yq eval '.image_registry_user' ./gorkem/values.yaml)
export HARBOR_PASSWORD=$(yq eval '.image_registry_password' ./gorkem/values.yaml)
export HARBOR_URL=$(yq eval '.image_registry' ./gorkem/values.yaml)

cat > ./gorkem/tmp-enc/tap-sensitive-values.yaml <<-EOF
---
tap_install:
  sensitive_values:
    shared:
      image_registry:
        username: $HARBOR_USERNAME
        password: $HARBOR_PASSWORD
    buildservice:
      kp_default_repository_password: $HARBOR_PASSWORD
EOF

sops --encrypt ./gorkem/tmp-enc/tap-sensitive-values.yaml > ./gorkem/tmp-enc/tap-sensitive-values.sops.yaml
mv ./gorkem/tmp-enc/tap-sensitive-values.sops.yaml ./clusters/full-profile/cluster-config/values

ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/custom-schema-template.yaml > ./clusters/full-profile/cluster-config/config/custom-schema.yaml
cp ./gorkem/templates/acs.yaml ./clusters/full-profile/cluster-config/config/acs.yaml
cp ./gorkem/templates/scg.yaml ./clusters/full-profile/cluster-config/config/scg.yaml

if [ "$AIRGAPPED" = "true" ]; then
  echo "samar inside if"
  export IMGPKG_REGISTRY_HOSTNAME_1=$(yq eval '.image_registry' ./gorkem/values.yaml)
  export TAP_PKGR_REPO=$IMGPKG_REGISTRY_HOSTNAME_1/tap-packages/tap
  echo $TAP_PKGR_REPO
  cp ./gorkem/templates/tbs-full-deps.yaml ./clusters/full-profile/cluster-config/config/tbs-full-deps.yaml
  export multi_line_text="#@data/values-schema\n#@overlay/match-child-defaults missing_ok=True\n---"
  echo -e "$multi_line_text" | cat - ./clusters/full-profile/cluster-config/config/custom-schema.yaml > temp && mv temp ./clusters/full-profile/cluster-config/config/custom-schema.yaml
fi
ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/tap-non-sensitive-values-template.yaml > ./clusters/full-profile/cluster-config/values/tap-values.yaml

export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
export INSTALL_REGISTRY_USERNAME=$(yq eval '.tanzuNet_username' ./gorkem/values.yaml)
export INSTALL_REGISTRY_PASSWORD=$(yq eval '.tanzuNet_password' ./gorkem/values.yaml)
export GIT_SSH_PRIVATE_KEY=$(cat $HOME/.ssh/id_rsa &>/dev/null || ssh-keygen -b 2048 -t rsa -f /$HOME/.ssh/id_rsa -q -N "" && cat $HOME/.ssh/id_rsa)
export GIT_KNOWN_HOSTS=$(ssh-keyscan github.com)
export SOPS_AGE_KEY=$(cat ./gorkem/tmp-enc/key.txt)


git init && git add . && git commit -m "Big Bang" && git branch -M main
git remote add origin https://github.com/samarsinghal/tap-gitops-3.git
git push -u origin main

echo "Git commit complete"


cd ./clusters/full-profile
./tanzu-sync/scripts/configure.sh
cd ../../

echo "configure.sh complete"

tanzu secret registry add registry-credentials --username $HARBOR_USERNAME --password $HARBOR_PASSWORD --server $HARBOR_URL --namespace default --export-to-all-namespaces

echo "Secret Updated"

if [ "$AIRGAPPED" = "true" ]; then
  export GIT_REPO=https://$(yq eval '.git_repo' gorkem/values.yaml)
  export GIT_USER=$(yq eval '.git_user' gorkem/values.yaml)
  export GIT_PASS=$(yq eval '.git_password' gorkem/values.yaml)
  export CA_CERT=$(yq eval '.ca_cert_data' ./gorkem/values.yaml)
  export INGRESS_DOMAIN=$(yq eval '.ingress_domain' ./gorkem/values.yaml)
  mkdir -p ./clusters/full-profile/cluster-config/dependant-resources/tools
cat > ./clusters/full-profile/cluster-config/dependant-resources/tools/workload-git-auth.yaml <<-EOF
apiVersion: v1
kind: Secret
metadata:
  name: workload-git-auth
  namespace: tap-install
type: Opaque
stringData:
  content.yaml: |
    git:
      ingress_domain: $INGRESS_DOMAIN
      host: $GIT_REPO
      username: $GIT_USER
      password: $GIT_PASS
      caFile: |
$(echo "$CA_CERT" | sed 's/^/        /')
EOF
  
  export remote_branch_=$( git status --porcelain=2 --branch | grep "^# branch.upstream" | awk '{ print $3 }' )
  export remote_name_=$( echo $remote_branch_ | awk -F/ '{ print $1 }' )
  export remote_url_=$( git config --get remote.${remote_name_}.url )
  ytt --ignore-unknown-comments --data-value git_push_repo=$remote_url_ -f gorkem/templates/dependant-resources-app.yaml > clusters/full-profile/cluster-config/config/dependant-resources-app.yaml
  
  # ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/tools/local-issuer.yaml > clusters/full-profile/cluster-config/dependant-resources/tools/local-issuer.yaml
  ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/tools/gitea.yaml > clusters/full-profile/cluster-config/dependant-resources/tools/gitea.yaml
  ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/tools/nexus.yaml > clusters/full-profile/cluster-config/dependant-resources/tools/nexus.yaml
  ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/tools/minio.yaml > clusters/full-profile/cluster-config/dependant-resources/tools/minio.yaml
  ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/tools/crossplane-ca.yaml > clusters/full-profile/cluster-config/dependant-resources/tools/crossplane-ca.yaml
  mkdir -p ./gorkem/templates/overlays/ && cp -r ./gorkem/templates/overlays/ clusters/full-profile/cluster-config/dependant-resources/overlays
  #cp ./gorkem/templates/tools/external-secrets.yaml clusters/full-profile/cluster-config/dependant-resources/tools/external-secrets.yaml
  #ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/tools/vault.yaml > clusters/full-profile/cluster-config/dependant-resources/tools/vault.yaml
fi
cp ./gorkem/templates/tools/openldap.yaml clusters/full-profile/cluster-config/dependant-resources/tools/openldap.yaml
ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/tools/dex.yaml > clusters/full-profile/cluster-config/dependant-resources/tools/dex.yaml
ytt --ignore-unknown-comments -f ./gorkem/values.yaml -f ./gorkem/templates/tools/efk.yaml > clusters/full-profile/cluster-config/dependant-resources/tools/efk.yaml

cd ./clusters/full-profile

git add ./cluster-config/ ./tanzu-sync/
git commit -m "Configure install of TAP 1.5.2"
git push

echo "run deploy.sh"
./tanzu-sync/scripts/deploy.sh