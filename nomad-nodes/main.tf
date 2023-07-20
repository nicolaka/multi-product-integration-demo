terraform {
  required_providers {
    doormat = {
      source  = "doormat.hashicorp.services/hashicorp-security/doormat"
      version = "~> 0.0.6"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.8.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "~> 0.66.0"
    }

    vault = {
      source = "hashicorp/vault"
      version = "~> 3.18.0"
    }

    nomad = {
      source = "hashicorp/nomad"
      version = "2.0.0-beta.1"
    }
  }
}

provider "doormat" {}

provider "hcp" {}

data "doormat_aws_credentials" "creds" {
  provider = doormat
  role_arn = "arn:aws:iam::365006510262:role/tfc-doormat-role_nomad-nodes"
}

provider "aws" {
  region     = var.region
  access_key = data.doormat_aws_credentials.creds.access_key
  secret_key = data.doormat_aws_credentials.creds.secret_key
  token      = data.doormat_aws_credentials.creds.token
}

data "terraform_remote_state" "networking" {
  backend = "remote"

  config = {
    organization = var.tfc_account_name
    workspaces = {
      name = "networking"
    }
  }
}

data "terraform_remote_state" "hcp_clusters" {
  backend = "remote"

  config = {
    organization = var.tfc_account_name
    workspaces = {
      name = "hcp-clusters"
    }
  }
}

data "terraform_remote_state" "nomad_cluster" {
  backend = "remote"

  config = {
    organization = var.tfc_account_name
    workspaces = {
      name = "nomad-cluster"
    }
  }
}

data "hcp_packer_image" "ubuntu_lunar_hashi_amd" {
  bucket_name    = "ubuntu-lunar-hashi"
  component_type = "amazon-ebs.amd"
  channel        = "latest"
  cloud_provider = "aws"
  region         = "us-east-2"
}

data "hcp_packer_image" "ubuntu_lunar_hashi_arm" {
  bucket_name    = "ubuntu-lunar-hashi"
  component_type = "amazon-ebs.arm"
  channel        = "latest"
  cloud_provider = "aws"
  region         = "us-east-2"
}

resource "aws_launch_template" "nomad_client_x86_launch_template" {
  name_prefix   = "lt-"
  image_id      = data.hcp_packer_image.ubuntu_lunar_hashi_amd.cloud_image_id
  instance_type = "t3a.medium"

  network_interfaces {
    associate_public_ip_address = false
    security_groups = [ 
      data.terraform_remote_state.nomad_cluster.outputs.nomad_sg,
      data.terraform_remote_state.networking.outputs.hvn_sg_id
    ]
  }

  private_dns_name_options {
    hostname_type = "resource-name"
  }

  user_data = base64encode(
    templatefile("${path.module}/scripts/nomad-node.tpl",
      {
        nomad_license      = var.nomad_license,
        consul_ca_file     = data.terraform_remote_state.hcp_clusters.outputs.consul_ca_file,
        consul_config_file = data.terraform_remote_state.hcp_clusters.outputs.consul_config_file
        consul_acl_token   = data.terraform_remote_state.hcp_clusters.outputs.consul_root_token
      }
    )
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "nomad_client_x86_asg" {
  desired_capacity  = 2
  max_size          = 5
  min_size          = 1
  health_check_type = "EC2"
  health_check_grace_period = "60"

  name = "nomad-client-x86"

  launch_template {
    id = aws_launch_template.nomad_client_x86_launch_template.id
    version = aws_launch_template.nomad_client_x86_launch_template.latest_version
  }
  
  vpc_zone_identifier = data.terraform_remote_state.networking.outputs.subnet_ids

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_template" "nomad_client_arm_launch_template" {
  name_prefix   = "lt-"
  image_id      = data.hcp_packer_image.ubuntu_lunar_hashi_arm.cloud_image_id
  instance_type = "t4g.medium"

  network_interfaces {
    associate_public_ip_address = false
    security_groups = [ 
      data.terraform_remote_state.nomad_cluster.outputs.nomad_sg,
      data.terraform_remote_state.networking.outputs.hvn_sg_id
    ]
  }

  private_dns_name_options {
    hostname_type = "resource-name"
  }

  user_data = base64encode(
    templatefile("${path.module}/scripts/nomad-node.tpl",
      {
        nomad_license      = var.nomad_license,
        consul_ca_file     = data.terraform_remote_state.hcp_clusters.outputs.consul_ca_file,
        consul_config_file = data.terraform_remote_state.hcp_clusters.outputs.consul_config_file
        consul_acl_token   = data.terraform_remote_state.hcp_clusters.outputs.consul_root_token
      }
    )
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "nomad_client_arm_asg" {
  desired_capacity  = 2
  max_size          = 5
  min_size          = 1
  health_check_type = "EC2"
  health_check_grace_period = "60"

  name = "nomad-client-arm"

  launch_template {
    id = aws_launch_template.nomad_client_arm_launch_template.id
    version = aws_launch_template.nomad_client_arm_launch_template.latest_version
  }
  
  vpc_zone_identifier = data.terraform_remote_state.networking.outputs.subnet_ids

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}