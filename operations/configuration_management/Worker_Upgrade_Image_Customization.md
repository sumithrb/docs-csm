# Worker Upgrade Image Customization

When performing an upgrade, NCN Image Customization must be performed with the NCN worker node image to ensure the appropriate CFS layers are applied. This step involves configuring CFS to use the default SAT bootprep files from the hpc-csm-software-recipe repo, and rebuilding the NCN worker nodes so they boot the newly customized image

The definition of the CFS configuration used for NCN worker node Image Customization is provided in the hpc-csm-software-recipe repo in VCS. The follow procedure describes how correctly edit the bootprep files to be able to use them to perform Image Cuztomiizationh

1. (`ncn-m#`) Perform the Steps contained in the `Accessing_Sat_Bootprep_Files` procedure to gather a copy of the SAT Bootprep files.

1. (`ncn-m#`) Create a local copy of the management-bootprep-yaml file and delete the ncn-personalization configuration. The ncn-image-customization configuration will be the only entry remaining in the file.

    ```
    cp management-bootprep.yaml management-bootprep-image-customization.yaml
    vi management-bootprep-image-customization.yaml
    ```

    Edit the `management-bootprep-image-customization.yaml` file to delete the ncn-personalization configuration definition.

    Verify the content now starts with just the image customization section.

    ```bash
    # (C) Copyright 2022 Hewlett Packard Enterprise Development LP
    ---
    schema_version: 1.0.2
    configurations:
    - name: ncn-image-customization
    ```

1. (`ncn-m#`) Use the management-bootprep-image-customization.yaml file as input when customizing the new NCN worker node image with CFS in the CSM documentation.
