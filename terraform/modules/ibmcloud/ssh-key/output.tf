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

output private_key {
   value = { for key in formatlist(var.name) : key => try(tls_private_key.ssh_private_key[key].private_key_openssh, "") }
   sensitive = true
}

output ssh_key_id {
   value = local.ssh_key_id
}