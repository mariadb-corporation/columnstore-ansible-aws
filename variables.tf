######## Before editing this file, be sure to read the AWS documentation on:
########
########  * VPCs
########  * Programmatic Access

######## EDIT THESE ITEMS

# Determines if Columnstore LocalStorage or S3 Topology
variable "use_s3" {
  type    = bool
  default = true
}

variable "mariadb_enterprise_token" {
  type    = string
  description = "MariaDB Enterprise Token (https://customers.mariadb.com/downloads/token/)"
  nullable = false
}

variable "cmapi_key" {
  type    = string
  description = "Columnstore API Key (any random string)"
  nullable = false
}

variable "pcs_pass" {
  type    = string
  description = "PCS Cluster Password (any random string)"
  nullable = false
}

######## DATABASE CREDENTIALS

variable "admin_user" {
  type    = string
  description = "MariaDB Admin Username"
  nullable = false
}

variable "admin_pass" {
  type    = string
  description = "MariaDB Admin Password (any random string)"
  nullable = false
}

variable "maxscale_user" {
  type    = string
  description = "MaxScale Username"
  nullable = false
}

variable "maxscale_pass" {
  type    = string
  description = "MaxScale Password (any random string)"
  nullable = false
}

variable "repli_user" {
  type    = string
  description = "Replica Username"
  nullable = false
}

variable "repli_pass" {
  type    = string
  description = "Replica Password (any random string)"
  nullable = false
}

variable "cej_user" {
  type    = string
  description = "Columnstore Utility Username"
  nullable = false
}

variable "cej_pass" {
  type    = string
  description = "Columnstore Utility Password (any random string)"
  nullable = false
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
  description = "MariaDB Server Version"
  default = "11.4"
}

variable "maxscale_version" {
  type    = string
  description = "MaxScale Version"
  default = "latest"
}

######## AWS CONFIGURATION
# Possible Authentication Combinations (leave unused variables = "")
# 1) aws_access_key + aws_secret_key
# 2) aws_access_key + aws_secret_key + aws_session_token
# 3) aws_profile

variable "aws_access_key" {
  type    = string
  description = "AWS Access Key"
  default = ""
}

variable "aws_secret_key" {
  type    = string
  description = "AWS Secret Key"
  default = ""
}

variable "aws_session_token" {
  type    = string
  description = "AWS Session Token"
  default = ""
}

variable "aws_profile" {
  type    = string
  description = "AWS Profile Name"
  default = ""
}

variable "key_pair_name" {
  type    = string
  description = "AWS Key Pair Name"
  nullable = false
}

variable "ssh_key_file" {
  type    = string
  description = "Path to SSH key file"
  nullable = false
}

variable "aws_region" {
  type    = string
  description = "AWS Region, will influence aws_vpc, aws_subnet, aws_zone & aws_ami"
  default = "us-west-2"
}

variable "aws_zone" {
  type    = string
  description = "AWS Zone"
  default = "us-west-2a"
}

# Confirm your VPC exists in aws_region choosen
variable "aws_vpc" {
  type    = string
  description = "AWS VPC ID"
  nullable = false
}

# Confirm your subnet exists in aws_vpc choosen
variable "aws_subnet" {
  type    = string
  description = "AWS Subnet ID"
  nullable = false
}

######## AWS EC2 Options

# If you are looking for AMIs of official Ubuntu distibutions,
#  look here: https://cloud-images.ubuntu.com/locator/ec2/
variable "aws_ami" {
  type    = string
  description = "AWS AMI ID, AMI's are specific to regions"
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

# Optional - Requires "mariadb_rpms_path" to be defined - Arguments for cs_package_manager to auto download rpms
variable "cs_package_manager_custom_version" {
  type    = string
  default = ""
}

# The path mariadb and columnstore rpms are preloaded to after terraform apply --auto-approve, but before running ansible
variable "mariadb_rpms_path" {
  type    = string
  default = ""
}