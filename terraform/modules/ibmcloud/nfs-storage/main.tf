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
   cluster_prefix = var.cluster_prefix
   nfs_share_name = local.cluster_prefix != "" ? "${local.cluster_prefix}-${var.nfs_storage_definition.nfs_prefix_name}" : var.nfs_storage_definition.nfs_prefix_name
   nfs_share_size = var.nfs_storage_definition.nfs_storage_size
   zone = var.zone
   replica_zone = var.nfs_storage_definition.nfs_replica_zone
  
   vpc_id = var.vpc_id
   resource_group_id = var.nfs_resource_group_id

   // Custom IOPS or 10 IOPS/GB up to 6000 IOPS
   nfs_storage_iops = var.nfs_storage_definition.nfs_storage_iops
   nfs_share_iops = local.nfs_storage_iops > 0 ? local.nfs_storage_iops : min(6000, local.nfs_share_size * 10)
   nfs_mount_points = var.nfs_storage_definition.mount_points

}

// Create a new share
resource "ibm_is_share" "nfs_storage" {
  access_control_mode = "security_group"
  name    = local.nfs_share_name
  size    = local.nfs_share_size
  iops    = local.nfs_share_iops
  profile = "dp2"
  zone    = local.zone

  resource_group = local.resource_group_id
  replica_share {
    name = "${local.nfs_share_name}-replica"
    replication_cron_spec = "0 */5 * * *"
    profile               = "dp2"
    zone                  = local.replica_zone
  }
}

module nfs_mount_points {
  source = "./modules/nfs-mount-point"
  for_each = {for index,obj in local.nfs_mount_points : obj.key => obj}
  resource_group_id = local.resource_group_id
  vpc_id = local.vpc_id
  nfs_storage_id = ibm_is_share.nfs_storage.id
  mount_point_definition = each.value
}


