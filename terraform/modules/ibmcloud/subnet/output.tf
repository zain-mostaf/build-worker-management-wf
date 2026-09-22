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

# Output variable definitions
output "id" {
  description = "(String) The unique identifier"
  value       = local.subnet_object.id
}

output "crn" {
  description = "(String) The full CRN"
  value       = local.subnet_object.crn
}

output "zone" {
  description = "(String) The zone"
  value       = local.subnet_object.zone
}

output "name" {
  description = "(String) The zone"
  value       = local.subnet_object.name
}

output ipv4_cidr_block {
  description = "CIDR Block for this subnet"
  value       = local.subnet_object.ipv4_cidr_block
}
