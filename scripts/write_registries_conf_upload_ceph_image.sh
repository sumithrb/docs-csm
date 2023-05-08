#!/bin/bash

# write registries.conf to a file
cat << EOF > /etc/containers/registries.conf
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
prefix = "localhost/quay.io"
location = "localhost:5000"
insecure = true

[[registry]]
prefix = "artifactory.algol60.net/csm-docker/stable/docker.io"
location = "artifactory.algol60.net/csm-docker/stable/docker.io"
insecure = true

[[registry.mirror]]
prefix = "artifactory.algol60.net/csm-docker/stable/docker.io"
location = "localhost:5000"
insecure = true

[[registry]]
prefix = "artifactory.algol60.net/csm-docker/stable/quay.io"
location = "artifactory.algol60.net/csm-docker/stable/quay.io"
insecure = true

[[registry.mirror]]
prefix = "artifactory.algol60.net/csm-docker/stable/quay.io"
location = "localhost:5000"
insecure = true

[[registry]]
location = "docker.io"
insecure = true

EOF

# upload current ceph image to nexus
m001_ip=$(host ncn-m001 | awk '{ print $NF }')
ssh-keygen -R ncn-m001 -f ~/.ssh/known_hosts > /dev/null 2>&1
ssh-keygen -R "${m001_ip}" -f ~/.ssh/known_hosts > /dev/null 2>&1
ssh-keyscan -H "ncn-m001,${m001_ip}" >> ~/.ssh/known_hosts

nexus_username=$(ssh ncn-m001 'kubectl get secret -n nexus nexus-admin-credential --template={{.data.username}} | base64 --decode')
nexus_password=$(ssh ncn-m001 'kubectl get secret -n nexus nexus-admin-credential --template={{.data.password}} | base64 --decode')

local_image=$(ceph --name client.ro orch ps --format json | jq '.[] | select(.daemon_type == "mgr") | .container_image_name' | tr -d '"' | sort -u | tail -1)
# if sha in image then remove and use version
if [[ $local_image == *"@sha"* ]]; then
    without_sha=${local_image%"@sha"*}
    version=$(ceph --name client.ro orch ps --format json | jq '.[] | select(.daemon_type == "mgr") | .version' | tr -d '"' | sort -u)
    if [[ $version != "v"* ]]; then version="v""$version"; fi
    local_image="$without_sha"":""$version"
fi

podman push --creds "$nexus_username":"$nexus_password" "$local_image"
podman pull $local_image

# copy /etc/containers/registries.conf to all storage nodes and pull ceph image from nexus
for storage_node in $(ceph orch host ls | grep ncn-s | awk '{print $1}'); do
    if [[ ${storage_node} != $(hostname) ]]; then
        scp /etc/containers/registries.conf ${storage_node}:/etc/containers/registries.conf
        ssh ${storage_node} "podman pull $local_image"
    fi
done
