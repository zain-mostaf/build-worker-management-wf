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

variable exists {
    type = bool
    description = "true if using an existent subnet and false if using a new subnet"
    default = false
}

variable name {
    type = string
    description = "Name for the subnet'"
}

variable vpc_id {
    type = string
    description = "VPC ID for the subnet'"
    default = null
}

variable vpc_name {
    type = string
    description = "the name of the vpc"
    default = null
}

variable zone {
    type = string
    description = "Zone for the subnet'"
    default = null
}

variable resource_group_id {
    type = string
    description = "the id of the resource group for a new subnet"
    default = null
}

variable acl_name {
    type        = string
    description = "The name of the acl"
    default     = null
}

variable ipv4_cidr_block {
    type = string
    description = "the IPV4 CIDR for a new subnet"
    default = null
}