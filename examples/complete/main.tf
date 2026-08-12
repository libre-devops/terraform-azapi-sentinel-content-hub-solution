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
  rg_name  = "rg-${var.short}-${var.loc}-${terraform.workspace}-002"
  law_name = "log-${var.short}-${var.loc}-${terraform.workspace}-002"
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
