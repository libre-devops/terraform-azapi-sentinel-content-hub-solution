output "content_hub_catalog" {
  description = "The whole Content Hub catalog as a list of {contentId, displayName, version, kind, deprecated}, for discovering the content id of a solution you only know by name. Null unless catalog_discovery_enabled is true, because it adds roughly 975 entries to state."
  value       = one(data.azapi_resource_list.catalog_discovery[*].output.catalog)
}

output "deployment_ids" {
  description = "Map of solution content id to the resource id of the ARM deployment that installed it."
  value       = { for id, r in azapi_resource.install : id => r.id }
}

output "deployment_names" {
  description = "Map of solution content id to the generated ARM deployment name, which is derived from the content id and hash-suffixed when it would exceed the ARM limit of 64 characters."
  value       = local.deployment_names
}

output "installed_versions" {
  description = "Map of solution content id to the version installed, which is the version the catalog was serving at apply time."
  value       = { for id, entry in local.catalog_resolved : id => entry.version }
}

output "solution_ids" {
  description = "Map of solution content id to the resource id of its installed contentPackages record, the resource whose deletion uninstalls the solution."
  value       = { for id, r in azapi_resource.package : id => r.id }
}

output "solution_ids_zipmap" {
  description = "Map of solution content id to {name, id} for easy composition."
  value       = { for id, r in azapi_resource.package : id => { name = id, id = r.id } }
}

output "solutions" {
  description = "Map of solution content id to everything resolved from the catalog for it: displayName, version, contentProductId, kind, schemaVersion and the deprecated flag."
  value       = local.catalog_resolved
}

output "solutions_with_ui_only_connectors" {
  description = <<DESC
Content ids of the installed solutions whose template ships a data connector. Read this: what a
solution installs for a connector is the connector's PAGE in Sentinel (kind StaticUI), not a working
connector. Nothing is ingested until the connector itself is created, for example with
libre-devops/sentinel-data-connector/azurerm or libre-devops/sentinel-defender-xdr-connector/azapi.
DESC
  value       = local.solutions_with_connectors
}

output "workspace_id" {
  description = "Resource id of the Sentinel-onboarded workspace the solutions were installed into, parsed back out of workspace_id so an onboarding id resolves to its workspace."
  value       = local.workspace_id
}
