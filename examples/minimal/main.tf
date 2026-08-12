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
