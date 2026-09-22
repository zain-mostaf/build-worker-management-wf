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

variable public_key {
    type = string
    default = null
    description = "Optional value to use for the SSH key. If not provided one will be generated"
}

variable private_key {
    type = object({
      exists = optional(bool)
      secrets_manager = optional(object({
        name = string
        secret_group = string
        secret_name = string
      }))
    })
    default = {}
    description = "Optional value to use for the SSH key. If not provided one will be generated"
}

variable name {
    type = string
    description = "Name for the ssh key"
}

variable exists {
    type = bool
    description = "true if using an existent vpc and false if using a new vpc"
    default = false
}

variable algorithm {
    type = string
    description = "the key algorithm"
    default = "RSA"
}

variable rsa_bits {
    type = number
    description = "the rsa bits"
    default = 4096
}