provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

resource "aws_security_group" "mcs_traffic" {
  name   = "mcs_traffic"
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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mcs_traffic"
  }
}

resource "aws_instance" "columnstore_node" {
  count             = var.num_columnstore_nodes
  ami               = var.aws_ami
  subnet_id         = var.aws_subnet
  availability_zone = var.aws_zone
  instance_type     = var.aws_mariadb_instance_size
  key_name          = var.key_pair_name
  root_block_device {
    volume_size = 100
  }
  user_data              = file("terraform_includes/create_user.sh")
  vpc_security_group_ids = [aws_security_group.mcs_traffic.id]
  tags = {
    Name = "mcs${count.index + 1}"
  }
}

resource "aws_instance" "maxscale_instance" {
  count             = var.num_maxscale_instances
  ami               = var.aws_ami
  availability_zone = var.aws_zone
  instance_type     = var.aws_maxscale_instance_size
  key_name          = var.key_pair_name
  root_block_device {
    volume_size = 40
  }
  user_data              = file("terraform_includes/create_user.sh")
  vpc_security_group_ids = [aws_security_group.mcs_traffic.id]
  tags = {
    Name = "mx${count.index + 1}"
  }
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
  count        = var.num_columnstore_nodes
  device_name  = "/dev/sdf"
  volume_id    = aws_ebs_volume.storagemanager.id
  instance_id  = aws_instance.columnstore_node[count.index].id
}
