# Complete example

Every input the module takes, installing three real solutions that between them cover each shape the
module handles:

| Solution | Why it is here |
| --- | --- |
| Microsoft Defender XDR | 374 content templates at roughly 1.9 MB, and the only one shipping a data connector, so it exercises the largest payload and the `solutions_with_ui_only_connectors` output |
| Sentinel SOAR Essentials | 26 templates of playbooks and workbooks, no connector |
| SOC Handbook | 13 workbook templates, published by the community rather than Microsoft, so its publisher prefix differs |

`expected_version` is set explicitly to `null` rather than pinned: a real pin would go stale and break
this example's CI run the day Microsoft ships an update. Pin it in a real estate, where being told
about the change is the entire point.

<!-- BEGIN_TF_DOCS -->
## Example configuration

```hcl
# Complete call: the full input surface, installing three real Content Hub solutions that between
# them cover every shape the module has to handle.
#
#   Microsoft Defender XDR   374 content templates at roughly 1.9 MB, and the only one of the three
#                            that ships a data connector, so it exercises the biggest payload and the
#                            solutions_with_ui_only_connectors output.
#   Sentinel SOAR Essentials 26 templates, playbooks and workbooks, no connector.
#   SOC Handbook             13 workbook templates, and a community rather than Microsoft publisher,
#                            so the publisher prefix differs from the other two.
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
  # not wait for, so order the whole module ahead of the install.
  depends_on = [module.law]

  # The sentinel module's onboarding_id is accepted here too; the module parses the workspace back
  # out of whichever it is given.
  workspace_id = module.law.workspace_ids[local.law_name]

  solutions = {
    "azuresentinel.azure-sentinel-solution-microsoft365defender" = {
      # expected_version is a CHANGE GATE, not a version selector: the catalog only ever serves the
      # current version, so this fails the plan when Microsoft publishes a new one rather than
      # installing an older one. Left null here precisely because a pin would go stale and break this
      # example's CI run the day Microsoft ships an update. Pin it in a real estate, where being told
      # about the change is the point.
      expected_version = null
      allow_deprecated = false
    }

    "azuresentinel.azure-sentinel-solution-sentinelsoaressentials" = {
      expected_version = null
      allow_deprecated = false
    }

    "microsoftsentinelcommunity.azure-sentinel-solution-sochandbook" = {
      expected_version = null
      allow_deprecated = false
    }
  }

  # Defaults to the workspace's own region when null; set explicitly here to show the override.
  location = local.location

  # Populates the content_hub_catalog output so you can find a solution's content id by display name.
  catalog_discovery_enabled = true

  deployment_name_prefix = "ldo-sentinel-solution-"

  catalog_api_version    = "2025-09-01"
  package_api_version    = "2025-09-01"
  deployment_api_version = "2021-04-01"

  resource_timeouts = {
    create = "20m"
    read   = "10m"
    update = "20m"
    delete = "30m"
  }

  retry_error_message_regex = [
    "(?i)not onboarded to Microsoft Sentinel",
    "(?i)workspace could not be found",
    "(?i)too many requests",
  ]
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
| <a name="output_catalog_size"></a> [catalog\_size](#output\_catalog\_size) | How many packages the Content Hub catalog offers this workspace, proving catalog\_discovery\_enabled populated. |
| <a name="output_deployment_names"></a> [deployment\_names](#output\_deployment\_names) | The generated ARM deployment name per solution. |
| <a name="output_installed_versions"></a> [installed\_versions](#output\_installed\_versions) | The version installed for each solution. |
| <a name="output_solution_ids_zipmap"></a> [solution\_ids\_zipmap](#output\_solution\_ids\_zipmap) | The installed solutions as {name, id} for composition. |
| <a name="output_solutions"></a> [solutions](#output\_solutions) | Everything resolved from the catalog for each solution. |
| <a name="output_solutions_with_ui_only_connectors"></a> [solutions\_with\_ui\_only\_connectors](#output\_solutions\_with\_ui\_only\_connectors) | Solutions whose template ships a data connector page that still needs the real connector creating separately. |
<!-- END_TF_DOCS -->