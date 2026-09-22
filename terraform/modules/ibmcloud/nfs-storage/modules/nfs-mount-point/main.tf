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
    mount_point_definition = var.mount_point_definition
    nfs_storage_id = var.nfs_storage_id
    vpc_id = var.vpc_id
    resource_group_id = var.resource_group_id
}


module nfs_security_groups {
    for_each = {for index,obj in local.mount_point_definition.security_groups : obj.name => obj}
    source = "./../../../security-group"
    vpc_id = local.vpc_id
    resource_group_id = local.resource_group_id
    name = each.value.name
    exists = each.value.exists
    rules = each.value.rules
    tags = []
}

module subnet {
    source = "./../../../subnet"
    name = local.mount_point_definition.nfs_storage_subnet_name
    exists = true
}


// Create a new mount point
resource "ibm_is_share_mount_target" "nfs_mnt" {
  share = local.nfs_storage_id
  virtual_network_interface {
      name = "i${replace(local.mount_point_definition.nfs_storage_ip, ".", "-")}-interface"
      primary_ip {
          auto_delete = true
          address = local.mount_point_definition.nfs_storage_ip
      }

      security_groups = [for sg_obj in module.nfs_security_groups : sg_obj.security_group_id ]
      subnet = module.subnet.id
      resource_group = local.resource_group_id
  }
  name = local.mount_point_definition.name
}