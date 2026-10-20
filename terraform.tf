terraform {
  # 1.11 rather than the estate's usual 1.9 floor: the install reads its ARM template through an
  # ephemeral resource and passes it to azapi's sensitive_body, a write-only argument, so the template
  # is sent to Azure without ever being persisted in the plan or the state. Running tests/ needs 1.17
  # or later (mock_ephemeral); consuming the module does not.
  required_version = ">= 1.11.0, < 2.0.0"

  required_providers {
    # 2.3.0 is the first release with the ephemeral azapi_resource_action.
    azapi = {
      source  = "Azure/azapi"
      version = ">= 2.3.0, < 3.0.0"
    }
  }
}
