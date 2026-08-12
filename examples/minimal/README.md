# Minimal example

Installs a single Content Hub solution into a Sentinel-onboarded workspace.

SOC Handbook is used deliberately: 13 workbook templates, no data connector, no licence requirement
and no ingestion, so the CI self-test installs and uninstalls it in seconds at no cost.

<!-- BEGIN_TF_DOCS -->
## Example configuration

```hcl
# Minimal call: install one Content Hub solution into a Sentinel-onboarded workspace. SOC Handbook
# is used because it is the cheapest possible real test, 13 workbook templates, no data connector, no
# licence requirement and no ingestion, so the CI self-test installs and uninstalls it in seconds.
locals {
  location = lookup(var.regions, var.loc, "uksouth")
  rg_name  = "rg-${var.short}-${var.loc}-${terraform.workspace}-001"
  law_name = "log-${var.short}-${var.loc}-${terraform.workspace}-001"
}

module "tags" {
  source  = "libre-devops/tags/azurerm"
  version = "~> 4.0"

  cost_centre     = "1888/67"
  owner           = "soc@example.com"
  deployed_branch = var.deployed_branch
  deployed_repo   = var.deployed_repo
}

module "rg" {
  source  = "libre-devops/rg/azurerm"
  version = "~> 4.0"

  resource_groups = [{ name = local.rg_name, location = local.location, tags = module.tags.tags }]
}

module "law" {
  source  = "libre-devops/log-analytics-workspace/azurerm"
  version = "~> 4.0"

  resource_group_id = module.rg.ids[local.rg_name]
  location          = local.location
  tags              = module.tags.tags

  log_analytics_workspaces = {
    (local.law_name) = {
      onboard_to_sentinel = true
    }
  }
}

module "content_hub_solution" {
  source = "../../"

  # Onboarding is a separate resource inside the workspace module that the workspace id output does
  # not wait for, so order the whole module ahead of the install; the module's retry regex covers
  # residual onboarding propagation lag after that.
  depends_on = [module.law]

  workspace_id = module.law.workspace_ids[local.law_name]

  solutions = {
    "microsoftsentinelcommunity.azure-sentinel-solution-sochandbook" = {}
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11.0, < 2.0.0 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | >= 2.0.0, < 3.0.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.0.0, < 5.0.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_content_hub_solution"></a> [content\_hub\_solution](#module\_content\_hub\_solution) | ../../ | n/a |
| <a name="module_law"></a> [law](#module\_law) | libre-devops/log-analytics-workspace/azurerm | ~> 4.0 |
| <a name="module_rg"></a> [rg](#module\_rg) | libre-devops/rg/azurerm | ~> 4.0 |
| <a name="module_tags"></a> [tags](#module\_tags) | libre-devops/tags/azurerm | ~> 4.0 |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_deployed_branch"></a> [deployed\_branch](#input\_deployed\_branch) | Git branch the deployment came from. Auto-filled in CI from TF\_VAR\_deployed\_branch. | `string` | `""` | no |
| <a name="input_deployed_repo"></a> [deployed\_repo](#input\_deployed\_repo) | Repository URL the deployment came from. Auto-filled in CI from TF\_VAR\_deployed\_repo. | `string` | `""` | no |
| <a name="input_loc"></a> [loc](#input\_loc) | Outfix: short Azure region code used in resource names (for example uks). | `string` | `"uks"` | no |
| <a name="input_regions"></a> [regions](#input\_regions) | Map of short region codes to Azure region slugs. | `map(string)` | <pre>{<br/>  "eus": "eastus",<br/>  "euw": "westeurope",<br/>  "uks": "uksouth",<br/>  "ukw": "ukwest"<br/>}</pre> | no |
| <a name="input_short"></a> [short](#input\_short) | Infix: short product code used in resource names. | `string` | `"ldo"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_installed_versions"></a> [installed\_versions](#output\_installed\_versions) | The version installed for each solution. |
| <a name="output_solution_ids"></a> [solution\_ids](#output\_solution\_ids) | The installed contentPackages record ids. |
<!-- END_TF_DOCS -->