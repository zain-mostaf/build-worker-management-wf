##
# Copyright (C) IBM Inc. - All Rights Reserved
# 
# This source code is protected under international copyright law.  All rights
# reserved and protected by the copyright holders.
# This file is confidential and only available to authorized individuals with the
# permission of the copyright holders.  If you encounter this file and do not have
# permission, please contact the copyright holders and delete this file.
# 
# This software is provided as-is, without warranties of any kind. 
##

locals {
    // IBM Cloud provider connection 
    ibmcloud_api_key = var.ibmcloud_api_key
    zone = var.zone
    region = join("-", slice(split("-", local.zone), 0, 2))

    // Datasources to look at
    vpc_name = var.vpc_name
    resource_group_name = var.resource_group_name
    dns_instance_name = var.private_dns_instance_name
    dns_zone_name = var.private_dns_zone_name

    nfs_storage_definition = var.nfs_storage_definition
    grid_manager_definition = var.grid_manager_definition

    cluster_prefix = var.cluster_prefix

    ssh_keys = var.ssh_keys

}

// Data sources to capture information
// resource group
data ibm_resource_group resource_group {
    name = local.resource_group_name
}

//vpc
data ibm_is_vpc  vpc {
    name = local.vpc_name
}

// dns instance ID and zone ID
data ibm_resource_instance dns_instance {
    count = local.dns_instance_name != "" ? 1:0
    name = local.dns_instance_name
    service = "dns-svcs"
}

data ibm_dns_zones zones {
    count = local.dns_instance_name != "" ? 1:0
    instance_id = data.ibm_resource_instance.dns_instance[0].guid
}

// Existing SSH key used by all managers created by this automation
data ibm_is_ssh_key internal_ssh_key {
    name = var.existing_ssh_key_name
}

data ibm_is_ssh_key ssh_key {
    for_each = toset(local.ssh_keys)
    name = each.key
}

locals {
    dns_instance_id = try(data.ibm_resource_instance.dns_instance[0].guid, "")
    dns_zone_id = try([for zone in data.ibm_dns_zones.zones[0].dns_zones : zone.zone_id if zone.name == local.dns_zone_name][0], "")
    ssh_key_ids = concat([data.ibm_is_ssh_key.internal_ssh_key.id], [for key,obj in data.ibm_is_ssh_key.ssh_key : obj.id ])
}

// NFS Storage
module nfs_storage {
    vpc_id = data.ibm_is_vpc.vpc.id
    source = "./modules/ibmcloud/nfs-storage"
    zone = local.zone
    nfs_resource_group_id = data.ibm_resource_group.resource_group.id
    nfs_storage_definition = local.nfs_storage_definition
    cluster_prefix = local.cluster_prefix
}

// IBM Security Key Lifecycle Manager

// Spectrum Scale Storage Managers 

// Spectrum Scale Compute Managers

// Spectrum Symphony Grid Managers
module grid_managers {
    source = "./modules/spectrum-symphony"
    cluster_prefix = local.cluster_prefix
    zone = local.zone
    vpc_name = local.vpc_name
    vpc_id = data.ibm_is_vpc.vpc.id
    resource_group_id = data.ibm_resource_group.resource_group.id
    ssh_keys = local.ssh_key_ids
    private_dns_instance_id = local.dns_instance_id
    private_dns_zone_id = local.dns_zone_id
    grid_manager_definition = local.grid_manager_definition
    symphony_admin_password = var.symphony_admin_password
    nfs_storage_path = module.nfs_storage.nfs_mount_paths[0]
    deployment_private_key = var.deployment_private_key
}