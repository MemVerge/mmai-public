#!/bin/bash

source logging.sh

## welcome message

div
log "Welcome to MMC.AI setup!"
div

NAMESPACE="mmcai-system"

while getopts "f:" opt; do
  case $opt in
    f)
        MMCAI_GHCR_SECRET="$OPTARG"
        ;;
    \?)
        div
        log_bad "Invalid option: -$OPTARG" >&2
        usage
        exit 1
        ;;
    :)
        div
        log_bad "Option -$OPTARG requires an argument." >&2
        usage
        exit 1
        ;;
  esac
done

if [ -z "$MMCAI_GHCR_SECRET" ]; then
    log_bad "Please provide a path to mmcai-ghcr-secret.yaml."
    usage
    exit 1
fi

div
log_good "Please provide information for billing database:"
div

read -p "MySQL database node hostname: " mysql_node_hostname
read -sp "MySQL root password: " MYSQL_ROOT_PASSWORD
echo ""

div
log_good "Creating directories for billing database:"
div

wget -O mysql-pre-setup.sh https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/main/mysql-pre-setup.sh
chmod +x mysql-pre-setup.sh
./mysql-pre-setup.sh

div
log_good "Creating namespaces if needed..."
div

if [[ -f "mmcai-ghcr-secret.yaml" ]]; then
    kubectl apply -f mmcai-ghcr-secret.yaml
else
    kubectl create ns $NAMESPACE
    kubectl create ns mmcloud-operator-system
fi

## Create monitoring namespace

kubectl get namespace monitoring &>/dev/null || kubectl create namespace monitoring

div
log_good "Creating secrets if needed..."
div

## Create MySQL secret

kubectl -n $NAMESPACE get secret mmai-mysql-secret &>/dev/null || \
# While we only need mysql-root-password, all of these keys are necessary for the secret according to the mysql Helm chart documentation
kubectl -n $NAMESPACE create secret generic mmai-mysql-secret \
    --from-literal=mysql-root-password=$MYSQL_ROOT_PASSWORD \
    --from-literal=mysql-password=$MYSQL_ROOT_PASSWORD \
    --from-literal=mysql-replication-password=$MYSQL_ROOT_PASSWORD

div
log_good "Beginning installation..."
div

## install mmc.ai system
helm install --debug -n $NAMESPACE mmcai-cluster oci://ghcr.io/memverge/charts/mmcai-cluster \
    --set billing.database.nodeHostname=$mysql_node_hostname

## install mmc.ai management
helm install --debug -n $NAMESPACE mmcai-manager oci://ghcr.io/memverge/charts/mmcai-manager
