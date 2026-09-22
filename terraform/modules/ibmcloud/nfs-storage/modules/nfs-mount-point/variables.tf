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

variable resource_group_id {}

variable vpc_id {}

variable nfs_storage_id {}

variable mount_point_definition {
    type = object({
         key  = string,
         name = string,
         nfs_storage_ip          = string,
         nfs_storage_subnet_name = string
         security_groups = list(object({
                name = string,
                exists = optional(bool, false),
                rules = optional(list(string),[])
         }))
    })
}