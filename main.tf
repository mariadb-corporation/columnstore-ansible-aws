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
    self        = "true"
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

  ingress {
    description = "Prometheus Exporter"
    from_port   = 9100
    to_port     = 9100
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

resource "aws_instance" "mcs1" {
  ami               = var.aws_ami
  availability_zone = var.aws_zone
  instance_type     = var.aws_mariadb_instance_size
  key_name          = var.key_pair_name
  root_block_device {
    volume_size = 100
  }
  user_data              = file("terraform_includes/create-user.sh")
  vpc_security_group_ids = [aws_security_group.mcs_traffic.id]
  tags = {
    Name = "mcs1"
  }
}

resource "aws_instance" "mcs2" {
  ami               = var.aws_ami
  availability_zone = var.aws_zone
  instance_type     = var.aws_mariadb_instance_size
  key_name          = var.key_pair_name
  root_block_device {
    volume_size = 100
  }
  user_data              = file("terraform_includes/create-user.sh")
  vpc_security_group_ids = [aws_security_group.mcs_traffic.id]
  tags = {
    Name = "mcs2"
  }
}

resource "aws_instance" "mcs3" {
  ami               = var.aws_ami
  availability_zone = var.aws_zone
  instance_type     = var.aws_mariadb_instance_size
  key_name          = var.key_pair_name
  root_block_device {
    volume_size = 100
  }
  user_data              = file("terraform_includes/create-user.sh")
  vpc_security_group_ids = [aws_security_group.mcs_traffic.id]
  tags = {
    Name = "mcs3"
  }
}

resource "aws_instance" "mx1" {
  ami                    = var.aws_ami
  availability_zone      = var.aws_zone
  instance_type          = var.aws_maxscale_instance_size
  key_name               = var.key_pair_name
  user_data              = file("terraform_includes/create-user.sh")
  vpc_security_group_ids = [aws_security_group.mcs_traffic.id]
  tags = {
    Name = "mx1"
  }
}

resource "aws_instance" "mx2" {
  ami                    = var.aws_ami
  availability_zone      = var.aws_zone
  instance_type          = var.aws_maxscale_instance_size
  key_name               = var.key_pair_name
  user_data              = file("terraform_includes/create-user.sh")
  vpc_security_group_ids = [aws_security_group.mcs_traffic.id]
  tags = {
    Name = "mx2"
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

resource "aws_ebs_volume" "metadata" {
  availability_zone    = var.aws_zone
  iops                 = 3000
  multi_attach_enabled = true
  size                 = 100
  type                 = "io1"
}

resource "aws_volume_attachment" "metadata_mount1" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.metadata.id
  instance_id = aws_instance.mcs1.id
}

resource "aws_volume_attachment" "metadata_mount2" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.metadata.id
  instance_id = aws_instance.mcs2.id
}

resource "aws_volume_attachment" "metadata_mount3" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.metadata.id
  instance_id = aws_instance.mcs3.id
}

resource "aws_elasticache_cluster" "mcscache" {
  cluster_id           = "mcscache"
  engine               = var.elasticache_engine
  node_type            = "cache.r6g.large"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis6.x"
  engine_version       = "6.x"
  port                 = var.elasticache_port
  availability_zone    = var.aws_zone
  security_group_ids   = [aws_security_group.mcs_traffic.id]
}
