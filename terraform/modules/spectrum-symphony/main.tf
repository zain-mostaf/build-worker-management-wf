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
    vpc_id = var.vpc_id
    resource_group_id = var.resource_group_id
    zone = var.zone

    grid_manager_definition = var.grid_manager_definition

    grid_manager_quantity = local.grid_manager_definition.quantity
    first_cidr = try(local.grid_manager_definition.subnets[0].subnet_section_cidrs)
    primary_ip_offset = local.grid_manager_definition.primary_ip_offset

    cluster_prefix = var.cluster_prefix
    manager_prefix = local.grid_manager_definition.prefix_name

    grid_manager_names = [for i in range(local.grid_manager_quantity) : "${local.cluster_prefix}-${local.manager_prefix}-${format("%02d", i + 1)}" ]
    available_primary_ips = flatten([ for ip_range in local.first_cidr : [for index in range(pow(2, 32 - split("/", ip_range)[1])) : cidrhost(ip_range, index)]])
    
    selected_primary_ips = slice(
        local.available_primary_ips,
        local.primary_ip_offset,
        local.primary_ip_offset + local.grid_manager_quantity
    )
    ip_machine_mapping = { for idx in range(local.grid_manager_quantity) : local.selected_primary_ips[idx] => local.grid_manager_names[idx]}

    private_dns_zone_id = var.private_dns_zone_id
    private_dns_instance_id = var.private_dns_instance_id
    // future: multiple zone entries with adoption of multiple netowrks?
    dns_zone_entries = { for idx,obj in [local.private_dns_zone_id] : obj => {
        dns_instance_id = local.private_dns_instance_id,
        dns_record_mapping = local.ip_machine_mapping
    } if obj != ""}

    nfs_storage_path = var.nfs_storage_path

    deployment_private_key = var.deployment_private_key

    ssh_keys = var.ssh_keys

    tags = concat(local.grid_manager_definition.tags, ["role:symphony-grid-manager"])
}



// Placement Group
module placement_group {
    for_each = local.grid_manager_definition.placement_group != null ? { 
        "${local.grid_manager_definition.placement_group.key}" = local.grid_manager_definition.placement_group 
    } : {}
    source = "./../ibmcloud/placement-group"
    resource_group_id = local.resource_group_id
    placement_group = each.value
}

// Subnets
module subnets {
    for_each = { for index,obj in local.grid_manager_definition.subnets : obj.key => obj}
    source = "./../ibmcloud/subnet"
    exists = each.value.exists
    name = each.value.name
    vpc_id = local.vpc_id
    resource_group_id = local.resource_group_id
    zone = local.zone
    acl_name = each.value.acl_name
    vpc_name = var.vpc_name
    ipv4_cidr_block = each.value.ipv4_cidr_block
}

// Security Groups
module security_groups {
    for_each = {for index,obj in local.grid_manager_definition.security_groups : obj.name => obj}
    source = "./../ibmcloud/security-group"
    vpc_id = local.vpc_id
    resource_group_id = local.resource_group_id
    name = each.value.name
    exists = each.value.exists
    rules = each.value.rules
    tags = []
}

// DNS entries
module dns_entries {
    for_each = local.dns_zone_entries
    source = "./../ibmcloud/dns-entry"
    private_dns_zone_id = each.key
    private_dns_instance_id = each.value.dns_instance_id
    machine_ip_name_mapping = each.value.dns_record_mapping
}

// Cloud-Init-Scripts
module cloud_init_scripts {
    for_each = toset(["primary", "others"])
    source = "./modules/cloud-init-scripts"
    ego_role = each.key
    ego_master_list = try(slice(local.grid_manager_names,0,2), [local.grid_manager_names[0]])
    nfs_storage_path = local.nfs_storage_path 
    cluster_domain = try(module.dns_entries[local.private_dns_zone_id].domain_name, "")
    grid_manager_definition = local.grid_manager_definition
    symphony_admin_password = var.symphony_admin_password
    subnet_cidrs = [ for index,obj in local.grid_manager_definition.subnets : module.subnets[obj.key].ipv4_cidr_block ]
    deployment_private_key = local.deployment_private_key
}

// Grid Managers (dependencies: DNS (explicit), cloud-init (implicit))
//// Primary 
module primary_grid_manager {
    depends_on = [ module.dns_entries ]
    source = "./../ibmcloud/shared-vsi"
    machine_ip_name_mapping = { "${local.selected_primary_ips[0]}" = local.ip_machine_mapping[local.selected_primary_ips[0]] }
    symphony_profile = local.grid_manager_definition.instance_profile
    security_group_ids = [ for security_group in module.security_groups : security_group.security_group_id ]
    zone = local.zone
    subnet_definition = [ 
        for subnet in local.grid_manager_definition.subnets : {
            subnet_id = module.subnets[subnet.key].id,
            assigned_cidr = subnet.subnet_section_cidrs
            offset = 0
        }
    ]
    resource_group_id = local.resource_group_id
    ssh_keys = local.ssh_keys
    cloud_init_script = module.cloud_init_scripts["primary"].cloud_init_linux.result
    vpc_id = local.vpc_id
    placement_group_id = try(module.placement_group[local.grid_manager_definition.placement_group.key].placement_group_id, null)
    symphony_image_name = local.grid_manager_definition.image_name
    tags = local.tags
}

//// Secondary + Others
module other_managers {
    depends_on = [ module.dns_entries ]
    source = "./../ibmcloud/shared-vsi"
    machine_ip_name_mapping = { for remaining_ip in slice(local.selected_primary_ips, 1, local.grid_manager_definition.quantity) : remaining_ip => local.ip_machine_mapping[remaining_ip] }
    symphony_profile = local.grid_manager_definition.instance_profile
    security_group_ids = [ for security_group in module.security_groups : security_group.security_group_id ]
    zone = local.zone
    subnet_definition = [ 
        for subnet in local.grid_manager_definition.subnets : {
            subnet_id = module.subnets[subnet.key].id,
            assigned_cidr = subnet.subnet_section_cidrs
            offset = 1
        }
    ]
    resource_group_id = local.resource_group_id
    ssh_keys = local.ssh_keys
    cloud_init_script = module.cloud_init_scripts["others"].cloud_init_linux.result
    vpc_id = local.vpc_id
    placement_group_id = try(module.placement_group[local.grid_manager_definition.placement_group.key].placement_group_id, null)
    symphony_image_name = local.grid_manager_definition.image_name
    tags = local.tags
}