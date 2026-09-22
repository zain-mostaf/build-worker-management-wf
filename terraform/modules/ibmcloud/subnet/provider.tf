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

terraform {
  required_version = ">= 0.14.11, < 2.0.0"
  required_providers {
    ibm = {
      source  = "IBM-Cloud/ibm"
      version = ">= 1.60.0"
    }
  }
}
