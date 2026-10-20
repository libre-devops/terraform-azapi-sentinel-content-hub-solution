# -------------------------------------------------------------------------------------------------
# Microsoft Sentinel Content Hub solutions as code.
#
# READ THIS BEFORE CHANGING THE RESOURCE SHAPE. Installing a Content Hub solution is NOT a PUT of
# Microsoft.SecurityInsights/contentPackages, despite that operation being documented as "Install a
# package to the workspace". That call is accepted and creates a package record, but it installs
# nothing: no content templates, no metadata, and installedVersion stays null. Verified empirically
# against a live workspace across api-versions 2023-04-01-preview, 2024-09-01 and 2025-09-01, with
# both a minimal body and the full catalog body, waiting five minutes each time.
#
# What actually installs a solution is an ARM deployment of the package's own packagedContent, a
# self-contained template that ships every content template plus the package record. That is what the
# portal's Install button does. So the flow here is:
#
#   1. List the catalog and resolve the content id to its versioned contentProductId, which is NOT
#      derivable (the content id is truncated, then suffixed with an opaque hash).
#   2. Fetch that package's packagedContent.
#   3. Claim the package record so Terraform owns it.
#   4. Deploy the template, which installs the content on top of the claimed record.
#
# Destroy runs in reverse: the deployment history entry goes first (a no-op for content), then the
# package delete, which is the call that actually uninstalls and cascades to every content template
# the solution delivered.
# -------------------------------------------------------------------------------------------------

# Only read the workspace when the caller has not pinned a location, so the common case needs no
# location input and no extra call is made when one is supplied.
data "azapi_resource" "workspace" {
  count = var.location == null ? 1 : 0

  type        = "Microsoft.OperationalInsights/workspaces@2023-09-01"
  resource_id = local.workspace_id

  response_export_values = ["location"]
}

# The Content Hub catalog. One list call serves every requested solution, with a per-solution
# JMESPath projection so only the handful of fields each install needs crosses into state.
data "azapi_resource_list" "catalog" {
  count = length(var.solutions) > 0 ? 1 : 0

  type      = "Microsoft.SecurityInsights/contentProductPackages@${var.catalog_api_version}"
  parent_id = local.workspace_id

  response_export_values = {
    for id, key in local.catalog_keys :
    key => "value[?properties.contentId=='${id}'] | [0].properties.${local.catalog_projection}"
  }
}

# Optional discovery aid: the whole catalog projected down to identity fields, so a caller who knows
# a solution only by its display name can find its content id. Off by default because it adds roughly
# 975 entries to state.
data "azapi_resource_list" "catalog_discovery" {
  count = var.catalog_discovery_enabled ? 1 : 0

  type      = "Microsoft.SecurityInsights/contentProductPackages@${var.catalog_api_version}"
  parent_id = local.workspace_id

  response_export_values = {
    catalog = "value[].properties.${local.catalog_projection}"
  }
}

# Three cheap JMESPath projections describing the package's packagedContent (the ARM template that
# installs it), all evaluated provider-side. Note the expand path is properties/packagedContent: the
# bare property name is rejected.
#
# The template itself is deliberately NOT exported here: see the ephemeral read below.
data "azapi_resource" "package" {
  for_each = var.solutions

  type        = "Microsoft.SecurityInsights/contentProductPackages@${var.catalog_api_version}"
  resource_id = "${local.workspace_id}/providers/Microsoft.SecurityInsights/contentProductPackages/${coalesce(local.catalog_resolved[each.key].productId, "unresolved")}"

  query_parameters = { "$expand" = ["properties/packagedContent"] }

  response_export_values = {
    parameter_names = "keys(properties.packagedContent.parameters)"
    resource_types  = "properties.packagedContent.resources[].type"
    template_bytes  = "length(to_string(properties.packagedContent))"
  }

  lifecycle {
    # Fail here with a useful message rather than letting a null product id build a malformed
    # resource id and surface as an opaque 404.
    precondition {
      condition     = local.catalog_resolved[each.key].found
      error_message = "Solution '${each.key}' was not found in the Content Hub catalog for this workspace. Check the content id (publisherId.offerId): list the catalog with the content_hub_catalog output, or read SolutionMetadata.json for the solution in the Azure/Azure-Sentinel repo."
    }

    precondition {
      condition     = each.value.expected_version == null || local.catalog_resolved[each.key].version == each.value.expected_version
      error_message = "Solution '${each.key}' is pinned to expected_version ${coalesce(each.value.expected_version, "null")} but the catalog is serving ${coalesce(local.catalog_resolved[each.key].version, "an unknown version")}. The catalog only ever exposes the current version, so an older one cannot be installed through this API: review the change, then update or clear expected_version."
    }

    precondition {
      condition     = each.value.allow_deprecated || !local.catalog_resolved[each.key].deprecated
      error_message = "Solution '${each.key}' is flagged deprecated in the Content Hub catalog. Set allow_deprecated = true on it to install anyway."
    }
  }
}

