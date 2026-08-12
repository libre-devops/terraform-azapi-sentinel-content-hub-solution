output "catalog_size" {
  description = "How many packages the Content Hub catalog offers this workspace, proving catalog_discovery_enabled populated."
  value       = length(coalesce(module.content_hub_solution.content_hub_catalog, []))
}

output "deployment_names" {
  description = "The generated ARM deployment name per solution."
  value       = module.content_hub_solution.deployment_names
}

output "installed_versions" {
  description = "The version installed for each solution."
  value       = module.content_hub_solution.installed_versions
}

output "solution_ids_zipmap" {
  description = "The installed solutions as {name, id} for composition."
  value       = module.content_hub_solution.solution_ids_zipmap
}

output "solutions" {
  description = "Everything resolved from the catalog for each solution."
  value       = module.content_hub_solution.solutions
}

output "solutions_with_ui_only_connectors" {
  description = "Solutions whose template ships a data connector page that still needs the real connector creating separately."
  value       = module.content_hub_solution.solutions_with_ui_only_connectors
}
