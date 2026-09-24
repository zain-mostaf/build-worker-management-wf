#!/usr/bin/env bash
set -Eeuo pipefail

# The repository default has no custom post-deployment commands.
# Custom Ansible YAML is intentionally not executed by the Bash conversion.
echo "Starting post-deployment tasks"
