<!--
  Keep the title and badges OUTSIDE the centered <div>: the Terraform Registry's markdown renderer
  does not parse markdown inside an HTML block, so a # heading or [![badge]] in the div renders as
  literal text on the registry. Only the logo (HTML) goes in the div.
-->
<div align="center">
  <a href="https://libredevops.org">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://libredevops.org/assets/libre-devops-white.png">
      <img alt="Libre DevOps" src="https://libredevops.org/assets/libre-devops-black.png" width="300">
    </picture>
  </a>
</div>

# Terraform AzAPI Sentinel Content Hub Solution

Microsoft Sentinel **Content Hub solutions** as code: the Install/Update button in the Content Hub,
expressed as a map of solutions, via the
[Azure/azapi](https://registry.terraform.io/providers/Azure/azapi/latest) provider.

[![CI](https://github.com/libre-devops/terraform-azapi-sentinel-content-hub-solution/actions/workflows/ci.yml/badge.svg)](https://github.com/libre-devops/terraform-azapi-sentinel-content-hub-solution/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/libre-devops/terraform-azapi-sentinel-content-hub-solution?sort=semver&label=release)](https://github.com/libre-devops/terraform-azapi-sentinel-content-hub-solution/releases/latest)
[![Terraform Registry](https://img.shields.io/badge/registry-libre--devops-7B42BC?logo=terraform&logoColor=white)](https://registry.terraform.io/namespaces/libre-devops)
[![License](https://img.shields.io/github/license/libre-devops/terraform-azapi-sentinel-content-hub-solution)](./LICENSE)

---

## Why this is not a one line resource

There is no `azurerm` resource for Content Hub solutions (the sentinel surface stops at
`azurerm_sentinel_metadata`), so it has to be azapi. That much is unsurprising. The surprise is that
the obvious azapi call does not work.

`Microsoft.SecurityInsights/contentPackages` is documented as
[Content Package - Install](https://learn.microsoft.com/en-us/rest/api/securityinsights/content-package/install),
"Install a package to the workspace". A PUT to it is accepted, returns 200, and creates a package
record that shows up in a `contentPackages` list. It installs **nothing**: no content templates, no
metadata, and `installedVersion` stays null. That was verified against a live workspace on
api-versions `2023-04-01-preview`, `2024-09-01` and `2025-09-01`, with both the documented minimal
body and the full catalog body, waiting five minutes each time. A naive module built on that call
produces a resource that looks installed in Terraform and in the API, and delivers no content.

What actually installs a solution is an **ARM deployment of the package's own `packagedContent`**, a
self-contained template carrying every content template plus the package record. That is what the
portal does. So the module:

1. Lists the catalog and resolves your content id to its versioned `contentProductId`, which is not
   derivable: the content id is truncated and then suffixed with an opaque hash
   (`azuresentinel.azure-sentinel-solution-microsoft365defender` becomes
   `azuresentinel.azure-sentinel-solution-microsoft365-sl-ly2pizzgu22as`).
2. Fetches that package's `packagedContent` (expand path `properties/packagedContent`; the bare
   property name is rejected).
3. Claims the `contentPackages` record so Terraform owns it.
4. Deploys the template, installing the content on top of the claimed record.

Destroy runs in reverse: the ARM deployment history entry goes first (a no-op for content), then the
package delete, which is the call that actually uninstalls and cascades to every content template the
solution delivered.

## Installing a solution is not enabling its content

Worth being blunt about, because it is the most common misconception. A solution delivers
**templates**. Installing Microsoft Defender XDR gives you 40 analytics rule *templates*, not 40
running rules. Turn them into live resources with the sibling modules:

| What the solution ships | What turns it on |
| --- | --- |
| Analytics rule templates | [`libre-devops/sentinel-alert-rule/azurerm`](https://registry.terraform.io/modules/libre-devops/sentinel-alert-rule/azurerm/latest) |
| Workbook templates | [`libre-devops/sentinel-workbook/azurerm`](https://registry.terraform.io/modules/libre-devops/sentinel-workbook/azurerm/latest) |
| Playbook templates | [`libre-devops/logic-app-workflow/azurerm`](https://registry.terraform.io/modules/libre-devops/logic-app-workflow/azurerm/latest) |
| A data connector | see below |

**The data connector case is the sharpest edge.** What a solution installs for a connector is the
connector's *page* in Sentinel (`kind: StaticUI`, a `connectorUiConfig` and nothing else), not a
working connector. Nothing is ingested until the connector itself is created, with
[`libre-devops/sentinel-data-connector/azurerm`](https://registry.terraform.io/modules/libre-devops/sentinel-data-connector/azurerm/latest)
or, for Defender XDR specifically,
[`libre-devops/sentinel-defender-xdr-connector/azapi`](https://registry.terraform.io/modules/libre-devops/sentinel-defender-xdr-connector/azapi/latest).
The `solutions_with_ui_only_connectors` output names the solutions this applies to, so it is visible
rather than something you find out when nothing arrives.

Note that the Defender XDR connector module has a hard `acknowledge_unonboarded_workspace`
precondition: on a workspace connected to the unified Microsoft Defender portal the platform owns
that connector and Terraform must not manage it. Installing the *solution* is safe either way.

## Version pinning is a change gate, not a version selector

`expected_version` asserts that the catalog is serving exactly that version and fails the plan
otherwise. It cannot install an older version, because the catalog only ever exposes the current
one's content. Pin it when you want to be told before a Microsoft update lands rather than have it
apply quietly; clear it to track whatever is current.

## Usage

```hcl
module "sentinel" {
  source  = "libre-devops/sentinel/azurerm"
  version = "~> 4.0"

  workspace_id = module.log_analytics.workspace_ids["log-ldo-uks-prd-001"]
}

module "content_hub_solution" {
  source  = "libre-devops/sentinel-content-hub-solution/azapi"
  version = "~> 1.0"

  workspace_id = module.sentinel.onboarding_id

  solutions = {
    "azuresentinel.azure-sentinel-solution-microsoft365defender"     = {}
    "azuresentinel.azure-sentinel-solution-sentinelsoaressentials"   = {}
    "microsoftsentinelcommunity.azure-sentinel-solution-sochandbook" = { expected_version = "3.0.6" }
  }
}
```

`workspace_id` accepts the sentinel module's `onboarding_id` or a plain workspace id; the module
parses the workspace back out of either.

## Finding a solution's content id

The key of the `solutions` map is the package content id, in `publisherId.offerId` form. Two ways to
get one:

- Set `catalog_discovery_enabled = true` and read the `content_hub_catalog` output, which lists every
  catalogued package with its content id, display name, version and deprecated flag.
- Read `SolutionMetadata.json` for the solution in the
  [Azure/Azure-Sentinel](https://github.com/Azure/Azure-Sentinel/tree/master/Solutions) repo and join
  its `publisherId` and `offerId` with a dot.

Do not infer the id from the display name. Microsoft Defender XDR is
`...-microsoft365defender`, not `...-microsoftthreatprotection`, and SOC Handbook publishes under
`microsoftsentinelcommunity`, not `azuresentinel`.

## What the module enforces

At plan: the content id shape, the api-version shapes, the numeric `expected_version` shape, and the
deployment name prefix. Per solution, a precondition that the package exists in this workspace's
catalog (with a message that tells you how to find the right id), that `expected_version` matches if
set, and that a package the catalog flags deprecated is not installed unless `allow_deprecated = true`
(104 of the 975 catalogued packages are deprecated, so this fires in practice). An advisory `check`
warns when a solution's template passes 75 percent of the ARM template limit of 4 MB.

## Notes worth knowing

- **State size.** Solution templates are large, and this module holds one copy per solution in state
  (Microsoft Defender XDR alone is 1.9 MB). Three solutions is roughly 4.4 MB of state. The template
  is passed to the install through azapi's `sensitive_body`, a write-only argument, so it is stored
  once rather than twice. Reading it through an ephemeral resource would keep it out of state
  entirely, but Terraform's test framework cannot mock ephemeral resource types, which would cost
  every plan-time unit test in `tests/`. That trade is revisitable when the limitation lifts.
- **ARM template limit.** A solution installs as one ARM deployment, so it is bound by the 4 MB
  template limit. Microsoft Defender XDR (374 content templates) sits at 1.9 MB today.
- **Deployment names.** Derived from the content id and capped at the ARM limit of 64 characters. The
  two Microsoft solutions above truncate to an identical 55 character prefix, so a hash suffix is
  appended to keep them distinct.
- **Permissions.** Installing content needs Microsoft Sentinel Contributor on the workspace.
- **api-versions are variables**, per the estate convention for azapi modules, so consumers are never
  pinned to this module's release cadence.

## Security scan exceptions

None. `tflint` and `trivy` are clean on the module and both examples, so there is no
`.trivyignore.yaml` in this repo.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11.0, < 2.0.0 |
| <a name="requirement_azapi"></a> [azapi](#requirement\_azapi) | >= 2.0.0, < 3.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_azapi"></a> [azapi](#provider\_azapi) | >= 2.0.0, < 3.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [azapi_resource.install](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.package](https://registry.terraform.io/providers/Azure/azapi/latest/docs/resources/resource) | resource |
| [azapi_resource.package](https://registry.terraform.io/providers/Azure/azapi/latest/docs/data-sources/resource) | data source |
| [azapi_resource.workspace](https://registry.terraform.io/providers/Azure/azapi/latest/docs/data-sources/resource) | data source |
| [azapi_resource_list.catalog](https://registry.terraform.io/providers/Azure/azapi/latest/docs/data-sources/resource_list) | data source |
| [azapi_resource_list.catalog_discovery](https://registry.terraform.io/providers/Azure/azapi/latest/docs/data-sources/resource_list) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_catalog_api_version"></a> [catalog\_api\_version](#input\_catalog\_api\_version) | API version for Microsoft.SecurityInsights/contentProductPackages, the read-only Content Hub catalog<br/>this module resolves solutions against. Variablised so consumers are never pinned to this module's<br/>release cadence. | `string` | `"2025-09-01"` | no |
| <a name="input_catalog_discovery_enabled"></a> [catalog\_discovery\_enabled](#input\_catalog\_discovery\_enabled) | Populate the content\_hub\_catalog output with every catalogued package (content id, display name, version, kind, deprecated flag), for finding the content id of a solution you only know by name. Off by default because it adds roughly 975 entries to state. | `bool` | `false` | no |
| <a name="input_deployment_api_version"></a> [deployment\_api\_version](#input\_deployment\_api\_version) | API version for Microsoft.Resources/deployments, the ARM deployment that actually installs a<br/>solution's content. See the README: the Content Hub install is an ARM deployment of the package's<br/>own template, not a plain PUT of the package resource. | `string` | `"2021-04-01"` | no |
| <a name="input_deployment_name_prefix"></a> [deployment\_name\_prefix](#input\_deployment\_name\_prefix) | Prefix for the generated ARM deployment name of each install. The rest of the name is derived from the solution's content id (and hash-suffixed when the combination would exceed the ARM limit of 64 characters). | `string` | `"sentinel-solution-"` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region passed to the solution template as its location and workspace-location parameters.<br/>Defaults to null, which reads the region from the target workspace, so the common case needs no<br/>input. Set it only to override that. | `string` | `null` | no |
| <a name="input_package_api_version"></a> [package\_api\_version](#input\_package\_api\_version) | API version for Microsoft.SecurityInsights/contentPackages, the installed-package record this module owns so that a destroy uninstalls the solution. | `string` | `"2025-09-01"` | no |
| <a name="input_resource_timeouts"></a> [resource\_timeouts](#input\_resource\_timeouts) | azapi operation timeouts for the install deployment and the package record. Create is bounded well<br/>below the azapi default of 30m: a solution that fails to install otherwise leaves azapi polling a<br/>stuck ARM deployment for the full default, hiding the real error behind a long hang. Large solutions<br/>(Microsoft Defender XDR carries 374 content templates) still install in well under a minute, so 20m<br/>is generous. | <pre>object({<br/>    create = optional(string, "20m")<br/>    read   = optional(string, "10m")<br/>    update = optional(string, "20m")<br/>    delete = optional(string, "30m")<br/>  })</pre> | `{}` | no |
| <a name="input_retry_error_message_regex"></a> [retry\_error\_message\_regex](#input\_retry\_error\_message\_regex) | Regular expressions azapi retries on when an install or package call fails. The default covers only<br/>the genuinely transient races: the Sentinel onboarding propagation race (a workspace onboarded in the<br/>same apply can still report "not onboarded to Microsoft Sentinel" for a short while), the freshly<br/>created workspace race, and throttling. It deliberately does NOT retry generic "not found" or 5xx<br/>errors, which for a content install are usually persistent faults that should fail fast. Set null to<br/>disable retries. | `list(string)` | <pre>[<br/>  "(?i)not onboarded to Microsoft Sentinel",<br/>  "(?i)workspace could not be found",<br/>  "(?i)too many requests"<br/>]</pre> | no |
| <a name="input_solutions"></a> [solutions](#input\_solutions) | Content Hub solutions to install, keyed by the package content id (its Content Hub identifier, for<br/>example "azuresentinel.azure-sentinel-solution-microsoft365defender"). Find an id in the catalog by<br/>display name with the content\_hub\_catalog output, or read it from the publisherId and offerId in the<br/>solution's SolutionMetadata.json in the Azure/Azure-Sentinel repo.<br/><br/>Per solution:<br/><br/>- expected\_version: assert the catalog is serving this exact version, and fail the plan if it is not.<br/>  This is a CHANGE GATE, not a version selector: the catalog only ever exposes the current version's<br/>  content, so an older version cannot be installed through this API. Leave null to track whatever<br/>  Microsoft currently publishes.<br/>- allow\_deprecated: install even though the catalog flags the package deprecated. Off by default, and<br/>  104 of the 975 catalogued packages are deprecated, so this guard fires in practice. | <pre>map(object({<br/>    expected_version = optional(string)<br/>    allow_deprecated = optional(bool, false)<br/>  }))</pre> | `{}` | no |
| <a name="input_workspace_id"></a> [workspace\_id](#input\_workspace\_id) | Resource id of the Sentinel-onboarded Log Analytics workspace to install into. Accepts the sentinel module's onboarding\_id or a plain workspace id, per the estate's pass-ids principle. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_content_hub_catalog"></a> [content\_hub\_catalog](#output\_content\_hub\_catalog) | The whole Content Hub catalog as a list of {contentId, displayName, version, kind, deprecated}, for discovering the content id of a solution you only know by name. Null unless catalog\_discovery\_enabled is true, because it adds roughly 975 entries to state. |
| <a name="output_deployment_ids"></a> [deployment\_ids](#output\_deployment\_ids) | Map of solution content id to the resource id of the ARM deployment that installed it. |
| <a name="output_deployment_names"></a> [deployment\_names](#output\_deployment\_names) | Map of solution content id to the generated ARM deployment name, which is derived from the content id and hash-suffixed when it would exceed the ARM limit of 64 characters. |
| <a name="output_installed_versions"></a> [installed\_versions](#output\_installed\_versions) | Map of solution content id to the version installed, which is the version the catalog was serving at apply time. |
| <a name="output_solution_ids"></a> [solution\_ids](#output\_solution\_ids) | Map of solution content id to the resource id of its installed contentPackages record, the resource whose deletion uninstalls the solution. |
| <a name="output_solution_ids_zipmap"></a> [solution\_ids\_zipmap](#output\_solution\_ids\_zipmap) | Map of solution content id to {name, id} for easy composition. |
| <a name="output_solutions"></a> [solutions](#output\_solutions) | Map of solution content id to everything resolved from the catalog for it: displayName, version, contentProductId, kind, schemaVersion and the deprecated flag. |
| <a name="output_solutions_with_ui_only_connectors"></a> [solutions\_with\_ui\_only\_connectors](#output\_solutions\_with\_ui\_only\_connectors) | Content ids of the installed solutions whose template ships a data connector. Read this: what a<br/>solution installs for a connector is the connector's PAGE in Sentinel (kind StaticUI), not a working<br/>connector. Nothing is ingested until the connector itself is created, for example with<br/>libre-devops/sentinel-data-connector/azurerm or libre-devops/sentinel-defender-xdr-connector/azapi. |
| <a name="output_workspace_id"></a> [workspace\_id](#output\_workspace\_id) | Resource id of the Sentinel-onboarded workspace the solutions were installed into, parsed back out of workspace\_id so an onboarding id resolves to its workspace. |
<!-- END_TF_DOCS -->