# The template itself, read ephemerally so it never reaches the plan or the state.
#
# It used to be exported from the data source above, but a data source's result is carried in every
# plan, and Terraform Stacks streams each resource instance's planned change to Terraform Core as one
# gRPC message capped at 4 MiB. The serialised result (the template plus its implied type) outgrew
# that, failing the apply with "streaming plan to Terraform Core ... received message larger than
# max". Solution templates tend to grow release on release, so the fix is to keep the template out of
# the plan entirely rather than to shrink it. It feeds sensitive_body below, a write-only argument, which accepts an
# ephemeral value.
#
# resource_id is taken from the data source rather than rebuilt, so this read waits for the
# preconditions above and a bad content id fails with their message rather than a 404 here. Testing
# it needs Terraform 1.17 or later, the first release whose mock providers support ephemeral
# resources (mock_ephemeral in tests/).
ephemeral "azapi_resource_action" "template" {
  for_each = var.solutions

  type        = "Microsoft.SecurityInsights/contentProductPackages@${var.catalog_api_version}"
  resource_id = data.azapi_resource.package[each.key].resource_id
  method      = "GET"

  query_parameters = { "$expand" = ["properties/packagedContent"] }

  response_export_values = {
    template = "properties.packagedContent"
  }
}

# Claimed BEFORE the deployment, deliberately. The deployment template creates this same record, and
# azapi refuses to create a resource that already exists, so claiming it first is what keeps the
# record under Terraform's ownership. A bare PUT like this installs no content (see the header), so
# claiming it early is harmless. Its delete is what uninstalls the solution on destroy.
resource "azapi_resource" "package" {
  for_each = var.solutions

  type      = "Microsoft.SecurityInsights/contentPackages@${var.package_api_version}"
  name      = each.key
  parent_id = local.workspace_id

  body = {
    properties = {
      contentId            = each.key
      contentProductId     = local.catalog_resolved[each.key].productId
      contentKind          = local.catalog_resolved[each.key].kind
      contentSchemaVersion = local.catalog_resolved[each.key].schemaVersion
      displayName          = local.catalog_resolved[each.key].displayName
      version              = local.catalog_resolved[each.key].version
    }
  }

  # The service returns a far richer record than it accepts, and the deployment enriches it further,
  # so compare only the properties this module sets.
  ignore_missing_property   = true
  schema_validation_enabled = false

  retry = var.retry_error_message_regex == null ? null : { error_message_regex = var.retry_error_message_regex }

  timeouts {
    create = var.resource_timeouts.create
    read   = var.resource_timeouts.read
    update = var.resource_timeouts.update
    delete = var.resource_timeouts.delete
  }
}

# The install itself. The template comes from the ephemeral read above and goes in sensitive_body, a
# write-only argument, so it is sent to Azure without being stored anywhere. sensitive_body_version
# keys redeployment off the solution version, since there is no stored copy to compare against.
resource "azapi_resource" "install" {
  for_each = var.solutions

  type      = "Microsoft.Resources/deployments@${var.deployment_api_version}"
  name      = local.deployment_names[each.key]
  parent_id = local.resource_group_id

  body = {
    properties = {
      mode       = "Incremental"
      parameters = local.deployment_parameters[each.key]
    }
  }

  sensitive_body = {
    properties = {
      template = ephemeral.azapi_resource_action.template[each.key].output.template
    }
  }

  sensitive_body_version = {
    "properties.template" = local.catalog_resolved[each.key].version
  }

  # The solution templates are authored by Microsoft and their partners against api-versions the
  # azapi embedded schema does not carry, so ARM validates the body on the PUT instead.
  schema_validation_enabled = false

  retry = var.retry_error_message_regex == null ? null : { error_message_regex = var.retry_error_message_regex }

  timeouts {
    create = var.resource_timeouts.create
    read   = var.resource_timeouts.read
    update = var.resource_timeouts.update
    delete = var.resource_timeouts.delete
  }

  depends_on = [azapi_resource.package]
}
