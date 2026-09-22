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

output cloud_init_output {
    value = try(module.cloud_init_scripts)
}

output symphony_subnet_ids {
    value = [
        for subnet in local.grid_manager_definition.subnets : module.subnets[subnet.key].id
    ]
}
