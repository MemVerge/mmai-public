#!/bin/bash

source logging.sh

div
log "Welcome to the MMC.AI Kubeflow installer!"
log "First, setting sysctl variables across all hosts..."
div

cat > sysctl-playbook.yaml <<EOF
---
- name: Configure sysctl settings across all hosts
  hosts: all
  become: yes
  tasks:
    - name: Ensure sysctl configuration file exists
      ansible.builtin.file:
        path: /etc/sysctl.conf
        state: touch

    - name: Set fs.inotify.max_queued_events
      ansible.builtin.lineinfile:
        path: /etc/sysctl.conf
        regexp: '^fs.inotify.max_queued_events'
        line: 'fs.inotify.max_queued_events = 32384'
        create: yes

    - name: Set fs.inotify.max_user_instances
      ansible.builtin.lineinfile:
        path: /etc/sysctl.conf
        regexp: '^fs.inotify.max_user_instances'
        line: 'fs.inotify.max_user_instances = 4096'
        create: yes

    - name: Set fs.inotify.max_user_watches
      ansible.builtin.lineinfile:
        path: /etc/sysctl.conf
        regexp: '^fs.inotify.max_user_watches'
        line: 'fs.inotify.max_user_watches = 2008100'
        create: yes

    - name: Set net.core.somaxconn
      ansible.builtin.lineinfile:
        path: /etc/sysctl.conf
        regexp: '^net.core.somaxconn'
        line: 'net.core.somaxconn = 8192'
        create: yes

    - name: Apply sysctl changes
      ansible.builtin.sysctl:
        name: "{{ item.key }}"
        value: "{{ item.value }}"
        state: present
        reload: yes
      loop:
        - { key: 'fs.inotify.max_queued_events', value: '32384' }
        - { key: 'fs.inotify.max_user_instances', value: '4096' }
        - { key: 'fs.inotify.max_user_watches', value: '2008100' }
        - { key: 'net.core.somaxconn', value: '8192' }
EOF

ansible-playbook sysctl-playbook.yaml

div
log "Second, installing kubeflow..."
div

KUBEFLOW_VERSION='v1.9.0'
KUBEFLOW_ISTIO_VERSION='1.22'
KUBEFLOW_MANIFEST='kubeflow-manifest.yaml'

log "Cloning Kubeflow manifests..."
git clone https://github.com/kubeflow/manifests.git kubeflow --branch $KUBEFLOW_VERSION

# From DeepOps: Change the default Istio Ingress Gateway configuration to support NodePort for ease-of-use in on-prem
path_istio_version=${KUBEFLOW_ISTIO_VERSION#v}
path_istio_version=${path_istio_version//./-}
sed -i 's:ClusterIP:NodePort:g' "kubeflow/common/istio-$path_istio_version/istio-install/base/patches/service.yaml"

# From DeepOps: Make the Kubeflow cluster allow insecure http instead of https
# https://github.com/kubeflow/manifests#connect-to-your-kubeflow-cluster
sed -i 's:JWA_APP_SECURE_COOKIES=true:JWA_APP_SECURE_COOKIES=false:' "kubeflow/apps/jupyter/jupyter-web-app/upstream/base/params.env"
sed -i 's:VWA_APP_SECURE_COOKIES=true:VWA_APP_SECURE_COOKIES=false:' "kubeflow/apps/volumes-web-app/upstream/base/params.env"
sed -i 's:TWA_APP_SECURE_COOKIES=true:TWA_APP_SECURE_COOKIES=false:' "kubeflow/apps/tensorboard/tensorboards-web-app/upstream/base/params.env"

kustomize build kubeflow/example > $KUBEFLOW_MANIFEST

log "Applying all Kubeflow resources..."
while ! kubectl apply -f $KUBEFLOW_MANIFEST; do
    log "Kubeflow installation incomplete."
    log "Waiting 15 seconds before attempt..."
    sleep 15
done
log "Kubeflow installed."
