terraform {
    required_providers {
        confluent = {
            source = "confluentinc/confluent"
            version = "1.23.0"
        }
    }
}

provider "confluent" {
    # Set through env vars as:
    # CONFLUENT_CLOUD_API_KEY="CLOUD-KEY"
    # CONFLUENT_CLOUD_API_SECRET="CLOUD-SECRET"
}
# --------------------------------------------------------
# This 'random_id' will make whatever you create (names, etc)
# unique in your account.
# --------------------------------------------------------
resource "random_id" "id" {
    byte_length = 4
}
# -------------------------------------------------------
# Environment
# -------------------------------------------------------
resource "confluent_environment" "simple_env" {
    display_name = "${local.env_name}-${random_id.id.hex}"
    lifecycle {
        prevent_destroy = false
    }
}
# --------------------------------------------------------
# Schema Registry
# --------------------------------------------------------
data "confluent_schema_registry_region" "simple_sr_region" {
    cloud = "AWS"
    region = "us-east-2"
    package = "ESSENTIALS" 
}
resource "confluent_schema_registry_cluster" "simple_sr_cluster" {
    package = data.confluent_schema_registry_region.simple_sr_region.package
    environment {
        id = confluent_environment.simple_env.id 
    }
    region {
        id = data.confluent_schema_registry_region.simple_sr_region.id
    }
    lifecycle {
        prevent_destroy = false
    }
}
# --------------------------------------------------------
# Cluster
# --------------------------------------------------------
resource "confluent_kafka_cluster" "simple_cluster" {
    display_name = "${local.cluster_name}"
    availability = "SINGLE_ZONE"
    cloud = "AWS"
    region = "us-east-2"
    basic {}
    environment {
        id = confluent_environment.simple_env.id
    }
    lifecycle {
        prevent_destroy = false
    }
}
# --------------------------------------------------------
# Service Accounts
# --------------------------------------------------------
resource "confluent_service_account" "app_manager" {
    display_name = "app-manager-${random_id.id.hex}"
    description = "${local.description}"
}
resource "confluent_service_account" "sr" {
    display_name = "sr-${random_id.id.hex}"
    description = "${local.description}"
}
resource "confluent_service_account" "clients" {
    display_name = "client-${random_id.id.hex}"
    description = "${local.description}"
}
# --------------------------------------------------------
# Role Bindings
# --------------------------------------------------------
resource "confluent_role_binding" "app_manager_environment_admin" {
    principal = "User:${confluent_service_account.app_manager.id}"
    role_name = "EnvironmentAdmin"
    crn_pattern = confluent_environment.simple_env.resource_name
}
resource "confluent_role_binding" "sr_environment_admin" {
    principal = "User:${confluent_service_account.sr.id}"
    role_name = "EnvironmentAdmin"
    crn_pattern = confluent_environment.simple_env.resource_name
}
resource "confluent_role_binding" "clients_cluster_admin" {
    principal = "User:${confluent_service_account.clients.id}"
    role_name = "CloudClusterAdmin"
    crn_pattern = confluent_kafka_cluster.simple_cluster.rbac_crn
}
# --------------------------------------------------------
# Credentials
# --------------------------------------------------------
resource "confluent_api_key" "app_manager_kafka_cluster_key" {
    display_name = "app-manager-${local.cluster_name}-key-${random_id.id.hex}"
    description = "${local.description}"
    owner {
        id = confluent_service_account.app_manager.id
        api_version = confluent_service_account.app_manager.api_version
        kind = confluent_service_account.app_manager.kind
    }
    managed_resource {
        id = confluent_kafka_cluster.simple_cluster.id
        api_version = confluent_kafka_cluster.simple_cluster.api_version
        kind = confluent_kafka_cluster.simple_cluster.kind
        environment {
            id = confluent_environment.simple_env.id
        }
    }
    depends_on = [
        confluent_role_binding.app_manager_environment_admin
    ]
}
resource "confluent_api_key" "sr_cluster_key" {
    display_name = "sr-${local.cluster_name}-key-${random_id.id.hex}"
    description = "${local.description}"
    owner {
        id = confluent_service_account.sr.id 
        api_version = confluent_service_account.sr.api_version
        kind = confluent_service_account.sr.kind
    }
    managed_resource {
        id = confluent_schema_registry_cluster.simple_sr_cluster.id
        api_version = confluent_schema_registry_cluster.simple_sr_cluster.api_version
        kind = confluent_schema_registry_cluster.simple_sr_cluster.kind 
        environment {
            id = confluent_environment.simple_env.id
        }
    }
    depends_on = [
      confluent_role_binding.sr_environment_admin
    ]
}
resource "confluent_api_key" "clients_kafka_cluster_key" {
    display_name = "clients-${local.cluster_name}-key-${random_id.id.hex}"
    description = "${local.description}"
    owner {
        id = confluent_service_account.clients.id
        api_version = confluent_service_account.clients.api_version
        kind = confluent_service_account.clients.kind
    }
    managed_resource {
        id = confluent_kafka_cluster.simple_cluster.id
        api_version = confluent_kafka_cluster.simple_cluster.api_version
        kind = confluent_kafka_cluster.simple_cluster.kind
        environment {
            id = confluent_environment.simple_env.id
        }
    }
    depends_on = [
        confluent_role_binding.clients_cluster_admin
    ]
}

resource "confluent_service_account" "app-ksql" {
  display_name = "app-ksql"
  description  = "Service account to manage 'example' ksqlDB cluster"

  lifecycle {
    prevent_destroy = false
  }
}

resource "confluent_role_binding" "app-ksql-kafka-cluster-admin" {
  principal   = "User:${confluent_service_account.app-ksql.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.simple_cluster.rbac_crn

  lifecycle {
    prevent_destroy = false
  }
}

resource "confluent_role_binding" "app-ksql-schema-registry-resource-owner" {
  principal   = "User:${confluent_service_account.app-ksql.id}"
  role_name   = "ResourceOwner"
  crn_pattern = format("%s/%s", confluent_schema_registry_cluster.simple_sr_cluster.resource_name, "subject=*")

  lifecycle {
    prevent_destroy = false
  }
}

resource "confluent_ksql_cluster" "example" {
  display_name = "example"
  csu          = 1
  kafka_cluster {
    id = confluent_kafka_cluster.simple_cluster.id
  }
  credential_identity {
    id = confluent_service_account.app-ksql.id
  }
  environment {
    id = confluent_environment.simple_env.id
  }
  depends_on = [
    confluent_role_binding.clients_cluster_admin,
    confluent_role_binding.app-ksql-schema-registry-resource-owner,
    confluent_schema_registry_cluster.simple_sr_cluster
  ]

  lifecycle {
    prevent_destroy = false
  }
}

output "client_key" {
    value = "${confluent_api_key.clients_kafka_cluster_key.id}, ${confluent_api_key.clients_kafka_cluster_key.secret}    "
    sensitive = true
}

output "sr_key" {
    value = "${confluent_api_key.sr_cluster_key.id}:${confluent_api_key.sr_cluster_key.secret}    "
    sensitive = true
}