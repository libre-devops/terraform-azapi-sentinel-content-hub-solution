output "installed_versions" {
  description = "The version installed for each solution."
  value       = module.content_hub_solution.installed_versions
}

output "solution_ids" {
  description = "The installed contentPackages record ids."
  value       = module.content_hub_solution.solution_ids
}
