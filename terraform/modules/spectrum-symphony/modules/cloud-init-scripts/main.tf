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

   grid_manager_definition = var.grid_manager_definition
   // EGO local properties for Jinja templating
   ego_base_port =  local.grid_manager_definition.symphony_config_info.ego_base_port
   ego_ssl_setup =  local.grid_manager_definition.symphony_config_info.ego_ssl_setup
   ego_ssl_port =   local.grid_manager_definition.symphony_config_info.ego_ssl_port
   ego_config_override = local.grid_manager_definition.symphony_config_info.ego_config_override
   symphony_ssm_port_range = local.grid_manager_definition.symphony_config_info.ego_ssm_range

   // EGO Grid Manager Role (Primary/Others)
   ego_role = var.ego_role
   post_deployment_tasks = local.grid_manager_definition.symphony_config_info.post_deployment_tasks
   
   // Cluster domain (used for DNS configuration in grid managers)
   cluster_domain = var.cluster_domain

   // Certificates to deploy for TLS solution (they will be generated if certificates not informed)
   symphony_cacert_certificate = local.grid_manager_definition.symphony_certificates.ca_certificate_pem
   symphony_cacert_intermediate_cert = local.grid_manager_definition.symphony_certificates.ca_intermediate_pem
   symphony_soam_certificate = local.grid_manager_definition.symphony_certificates.soam_certificate_pem
   symphony_soam_private_key = local.grid_manager_definition.symphony_certificates.soam_private_key_pem
   symphony_webgui_certificate = local.grid_manager_definition.symphony_certificates.webgui_certificate_pem

   // Private Key to be deployed on Grid Managers
   deployment_private_key = var.deployment_private_key

   // List of Subnet CIDRs
   subnet_cidrs = var.subnet_cidrs

   // Additional routing rules to be configured
   additional_routes = [ for index, subnet in local.subnet_cidrs : {
      conn_name = "Wired connection ${index}"
      gateway = cidrhost(subnet, 1)
      priority = 200 + index
      table = 5000 + index
      cidr = subnet
   } if index > 0]

   // Worker OS
   worker_os = var.grid_manager_definition.worker_os

   // New attribute lines to be included (all string)
   ego_new_attributes = [ for attr in ["workerPool", "techStack"] : "${attr}  String  ()       ()              (Custom Attribute - ${attr})"]

    // Template data used by the Linux deployment scripts.
   template_data = {
      EGO_TOP = "/opt/ibm/spectrumcomputing",
      SHARED_EGO_TOP = "/data/${local.grid_manager_definition.symphony_config_info.sym_cluster_id}/sym732"
      ego_primary_host = var.ego_master_list[0],
      ego_secondary_host = try(var.ego_master_list[1], ""),
      ego_base_port = local.ego_base_port,
      ego_ssl_setup = local.ego_ssl_setup,
      ego_ssl_port = local.ego_ssl_port,
      ego_additional_properties = local.ego_config_override,
      cluster_domain = local.cluster_domain,
      os_delim = "/",
      manager_os = "linux"
      cluster_id = local.grid_manager_definition.symphony_config_info.sym_cluster_id
      network_setup = "NetworkManager"
      nfs_storage_path = var.nfs_storage_path
      symphony_ssm_port_range = local.symphony_ssm_port_range
            symphony_password = base64encode(var.symphony_admin_password)
            dns_server_ips = try(local.grid_manager_definition.dns_server, "161.26.0.10")
      additional_routes = try(local.additional_routes, [])
      symphony_web_certificate = local.symphony_webgui_certificate != "" ? "true" : "false"
      symphony_soam_certificate = local.symphony_soam_certificate != "" ? "true" : "false"
      symphony_cacert_certificate = local.symphony_cacert_certificate
      symphony_cacert_intermediate_cert = local.symphony_cacert_intermediate_cert
      ego_role = local.ego_role
      ego_preferred_ip_mask = "${split(".", local.subnet_cidrs[0])[0]}.0.0.0/8"
      ego_new_attributes = local.ego_new_attributes
      worker_os = local.worker_os
   }

    // Legacy Active Directory fields remain optional for input compatibility.
   ad_join_user = try(local.grid_manager_definition.ad_configuration.ad_join_user, "")
   ad_join_password = try(local.grid_manager_definition.ad_configuration.ad_join_password, "")
}

// ego.conf generation
data "jinja_template" "ego_conf_file" {
   template = "${path.module}/templates/ego.conf.j2"
   
   context {
      type = "json"
      data = jsonencode(local.template_data)
   }
}

// linux-cloud-init.yaml generation
data jinja_template linux_cloud_init_file {
    template = "${path.module}/templates/linux-cloud-init.yaml.j2"
    context {
        type = "json"
        data = jsonencode({ 
            ego_role = local.ego_role 
            linux_master_deployment_content = base64gzip(file("${path.module}/bash-scripts/linux-${local.ego_role}-deployment.sh")),
            linux_master_postdeployment_content = base64gzip(file("${path.module}/bash-scripts/linux-master-postdeployment.sh")),
            ego_conf_content = base64gzip(local.ego_conf_content),
            linux_master_deployment_env_content = base64gzip(jsonencode(local.template_data)),
            cacert_pem_content = base64gzip(local.symphony_cacert_certificate)
            cacert_intermediate_pem_content = base64gzip(local.symphony_cacert_intermediate_cert)
            user_pem_content = base64gzip(local.symphony_soam_certificate)
            user_key_content = base64gzip(local.symphony_soam_private_key)
            server_pem_content = base64gzip(local.symphony_webgui_certificate)
            id_rsa_content = base64gzip(local.deployment_private_key)
            inventory_content = base64gzip(<<EOT
[primary]
${var.ego_master_list[0]}
            EOT
            )
        })
    }
}

// cloud-init-generation  
locals {

    ego_conf_content = data.jinja_template.ego_conf_file.result

    // Linux cloud init after Jinja parsing
    cloud_init_linux = data.jinja_template.linux_cloud_init_file

}

