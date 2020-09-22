#!/bin/bash

set -e
set -x

function keep_alive() {
  while true; do
    echo -en "\a"
    sleep 300
  done
}
keep_alive &

OVFTOOL_MD5=$(docker run -it moander/ovftool md5sum /usr/local/bin/ovftool | cut -d ' ' -f 1)
if [ "$OVFTOOL_MD5" != "e521b64686d65de9e91288225b38d5da" ]; then
  echo ovftool md5 mismatch ... exiting
  exit 1
fi

IMAGE_NAME=ubuntu2004-$TRAVIS_BRANCH-$TRAVIS_BUILD_NUMBER
./packer build packer.json
openstack image save $IMAGE_NAME --file $IMAGE_NAME.qcow2

# Create container
openstack container create automium-catalog-images
swift post automium-catalog-images --read-acl ".r:*,.rlistings"

# Upload image for openstack to swift
mkdir openstack
ln $IMAGE_NAME.qcow2 openstack/$IMAGE_NAME.qcow2
swift upload automium-catalog-images openstack/$IMAGE_NAME.qcow2 &

# Create ova
qemu-img convert -f qcow2 -O vmdk $IMAGE_NAME.qcow2 automium-dummy.vmdk
docker run --rm -it -v $(pwd):/root moander/ovftool ovftool /root/dummy.vmx /root/$IMAGE_NAME.ova
sudo chmod o+r $IMAGE_NAME.ova

# Upload image for vsphere to swift
mkdir vsphere
mv $IMAGE_NAME.ova vsphere/$IMAGE_NAME.ova
swift upload automium-catalog-images vsphere/$IMAGE_NAME.ova &

# Wait vsphere image upload
wait %2

# Upload image for vcd to swift (link to vsphere)
touch temp && swift upload automium-catalog-images --object-name vcd/$IMAGE_NAME.ova -H "X-Object-Manifest: automium-catalog-images/vsphere/$IMAGE_NAME.ova" temp

# Wait openstack image upload
wait %3
