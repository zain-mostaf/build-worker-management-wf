##
# Copyright (C) IBM Inc. - All Rights Reserved
#
# This source code is protected under international copyright law. All rights
# reserved and protected by the copyright holders.
#
# This software is provided as-is, without warranties of any kind.
##

locals {
  machine_ip_name_mapping = var.machine_ip_name_mapping
  symphony_image_id       = var.symphony_image_name
  symphony_profile       = var.symphony_profile
  security_groups        = var.security_group_ids
  zone                   = var.zone
  vpc_id                 = var.vpc_id
  resource_group_id      = var.resource_group_id
  ssh_keys               = var.ssh_keys
  cloud_init_script       = var.cloud_init_script
  tags                    = var.tags
  subnet_definition       = var.subnet_definition

  placement_group_id = var.placement_group_id

  # List all primary IPs.
  # This is used to determine the machine number being provisioned
  # and therefore the IP to select for each additional subnet.
  ips_list = [
    for ip, name in local.machine_ip_name_mapping : ip
  ]

  # List of available IPs for every additional subnet.
  #
  # Example:
  #
  # subnet 10.200.0.6/31
  # subnet 10.200.0.8/30
  #
  # will produce:
  #
  # "subnet-id" => {
  #   available_ips = [
  #     "10.200.0.6",
  #     "10.200.0.7",
  #     "10.200.0.8",
  #     "10.200.0.9",
  #     "10.200.0.10",
  #     "10.200.0.11"
  #   ]
  # }
  other_networks_available_ips = {
    for i in range(1, length(local.subnet_definition)) :
    local.subnet_definition[i].subnet_id => {
      available_ips = flatten([
        for cidr in local.subnet_definition[i].assigned_cidr : [
          for index in range(
            pow(2, 32 - split("/", cidr)[1])
          ) : cidrhost(cidr, index)
        ]
      ])
    }
  }

  # Build the secondary VNI configuration.
  #
  # Each machine gets one VNI for every additional subnet.
  #
  # Key format:
  #
  # <primary-ip>-<interface-index>
  #
  # Example:
  #
  # 10.10.1.10-1
  # 10.10.1.10-2
  # 10.10.1.11-1
  # 10.10.1.11-2
  secondary_vni_configuration = {
    for item in flatten([
      for machine_ip, machine_name in local.machine_ip_name_mapping : [
        for index in range(1, length(local.subnet_definition)) : {
          key          = "${machine_ip}-${index}"
          machine_ip   = machine_ip
          machine_name = machine_name
          interface_index = index

          subnet_id = local.subnet_definition[index].subnet_id

          ip = local.other_networks_available_ips[
            local.subnet_definition[index].subnet_id
          ].available_ips[
            index(local.ips_list, machine_ip) +
            local.subnet_definition[index].offset
          ]
        }
      ]
    ]) : item.key => item
  }
}


###############################################################################
# IMAGE
###############################################################################

data "ibm_is_image" "image_by_name" {
  count = length(
    regexall(
      "\\w{4}-\\w{8}-\\w{4}-\\w{4}-\\w{4}-\\w{12}",
      local.symphony_image_id
    )
  ) == 0 ? 1 : 0

  name = local.symphony_image_id
}


###############################################################################
# PRIMARY VNI
###############################################################################

resource "ibm_is_virtual_network_interface" "primary" {

  for_each = local.machine_ip_name_mapping

  name = "${each.value}-eth0-vni"

  subnet = local.subnet_definition[0].subnet_id

  security_groups = local.security_groups

  primary_ip {
    address     = each.key
    auto_delete = true
  }

  allow_ip_spoofing         = false
  enable_infrastructure_nat = true

  resource_group = local.resource_group_id

  tags = local.tags
}


###############################################################################
# SECONDARY VNIs
###############################################################################

resource "ibm_is_virtual_network_interface" "secondary" {

  for_each = local.secondary_vni_configuration

  name = "${each.value.machine_name}-eth${each.value.interface_index}-vni"

  subnet = each.value.subnet_id

  security_groups = local.security_groups

  primary_ip {
    address     = each.value.ip
    auto_delete = true
  }

  allow_ip_spoofing         = false
  enable_infrastructure_nat = true

  resource_group = local.resource_group_id

  tags = local.tags
}


###############################################################################
# VSI
###############################################################################

resource "ibm_is_instance" "vsi" {

  for_each = local.machine_ip_name_mapping

  name           = each.value
  image          = try(data.ibm_is_image.image_by_name[0].id, local.symphony_image_id)
  profile        = local.symphony_profile
  vpc            = local.vpc_id
  zone           = local.zone
  keys           = local.ssh_keys
  resource_group = local.resource_group_id

  user_data = replace(
    local.cloud_init_script,
    "__COMPUTERNAME__",
    each.value
  )

  # Placement group
  placement_group = local.placement_group_id

  tags = local.tags


  ###########################################################################
  # Metadata Service
  ###########################################################################

  metadata_service {
    enabled = true
  }


  ###########################################################################
  # PRIMARY NETWORK ATTACHMENT
  #
  # eth0
  #
  # The primary VNI is created separately and attached to the VSI.
  ###########################################################################

  primary_network_attachment {

    name = "${each.value}-eth0-attachment"

    virtual_network_interface {
      id = ibm_is_virtual_network_interface.primary[each.key].id
    }
  }


  ###########################################################################
  # SECONDARY NETWORK ATTACHMENTS
  #
  # eth1
  # eth2
  # eth3
  # ...
  #
  # Only VNIs belonging to this VSI are attached.
  ###########################################################################

  dynamic "network_attachments" {

    for_each = {
      for key, vni in ibm_is_virtual_network_interface.secondary :
      key => vni
      if local.secondary_vni_configuration[key].machine_name == each.value
    }

    content {

      name = "${network_attachments.value.name}-attachment"

      virtual_network_interface {
        id = network_attachments.value.id
      }
    }
  }


  ###########################################################################
  # LIFECYCLE
  ###########################################################################

  lifecycle {

    ignore_changes = [
      user_data,
      tags,
      image
    ]
  }


  ###########################################################################
  # BOOT VOLUME
  ###########################################################################

  boot_volume {

    name = "${each.value}-boot"

    size = 150
  }


  ###########################################################################
  # DATA VOLUMES
  #
  # Add data volumes here later if required.
  ###########################################################################
}
```

### Important correction

There is one thing I would change from my previous answer.

The `network_attachments` filtering above relies on the VNI name. A **cleaner and safer implementation** is to filter using the VNI configuration key rather than the resource name.

So I recommend changing this:

```hcl
dynamic "network_attachments" {

  for_each = {
    for key, vni in ibm_is_virtual_network_interface.secondary :
    key => vni
    if vni.name != null &&
       startswith(
         vni.name,
         "${each.value}-eth"
       )
  }

  content {
    name = "${network_attachments.value.name}-attachment"

    virtual_network_interface {
      id = network_attachments.value.id
    }
  }
}
