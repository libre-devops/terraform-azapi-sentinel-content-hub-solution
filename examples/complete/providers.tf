provider "azurerm" {
  features {}

  storage_use_azuread = true
  use_oidc            = true
}

# azapi drives the Content Hub catalog reads and the solution install deployment; it authenticates
# exactly like azurerm (OIDC in CI, az CLI locally).
provider "azapi" {
  use_oidc = true
}
