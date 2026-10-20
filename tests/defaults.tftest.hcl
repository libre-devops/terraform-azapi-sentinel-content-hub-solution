# Plan-time tests with a mocked azapi provider: no cloud, no credentials. They pin the workspace id
# parsing (a plain id and a Sentinel onboarding id both resolve), the ARM deployment name derivation
# including the 64 character cap, and every input validation.
#
# Needs Terraform 1.17 or later: the template is read through an ephemeral resource, and 1.17 is the
# first release whose mock providers accept ephemeral resource types (mock_ephemeral below). Earlier
# versions fail validation with "No ephemeral resource types in mock providers".

mock_provider "azapi" {
  # The catalog projection is keyed by the content id with dots and hyphens folded to underscores,
  # so the mock has to answer on that folded key. Both a short id (fits the ARM name limit) and a
  # long one (overflows it) are stubbed so the name derivation can be tested both ways.
  mock_data "azapi_resource_list" {
    defaults = {
      output = {
        contoso_solution_demo = {
          contentId     = "contoso.solution-demo"
          productId     = "contoso.solution-demo-sl-aaaaaaaaaaaaa"
          version       = "1.0.0"
          displayName   = "Contoso Demo"
          kind          = "Solution"
          schemaVersion = "3.0.0"
          deprecated    = false
        }
        contoso_solution_retired = {
          contentId     = "contoso.solution-retired"
          productId     = "contoso.solution-retired-sl-bbbbbbbbbbbbb"
          version       = "1.0.0"
          displayName   = "Contoso Retired"
          kind          = "Solution"
          schemaVersion = "3.0.0"
          deprecated    = true
        }
        microsoftsentinelcommunity_azure_sentinel_solution_sochandbook = {
          contentId     = "microsoftsentinelcommunity.azure-sentinel-solution-sochandbook"
          productId     = "microsoftsentinelcommunity.azure-sentinel-solution-sl-bo62w63p3do4u"
          version       = "3.0.6"
          displayName   = "SOC Handbook"
          kind          = "Solution"
          schemaVersion = "3.0.0"
          deprecated    = false
        }
      }
    }
  }

  # Serves both uses of this data source: the workspace read (location) and the package read (its
  # JMESPath projections, which fall back to empty when absent). The module only ever touches the
  # attribute relevant to each.
  mock_data "azapi_resource" {
    defaults = {
      output = {
        location = "uksouth"
      }
    }
  }

  # The ephemeral template read that feeds the install's sensitive_body.
  mock_ephemeral "azapi_resource_action" {
    defaults = {
      output = {
        template = {
          parameters = {
            location             = {}
            workspace            = {}
            "workspace-location" = {}
          }
          resources = []
        }
      }
    }
  }
}

variables {
  workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-t/providers/Microsoft.OperationalInsights/workspaces/log-t"
  location     = "uksouth"
}

run "parses_a_plain_workspace_id" {
  command = plan

  assert {
    condition     = output.workspace_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-t/providers/Microsoft.OperationalInsights/workspaces/log-t"
    error_message = "A plain workspace id passes through unchanged."
  }
}

run "parses_a_sentinel_onboarding_id_back_to_its_workspace" {
  command = plan

  variables {
    workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-t/providers/Microsoft.OperationalInsights/workspaces/log-t/providers/Microsoft.SecurityInsights/onboardingStates/default"
  }

  assert {
    condition     = output.workspace_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-t/providers/Microsoft.OperationalInsights/workspaces/log-t"
    error_message = "An onboarding id is trimmed back to the workspace it hangs off, so the module accepts either."
  }
}

run "derives_a_readable_deployment_name" {
  command = plan

  variables {
    solutions = {
      "contoso.solution-demo" = {}
    }
  }

  assert {
    condition     = output.deployment_names["contoso.solution-demo"] == "sentinel-solution-contoso-solution-demo"
    error_message = "A content id that fits keeps its readable derived name, with dots folded to hyphens."
  }
}

run "hash_suffixes_a_name_that_would_overflow" {
  command = plan

  variables {
    solutions = {
      "microsoftsentinelcommunity.azure-sentinel-solution-sochandbook" = {}
    }
  }

  assert {
    condition     = length(output.deployment_names["microsoftsentinelcommunity.azure-sentinel-solution-sochandbook"]) == 64
    error_message = "An overflowing name is truncated to 55 characters plus a hyphen and 8 hash characters."
  }

  assert {
    condition     = can(regex("-[0-9a-f]{8}$", output.deployment_names["microsoftsentinelcommunity.azure-sentinel-solution-sochandbook"]))
    error_message = "The truncated name carries a hash suffix so two long content ids cannot collide."
  }
}

run "unknown_solution_fails_with_a_useful_message" {
  command = plan

  variables {
    solutions = {
      "contoso.solution-does-not-exist" = {}
    }
  }

  expect_failures = [data.azapi_resource.package]
}

run "version_gate_fails_when_the_catalog_has_moved_on" {
  command = plan

  variables {
    solutions = {
      "contoso.solution-demo" = { expected_version = "9.9.9" }
    }
  }

  expect_failures = [data.azapi_resource.package]
}

run "version_gate_passes_on_an_exact_match" {
  command = plan

  variables {
    solutions = {
      "contoso.solution-demo" = { expected_version = "1.0.0" }
    }
  }

  assert {
    condition     = output.installed_versions["contoso.solution-demo"] == "1.0.0"
    error_message = "A matching expected_version installs the catalog version."
  }
}

run "deprecated_solution_is_blocked_by_default" {
  command = plan

  variables {
    solutions = {
      "contoso.solution-retired" = {}
    }
  }

  expect_failures = [data.azapi_resource.package]
}

run "deprecated_solution_installs_when_acknowledged" {
  command = plan

  variables {
    solutions = {
      "contoso.solution-retired" = { allow_deprecated = true }
    }
  }

  assert {
    condition     = output.solutions["contoso.solution-retired"].deprecated == true
    error_message = "The deprecated flag is surfaced on the solutions output even when the install is allowed."
  }
}

run "content_id_must_be_publisher_dot_offer" {
  command = plan

  variables {
    solutions = {
      "not-a-content-id" = {}
    }
  }

  expect_failures = [var.solutions]
}

run "expected_version_must_be_numeric" {
  command = plan

  variables {
    solutions = {
      "azuresentinel.azure-sentinel-solution-microsoft365defender" = { expected_version = "latest" }
    }
  }

  expect_failures = [var.solutions]
}

run "workspace_id_must_be_a_workspace" {
  command = plan

  variables {
    workspace_id = "/subscriptions/0/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/x"
  }

  expect_failures = [var.workspace_id]
}

run "catalog_api_version_must_be_an_api_version" {
  command = plan

  variables {
    catalog_api_version = "v1"
  }

  expect_failures = [var.catalog_api_version]
}

run "package_api_version_must_be_an_api_version" {
  command = plan

  variables {
    package_api_version = "latest"
  }

  expect_failures = [var.package_api_version]
}

run "deployment_api_version_must_be_an_api_version" {
  command = plan

  variables {
    deployment_api_version = "2021"
  }

  expect_failures = [var.deployment_api_version]
}

run "deployment_name_prefix_is_constrained" {
  command = plan

  variables {
    deployment_name_prefix = "has spaces and is far too long to be a sensible prefix"
  }

  expect_failures = [var.deployment_name_prefix]
}
