#!/bin/bash
#
# MIT License
#
# (C) Copyright 2023 Hewlett Packard Enterprise Development LP
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
# OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
# ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
# OTHER DEALINGS IN THE SOFTWARE.
#

# File name is a bit of a historical misnomer, this does upload executable
# ceph container images from a storage node to nexus, but it also changes what
# is running (so that those pushed images are actually used). It does this by
# modifying the /etc/containers/registry.conf file on the storage node to point
# to the nexus registry and then restarting the services.

nexus_username=$(kubectl get secret -n nexus nexus-admin-credential --template={{.data.username}} | base64 --decode)
nexus_password=$(kubectl get secret -n nexus nexus-admin-credential --template={{.data.password}} | base64 --decode)
ssh_options="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

function oneshot_health_check() {
  ceph_status=$(ceph health -f json-pretty | jq -r .status)
  if [[ $ceph_status != "HEALTH_OK" ]]; then
    echo "ERROR: Ceph is not healthy!"
    return 1
  fi
}

function wait_for_health_ok() {
  cnt=0
  cnt2=0
  while true; do
    if [[ -n "$node" ]] && [[ "$cnt" -eq 300 ]] ; then
      check_mon_daemon "${node}"
    else
      if [[ "$cnt" -eq 360 ]]; then
        echo "ERROR: Giving up on waiting for Ceph to become healthy..."
        break
      fi
      if [[ $(ceph crash ls-new -f json|jq -r '.|map(.crash_id)|length') -gt 0 ]]; then
        echo "archiving ceph crashes that may have been caused by restarts."
	ceph crash archive-all
      fi
      ceph_status=$(ceph health -f json-pretty | jq -r .status)
      if [[ $ceph_status == "HEALTH_OK" ]]; then
        echo "Ceph is healthy -- continuing..."
        break
      fi
    fi
    sleep 5
    echo "Sleeping for five seconds waiting for Ceph to be healthy..."
    cnt2=$((cnt2+1))
    if [[ $cnt2 -ge 10 ]]; then
      echo "Failing Ceph mgr daemon over to clear any stuck messages and sleeping 20 seconds."
      ceph mgr fail
      sleep 20
      cnt2=0
    fi
  done
} # end wait_for_health_ok()

function upload_image() {
    # get local image and nexus image location
    name=$1
    prefix=$2
    to_configure=$3
    local_image=$(ceph --name client.ro orch ps --format json | jq --arg DAEMON "$name" '.[] | select(.daemon_type == $DAEMON) | .container_image_name' | tr -d '"' | sort -u | tail -1)
    # if sha in image then remove and use version
    if [[ $local_image == *"@sha"* ]]; then
        without_sha=${local_image%"@sha"*}
        version=$(ceph --name client.ro orch ps --format json | jq --arg DAEMON "$name" '.[] | select(.daemon_type == $DAEMON) | .version' | tr -d '"' | sort -u)
        if [[ $version != "v"* ]]; then version="v""$version"; fi
        local_image="$without_sha"":""$version"
    fi
    nexus_location="${prefix}""$(echo "$local_image" | rev | cut -d "/" -f1 | rev)"

    # push images to nexus, point to nexus and run upgrade
    echo "Pushing image: $local_image to $nexus_location"
    podman pull "$local_image"
    podman tag "$local_image" "$nexus_location"
    podman push --creds "$nexus_username":"$nexus_password" "$nexus_location"
    ceph config set mgr $to_configure $nexus_location
} # end of upload_image()

function upload_monitoring_images() {
    # ceph_prefix is used with ceph and ceph-grafana
    ceph_prefix="registry.local/artifactory.algol60.net/csm-docker/stable/quay.io/ceph/"
    # prometheus_prefix is used with prometheus, node-exporter, and alertmanager
    prometheus_prefix="registry.local/artifactory.algol60.net/csm-docker/stable/quay.io/prometheus/"
    upload_image "prometheus" $prometheus_prefix "mgr/cephadm/container_image_prometheus"
    upload_image "node-exporter" $prometheus_prefix "mgr/cephadm/container_image_node_exporter"
    upload_image "alertmanager" $prometheus_prefix "mgr/cephadm/container_image_alertmanager"
    upload_image "grafana" $ceph_prefix "mgr/cephadm/container_image_grafana"
} # end of upload_monitoring_images()

function disable_local_registries() {
  echo "Disabling local docker registries"
  systemctl_force="--now"

  for storage_node in $(ceph orch host ls -f json |jq -r '.[].hostname'); do
    #shellcheck disable=SC2029
    if ssh "${storage_node}" ${ssh_options} "systemctl disable registry.container.service ${systemctl_force}"; then
       if ! ssh "${storage_node}" ${ssh_options} "systemctl is-enabled registry.container.service"; then
         echo "Docker registry service on ${storage_node} has been disabled"
       fi
    fi
  done
} # end of disable_local_registries()

