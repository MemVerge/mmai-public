#!/bin/bash

set -uo pipefail

ignore_errors=false

while getopts "i" option; do
    case $option in
        i ) ignore_errors=true;;
        * ) echo "Invalid option. Use -i to ignore errors."
    esac
done

if ! $ignore_errors; then
    set -e
fi

imports='
    common.sh
    logging.sh
    venv.sh
'
for import in $imports; do
    if ! curl -LfsSo $import https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/unified-setup/util/$import; then
        echo "Error getting script dependency: $import"
        exit 1
    fi
    source $import
done

MMAI_TEARDOWN_LOG_DIR="mmai-teardown-$(file_timestamp)"
mkdir -p $MMAI_TEARDOWN_LOG_DIR
LOG_FILE="$MMAI_TEARDOWN_LOG_DIR/mmai-teardown.log"
set_log_file $LOG_FILE

ensure_prerequisites

log_good "Script dependencies satisfied."

TEMP_DIR=$(mktemp -d)
cleanup() {
    dvenv || true
    rm -rf $TEMP_DIR
}
trap cleanup EXIT

cvenv $ANSIBLE_VENV || true
avenv $ANSIBLE_VENV
pip install -q ansible

log_good "venv $ANSIBLE_VENV set up."

################################################################################

remove_mmcai_cluster=false
remove_mmcai_manager=false
remove_cluster_resources=false
remove_billing_database=false
remove_memverge_secrets=false
remove_namespaces=false
remove_prometheus_crds_namespace=false
remove_nvidia_gpu_operator=false
remove_kubeflow=false

force_if_remove_cluster_resources=false

confirm_selection=false

# Sanity check.
log "Getting version to check connectivity."
if ! "$KUBECTL" version; then
    log_bad "Cannot proceed with teardown."
    exit 1
else
    log_good "Proceeding with teardown."
fi

# Determine if mmcai-cluster and mmcai-manager are installed.
if "$HELM" list -n mmcai-system -a -q | grep mmcai-cluster; then
    mmcai_cluster_detected=true
else
    mmcai_cluster_detected=false
    log "MMC.AI Cluster not detected."
fi

if "$HELM" list -n mmcai-system -a -q | grep mmcai-manager; then
    mmcai_manager_detected=true
else
    mmcai_manager_detected=false
    log "MMC.AI Manager not detected."
fi

################################################################################

# Remove mmcai-cluster?
if $mmcai_cluster_detected; then
    div
    if input_default_yn "Remove MMC.AI Cluster [y/N]:" n; then
        remove_mmcai_cluster=true
    else
        remove_mmcai_cluster=false
    fi
fi

if $remove_mmcai_cluster || ! $mmcai_cluster_detected; then
    no_mmcai_cluster=true
else
    no_mmcai_cluster=false
fi


# Remove mmcai-manager?
if $mmcai_manager_detected; then
    if $no_mmcai_cluster; then
        # mmcai-manager does not work without mmcai-cluster.
        echo "MMC.AI Manager does not work without MMC.AI Cluster. MMC.AI Manager will be removed."
        remove_mmcai_manager=true
    else
        div
        if input_default_yn "Remove MMC.AI Manager [y/N]:" n; then
            remove_mmcai_manager=true
        else
            remove_mmcai_manager=false
        fi
    fi
fi

if $remove_mmcai_manager || ! $mmcai_manager_detected; then
    no_mmcai_manager=true
else
    no_mmcai_manager=false
fi


