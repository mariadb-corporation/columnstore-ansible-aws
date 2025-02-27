######## Before editing this file, be sure to read the AWS documentation on:
########
########  * VPCs
########  * Programmatic Access
########
######## Grab your enterprise token from the MariaDB website (https://customers.mariadb.com/downloads/token/).

######## EDIT THESE ITEMS

# Determines if Columnstore LocalStorage or S3 Topology
variable "use_s3" {
  type    = bool
  default = true
}

variable "mariadb_enterprise_token" {
  type    = string
  default = "YOUR MARIADB ENTERPRISE TOKEN HERE"
}

variable "cmapi_key" {
  type    = string
  default = "CREATE A COLUMNSTORE API KEY HERE - ANY RANDOM STRING"
}

variable "pcs_pass" {
  type    = string
  default = "SET PCS CLUSTER PASSWORD HERE - ANY RANDOM STRING"
}

######## DATABASE CREDENTIALS

variable "admin_user" {
  type    = string
  default = "CHOOSE A MARIADB ADMIN USERNAME HERE"
}

variable "admin_pass" {
  type    = string
  default = "SET YOUR MARIADB ADMIN USER PASSWORD HERE"
}

variable "maxscale_user" {
  type    = string
  default = "CHOOSE A MAXSCALE USERNAME HERE"
}

variable "maxscale_pass" {
  type    = string
  default = "SET YOUR MAXSCALE USER PASSWORD HERE"
}

variable "repli_user" {
  type    = string
  default = "CHOOSE A REPLICA USERNAME HERE"
}

variable "repli_pass" {
  type    = string
  default = "SET YOUR REPLICA USER PASSWORD HERE"
}

variable "cej_user" {
  type    = string
  default = "CHOOSE A COLUMNSTORE UTILITY USERNAME HERE"
}

variable "cej_pass" {
  type    = string
  default = "SET YOUR COLUMNSTORE UTILITY USER PASSWORD HERE"
}

######## Cluster Size

variable "num_columnstore_nodes" {
  description = "Number of Columnstore nodes"
  type        = number
  default     = 3
}

variable "num_maxscale_instances" {
  description = "Number of MaxScale instances"
  type        = number
  default     = 2
}

######## MariaDB Versions

variable "mariadb_version" {
  type    = string
  default = "11.4"
}

variable "maxscale_version" {
  type    = string
  default = "latest"
}

######## AWS CONFIGURATION 

variable "key_pair_name" {
  type    = string
  default = "YOUR AWS KEY PAIR NAME HERE"
}

variable "ssh_key_file" {
  type    = string
  default = "/PATH/TO/KEY/FILE.PEM"
}

variable "aws_access_key" {
  type    = string
  default = "YOUR AWS ACCESS KEY HERE"
}

variable "aws_secret_key" {
  type    = string
  default = "YOUR AWS SECRET KEY HERE"
}

# aws_region will influence aws_vpc, aws_subnet, aws_zone & aws_ami
variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "aws_zone" {
  type    = string
  default = "us-west-2a"
}

# Confirm your VPC exists in aws_region choosen
variable "aws_vpc" {
  type    = string
  default = "YOUR AWS VPC ID HERE"
}

# Confirm your subnet exists in aws_vpc choosen
variable "aws_subnet" {
  type    = string
  default = "YOUR AWS SUBNET ID HERE"
}

######## AWS EC2 Options 

# AMI's are specific to regions
variable "aws_ami" {
  type    = string
  default = "ami-0faa73a0256c330e9"
}

variable "security_group_name" {
  type    = string
  default = "mcs_traffic"
}

variable "aws_mariadb_instance_size" {
  type    = string
  default = "c6a.8xlarge"
}

variable "aws_maxscale_instance_size" {
  type    = string
  default = "c6a.large"
}

variable "columnstore_node_root_block_size" {
  description = "Number of GB for EBS root storage on columnstore nodes"
  type        = number
  default     = 1000
}

variable "maxscale_node_root_block_size" {
  description = "Number of GB for EBS root storage on maxscale nodes"
  type        = number
  default     = 100
}

# Prefix of the cluster to standup - Any Name You Want
variable "deployment_prefix" {
  type    = string
  default = "testing"
}

variable "additional_tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {
    description = "testing columnstore"
  }
}

variable "s3_domain" {
  type    = string
  default = "amazonaws.com"
}


variable "s3_ssl_disable" {
  type    = bool
  default = false
}

variable "s3_use_http" {
  type    = bool
  default = false
}

######## Optional Install Options

variable "reboot" {
  type    = bool
  default = true
}

# Optional - Requires "mariadb_rpms_path" to be defined - Argumemts for cs_package_manager to auto download rpms 
variable "cs_package_manager_custom_version" {
  type    = string
  default = ""
}

# The path mariadb and columnstore rpms are preloaded to after terraform apply --auto-approve, but before running ansible
variable "mariadb_rpms_path" {
  type    = string
  default = ""
}