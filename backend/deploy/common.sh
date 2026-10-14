#!/usr/bin/env bash
# Retired unsafe legacy provisioning helpers. No supported entrypoint sources this file.
# Fail closed for external/old callers instead of enabling APIs, building images,
# granting IAM, scheduling before verification, or selecting a latest execution.
printf '%s\n' 'Legacy deploy/common.sh is retired. Use provision_<job>.sh or verify_<job>.sh with exported configuration and pre-existing prerequisites.' >&2
return 1 2>/dev/null || exit 1
