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

variable ibmcloud_api_key {
    description = "IBM Cloud API Key to be used by "
}

variable cluster_prefix {
    description = "Default Name to identify the cluster prefix."
}

variable zone {
    description = "Availability Zone where this Cluster will take place."
}

variable vpc_name {
    description = "An existent VPC created by the HPC Foundation offering."
}

variable resource_group_name {
    description = "An existent Resource Group created by the HPC Foundation offering."
}

variable ssh_keys {
    description = "A list of SSH key names to add into the servers."
    type = list(string)
    default = []
}

variable private_dns_instance_name {
    default = ""
    description = "Name of a Private DNS instance to create DNS records for the Virtual Machines."
}

variable private_dns_zone_name {
    default = ""
    description = "Name of a zone under Private DNS instance where DNS records will be created."   
}

variable nfs_storage_definition {
    description = "NFS Storage definition for Symphony metadata." 
     type = object({
        key                     = string,
        nfs_prefix_name         = optional(string, "nfs-storage"),
        nfs_storage_size        = number,
        nfs_storage_iops        = optional(number, 0),
        nfs_replica_zone        = string,
       
        mount_points = list(object({
            key  = string,
            name = string,
            nfs_storage_ip          = string,
            nfs_storage_subnet_name = string
            security_groups = list(object({
                name = string,
                exists = optional(bool, false),
                rules = optional(list(string),[])
            }))
        }))
    })

    default = {
        key = "nfs-storage"
        nfs_prefix_name = "nfs-storage"
        nfs_storage_size = 100
        nfs_replica_zone = "ca-tor-3"

        mount_points = [
            {
                key = "data"
                name = "data"
                nfs_storage_ip = "10.249.0.8"
                nfs_storage_subnet_name = "sn-20231031-01"
                security_groups = [
                    {
                        name = "unleaded-quirk-stranger-congenial"
                        exists =  true
                    }
                ]
            }
        ]
    }
}


variable grid_manager_definition {
    description = "Complex object describing the Grid Managers for a Symphony cluster."
    type = object({
        prefix_name         = optional(string, "grid-man"),
        server_type         = optional(string, "shared"),
        quantity            = number,
        instance_profile    = string,
        image_name          = string,
        subnets             = list(object({
            key = string,
            name                 = string,
            exists               = optional(bool, true),
            ipv4_cidr_block      = optional(string),
            acl_name             = optional(string, null),
            subnet_section_cidrs = list(string)
        }))
        ad_configuration    = optional(object({
            ad_dns_server = optional(string),
            ad_domain = optional(string),
            ad_join_user = optional(string),
            ad_join_password = optional(string)
        })),
        symphony_config_info     = optional(object({
            sym_cluster_id  = string,
            ego_base_port   = optional(number, 7869),
            ego_ssl_setup   = optional(bool, false),
            ego_ssl_port    = optional(number),
            ego_ssm_range   = optional(string, "20000-20030"),
            ego_config_override   = optional(string),
            post_deployment_tasks = optional(string),

        })),
        symphony_certificates=optional(object({
            ca_certificate_pem     = optional(string),
            ca_intermediate_pem    = optional(string),
            soam_certificate_pem   = optional(string),
            soam_private_key_pem   = optional(string),
            webgui_certificate_pem = optional(string)
        })),
        placement_group = optional(object({
            key  = optional(string),
            name = optional(string),
            type = optional(string),
            exists = optional(bool, true)
        }), null)
        security_groups = optional(list(object({
            name = string,
            exists = optional(bool, false),
            rules = optional(list(string),[])
        }))),
        data_volumes = optional(list(object({
            key = string,
            prefix_name = optional(string, "dv"),
            volume_size = number,
            volume_iops = optional(number)
        })), []),
        tags = optional(list(string), []),
        worker_os = optional(string, "linux")
    })

}