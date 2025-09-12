provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key != "" ? var.aws_access_key : null
  secret_key = var.aws_secret_key != "" ? var.aws_secret_key : null
  token = var.aws_session_token != "" ? var.aws_session_token : null
  profile = var.aws_profile != "" ? var.aws_profile : null
}

# We use external VPC (that we don't create here), but we need to reference it
data "aws_vpc" "selected" {
  id = var.aws_vpc
}

# If create_key_pair is true, we create a new key pair
resource "tls_private_key" "generated_key" {
  count = var.create_key_pair ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  count = var.create_key_pair ? 1 : 0
  key_name   = local.effective_key_pair_name
  public_key = tls_private_key.generated_key[0].public_key_openssh
  tags = {
    Name = local.effective_key_pair_name,
    "Created by" = "Terraform"
  }
}

resource "local_file" "private_key" {
  count    = var.create_key_pair ? 1 : 0
  content  = tls_private_key.generated_key[0].private_key_pem
  filename = var.ssh_key_file
  file_permission = "0600"
}

# Explicitly wait for the key pair to be created before using it
# This is a workaround for the fact that the key pair is not immediately available after creation
resource "null_resource" "wait_for_key_pair" {
  count = var.create_key_pair ? 1 : 0
  depends_on = [aws_key_pair.generated_key]
  provisioner "local-exec" {
    command = "sleep 10"
  }
}

resource "aws_security_group" "mcs_traffic" {
  name   = "${var.deployment_prefix}_${var.security_group_name}"
  vpc_id = var.aws_vpc

  ingress {
    description = "Internal Traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description = "Remote Management"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "MariaDB"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "MaxScale GUI"
    from_port   = 8989
    to_port     = 8989
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow access to the shared EFS from the dev host VPC if the flag is set
  dynamic "ingress" {
    for_each = var.shared_efs_include_dev_host ? [1] : []

    content {
      description = "Allow EFS access from dev host VPC"
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = [data.aws_vpc.selected.cidr_block]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.deployment_prefix}_${var.security_group_name}"
  }
}

resource "aws_instance" "columnstore_node" {
  count             = var.num_columnstore_nodes
  ami               = var.aws_ami
  subnet_id         = var.aws_subnet
  availability_zone = var.aws_zone
  instance_type     = var.aws_mariadb_instance_size
  key_name          = local.effective_key_pair_name
  associate_public_ip_address = true
  root_block_device {
    volume_size = var.columnstore_node_root_block_size
    volume_type = "gp3"
    iops        = 16000
  }
  user_data              = file("terraform_includes/create_user.sh")
  vpc_security_group_ids = [aws_security_group.mcs_traffic.id]
  tags = merge(
    {
      Name = "${var.deployment_prefix}-mcs${count.index + 1}"
    },
    var.additional_tags
  )
  depends_on = [null_resource.wait_for_key_pair]
}

resource "aws_instance" "maxscale_instance" {
  count             = var.num_maxscale_instances
  ami               = var.aws_ami
  subnet_id         = var.aws_subnet
  availability_zone = var.aws_zone
  instance_type     = var.aws_maxscale_instance_size
  key_name          = local.effective_key_pair_name
  associate_public_ip_address = true
  root_block_device {
    volume_size = var.maxscale_node_root_block_size
  }
  user_data              = file("terraform_includes/create_user.sh")
  vpc_security_group_ids = [aws_security_group.mcs_traffic.id]
  tags = merge(
    {
      Name = "${var.deployment_prefix}-mx${count.index + 1}"
    },
    var.additional_tags
  )
  depends_on = [null_resource.wait_for_key_pair]
}

resource "aws_s3_bucket" "s3_bucket" {
  count         = var.use_s3 ? 1 : 0
  bucket_prefix = "mcs-"
  force_destroy = true
  tags = {
    Name = "mcs-bucket"
  }
}

resource "aws_ebs_volume" "storagemanager" {
  count                   = var.use_s3 ? 1 : 0
  availability_zone       = var.aws_zone
  size                    = 100
  multi_attach_enabled    = true
  type                    = "io2"
  iops                    = 3000
  tags = {
    Name = "mcs-metadata"
  }
}

resource "aws_volume_attachment" "ebs_attachment" {
  count        = var.use_s3 ? var.num_columnstore_nodes : 0
  device_name  = "/dev/sdf"
  volume_id    = aws_ebs_volume.storagemanager[0].id
  instance_id  = aws_instance.columnstore_node[count.index].id
}

# Creates an internal EFS file system for ColumnStore data when not using S3
resource "aws_efs_file_system" "internal_efs" {
  count = var.use_s3 ? 0 : 1

  tags = {
    Name = "${var.deployment_prefix}-internal-efs"
    Purpose = "columnstore-data"
  }
}

# Creates a mount target for the internal EFS in the specified subnet
resource "aws_efs_mount_target" "internal_efs_target" {
  count          = var.use_s3 ? 0 : 1
  file_system_id = aws_efs_file_system.internal_efs[0].id
  subnet_id      = var.aws_subnet

  # Allows traffic to the EFS only from instances in the mcs_traffic security group
  security_groups = [
    aws_security_group.mcs_traffic.id
  ]
}

# Creates the EFS file system if the create_shared_efs flag is enabled
resource "aws_efs_file_system" "shared_efs" {
  count = var.create_shared_efs ? 1 : 0

  tags = {
    Name = "${var.deployment_prefix}-shared-efs"
  }
}

# Creates a mount target for the EFS in the specified subnet.
# EC2 instances in the VPC use mount targets to connect to the EFS.
# There must be at least one mount target in each availability zone where instances need access.
resource "aws_efs_mount_target" "shared_efs_target" {
  count          = var.create_shared_efs ? 1 : 0
  file_system_id = aws_efs_file_system.shared_efs[0].id
  subnet_id      = var.aws_subnet

  # Allows traffic to the EFS only from instances in the mcs_traffic security group
  security_groups = [
    aws_security_group.mcs_traffic.id
  ]
}

# If we create a new key pair, prepend its name with the deployment prefix to avoid conflicts with existing key pairs
locals {
  effective_key_pair_name = var.create_key_pair ? "${var.deployment_prefix}_${var.key_pair_name}" : var.key_pair_name
}