if $no_mmcai_cluster; then
    # Remove cluster resources?
    div
    if ! $mmcai_cluster_detected; then
        echo_red "MMC.AI Cluster not detected. Removing cluster resources will require force. This may result in an unclean state."
        force_if_remove_cluster_resources=true
    fi

    echo_red "Caution: This will cause data loss!"
    if input_default_yn "Remove cluster resources (e.g. node groups, departments, projects, workloads) [y/N]:" n; then
        remove_cluster_resources=true
    else
        remove_cluster_resources=false
    fi

    if $remove_cluster_resources && $mmcai_cluster_detected; then
        if input_default_yn "Force? This may result in an unclean state [y/N]:" n; then
            force_if_remove_cluster_resources=true
        else
            force_if_remove_cluster_resources=false
        fi
    fi


    # Remove billing database?
    div
    echo_red "Caution: This will cause data loss!"
    if input_default_yn "Remove billing database [y/N]:" n; then
        remove_billing_database=true
    else
        remove_billing_database=false
    fi
    if $remove_billing_database; then
        echo "Provide an Ansible inventory of nodes (Ansible host group [$ANSIBLE_INVENTORY_DATABASE_NODE_GROUP]) to remove billing databases from."
        ANSIBLE_INVENTORY=''
        until [[ -e "$ANSIBLE_INVENTORY" ]]; do
            input "Ansible inventory: " ANSIBLE_INVENTORY
            if ! [[ -e "$ANSIBLE_INVENTORY" ]]; then
                log_bad "Path does not exist."
            fi
        done
    fi

    # Remove MemVerge image pull secrets?
    div
    if input_default_yn "Remove MemVerge image pull secrets [y/N]:" n; then
        remove_memverge_secrets=true
    else
        remove_memverge_secrets=false
    fi

    # Remove namespaces?
    if $remove_cluster_resources \
    && $remove_billing_database \
    && $remove_memverge_secrets
    then
        div
        echo_red "Caution: This is dangerous!"
        if input_default_yn "Remove MMC.AI namespaces [y/N]:" n; then
            remove_namespaces=true
        else
            remove_namespaces=false
        fi
    fi


    # Remove Prometheus CRDs and namespace?
    div
    echo_red "Caution: This is dangerous!"
    if input_default_yn "Remove Prometheus CRDs and namespace (MMC.AI included dependency) [y/N]:" n; then
        remove_prometheus_crds_namespace=true
    else
        remove_prometheus_crds_namespace=false
    fi


    # Remove NVIDIA GPU Operator?
    div
    echo_red "Caution: This is dangerous!"
    if input_default_yn "Remove NVIDIA GPU Operator (MMC.AI standalone dependency) [y/N]:" n; then
        remove_nvidia_gpu_operator=true
    else
        remove_nvidia_gpu_operator=false
    fi


    # Remove Kubeflow?
    div
    echo_red "Caution: This is dangerous!"
    if input_default_yn "Remove Kubeflow (MMC.AI standalone dependency) [y/N]:" n; then
        remove_kubeflow=true
    else
        remove_kubeflow=false
    fi
fi

################################################################################

div
echo "COMPONENT: REMOVE"
echo "MMC.AI Manager:" $remove_mmcai_manager
echo "MMC.AI Cluster:" $remove_mmcai_cluster
if $remove_cluster_resources && $force_if_remove_cluster_resources; then
    force_indication='(force)'
else
    force_indication=''
fi
echo "Cluster resources:" $remove_cluster_resources $force_indication
echo "Billing database:" $remove_billing_database
echo "MemVerge image pull secrets:" $remove_memverge_secrets
echo "MMC.AI namespaces:" $remove_namespaces
echo "Prometheus CRDs and namespace:" $remove_prometheus_crds_namespace
echo "NVIDIA GPU Operator:" $remove_nvidia_gpu_operator
echo "Kubeflow:" $remove_kubeflow

div
if input_default_yn "Confirm selection [y/N]:" n; then
    confirm_selection=true
else
    confirm_selection=false
fi

if ! $confirm_selection; then
    div
    log_good "Aborting..."
    exit 0
fi

div
log_good "Beginning teardown..."

################################################################################

if $remove_mmcai_manager; then
    div
    LOG_FILE="$MMAI_TEARDOWN_LOG_DIR/remove-mmcai-manager.log"
    set_log_file $LOG_FILE
    log_good "Removing MMC.AI Manager..."
    "$HELM" uninstall -n $RELEASE_NAMESPACE mmcai-manager --ignore-not-found --debug
fi

