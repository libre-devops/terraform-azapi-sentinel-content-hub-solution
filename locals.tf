locals {
  # workspace_id accepts a plain workspace id or the sentinel module's onboarding_id (which is a
  # child of the workspace), so trim anything below the workspace segment back off. Non-greedy, so a
  # nested provider path cannot swallow the workspace name.
  workspace_id = regex("(?i)^.*?/providers/Microsoft\\.OperationalInsights/workspaces/[^/]+", var.workspace_id)

  workspace_name = element(split("/", local.workspace_id), length(split("/", local.workspace_id)) - 1)

  # The install is an ARM deployment, which is created in the workspace's resource group.
  resource_group_id = split("/providers/", local.workspace_id)[0]

  location = var.location != null ? var.location : one(data.azapi_resource.workspace[*].output.location)

  # response_export_values keys are used as attribute names on the data source output, so the dots
  # and hyphens in a content id are folded to underscores.
  catalog_keys = {
    for id in keys(var.solutions) : id => replace(replace(id, ".", "_"), "-", "_")
  }

  # One JMESPath projection per requested solution, evaluated provider-side. This matters: the raw
  # catalog list is roughly 3.7 MB across 975 packages, and projecting first keeps all of that out of
  # the plan and the state file.
  catalog_projection = "{contentId: contentId, productId: contentProductId, version: version, displayName: displayName, kind: contentKind, schemaVersion: contentSchemaVersion, deprecated: isDeprecated}"

  catalog = {
    for id, key in local.catalog_keys : id => try(data.azapi_resource_list.catalog[0].output[key], null)
  }

  # Field-by-field resolution with null fallbacks. Without this, a mistyped content id resolves to a
  # null catalog entry and every reference below fails with "Attempt to get attribute from null
  # value" pointing at a line of this module, instead of the precondition that explains the problem.
  catalog_resolved = {
    for id in keys(var.solutions) : id => {
      found         = try(local.catalog[id].productId, null) != null
      productId     = try(local.catalog[id].productId, null)
      version       = try(local.catalog[id].version, null)
      displayName   = try(local.catalog[id].displayName, null)
      kind          = try(local.catalog[id].kind, null)
      schemaVersion = try(local.catalog[id].schemaVersion, null)
      deprecated    = try(local.catalog[id].deprecated, false)
    }
  }

  # ARM deployment names are capped at 64 characters. Keep the readable derived name when it fits,
  # otherwise truncate and append a hash so two long ids cannot collide.
  deployment_names = {
    for id in keys(var.solutions) : id => (
      length("${var.deployment_name_prefix}${replace(id, ".", "-")}") <= 64
      ? "${var.deployment_name_prefix}${replace(id, ".", "-")}"
      : "${substr("${var.deployment_name_prefix}${replace(id, ".", "-")}", 0, 55)}-${substr(md5(id), 0, 8)}"
    )
  }

  # Every Content Hub solution template declares location, workspace and workspace-location, but ARM
  # rejects a parameter the template does not declare, so intersect what we can supply with what the
  # fetched template actually asks for rather than assuming the trio.
  deployment_parameters = {
    for id in keys(var.solutions) : id => {
      for name, value in {
        location             = local.location
        workspace            = local.workspace_name
        "workspace-location" = local.location
      } : name => { value = value }
      if contains(try(data.azapi_resource.package[id].output.parameter_names, []), name)
    }
  }

  # Serialised size of each solution's template, used by the ARM limit advisory in checks.tf. Measured
  # provider-side by the projection rather than by pulling the template in to jsonencode it here.
  template_sizes = {
    for id in keys(var.solutions) : id => try(data.azapi_resource.package[id].output.template_bytes, 0)
  }

  arm_template_limit_bytes = 4 * 1024 * 1024

  oversized_solutions = [
    for id, size in local.template_sizes : id
    if size > local.arm_template_limit_bytes * 0.75
  ]

  # Solutions whose template ships a data connector. Installing one creates the connector's PAGE in
  # Sentinel (kind StaticUI), not a working connector, so this is surfaced as an output rather than
  # left for the caller to discover when nothing ingests.
  solutions_with_connectors = [
    for id in keys(var.solutions) : id
    if anytrue([
      for type in try(data.azapi_resource.package[id].output.resource_types, []) :
      endswith(lower(type), "/dataconnectors")
    ])
  ]
}
