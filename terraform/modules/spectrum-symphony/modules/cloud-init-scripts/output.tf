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

output ego_conf_content {
    value = local.ego_conf_content
}

output cloud_init_linux {
    value = local.cloud_init_linux
}

output additional_routes {
    value = local.additional_routes
}