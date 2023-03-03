#!/bin/bash
curl -sfL https://get.k3s.io | sed -e 's/k3s-ci-builds.s3.amazonaws.com/s3.dualstack.us-east-1.amazonaws.com\/k3s-ci-builds/g' | INSTALL_K3S_COMMIT='${k3s_git_commit}' K3S_KUBECONFIG_MODE='${k3s_kubeconfig_mode}' K3S_TOKEN='${k3s_token}' sh -s - --docker --node-label=manager='true'

#GPU
if [ '${gpu}' -ne "0" ]; then
	sudo yum-config-manager --disable amzn2-graphics

	distribution=$(. /etc/os-release;echo $ID$VERSION_ID) \
		&& curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.repo | sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo

	sudo yum install -y nvidia-docker2

	# When running kubernetes with docker, edit the config file which is usually present at /etc/docker/daemon.json to set up nvidia-container-runtime as the default low-level runtime:
	sudo bash -c 'cat << EOF > /etc/docker/daemon.json
	{
			"default-runtime": "nvidia",
			"runtimes": {
					"nvidia": {
							"path": "/usr/bin/nvidia-container-runtime",
							"runtimeArgs": []
					}
			}
	}
EOF'

fi
sudo systemctl restart docker
sudo systemctl restart k3s.service

#GPU
if [ '${gpu}' -ne "0" ]; then
	export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
	kubectl create -f - <<EOF
# Copyright (c) 2019, NVIDIA CORPORATION.  All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nvidia-device-plugin-daemonset
  namespace: kube-system
spec:
  selector:
    matchLabels:
      name: nvidia-device-plugin-ds
  updateStrategy:
    type: RollingUpdate
  template:
    metadata:
      labels:
        name: nvidia-device-plugin-ds
    spec:
      tolerations:
      - key: nvidia.com/gpu
        operator: Exists
        effect: NoSchedule
      # Mark this pod as a critical add-on; when enabled, the critical add-on
      # scheduler reserves resources for critical add-on pods so that they can
      # be rescheduled after a failure.
      # See https://kubernetes.io/docs/tasks/administer-cluster/guaranteed-scheduling-critical-addon-pods/
      priorityClassName: "system-node-critical"
      containers:
      - image: kaenai/nvidia-k8s-device-plugin:v0.13.0
        name: nvidia-device-plugin-ctr
        env:
          - name: FAIL_ON_INIT_ERROR
            value: "false"
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
        volumeMounts:
        - name: device-plugin
          mountPath: /var/lib/kubelet/device-plugins
      volumes:
      - name: device-plugin
        hostPath:
          path: /var/lib/kubelet/device-plugins
EOF

fi