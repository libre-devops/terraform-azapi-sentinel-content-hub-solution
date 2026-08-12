variable "catalog_api_version" {
  description = <<DESC
API version for Microsoft.SecurityInsights/contentProductPackages, the read-only Content Hub catalog
this module resolves solutions against. Variablised so consumers are never pinned to this module's
release cadence.
DESC
  type        = string
  default     = "2025-09-01"

  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}(-preview)?$", var.catalog_api_version))
    error_message = "catalog_api_version must be an Azure api-version such as 2025-09-01 or 2025-10-01-preview."
  }
}

variable "catalog_discovery_enabled" {
  description = "Populate the content_hub_catalog output with every catalogued package (content id, display name, version, kind, deprecated flag), for finding the content id of a solution you only know by name. Off by default because it adds roughly 975 entries to state."
  type        = bool
  default     = false
}

variable "deployment_api_version" {
  description = <<DESC
API version for Microsoft.Resources/deployments, the ARM deployment that actually installs a
solution's content. See the README: the Content Hub install is an ARM deployment of the package's
own template, not a plain PUT of the package resource.
DESC
  type        = string
  default     = "2021-04-01"

  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}(-preview)?$", var.deployment_api_version))
    error_message = "deployment_api_version must be an Azure api-version such as 2021-04-01."
  }
}

variable "deployment_name_prefix" {
  description = "Prefix for the generated ARM deployment name of each install. The rest of the name is derived from the solution's content id (and hash-suffixed when the combination would exceed the ARM limit of 64 characters)."
  type        = string
  default     = "sentinel-solution-"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{0,32}$", var.deployment_name_prefix))
    error_message = "deployment_name_prefix must be 32 characters or fewer of letters, digits, dots, underscores, or hyphens."
  }
}

variable "location" {
  description = <<DESC
Azure region passed to the solution template as its location and workspace-location parameters.
Defaults to null, which reads the region from the target workspace, so the common case needs no
input. Set it only to override that.
DESC
  type        = string
  default     = null
}

variable "package_api_version" {
  description = "API version for Microsoft.SecurityInsights/contentPackages, the installed-package record this module owns so that a destroy uninstalls the solution."
  type        = string
  default     = "2025-09-01"

  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}(-preview)?$", var.package_api_version))
    error_message = "package_api_version must be an Azure api-version such as 2025-09-01."
  }
}

variable "resource_timeouts" {
  description = <<DESC
azapi operation timeouts for the install deployment and the package record. Create is bounded well
below the azapi default of 30m: a solution that fails to install otherwise leaves azapi polling a
stuck ARM deployment for the full default, hiding the real error behind a long hang. Large solutions
(Microsoft Defender XDR carries 374 content templates) still install in well under a minute, so 20m
is generous.
DESC
  type = object({
    create = optional(string, "20m")
    read   = optional(string, "10m")
    update = optional(string, "20m")
    delete = optional(string, "30m")
  })
  default = {}
}

variable "retry_error_message_regex" {
  description = <<DESC
Regular expressions azapi retries on when an install or package call fails. The default covers only
the genuinely transient races: the Sentinel onboarding propagation race (a workspace onboarded in the
same apply can still report "not onboarded to Microsoft Sentinel" for a short while), the freshly
created workspace race, and throttling. It deliberately does NOT retry generic "not found" or 5xx
errors, which for a content install are usually persistent faults that should fail fast. Set null to
disable retries.
DESC
  type        = list(string)
  default     = ["(?i)not onboarded to Microsoft Sentinel", "(?i)workspace could not be found", "(?i)too many requests"]
}

variable "solutions" {
  description = <<DESC
Content Hub solutions to install, keyed by the package content id (its Content Hub identifier, for
example "azuresentinel.azure-sentinel-solution-microsoft365defender"). Find an id in the catalog by
display name with the content_hub_catalog output, or read it from the publisherId and offerId in the
solution's SolutionMetadata.json in the Azure/Azure-Sentinel repo.

Per solution:

- expected_version: assert the catalog is serving this exact version, and fail the plan if it is not.
  This is a CHANGE GATE, not a version selector: the catalog only ever exposes the current version's
  content, so an older version cannot be installed through this API. Leave null to track whatever
  Microsoft currently publishes.
- allow_deprecated: install even though the catalog flags the package deprecated. Off by default, and
  104 of the 975 catalogued packages are deprecated, so this guard fires in practice.
DESC
  type = map(object({
    expected_version = optional(string)
    allow_deprecated = optional(bool, false)
  }))
  default = {}

  validation {
    condition     = alltrue([for id in keys(var.solutions) : can(regex("^[A-Za-z0-9][A-Za-z0-9_-]*\\.[A-Za-z0-9][A-Za-z0-9._-]*$", id))])
    error_message = "Each solutions key must be a Content Hub package content id in publisherId.offerId form, for example azuresentinel.azure-sentinel-solution-microsoft365defender."
  }

  validation {
    condition     = alltrue([for s in values(var.solutions) : s.expected_version == null || can(regex("^[0-9]+(\\.[0-9]+)*$", s.expected_version))])
    error_message = "expected_version must be a numeric version such as 3.0.15, or null to track the catalog."
  }
}

variable "workspace_id" {
  description = "Resource id of the Sentinel-onboarded Log Analytics workspace to install into. Accepts the sentinel module's onboarding_id or a plain workspace id, per the estate's pass-ids principle."
  type        = string

  validation {
    condition     = can(regex("(?i)/providers/Microsoft\\.OperationalInsights/workspaces/[^/]+", var.workspace_id))
    error_message = "workspace_id must be a Log Analytics workspace resource id (or a Sentinel onboarding id under one)."
  }
}