if $remove_cluster_resources; then
    div
    LOG_FILE="$MMAI_TEARDOWN_LOG_DIR/remove-cluster-resources.log"
    set_log_file $LOG_FILE
    log_good "Removing cluster resources..."

    cluster_resource_crds='
        admissionchecks.kueue.x-k8s.io
        clusterqueues.kueue.x-k8s.io
        localqueues.kueue.x-k8s.io
        multikueueclusters.kueue.x-k8s.io
        multikueueconfigs.kueue.x-k8s.io
        provisioningrequestconfigs.kueue.x-k8s.io
        resourceflavors.kueue.x-k8s.io
        workloadpriorityclasses.kueue.x-k8s.io
        workloads.kueue.x-k8s.io
        departments.mmc.ai
    '

    log "Requesting CRD deletion..."
    "$KUBECTL" delete crd $cluster_resource_crds --ignore-not-found &
    cluster_resource_crds_removed=$!

    if $force_if_remove_cluster_resources; then
        log "Force removing cluster resources..."
        for cluster_resource_crd in $cluster_resource_crds; do
            log "Removing $cluster_resource_crd resources..."

            if ! get_crd_output=$("$KUBECTL" get crd $cluster_resource_crd --ignore-not-found); then
                error_or_found=true
            elif [[ -z "$get_crd_output" ]]; then
                error_or_found=false
            else
                error_or_found=true
            fi

            while $error_or_found; do
                namespaces=$("$KUBECTL" get namespaces -o custom-columns=:.metadata.name)
                for namespace in $namespaces; do
                    if ! get_crd_output=$("$KUBECTL" get crd $cluster_resource_crd --ignore-not-found); then
                        error_or_found=true
                        log_bad "Unhandled error getting CRD $cluster_resource_crd. May loop infinitely."
                        sleep 1
                    elif [[ -z "$get_crd_output" ]]; then
                        error_or_found=false
                    else
                        error_or_found=true
                        # This should work for cluster-wide resources.
                        if ! resources=$("$KUBECTL" get -n $namespace $cluster_resource_crd -o custom-columns=:.metadata.name); then
                            log_bad "Unhandled error getting $cluster_resource_crd resources in namespace $namespace. May loop infinitely."
                            sleep 1
                        elif [[ -n "$resources" ]]; then
                            if ! "$KUBECTL" patch $cluster_resource_crd -n $namespace $resources --type json --patch='[{ "op": "remove", "path": "/metadata/finalizers" }]'; then
                                log_bad "Unhandled error patching $cluster_resource_crd resources in namespace $namespace. May loop infinitely."
                                sleep 1
                            fi
                        elif ! all_resources=$("$KUBECTL" get $cluster_resource_crd -A --ignore-not-found); then
                            log_bad "Unhandled error getting all $cluster_resource_crd resources in cluster. May loop infinitely."
                            sleep 1
                        elif [[ -z "$all_resources" ]]; then
                            log "No $cluster_resource_crd resources found. CRD should be removed soon. Otherwise, may loop infinitely."
                            sleep 1
                        fi
                    fi
                done
            done
        done
    fi

    # Get all mmc.ai labels attached to nodes
    node_labels=$("$KUBECTL" get nodes -o json | "$JQ" -r '.items[].metadata.labels | keys[]')
    if mmcai_labels=$(echo "$node_labels" | grep mmc.ai); then
        for label in $mmcai_labels; do
            "$KUBECTL" label nodes --all ${label}-
        done
    fi

    if ! wait $cluster_resource_crds_removed; then
        log_bad "Cluster resources may not have been removed successfully."
    fi

    for cluster_resource_crd in $cluster_resource_crds; do
        if ! get_crd_output=$("$KUBECTL" get crd $cluster_resource_crd --ignore-not-found); then
            log_bad "CRD $cluster_resource_crd may not have been removed successfully."
        elif [[ -n "$get_crd_output" ]]; then
            log_bad "CRD $cluster_resource_crd was not removed successfully."
        fi
    done
fi

if $remove_mmcai_cluster; then
    div
    LOG_FILE="$MMAI_TEARDOWN_LOG_DIR/remove-mmcai-cluster.log"
    set_log_file $LOG_FILE
    log_good "Removing MMC.AI Cluster..."
    echo "If you selected to remove cluster resources, disregard below messages that resources are kept due to the resource policy:"
    ## If no service account, run helm uninstall without the engine cleanup hook.
    if ! "$KUBECTL" get serviceaccount mmcloud-operator-controller-manager -n mmcloud-operator-system &> /dev/null; then
        log "Service account mmcloud-operator-controller-manager not found. Skipping mmcloud-engine cleanup Helm hook."
        "$HELM" uninstall --debug --no-hooks -n $RELEASE_NAMESPACE mmcai-cluster --ignore-not-found
    else
        "$HELM" uninstall --debug -n $RELEASE_NAMESPACE mmcai-cluster --ignore-not-found
        log "Performed uninstallation with mmcloud-engine cleanup Helm hook. On success, engines.mmcloud.io CRD should be removed irrespective of resource policy."
    fi
fi

if $remove_billing_database; then
    div
    LOG_FILE="$MMAI_TEARDOWN_LOG_DIR/remove-billing-database.log"
    set_log_file $LOG_FILE
    log_good "Removing billing database..."

    curl -LfsS https://raw.githubusercontent.com/MemVerge/mmc.ai-setup/unified-setup/playbooks/mysql-teardown-playbook.yaml | \
    ansible-playbook -i $ANSIBLE_INVENTORY /dev/stdin

    "$KUBECTL" delete secret -n $RELEASE_NAMESPACE mmai-mysql-secret --ignore-not-found
fi

