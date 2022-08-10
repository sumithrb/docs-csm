# Pre-Boot Configuration of NCN Images

**NOTE:** Some of the documentation linked from this page mentions use of the Boot Orchestration Service (BOS). The use of BOS
is only relevant for booting compute nodes and can be ignored when working with NCN images.

This document describes the configuration of a Kubernetes NCN image. The same steps are relevant for modifying
a Ceph image.

1. (`ncn#`) Locate the NCN Image to be Modified

    This example assumes the administrator wants to modify the Kubernetes image that is currently in use by NCNs. However, the steps are the same for any NCN SquashFS image.

    ```bash
    ARTIFACT_VERSION=<your-version>

    cray artifacts get boot-images k8s/$ARTIFACT_VERSION/filesystem.squashfs ./$ARTIFACT_VERSION-filesystem.squashfs

    cray artifacts get boot-images k8s/$ARTIFACT_VERSION/kernel ./$ARTIFACT_VERSION-kernel

    cray artifacts get boot-images k8s/$ARTIFACT_VERSION/initrd ./$ARTIFACT_VERSION-initrd

    export IMS_ROOTFS_FILENAME=$ARTIFACT_VERSION-filesystem.squashfs

    export IMS_KERNEL_FILENAME=$ARTIFACT_VERSION-kernel

    export IMS_INITRD_FILENAME=$ARTIFACT_VERSION-initrd
    ```

1. [Import External Image to IMS](../image_management/Import_External_Image_to_IMS.md)

    This document will instruct the administrator to set several environment variables, including the three set in
    the previous step.

1. [Create and Populate a VCS Configuration Repository](Create_and_Populate_a_VCS_Configuration_Repository.md)

   **NOTE:** If the image modification is a kernel-level change, a new `initrd` must be created by invoking
   the following script: `/srv/cray/scripts/common/create-ims-initrd.sh`. This script is embedded in the
   NCN SquashFS. After the script completes, a new `initrd` will be available at `/boot/initrd`. CFS will
   automatically make this `initrd` available at the end of the CFS session. This script should be executed
   as a step in the CFS ansible.

1. [Create a CFS Configuration](Create_a_CFS_Configuration.md)

   **NOTE:** If the platform certificate is needed for the purpose of accessing Zypper repos,
   the `csm.ncn.ca_cert` role can be added to a playbook within the `csm-config-management` repo.

   ```yaml
    # Install the platform certificate
    - role: csm.ncn.ca_cert
   ```

   The first layer in the CFS session should be similar to this, where `<example-playbook.yml>` is the playbook
   that includes the `csm.ncn.ca_cert` role.

   ```json
   "layers": [
   {
     "name": "csm-config",
     "cloneUrl": "https://api-gw-service-nmn.local/vcs/cray/csm-config-management.git",
     "playbook": "<example-playbook.yml>",
     "commit": "<git commit id>"
   },
   ```

   **NOTE:** There are three existing playbooks available for NCNs:
   - `ansible/ncn-worker_nodes.yml`
   - `ansible/ncn-storage_nodes.yml`
   - `ansible/ncn-master_nodes.yml`

1. [Create an Image Customization CFS Session](Create_an_Image_Customization_CFS_Session.md)


1. (`ncn#`) Update NCN Boot Parameters

    Get the existing `metal.server` setting for the xname of the node of interest:

    ```bash
    XNAME=<your-xname>
    METAL_SERVER=$(cray bss bootparameters list --hosts $XNAME --format json | jq '.[] |."params"' \
         | awk -F 'metal.server=' '{print $2}' \
         | awk -F ' ' '{print $1}')
    ```

    Verify the variable was set correctly: `echo $METAL_SERVER`

    Update the kernel, initrd, and metal server to point to the new artifacts.

    **NOTE:** `$IMS_RESULTANT_IMAGE_ID` is the `result_id` returned in the output of the last
    `cfs sessions` command in the previous section:
    ```bash
    cray cfs sessions describe example --format json | jq .status.artifacts
    ```

    ```bash
    S3_ARTIFACT_PATH="boot-images/$IMS_RESULTANT_IMAGE_ID"
    NEW_METAL_SERVER=http://rgw-vip.nmn/$S3_ARTIFACT_PATH

    PARAMS=$(cray bss bootparameters list --hosts $XNAME --format json | jq '.[] |."params"' | \
         sed "/metal.server/ s|$METAL_SERVER|$NEW_METAL_SERVER|" | \
         sed "s/metal.no-wipe=1/metal.no-wipe=0/" | \
         tr -d \")
    ```

    Verify the value of `$NEW_METAL_SERVER` was set correctly within the boot parameters: `echo $PARAMS`

    ```bash
    cray bss bootparameters update --hosts $XNAME \
         --kernel "s3://$S3_ARTIFACT_PATH/kernel" \
         --initrd "s3://$S3_ARTIFACT_PATH/initrd" \
         --params "$PARAMS"
    ```

1. (`ncn#`) Prepare for Reboot

   On the node or nodes being rebooted, run the following command to disable the bootloader and prepare the
   node to accept a new SquashFS.

   ```bash
   rm -rf /metal/recovery/*
   ```

1. [Reboot the NCN](../node_management/Reboot_NCNs.md)

   **NOTE:** The procedure above indicates that `metal.no-wipe` should be set to `1`. However, in this case
   it needs to be set to `0`, and that was done in a prior step.
