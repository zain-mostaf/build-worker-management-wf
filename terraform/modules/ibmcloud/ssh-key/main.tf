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
  ssh_key_object = var.exists == true ? data.ibm_is_ssh_key.ssh_key[var.name] : ibm_is_ssh_key.ssh_key[var.name]
  public_key = var.public_key != null ? var.public_key : trimspace(tls_private_key.ssh_private_key[var.name].public_key_openssh)
  ssh_key_id = local.ssh_key_object.id
}

resource "tls_private_key" "ssh_private_key" {
  for_each = { for val in formatlist(var.name) : val => val if var.exists == false}
  algorithm = upper(var.algorithm)
  rsa_bits  = var.rsa_bits
}

resource "ibm_is_ssh_key" "ssh_key" {
  for_each = { for val in formatlist(var.name) : val => val if var.exists == false}
  name       = each.value
  public_key = local.public_key
  type       = lower(var.algorithm)
}

data "ibm_is_ssh_key" "ssh_key" {
  for_each = { for val in formatlist(var.name) : val => val if var.exists == true}
  name = each.value
}
