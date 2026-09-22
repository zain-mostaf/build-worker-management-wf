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
    sg_obj = var.exists == true ? data.ibm_is_security_group.security_group[var.name] : ibm_is_security_group.security_group[var.name]
}

data ibm_is_security_group security_group {
    for_each = toset([for name in [var.name] : name if var.exists == true])
    name = var.name
}

resource ibm_is_security_group security_group {
    for_each = toset([for name in [var.name] : name if var.exists == false])
    name = var.name
    resource_group = var.resource_group_id
    vpc = var.vpc_id
    tags = var.tags
}

resource ibm_is_security_group_rule security_group_rules {
    for_each = { for index, obj in var.rules: obj => obj }
    group = local.sg_obj.id
    direction = split("|", each.value)[0]
    remote = split("|", each.value)[1]
    dynamic "tcp" {
        for_each = split("|", each.value)[2] == "tcp" ? [split("-", split("|", each.value)[3])] : []
        content {
            port_min = tcp.value[0]
            port_max = length(tcp.value) > 1 ? tcp.value[1] : tcp.value[0]
        }
    }

    dynamic "udp" {
        for_each = split("|", each.value)[2] == "udp" ? [split("-", split("|", each.value)[3])] : []
        content {
            port_min = udp.value[0]
            port_max = length(udp.value) > 1 ? udp.value[1] : udp.value[0]
        }
    }

    dynamic "icmp" {
        for_each = split("|", each.value)[2] == "icmp" ? [split("-", split("|", each.value)[3])] : []
        content {
            code = icmp.value[0]
            type = length(icmp.value) > 1 ? icmp.value[1] : null
        }
    }
}