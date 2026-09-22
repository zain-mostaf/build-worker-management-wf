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
   placement_group = var.placement_group
   resource_group_id = var.resource_group_id
   obj_key = local.placement_group.key
   placement_group_id = try(data.ibm_is_placement_group.placement_group[local.obj_key].id, try(ibm_is_placement_group.placement_group[local.obj_key].id, ""))
}

data ibm_is_placement_group placement_group {
    for_each = local.placement_group.exists == true  ? { "${local.placement_group.key}" =  local.placement_group } : {}
    name = local.placement_group.name
}

resource ibm_is_placement_group placement_group {
    for_each =  local.placement_group.exists == false ?  { "${local.placement_group.key}" =  local.placement_group } : {}
    name = local.placement_group.name
    resource_group = local.resource_group_id
    strategy = local.placement_group.type
}