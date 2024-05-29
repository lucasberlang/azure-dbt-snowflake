# Introduction

The world of data is constantly evolving, demanding tools and platforms that facilitate the management and transformation of large volumes of information in an efficient and scalable way. One such tool is [DBT-Core](https://www.getdbt.com/), a powerful solution that allows data and analytics teams to transform and organise data in a manageable and reproducible environment.

In this article, we will explore how to integrate DBT into an environment that combines the capabilities of [Azure](https://azure.microsoft.com/) and [Snowflake](https://www.snowflake.com/), two of the most prominent cloud platforms for data management. Specifically, we will focus on the use of [Azure Container Instances](https://azure.microsoft.com/es-es/products/container-instances) also called ACI to run DBT containers, allowing for flexible and scalable management of data transformations while keeping costs in check.

In addition, we will address the Continuous Integration and Continuous Deployment (CI/CD) cycle using [GitHub](https://github.com/) and [Azure Container Registry](https://azure.microsoft.com/es-es/products/container-registry) also called ACR. This approach not only facilitates the automation of the process of building and deploying DBT container images, but also ensures that any changes to the transformation scripts are tested and deployed efficiently and reliably.

To ensure a consistent and reproducible implementation of all these components, we will use [Terraform](https://www.terraform.io/), an Infrastructure-as-Code (IaC) tool. Terraform enables the provisioning and management of infrastructure resources in a declarative manner, facilitating the deployment and configuration of cloud environments in an automated and efficient way.

At the end of this article we want to demonstrate the end to end of a DBT application, from the beginning when a developer starts to create his custom transformations to the production deployment of this development.

## Table of contents

- [Introduction](#introduction)
  - [Table of contents](#table-of-contents)
  - [What do you need to understand this article?](#what-do-you-need-to-understand-this-article)
  - [Architecture](#architecture)
  - [Deployment of infrastructure](#deployment-of-infrastructure)
  - [Snowflake setup](#snowflake-setup)
  - [DBT setup](#dbt-setup)
  - [Github Actions setup](#github-actions-setup)
  - [Conclusions](#conclusions)

## What do you need to understand this article?

- Some concepts of [Terraform](https://developer.hashicorp.com/terraform).
- Some concepts of [DBT](https://www.getdbt.com/).
- Some concepts of [Azure](https://azure.microsoft.com/).
- Some concepts from [Snowflake](https://www.snowflake.com/).
- A Azure and Snowflake account.

## Architecture

<p align="center">
  <img src="./images/snowflake_architecture.png" width="1500" title="hover text">
</p>

For all components used in DBT we will deploy a new resource group in azure and as a centrepiece for the processing part we will use ACI. The use of this service is because it allows us to deploy our containers in a simple way and at a very low cost. For the deployment of these containers we will use a Github Action. For this demo what we will do is that every time there is a new push on the main branch we will build the image of our development and publish it in ACR with the SHA of the commit as a tag. Once the image is published in ACR we will deploy the instances container to use the new image. For all this we will use Terraform, as we will see in more detail.

Once the new image is published and deployed, the container will be executed immediately, with all the logic you want to perform for the transformation. For some sensitive information, such as Snowflake credentials, we will use the azure key vault service, where we will store these credentials as a secret. When starting the container we will download the Snowflake credentials in order to make the connection against Snowflake.

The advantage of this architecture is that we will use the power of Snowflake for all the processing, since DBT will push down against the data warehouse that we indicate and we will not need almost no resources to execute the ACI. This opens up a world of possibilities as we can forget about the computation on the Azure side and we will only have to create different types of data warehouse in Snowflake for our different transformations.

## Deployment of infrastructure

Once the architecture has been explained, we are going to proceed to deploy all the components, for which we are going to use Terraform as an IaC tool. As important parts of this deployment we will have the most traditional infrastructure part which are the Resource groups, Azure Key Vault and Azure container Registry. You can find all the deployment code in the baseline folder.

Let's start with the explanation of the most classic infrastructure. For this deployment we will make use of three resources:

- [Azure Resource Group](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group)
- [Azure Container Registry](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_registry)
- [Azure Key Vault](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault)

These three resources are invoked in the `main.tf` repository and make use of the Azure provider for deployment:

```tf

provider "azurerm" {
  features {}
  # More information on the authentication methods supported by
  # the AzureRM Provider can be found here:
  # https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "rg" {
  name     = var.rg_name
  location = var.location

  tags = var.tags
}

resource "azurerm_container_registry" "acr" {
  name                = "dbtjobs"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  sku                 = "Basic"
  admin_enabled       = true
}

resource "azurerm_key_vault" "keyvault" {
  name                        = "secrets-aci"
  location                    = var.location
  resource_group_name         = azurerm_resource_group.rg.name
  enabled_for_disk_encryption = true
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  tenant_id                   = data.azurerm_client_config.current.tenant_id

  sku_name = "standard"
  tags = var.tags 
}

```

Once the baseline is deployed, it will only be necessary to create a secret in keyvault with the Snowflake key. To do this we will have to generate a key in Snowflake following this guide. Once we have created the key we will pass it to base64 and save it as a secret in key vault:

```bash
base64 -i snowflake_dbt.p8
```
For the deployment of the ACI part we will use the code that is stored in the folder infra. We make this separation in two folders because every time there is a change in the DBT code, the execution of this resource will be done and so we separate the baseline infrastructure from the development one. The only part that stands out is that we have to pass by variable the image that we will use in the deployment, this part is included in the action so that it is transparent to the developer.

```tf

provider "azurerm" {
  features {}
  # More information on the authentication methods supported by
  # the AzureRM Provider can be found here:
  # https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs
}

locals {
  image_name = "dbtjobs.azurecr.io/dbt/tpch_transform:${var.image_version}"
}

data "terraform_remote_state" "azure_baseline" {
  backend = "azurerm"
  config = {
    resource_group_name  = "az-euw-syn-pract-cloud-baseline-rg01-pro"
    storage_account_name = "azeuwsynbasstategsa01pro"
    container_name       = "az-euw-syn-pract-cloud-tfstate-container01-pro"
    key                  = "dbt_baseline.terraform.tfstate"
  }
}

resource "azurerm_container_group" "aci" {
  name                = "dbt-job-example"
  location            = var.location
  resource_group_name = var.rg_name
  ip_address_type     = "Public"
  os_type             = "Linux"
  restart_policy      = "Never"

  container {
    name   = "dbt"
    image  = local.image_name
    cpu    = "0.5"
    memory = "1"

    ports {
      port     = 80
      protocol = "TCP"
    }
    environment_variables = {
      ENV_KV_URL = "https://secrets-aci.vault.azure.net"
      ENV_SNOW_SECRET = "snowflake-certificate"
    }
  }

  image_registry_credential {
    server                    = "dbtjobs.azurecr.io"
    username = data.terraform_remote_state.azure_baseline.outputs.acr_admin_username
    password = data.terraform_remote_state.azure_baseline.outputs.acr_admin_password
  }

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

data "azurerm_key_vault" "secrets" {
  name                = "secrets-aci"
  resource_group_name = var.rg_name
}

resource "azurerm_role_assignment" "keyvault" {
  scope                = data.azurerm_key_vault.secrets.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_container_group.aci.identity.0.principal_id
}

```

To execute this apply with the environment variable, the following command will be used:

```bash

image_version=latest
terraform apply -auto-approve -var='image_version=${image_version}'

```

## Snowflake setup

Snowflake is a cloud data platform designed to handle large volumes of data and run complex analytics workloads. It is widely recognized for its unique architecture and its ability to deliver fast performance and unprecedented scalability. The key point of this platform is that it has completely separated storage from data processing since it stores data in compressed and columnar format in its own proprietary file system, which facilitates rapid recovery and processing and you can create different processing clusters to your different use cases. Compute clusters can dynamically grow or shrink based on workload needs.

Once all the infrastructure has been deployed we will move on to the Snowflake configuration. For this we need to have generated an account and create a warehouse for the demo. The dataset used to perform the transformations is the tpch_sf1, making use of the customer and orders tables for data cleansing and simple transformations.

For this demo we will use the COMPUTE_WH warehouse which we will then configure in DBT:

<p align="center">
  <img src="./images/snowflake_warehouses.png" width="1500" title="hover text">
</p>

To persist the information once it is transformed with DBT, we will generate a new database called DBT_MODELS. Within this database we will generate two new schemas: staging and staging_intermediate. In the first we will generate the first layer of data by cleaning certain columns to collect only the data we want, in the second scheme we will have the business information with the logic applied to the first layer with certain intersections. This last layer will be the one that can be exploited from visualization tools or the data scientist himself to perform any type of analysis:


<p align="center">
  <img src="./images/snowflake_databases.png" width="1500" title="hover text">
</p>

Finally we will generate a certificate in snowflake to connect from our DBT application, to follow this [guide](https://docs.snowflake.com/en/user-guide/key-pair-auth)

## DBT setup

DBT (data build tool) is a data transformation tool that allows data teams and analysts to efficiently transform, manage and document their data within their data warehouses. Designed to be used by professionals who already know SQL, DBT simplifies the development, testing, and deployment of data transformations through a code-based approach and collaborative workflows. Its strong point is that it does not consume processing resources since the computing resources are consumed by the warehouse it is using. In addition, it has a large number of connectors for the different leading tools on the market, such as Snowflake, Bigquery, Redshift and many others.

The use of DBT allows developers to generate their own classes and configurations so that they are reusable and in a very simple way since it allows the use of SQL. Furthermore, one of its greatest strengths is that it integrates very easily with different CI/CD tools to guarantee good practices in the development of applications and data products.

For this demo we will use the code found under the tpch_transform folder, and we will review the configuration part of the most important elements.

The first notable configuration file in this project is the dbt_project.yml file. This file contains important information that tells dbt how to operate your project. Among other things, it indicates how DBT has to save model information. A model is a representation of a table or view in the data warehouse, defined through an SQL file. Models are the fundamental unit of data transformations in dbt and allow users to organize and structure their data in a modular and reusable way.

In our case the dbt_project.yml configuration will be as follows:

```yml

# Name your project! Project names should contain only lowercase characters
# and underscores. A good package name should reflect your organization's
# name or the intended use of these models
name: 'tpch_transform'
version: '1.0.0'
config-version: 2

# This setting configures which "profile" dbt uses for this project.
profile: 'tpch_transform'

# These configurations specify where dbt should look for different types of files.
# The `model-paths` config, for example, states that models in this project can be
# found in the "models/" directory. You probably won't need to change these!
model-paths: ["models"]
analysis-paths: ["analyses"]
test-paths: ["tests"]
seed-paths: ["seeds"]
macro-paths: ["macros"]
snapshot-paths: ["snapshots"]

clean-targets:         # directories to be removed by `dbt clean`
  - "target"
  - "dbt_packages"
  - "dbt_modules"


# Configuring models
# Full documentation: https://docs.getdbt.com/docs/configuring-models

# In this example config, we tell dbt to build all models in the example/
# directory as views. These settings can be overridden in the individual model
# files using the `{{ config(...) }}` macro.
models:
  tpch_transform:
    intermediate:
      +materialized: table
      +labels:
        domain: finance
      +persist_docs:
        relation: true
        columns: true
      +schema: intermediate
    # Config indicated by + and applies to all files under models/example/
    staging:
      +materialized: view

```

An important part that we have is the way we want the model information to be persisted in snowflake. For the staging scheme we will save the information as views and for the intermediate scheme we will save the information as final tables.

Another important file in profiles.yml. The profiles.yml file in dbt is a configuration file that defines the database connection profiles that dbt will use to run its transformations. This file allows dbt to connect to different database environments (such as development, testing, and production) and manage the credentials and configurations required for each environment. In our case we will make the connection to snowflake and we have this configuration:

```yml

tpch_transform:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: ${account_id}.west-europe.azure

      user: ${user}
      private_key_path: /Users/${user}/.ssh/snowflake_dbt.p8

      role: ACCOUNTADMIN
      database: DBT_MODELS
      warehouse: COMPUTE_WH
      schema: staging
      client_session_keep_alive: False
      connect_retries: 0
      connect_timeout: 10
      retry_on_database_errors: False
      retry_all: False 
      reuse_connections: False
    pro:
      type: snowflake
      account: ${account_id}.west-europe.azure

      user: ${user}
      private_key_path: /snowflake_dbt.pem

      role: ACCOUNTADMIN
      database: DBT_MODELS
      warehouse: COMPUTE_WH
      schema: staging
      client_session_keep_alive: False
      connect_retries: 0
      connect_timeout: 10
      retry_on_database_errors: False
      retry_all: False 
      reuse_connections: False

```

In this example we have two profiles, one for the development environment and another for the production environment. Here we will configure the connection and the warehouse that we will use, as well as the role that we use for it and the user and credentials that we will use. There are also other settings such as timeout or the schema that we will use by default to persist the information if there is not one defined in the model.

To build the image we will use the Dockerfile file, in this we use the one provided by Azure as the base image. We also install some necessary libraries and our application to be able to execute it.

```Dockerfile

FROM mcr.microsoft.com/azure-cli as base

RUN apk add --no-cache unixodbc-dev g++ curl \
  && pip install -q --upgrade pip setuptools wheel \
  && pip install -q --no-cache-dir dbt-core \
  && pip install -q --no-cache-dir dbt-snowflake

COPY . /usr/app/tpch_transform

WORKDIR /usr/app/tpch_transform

ENV PYTHONUNBUFFERED=1

RUN chmod 700 /usr/app/tpch_transform/entrypoint.sh 

ENTRYPOINT ["/usr/app/tpch_transform/entrypoint.sh"]

```

Finally, we have the entrypoint.sh configuration files. This script is the one we will use when the image is uploaded. In this script, in addition to running DBT, we will obtain the snowflake certificate by connecting to the key vault. To do this we will obtain a connection token using the profile of the container instance and then we will recover the secret called snowflake_certificate that is added as an environment variable in the infrastructure part of the container.

```bash

#!/bin/sh

echo "================================="
echo "Starting new job"

echo "Retrieving snowflake certificate"
kv_url="$ENV_KV_URL/secrets/$ENV_SNOW_SECRET"
token=$(curl 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net' -H Metadata:true -s | jq -r '.access_token')


curl 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fvault.azure.net' -H Metadata:true
curl "$kv_url/?api-version=2016-10-01"  -H "Authorization: Bearer $token" | jq -r ".value" > /snowflake_dbt.64

base64 -d /snowflake_dbt.64 > /snowflake_dbt.pem 

echo "Executing new job on DBT"

dbt run -t pro

echo " Finished"
echo "================================="

```

In the transformation part we will zoom into the models folder, where we have all the transformation logic. There are two models created in it: staging and intermediate. In the first the only thing we will do is read from the orders and customer tables and we will generate two views.   We will find the definition of the views created in the schema.yml file and the connection to the source tables in the stg_sources.yaml file. The other two files with a .sql extension are the ones that have the logic of taking certain fields from these tables and generating new views with certain aliases.

File stg_customers.sql: 
```sql

select
    c_custkey as customer_id,
    c_name,
    c_address

 from {{ source('tpch', 'customer') }}

```

File stg_orders.sql:

```sql

select
    o_orderkey as order_id,
    o_custkey as customer_id,
    o_orderdate as order_date,
    o_orderstatus as status

from {{ source('tpch', 'orders') }}
 
```

In the intermediate model we will have something similar but without the need to have the connection to the source tables, since we already have it generated as a new staging model. In the files with the .sql extension we have the logic of crossings between the tables of the staging model.

File int_customers.sql:

```sql

with customers as (

    select * from {{ ref('stg_customers') }}

),

orders as (

    select * from {{ ref('stg_orders') }}

),

customer_orders as (

    select
        customer_id,
        min(order_date) as first_order_date,
        max(order_date) as most_recent_order_date,
        count(order_id) as number_of_orders

    from orders

    group by 1

),

final as (

    select
        customers.customer_id,
        customers.c_name,
        customers.c_address,
        customer_orders.first_order_date,
        customer_orders.most_recent_order_date,
        coalesce(customer_orders.number_of_orders, 0) as number_of_orders

    from customers

    left join customer_orders using (customer_id)

)

select * from final

```

File int_orders.sql:

```sql

with orders as (

    select * from {{ ref('stg_orders') }}

),

final as (

    select
        customer_id,

        min(order_date) as first_order_date,
        max(order_date) as most_recent_order_date,
        count(order_id) as number_of_orders

    from orders

    group by 1

)

select * from final

```

Once DBT is configured we can run our application from local with the following command:

```bash

dbt run

```

## Github Actions setup

GitHub Actions is a workflow automation platform that allows developers to automate software development tasks directly in their GitHub repositories. With GitHub Actions, users can define custom workflows that run in response to events in the repository, such as commits, pull requests, releases, and more.

The high-level architecture will be as follows:

<p align="center">
  <img src="./images/snowflake_architecture-CI-CD.png" width="1000" title="hover text">
</p>

For this demo, the flow we have created is developed so that every time there is a new commit in main, the github action is executed. This github action has two stages, the first is to build and publish the image to Azure Cointaner Registry. To do this, log in to Azure using credentials that we have saved on Github. The second stage of the action is to deploy the infrastructure part, for this we use the code from the folder below explained above. In the construction of the infrastructure we will pass the version of the image that we have previously built as a variable.

The configuration of secrets that we have made is this:

<p align="center">
  <img src="./images/secrets-github.png" width="1000" title="hover text">
</p>

Here we have the configuration for both the Azure credentials and the ACR credentials so we can log in to Docker.

The code we have left for the github action is the following:

```yml

on: [push]
name: DBT_Deploy_tpch_transform

env:
  ARM_CLIENT_ID: "${{ secrets.AZURE_CLIENT_ID }}"
  ARM_CLIENT_SECRET: "${{ secrets.AZURE_CLIENT_SECRET }}"
  ARM_SUBSCRIPTION_ID: "${{ secrets.AZURE_SUBSCRIPTION_ID }}"
  ARM_TENANT_ID: "${{ secrets.AZURE_TENANT_ID }}"

jobs:
    build-and-push:
        runs-on: ubuntu-latest
        steps:
        - name: 'Checkout GitHub Action'
          uses: actions/checkout@main
          
        - name: 'Login via Azure CLI'
          uses: azure/login@v1
          with:
            creds: ${{ secrets.AZURE_CREDENTIALS }}
        
        - uses: azure/docker-login@v1
          with:
            login-server: dbtjobs.azurecr.io
            username: ${{ secrets.REGISTRY_USERNAME }}
            password: ${{ secrets.REGISTRY_PASSWORD }}

        - run: |
            docker build . -t dbtjobs.azurecr.io/dbt/tpch_transform:${{ github.sha }}
            docker push dbtjobs.azurecr.io/dbt/tpch_transform:${{ github.sha }}
          working-directory: ./tpch_transform
    terraform-apply:
        name: 'Terraform Apply'
        needs: build-and-push
        runs-on: ubuntu-latest
        env:
          ARM_SKIP_PROVIDER_REGISTRATION: true
      
        steps:
        - name: Checkout
          uses: actions/checkout@v4
  
        - name: Setup Terraform
          uses: hashicorp/setup-terraform@v3
          with:
            terraform_version: "1.2.9"
    
        - name: Terraform Init
          run: terraform init
          working-directory: ./infra

        - name: Terraform Apply
          run: terraform apply -auto-approve -var='image_version=${{ github.sha }}'
          working-directory: ./infra

```

## Conclusions

Integrating DBT with Azure and Snowflake, using Azure Container Instances (ACI) and a CI/CD pipeline with GitHub and Azure Container Registry (ACR) for image registration, provides a robust and scalable solution for data transformation and management. Throughout this article, we have explored how each component contributes to creating an efficient and automated data pipeline, highlighting the following key takeaways:

* Efficiency and Scalability: The combination of DBT with Snowflake and Azure allows you to take advantage of the power of both platforms to handle large volumes of data and execute complex transformations. Azure Container Instances provide the flexibility to scale DBT operations based on project needs.

* Automation and Consistency with CI/CD: Implementing a Continuous Integration and Continuous Deployment (CI/CD) cycle with GitHub Actions and Azure Container Registry makes it easy to automate the build, test, and deployment of DBT images. This ensures that any changes to the transformation scripts are tested and deployed consistently and reliably.

* Infrastructure Management with Terraform: Using Terraform to deploy and manage infrastructure components provides a declarative and reproducible way to configure the environment, reducing the possibility of manual errors and improving the consistency of deployments.

* Modularity and Model Reuse: DBT promotes the creation of modular and reusable data models, which simplifies the management of data transformations and facilitates pipeline maintenance. This allows data teams to quickly adapt to changes in business requirements.

* Security and Best Practices: By separating sensitive configurations in the profiles.yml file and using GitHub for code management, security and collaboration practices are promoted, ensuring that credentials and configurations are handled in a secure and controlled manner.

In summary, the integration of these technologies and practices creates a modern, efficient and highly adaptable data environment, which not only improves the productivity of the data team, but also ensures that data transformation and analysis processes are robust, scalable. and aligned with the best practices of software development and DevOps. This configuration allows organizations to maximize the value of their data, providing accurate and timely insights for decision making and accelerating the creation of data products.