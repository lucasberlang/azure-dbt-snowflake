
terraform {
  backend "azurerm" {
    resource_group_name  = "az-euw-syn-pract-cloud-baseline-rg01-pro"
    storage_account_name = "azeuwsynbasstategsa01pro"
    container_name       = "az-euw-syn-pract-cloud-tfstate-container01-pro"
    key                  = "dbt_baseline.terraform.tfstate"
  }
}