if $remove_memverge_secrets; then
    div
    LOG_FILE="$MMAI_TEARDOWN_LOG_DIR/remove-memverge-secrets.log"
    set_log_file $LOG_FILE
    log_good "Removing MemVerge image pull secrets..."
    "$KUBECTL" delete secret -n $RELEASE_NAMESPACE memverge-dockerconfig --ignore-not-found
    "$KUBECTL" delete secret -n $MMCLOUD_OPERATOR_NAMESPACE memverge-dockerconfig --ignore-not-found
fi

if $remove_namespaces; then
    div
    LOG_FILE="$MMAI_TEARDOWN_LOG_DIR/remove-namespaces.log"
    set_log_file $LOG_FILE
    log_good "Removing MMC.AI namespaces..."
    "$KUBECTL" delete namespace $RELEASE_NAMESPACE --ignore-not-found
    "$KUBECTL" delete namespace mmcloud-operator-system --ignore-not-found
fi

if $remove_nvidia_gpu_operator; then
    div
    LOG_FILE="$MMAI_TEARDOWN_LOG_DIR/remove-nvidia-gpu-operator.log"
    set_log_file $LOG_FILE
    log_good "Removing NVIDIA GPU Operator..."

    # The order is important here.
    # NVIDIA GPU Operator Helm chart does not create an instance of this CRD so the CRD can be deleted first.
    "$KUBECTL" delete crd nvidiadrivers.nvidia.com --ignore-not-found

    if cluster_policies=$("$KUBECTL" get clusterpolicies -o custom-columns=:.metadata.name) \
    && [[ -n "$cluster_policies" ]]
    then
        if ! "$KUBECTL" delete clusterpolicies $cluster_policies --ignore-not-found; then
            log_bad "NVIDIA cluster policies may not have been removed successfully."
        fi
    fi

    "$HELM" uninstall --debug -n gpu-operator nvidia-gpu-operator --ignore-not-found
    "$KUBECTL" delete namespace gpu-operator --ignore-not-found

    # NVIDIA GPU Operator Helm chart creates an instance of this CRD so the CRD must be deleted after.
    "$KUBECTL" delete crd clusterpolicies.nvidia.com --ignore-not-found

    # NFD
    "$KUBECTL" delete crd nodefeatures.nfd.k8s-sigs.io --ignore-not-found
    "$KUBECTL" delete crd nodefeaturerules.nfd.k8s-sigs.io --ignore-not-found
fi

if $remove_prometheus_crds_namespace; then
    div
    LOG_FILE="$MMAI_TEARDOWN_LOG_DIR/remove-prometheus-crds-namespace.log"
    set_log_file $LOG_FILE
    log_good "Removing Prometheus CRDs and namespace..."
    prometheus_crds='
        alertmanagerconfigs.monitoring.coreos.com
        alertmanagers.monitoring.coreos.com
        podmonitors.monitoring.coreos.com
        probes.monitoring.coreos.com
        prometheusagents.monitoring.coreos.com
        prometheuses.monitoring.coreos.com
        prometheusrules.monitoring.coreos.com
        scrapeconfigs.monitoring.coreos.com
        servicemonitors.monitoring.coreos.com
        thanosrulers.monitoring.coreos.com
    '
    for crd in $prometheus_crds; do
        "$KUBECTL" delete crd $crd --ignore-not-found
    done
    "$KUBECTL" delete namespace $PROMETHEUS_NAMESPACE --ignore-not-found
fi

delete_kubeflow() {
    if "$KUBECTL" get profiles.kubeflow.org &> /dev/null && ! "$KUBECTL" delete profiles.kubeflow.org --all && "$KUBECTL" get profiles.kubeflow.org; then
        return 1
    fi
    "$KUBECTL" delete --ignore-not-found -f $TEMP_DIR/$KUBEFLOW_MANIFEST
}

if $remove_kubeflow; then
    div
    LOG_FILE="$MMAI_TEARDOWN_LOG_DIR/remove-kubeflow.log"
    set_log_file $LOG_FILE
    log_good "Removing Kubeflow..."

    build_kubeflow $TEMP_DIR

    attempts=5
    log "Deleting all Kubeflow resources..."
    log "Attempts remaining: $((attempts))"
    while (( attempts > 0 )) && ! delete_kubeflow; do
        attempts=$((attempts - 1))
        log "Kubeflow removal incomplete."
        log "Attempts remaining: $((attempts))"
        log "Waiting 15 seconds before attempt..."
        sleep 15
    done
    log "Kubeflow removed."
fi

div
log_good "Done!"
