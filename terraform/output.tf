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

//output ego_conf_content {
//    value = try(module.grid_managers.module.cloud_init_scripts.ego_conf_content, "")
//}

/**
*  Input properties to be consumed by worker pool offering
**/
output zone {
    value = local.zone
}

output cluster_prefix {
    value = local.cluster_prefix
}

output tags {
    value = jsonencode(local.grid_manager_definition.tags)
}

output ssh_keys {
    value = local.ssh_keys
}

output symphony_cluster_info {
    value = <<EOT
{
   ego_base_port = ${try(local.grid_manager_definition.symphony_config_info.ego_base_port, "7869")}
   ego_ssl_setup = ${try(local.grid_manager_definition.symphony_config_info.ego_ssl_setup, "false")}
   ego_ssl_port = ${try(local.grid_manager_definition.symphony_config_info.ego_ssl_port, "")}
}

EOT
}

output ad_dns_ips {
    value = try(local.grid_manager_definition.ad_configuration.ad_dns_server, "")
}

output ad_domain {
    value = try(local.grid_manager_definition.ad_configuration.ad_domain, "")    
}

output ad_user {
    value = try(local.grid_manager_definition.ad_configuration.ad_join_user, "") 
}

output ad_password {
    value = try(local.grid_manager_definition.ad_configuration.ad_join_password, "")
}

output symphony_image_name {
    value = try(local.grid_manager_definition.image_name, "")
}

/**
*  Output/Computed values coming from this offering and reused by worker pool
**/
output workload_vpc_id {
    value = data.ibm_is_vpc.vpc.id
}

output resource_group_id {
    value = data.ibm_resource_group.resource_group.id
}

output private_dns_instance_id {
    value = local.dns_instance_id
}

output private_dns_zone_id {
    value = local.dns_zone_id
}

output ssh_key_ids {
    value = jsonencode(local.ssh_key_ids)
}

output symphony_subnet_id {
    value = try(module.grid_managers.symphony_subnet_ids[0], "")
}

output symphony_worker_security_group {
    value = jsonencode([])
}