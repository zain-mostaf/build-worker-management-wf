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

variable vpc_id {
    type = string
    description = "VPC ID for the security_group'"
}

variable resource_group_id {
    type = string
    description = "the id of the resource group for a new security_group"
}

variable name {
  type = string
  description = "Name for created resources."
}

variable exists {
  type = bool
  description = "Check if the security group exists or not (reads it from data source if it exists)."
}

variable rules {
  type = list(string)
  description = "Map of security group names and allowed network connectivity."
}

variable tags {
    type = list(string)
    description = "User tags to attach to resources."
    default = []
}