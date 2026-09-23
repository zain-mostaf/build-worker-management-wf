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

output dns_ptr_diagnostics {
    value = {
        for zone_id, dns_entry in module.dns_entries : zone_id => {
            forward_zone    = dns_entry.domain_name
            reverse_zone    = dns_entry.reverse_zone_name
            reverse_zone_id = dns_entry.reverse_zone_id
            ptr_record_count = dns_entry.ptr_record_count
        }
    }
}
