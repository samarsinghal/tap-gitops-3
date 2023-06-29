#!/bin/bash

if [ $# -ne 1 ]; then
    echo "Usage: $0 gen-cert|prep|import-cli|import-packages|post-install"
    exit 1
fi

export INGRESS_DOMAIN=$(yq eval '.ingress_domain' ./gorkem/values.yaml)
export minioURL=minio.$INGRESS_DOMAIN
export HARBOR_URL=$(yq eval '.image_registry' ./gorkem/values.yaml)
export HARBOR_USERNAME=$(yq eval '.image_registry_user' ./gorkem/values.yaml)
export HARBOR_PASSWORD=$(yq eval '.image_registry_password' ./gorkem/values.yaml)
export HARBOR_TAP_REPO=$(yq eval '.image_registry_tap' ./gorkem/values.yaml)
export pivnet_token=$(yq eval '.pivnet_token' ./gorkem/values.yaml)
export IMGPKG_REGISTRY_HOSTNAME_0=registry.tanzu.vmware.com
export IMGPKG_REGISTRY_USERNAME_0=$(yq eval '.tanzuNet_username' gorkem/values.yaml)
export IMGPKG_REGISTRY_PASSWORD_0=$(yq eval '.tanzuNet_password' gorkem/values.yaml)
export IMGPKG_REGISTRY_HOSTNAME_1=$(yq eval '.image_registry' ./gorkem/values.yaml)
export IMGPKG_REGISTRY_USERNAME_1=$(yq eval '.image_registry_user' ./gorkem/values.yaml)
export IMGPKG_REGISTRY_PASSWORD_1=$(yq eval '.image_registry_password' ./gorkem/values.yaml)
export IMGPKG_REGISTRY_HOSTNAME=$(yq eval '.image_registry' ./gorkem/values.yaml)
export IMGPKG_REGISTRY_USERNAME=$(yq eval '.image_registry_user' ./gorkem/values.yaml)
export IMGPKG_REGISTRY_PASSWORD=$(yq eval '.image_registry_password' ./gorkem/values.yaml)
export TAP_VERSION=$(yq eval '.tap_version' ./gorkem/values.yaml)
export TBS_VERSION=$(yq eval '.tbs_version' ./gorkem/values.yaml)
yq eval '.ca_cert_data' ./gorkem/values.yaml | sed 's/^[ ]*//' > ./gorkem/ca.crt
export REGISTRY_CA_PATH="$(pwd)/gorkem/ca.crt"
export TAP_PKGR_REPO=$IMGPKG_REGISTRY_HOSTNAME_1/tap-packages/tap
pivnet login --api-token $pivnet_token
mkdir -p $HOME/tmp/
export TMPDIR="$HOME/tmp/"

# check the first parameter
if [ "$1" = "prep" ]; then
    echo "start prepping files...."

    mkdir -p airgapped-files/
    cd airgapped-files/
    
    echo "Downloading age"
    wget -q https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz && tar -xvf age-v1.1.1-linux-amd64.tar.gz
    
    echo "Downloading sops"
    wget -q https://github.com/mozilla/sops/releases/download/v3.7.3/sops-v3.7.3.linux.amd64 && chmod +x sops-v3.7.3.linux.amd64
    
    echo "Downloading pivnet"
    uname -s| grep Linux && wget -q https://github.com/pivotal-cf/pivnet-cli/releases/download/v3.0.1/pivnet-linux-amd64-3.0.1 && chmod +x pivnet-linux-amd64-3.0.1 && mv pivnet-linux-amd64-3.0.1 pivnet && cp pivnet /usr/local/bin/pivnet
    uname -s| grep Darwin && wget -q https://github.com/pivotal-cf/pivnet-cli/releases/download/v3.0.1/pivnet-darwin-amd64-3.0.1 && chmod +x pivnet-darwin-amd64-3.0.1 && mv pivnet-darwin-amd64-3.0.1 pivnet && cp pivnet /usr/local/bin/pivnet
    
    echo "Downloading charts-syncer"
    uname -s| grep Linux && wget -q https://github.com/bitnami-labs/charts-syncer/releases/download/v0.20.1/charts-syncer_0.20.1_linux_x86_64.tar.gz && tar -xvf charts-syncer_0.20.1_linux_x86_64.tar.gz && cp charts-syncer /usr/local/bin/charts-syncer
    uname -s| grep Darwin && wget -q https://github.com/bitnami-labs/charts-syncer/releases/download/v0.20.1/charts-syncer_0.20.1_darwin_x86_64.tar.gz && tar -xvf charts-syncer_0.20.1_darwin_x86_64.tar.gz && cp charts-syncer /usr/local/bin/charts-syncer
    
    echo "Downloading minio client"
    uname -s| grep Linux && wget -q https://dl.min.io/client/mc/release/linux-amd64/mc && chmod +x mc && cp mc /usr/local/bin/mc
    uname -s| grep Darwin && brew install minio/stable/mc
    
    echo "Downloading GitOps Ref. Implementation"
    pivnet download-product-files --product-slug='tanzu-application-platform' --release-version='1.5.2' --product-file-id=1467377
    
    echo "Downloading Cluster-Essentials"
    uname -s| grep Darwin && pivnet download-product-files --product-slug='tanzu-cluster-essentials' --release-version='1.5.2' --product-file-id=1460874
    uname -s| grep Linux && pivnet download-product-files --product-slug='tanzu-cluster-essentials' --release-version='1.5.2' --product-file-id=1460876
    
    # imgpkg binary check
    if ! command -v imgpkg >/dev/null 2>&1 ; then
      echo "installing imgpkg"
      tar -xvf tanzu-cluster-essentials*.tgz
      cp imgpkg /usr/local/bin/imgpkg
    fi
    
    echo "Downloading TAP Packages"
    imgpkg copy \
      -b registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:$TAP_VERSION \
      --to-tar tap-packages-$TAP_VERSION.tar \
      --include-non-distributable-layers \
      --concurrency 30
    
    echo "Downloading TBS Full Dependencies"
    imgpkg copy -b registry.tanzu.vmware.com/tanzu-application-platform/full-tbs-deps-package-repo:$TBS_VERSION \
      --to-tar=tbs-full-deps.tar --concurrency 30
    
    echo "Downloading Cluster Essentials"
    imgpkg copy \
      -b registry.tanzu.vmware.com/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:79abddbc3b49b44fc368fede0dab93c266ff7c1fe305e2d555ed52d00361b446 \
      --to-tar cluster-essentials-bundle-1.5.2.tar \
      --include-non-distributable-layers
    
    echo "Downloading Grype Vulnerability Definitions"
    wget -q https://toolbox-data.anchore.io/grype/databases/listing.json
    jq --arg v1 "$v1" '{ "available": { "1" : [.available."1"[0]] , "2" : [.available."2"[0]], "3" : [.available."3"[0]] , "4" : [.available."4"[0]] , "5" : [.available."5"[0]] } }' listing.json > listing.json.tmp
    mv listing.json.tmp listing.json
    wget -q $(cat listing.json |jq -r '.available."1"[0].url')
    wget -q $(cat listing.json |jq -r '.available."2"[0].url')
    wget -q $(cat listing.json |jq -r '.available."3"[0].url')
    wget -q $(cat listing.json |jq -r '.available."4"[0].url')
    wget -q $(cat listing.json |jq -r '.available."5"[0].url')
    sed -i -e "s|toolbox-data.anchore.io|$minioURL|g" listing.json
    
    echo "Downloading tool images"
    export tool_images=$(cat ../gorkem/templates/tools/*.yaml|grep "image: "|awk '{ print $2 }')
    mkdir -p images
    for image in $tool_images
    do
        echo $image
        export tool=$(echo $image | awk -F'/' '{print $(NF)}')
        imgpkg copy -i $image --to-tar=images/$tool.tar
        # do something with the image
    done

    git clone https://github.com/gorkemozlu/weatherforecast-steeltoe-net-tap && rm -rf weatherforecast-steeltoe-net-tap/.git
    git clone https://github.com/gorkemozlu/tanzu-java-web-app && rm -rf tanzu-java-web-app/.git
    git clone https://github.com/gorkemozlu/node-express && rm -rf node-express/.git
    git clone https://github.com/MoSehsah/bank-demo && rm -rf bank-demo/.git
    
    echo "Downloading Bitnami Catalog"
cat > 01-bitnami-to-local.yaml <<-EOF
source:
  repo:
    kind: HELM
    url: https://charts.app-catalog.vmware.com/demo
target:
  intermediateBundlesPath: bitnami-local
charts:
- redis
- mysql
- rabbitmq
- postgresql
EOF
    charts-syncer sync --config 01-bitnami-to-local.yaml --latest-version-only
    
    cd ..

elif [ "$1" = "import-cli" ]; then
    echo "start importing clis...."

    cd airgapped-files/
    # age
    if ! command -v age >/dev/null 2>&1 ; then
      echo "installing age"
      cp age/age /usr/local/bin/age && cp age/age-keygen /usr/local/bin/age-keygen
    fi
    
    # sops
    if ! command -v sops >/dev/null 2>&1 ; then
      echo "installing sops"
      cp sops-v3.7.3.linux.amd64 /usr/local/bin/sops
    fi
    
    # pivnet
    if ! command -v pivnet >/dev/null 2>&1 ; then
      echo "installing pivnet"
      cp pivnet-linux-amd64-3.0.1 /usr/local/bin/pivnet
    fi
    
    # kapp
    if ! command -v kapp >/dev/null 2>&1 ; then
      echo "installing kapp"
      tar -xvf tanzu-cluster-essentials*.tgz
      cp kapp /usr/local/bin/kapp
    fi
    
    # imgpkg
    if ! command -v imgpkg >/dev/null 2>&1 ; then
      echo "installing imgpkg"
      tar -xvf tanzu-cluster-essentials*.tgz
      cp imgpkg /usr/local/bin/imgpkg
    fi
    
    # mc
    if ! command -v mc >/dev/null 2>&1 ; then
      echo "installing mc"
      cp mc /usr/local/bin/mc
    fi
    
    cd ..

elif [ "$1" = "import-packages" ]; then
    echo "start importing files...."
    cp $REGISTRY_CA_PATH /etc/ssl/certs/tap-ca.crt
    curl -u "${HARBOR_USERNAME}:${HARBOR_PASSWORD}" -X POST -H "content-type: application/json" "https://${HARBOR_URL}/api/v2.0/projects" -d "{\"project_name\": \"${HARBOR_TAP_REPO}\", \"public\": true, \"storage_limit\": -1 }" -k
    curl -u "${HARBOR_USERNAME}:${HARBOR_PASSWORD}" -X POST -H "content-type: application/json" "https://${HARBOR_URL}/api/v2.0/projects" -d "{\"project_name\": \"tap-packages\", \"public\": true, \"storage_limit\": -1 }" -k
    curl -u "${HARBOR_USERNAME}:${HARBOR_PASSWORD}" -X POST -H "content-type: application/json" "https://${HARBOR_URL}/api/v2.0/projects" -d "{\"project_name\": \"bitnami\", \"public\": true, \"storage_limit\": -1 }" -k
    curl -u "${HARBOR_USERNAME}:${HARBOR_PASSWORD}" -X POST -H "content-type: application/json" "https://${HARBOR_URL}/api/v2.0/projects" -d "{\"project_name\": \"tools\", \"public\": true, \"storage_limit\": -1 }" -k

    cp airgapped-files/tanzu-gitops-ri-*.tgz .
    cp airgapped-files/tanzu-cluster-essentials*.tgz gorkem/
    
    imgpkg copy \
      --tar airgapped-files/tap-packages-$TAP_VERSION.tar \
      --to-repo $IMGPKG_REGISTRY_HOSTNAME_1/tap-packages/tap \
      --include-non-distributable-layers \
      --concurrency 30 \
      --registry-ca-cert-path $REGISTRY_CA_PATH
    
    imgpkg copy --tar airgapped-files/tbs-full-deps.tar \
      --to-repo=$IMGPKG_REGISTRY_HOSTNAME_1/tap-packages/tbs-full-deps --concurrency 30 --registry-ca-cert-path $REGISTRY_CA_PATH
    
    
    export KAPP_NS=$(kubectl get pods --all-namespaces -l app=kapp-controller -o jsonpath='{range .items[*]}{.metadata.namespace}{" "}{.status.phase}{"\n"}{end}'|awk '{print $1}')
    export KAPP_POD=$(kubectl get pods --all-namespaces -l app=kapp-controller -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'|awk '{print $1}')
    
    if [ -n "$KAPP_NS" ]; then
        echo "kapp is running, adding ca.cert"
        kubectl create secret generic kapp-controller-config \
           --namespace $KAPP_NS \
           --from-file caCerts=gorkem/ca.crt
        kubectl delete pod $KAPP_POD -n $KAPP_NS
    else
        echo "kapp is not running, therefore installing."
        kubectl create namespace kapp-controller
        kubectl create secret generic kapp-controller-config \
           --namespace kapp-controller \
           --from-file caCerts=gorkem/ca.crt
        imgpkg copy \
          --tar airgapped-files/cluster-essentials-bundle-1.5.2.tar \
          --to-repo $IMGPKG_REGISTRY_HOSTNAME_1/tap-packages/cluster-essentials-bundle \
          --include-non-distributable-layers \
          --registry-ca-cert-path $REGISTRY_CA_PATH
        export INSTALL_BUNDLE=$IMGPKG_REGISTRY_HOSTNAME_1/tap-packages/tanzu-cluster-essentials/cluster-essentials-bundle@sha256:79abddbc3b49b44fc368fede0dab93c266ff7c1fe305e2d555ed52d00361b446
        export INSTALL_REGISTRY_HOSTNAME=registry.tanzu.vmware.com
        export INSTALL_REGISTRY_USERNAME=$(yq eval '.tanzuNet_username' gorkem/values.yaml)
        export INSTALL_REGISTRY_PASSWORD=$(yq eval '.tanzuNet_password' gorkem/values.yaml)
        cd gorkem/tanzu-cluster-essentials
        ./install.sh --yes
        cd ../..
    fi

    cd airgapped-files/
cat > 02-bitnami-from-local.yaml <<-EOF
source:
  intermediateBundlesPath: bitnami-local
target:
  containerRegistry: $HARBOR_URL
  containerRepository: bitnami/containers
  containers:
    auth:
      username: admin
      password: VMware1!
  repo:
    kind: OCI
    url: https://$HARBOR_URL/bitnami/charts
    auth:
      username: $HARBOR_USERNAME
      password: $HARBOR_PASSWORD
EOF
    charts-syncer sync --config 02-bitnami-from-local.yaml
    cd ..

    export tool_images=$(cat gorkem/templates/tools/*.yaml|grep "image: "|awk '{ print $2 }')
    echo $tool_images
    for image in $tool_images
    do
        echo $image
        export tool=$(echo $image | awk -F'/' '{print $(NF)}')
        export tool_name=$(echo $tool | cut -d':' -f1)
        imgpkg copy \
          --tar airgapped-files/images/$tool.tar \
          --to-repo $IMGPKG_REGISTRY_HOSTNAME_1/tools/tools/$tool_name \
          --include-non-distributable-layers \
          --registry-ca-cert-path $REGISTRY_CA_PATH
        sed -i -e "s~$image~$IMGPKG_REGISTRY_HOSTNAME_1\/tools\/tools\/${tool}~g" gorkem/templates/tools/*.yaml
        rm -f gorkem/templates/tools/*.yaml-e
    done

elif [ "$1" = "post-install" ]; then

    export nexus_init_pass=$(kubectl exec -it $(kubectl get pod -n nexus -l app=nexus -o jsonpath='{.items[0].metadata.name}') -n nexus -- cat /nexus-data/admin.password)
    curl -u "admin:${nexus_init_pass}" -X 'PUT' "https://nexus-80.$INGRESS_DOMAIN/service/rest/v1/security/users/admin/change-password" -H 'accept: application/json' -H 'Content-Type: text/plain' -d ${HARBOR_PASSWORD} -k
    curl -u "admin:${HARBOR_PASSWORD}" -X 'PUT' "https://nexus-80.$INGRESS_DOMAIN/service/rest/v1/security/anonymous" -H 'accept: application/json' -H 'Content-Type: text/plain' -d '{"enabled": true, "userId": "anonymous", "realmName": "NexusAuthorizingRealm"}' -k
    curl -u "admin:${HARBOR_PASSWORD}" -X 'POST' "https://nexus-80.$INGRESS_DOMAIN/service/rest/v1/repositories/npm/proxy" -H 'accept: application/json' -H 'Content-Type: application/json' -d '{"name": "npm","online": true,"storage": {"blobStoreName": "default","strictContentTypeValidation": true,"writePolicy": "ALLOW"},"cleanup": null,"proxy": {"remoteUrl": "https://registry.npmjs.org","contentMaxAge": 1440,"metadataMaxAge": 1440},"negativeCache": {"enabled": true,"timeToLive": 1440},"httpClient": {"blocked": false,"autoBlock": true,"connection": {"retries": null,"userAgentSuffix": null,"timeout": null,"enableCircularRedirects": false,"enableCookies": false,"useTrustStore": false},"authentication": null},"routingRuleName": null,"npm": {"removeNonCataloged": false,"removeQuarantined": false},"format": "npm","type": "proxy"}' -k
    curl -u "admin:${HARBOR_PASSWORD}" -X 'POST' "https://nexus-80.$INGRESS_DOMAIN/service/rest/v1/security/users" -H 'accept: application/json' -H 'Content-Type: application/json' -d '{"userId": "tanzu","firstName": "tanzu","lastName": "tanzu","emailAddress": "tanzu@vmware.com","password": "VMware1!","status": "active","roles": ["nx-admin"]}' -k

    mc alias set minio https://$minioURL minio minio123 --insecure
    mc mb minio/grype --insecure
    mc cp airgapped-files/vulnerability*.tar.gz minio/grype/databases/ --insecure
    mc cp airgapped-files/listing.json minio/grype/databases/ --insecure
    mc anonymous set download minio/grype --insecure

elif [ "$1" = "gen-cert" ]; then
    mkdir -p cert/
    cd cert
    export DOMAIN=*.$INGRESS_DOMAIN
    
    export SUBJ="/C=TR/ST=Istanbul/L=Istanbul/O=Customer, Inc./OU=IT/CN=${DOMAIN}"
    openssl genrsa -des3 -out ca.key -passout pass:1234 4096
    openssl req -x509 -new -nodes -key ca.key -sha256 -days 1024 -passin pass:1234 -addext "keyUsage=critical, digitalSignature, cRLSign, keyCertSign" -addext "basicConstraints=critical,CA:true" -out ca.crt -subj "$SUBJ"
    openssl genrsa -out server-app.key 4096
    openssl req -sha512 -new \
          -subj "$SUBJ" \
          -key server-app.key \
          -out server-app.csr
cat > v3.ext <<-EOF
  authorityKeyIdentifier=keyid,issuer
  basicConstraints=CA:FALSE
  keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
  extendedKeyUsage = serverAuth
  subjectAltName = @alt_names
  [alt_names]
  DNS.1=${DOMAIN}
EOF
    openssl x509 -req -sha512 -days 3650 \
          -passin pass:1234 \
          -extfile v3.ext \
          -CA ca.crt -CAkey ca.key -CAcreateserial \
          -in server-app.csr \
          -out server-app.crt
    openssl rsa -in ca.key -out ca-no-pass.key -passin pass:1234
    cd ..
else
    echo "Invalid parameter: $1"
    exit 1
fi

