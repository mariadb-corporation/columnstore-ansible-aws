output "ansible_inventory" {
  value = local_file.AnsibleInventory.filename
}

output "ansible_variables" {
  value = local_file.AnsibleVariables.filename
}

output "ansible_config" {
  value = local_file.AnsibleConfig.filename
}

locals {
  columnstore_nodes = [
    for i in range(0, length(aws_instance.columnstore_node)) : 
    {
      name        = "mcs${i+1}"
      public_dns  = aws_instance.columnstore_node[i].public_dns
      private_dns = aws_instance.columnstore_node[i].private_dns
      private_ip  = aws_instance.columnstore_node[i].private_ip
      id          = aws_instance.columnstore_node[i].id
    }
  ]

  maxscale_nodes = [
    for i in range(0, length(aws_instance.maxscale_instance)) : 
    {
      name        = "mx${i+1}"
      public_dns  = aws_instance.maxscale_instance[i].public_dns
      private_dns = aws_instance.maxscale_instance[i].private_dns
      private_ip  = aws_instance.maxscale_instance[i].private_ip
      id          = aws_instance.maxscale_instance[i].id
    }
  ]
}

resource "local_file" "AnsibleInventory" {
  content = templatefile("terraform_includes/inventory.tmpl",
    {
      columnstore_nodes = local.columnstore_nodes,
      maxscale_nodes    = local.maxscale_nodes
    }
  )
  filename = "inventory/hosts"
}

resource "local_file" "AnsibleVariables" {
  content = templatefile("terraform_includes/all.tmpl",
    {
      admin_pass               = var.admin_pass,
      admin_user               = var.admin_user,
      aws_access_key           = var.aws_access_key,
      aws_region               = var.aws_region,
      aws_secret_key           = var.aws_secret_key,
      aws_zone                 = var.aws_zone,
      cej_pass                 = var.cej_pass,
      cej_user                 = var.cej_user,
      cmapi_key                = var.cmapi_key,
      mariadb_enterprise_token = var.mariadb_enterprise_token,
      mariadb_version          = var.mariadb_version,
      maxscale_pass            = var.maxscale_pass,
      maxscale_user            = var.maxscale_user,
      maxscale_version         = var.maxscale_version,
      pcs_pass                 = var.pcs_pass,
      repli_pass               = var.repli_pass,
      repli_user               = var.repli_user,
      s3_bucket                = var.use_s3 ? aws_s3_bucket.s3_bucket[0].id : null,
      s3_domain                = var.s3_domain,
      s3_ssl_disable           = var.s3_ssl_disable,
      s3_use_http              = var.s3_use_http,
      use_s3                   = var.use_s3,
    }
  )
  filename = "inventory/group_vars/all.yml"
}

resource "local_file" "AnsibleConfig" {
  content = templatefile("terraform_includes/ansible.tmpl",
    {
      ssh_key_file = var.ssh_key_file
    }
  )
  filename = "ansible.cfg"
}