function fix_registries_conf() {
  HEREFILE=$(mktemp)
  cat > "${HEREFILE}" <<'EOF'
# For more information on this configuration file, see containers-registries.conf(5).
#
# Registries to search for images that are not fully-qualified.
# i.e. foobar.com/my_image:latest vs my_image:latest
[registries.search]
registries = []
unqualified-search-registries = ["registry.local", "localhost"]

# Registries that do not use TLS when pulling images or uses self-signed
# certificates.
[registries.insecure]
registries = []
unqualified-search-registries = ["localhost", "registry.local"]

# Blocked Registries, blocks the  from pulling from the blocked registry.  If you specify
# "*", then the docker daemon will only be allowed to pull from registries listed above in the search
# registries.  Blocked Registries is deprecated because other container runtimes and tools will not use it.
# It is recommended that you use the trust policy file /etc/containers/policy.json to control which
# registries you want to allow users to pull and push from.  policy.json gives greater flexibility, and
# supports all container runtimes and tools including the docker daemon, cri-o, buildah ...
[registries.block]
registries = []

## ADD BELOW

[[registry]]
prefix = "registry.local"
location = "registry.local"
insecure = true

[[registry.mirror]]
prefix = "registry.local"
location = "localhost:5000"
insecure = true

[[registry]]
location = "localhost:5000"
insecure = true

[[registry]]
prefix = "localhost"
location = "localhost:5000"
insecure = true

[[registry]]
prefix = "artifactory.algol60.net/csm-docker/stable/quay.io"
location = "artifactory.algol60.net/csm-docker/stable/quay.io"
insecure = true

[[registry.mirror]]
prefix = "artifactory.algol60.net/csm-docker/stable/quay.io"
location = "registry.local/artifactory.algol60.net/csm-docker/stable/quay.io"
insecure = true

EOF

  for storage_node in $(ceph orch host ls -f json |jq -r '.[].hostname'); do
    scp ${ssh_options} "${HEREFILE}" "${storage_node}":/etc/containers/registries.conf
  done
} # end of fix_registries_conf()

function redeploy_monitoring_stack() {
# restart daemons
for daemon in "prometheus" "node-exporter" "alertmanager" "grafana"; do
  daemons_to_restart=$(ceph --name client.ro orch ps | awk '{print $1}' | grep $daemon)
  for each in $daemons_to_restart; do
    ceph orch daemon redeploy $each
  done
done
} # end of redeploy_monitoring_stack()

function upgrade_ceph() {
    current_ceph_version=$(ceph version --format json | jq '.version' | awk '{ print $3 }')
    upgrade_version=""
    if [[ $current_ceph_version == "15"* ]]; then
      upgrade_version="15.2.17"
    elif [[ $current_ceph_version == "16"* ]]; then
      upgrade_version="16.2.13"
    elif [[ $current_ceph_version == "17"* ]]; then
      upgrade_version="17.2.6"
    else
      echo "ERROR Ceph does not have major version 15,16, or 17. This script it only designed for these versions."
      exit 1
    fi
    # run the Ceph patch upgrade
    echo "Upgrading Ceph to $upgrade_version"
    ssh ncn-m001 ${ssh_options} "export PYTHONUNBUFFERED=1; /usr/share/doc/csm/upgrade/scripts/ceph/ceph-upgrade-tool.py --version $upgrade_version"
} # end of upgrade_ceph()

function check_daemons_running_nexus_image() {
    print=$1
    error=0
    for storage_node in $(ceph orch host ls -f json |jq -r '.[].hostname'); do
        running_images=$(ssh ${storage_node} ${ssh_options} 'podman ps --format {{.Image}} | sort -u')
        for each in $running_images; do
          if [[ $each != "registry.local/artifactory.algol60.net/csm-docker/"* ]]; then
            if $print; then
                echo "ERROR on $storage_node: a ceph daemon is running $each which is not an image in nexus."
            fi
            error=1
          fi
        done
    done
    if [[ $error == 1 ]]; then
        if $print; then
            echo "Try rerunning this script or manually redeploying daemons not running the nexus image onto the image in nexus."
        fi
        running_nexus=1
    else
        running_nexus=0
    fi
} # end of check_daemons_running_nexus_image()

function remove_local_images() {
    # this will remove all unused images on storage nodes
    for storage_node in $(ceph orch host ls -f json |jq -r '.[].hostname'); do
        ssh ${storage_node} ${ssh_options} "podman rmi --all"
    done
} # end remove_local_images()

#First check to make sure ceph is healthy prior to making any changes
if ! oneshot_health_check; then
  echo "Ceph is not healthy.  Please check ceph status and try again."
  exit 1
fi

# remove unneccessary entry in ceph config
ceph config rm mgr mgr/cephadm/container_image_base

# check if it is neccessary to move daemons to nexus
# they may be already using images in nexus
check_daemons_running_nexus_image false
if [[ $running_nexus == 1 ]]; then
    # redeploy monitoring stack
    upload_monitoring_images
    redeploy_monitoring_stack
    wait_for_health_ok

    # upgrade ceph to latest patch version
    upgrade_ceph
    check_daemons_running_nexus_image true
    if [[ $running_nexus == 1 ]]; then
        exit 1
    fi
else
    echo "Ceph daemons are already running container images from Nexus"
fi

fix_registries_conf

# stop local registry
disable_local_registries

# remove all local images that aren't in use
remove_local_images

echo "This process has been completed. All Ceph daemons should be using container images in Nexus and the local docker registry has been stopped."
