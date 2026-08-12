terraform {
  # 1.11 rather than the estate's usual 1.9 floor: the install passes its ARM template to azapi's
  # sensitive_body, a write-only argument, so the template is sent to Azure without being persisted a
  # second time in the resource's own state.
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = ">= 2.0.0, < 3.0.0"
    }
  }
}
