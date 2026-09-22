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

variable cluster_prefix {} 

variable vpc_id {}

variable zone {}

variable nfs_resource_group_id {
    default = ""
}

variable nfs_storage_definition {
    description = "NFS Storage definition for Symphony metadata." 
    type = object({
        key                     = string,
        cluster_prefix          = optional(string, ""),
        nfs_prefix_name         = optional(string, "nfs-storage"),
        nfs_storage_size        = number,
        nfs_storage_iops        = optional(number, 0),
        nfs_replica_zone        = string,
       
        mount_points = list(object({
            key = string,
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
}
