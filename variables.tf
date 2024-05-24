#### Before editing this file, be sure to read the AWS documentation on:
####
####  * VPCs
####  * Programmatic Access
####
#### Grab your enterprise token from the MariaDB website (https://customers.mariadb.com/downloads/token/).

#### EDIT THESE ITEMS

# Determines if LocalStorage or S3 Topology
variable "use_s3" {
  type    = bool
  default = true
}

variable "mariadb_enterprise_token" {
  type    = string
  default = "YOUR MARIADB ENTERPRISE TOKEN HERE"
}

variable "aws_access_key" {
  type    = string
  default = "YOUR AWS ACCESS KEY HERE"
}

variable "aws_secret_key" {
  type    = string
  default = "YOUR AWS SECRET KEY HERE"
}

variable "key_pair_name" {
  type    = string
  default = "YOUR AWS KEY PAIR NAME HERE"
}

variable "ssh_key_file" {
  type    = string
  default = "/PATH/TO/KEY/FILE.PEM"
}

variable "aws_vpc" {
  type    = string
  default = "YOUR AWS VPC ID HERE"
}

variable "aws_subnet" {
  type    = string
  default = "YOUR AWS SUBNET ID HERE"
}

variable "cmapi_key" {
  type    = string
  default = "CREATE A COLUMNSTORE API KEY HERE"
}

variable "pcs_pass" {
  type    = string
  default = "SET PCS CLUSTER PASSWORD HERE"
}

#### DATABASE CREDENTIALS

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

#### Cluster Size

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

#### MariaDB Versions

variable "mariadb_version" {
  type    = string
  default = "10.6"
}

variable "maxscale_version" {
  type    = string
  default = "latest"
}

#### AWS EC2 Options 

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "aws_zone" {
  type    = string
  default = "us-west-2a"
}

variable "aws_ami" {
  type    = string
  default = "ami-0bc06212a56393ee1"
}

variable "aws_mariadb_instance_size" {
  type    = string
  default = "c6a.8xlarge"
}

variable "aws_maxscale_instance_size" {
  type    = string
  default = "c6a.large"
}

#### DO NOT EDIT BELOW THIS POINT UNLESS YOU ARE FAMILIAR WITH THESE PARAMETERS

variable "s3_ssl_disable" {
  type    = bool
  default = false
}

variable "s3_use_http" {
  type    = bool
  default = false
}
variable "reboot" {
  type    = bool
  default = true
}

variable "s3_ssl_disable" {
  type    = bool
  default = false
}

variable "s3_use_http" {
  type    = bool
  default = false
}

variable "s3_domain" {
  type    = string
  default = "amazonaws.com"
}
