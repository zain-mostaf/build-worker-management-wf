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
   subnet_object = var.exists == true ? data.ibm_is_subnet.subnet[var.name] : ibm_is_subnet.subnet[var.name]
   use_acl = var.acl_name != null
}

data "ibm_is_subnet" "subnet" {
  for_each = { for val in formatlist(var.name) : val => val if var.exists == true}
  name = each.value
}

data "ibm_is_network_acl" "acl" {
  for_each  = { for val in try(formatlist(var.acl_name) , []): val => val if var.acl_name != null}
  vpc_name  = var.vpc_name
  name      = each.value
}

resource "ibm_is_subnet" "subnet" {
  for_each = { for val in formatlist(var.name) : val => val if var.exists == false}
  name            = each.value
  vpc             = var.vpc_id
  zone            = var.zone
  resource_group  = var.resource_group_id
  network_acl     = var.acl_name != null ? data.ibm_is_network_acl.acl[var.acl_name].id : null
  ipv4_cidr_block = var.ipv4_cidr_block
  depends_on = [
    data.ibm_is_network_acl.acl
  ]
}