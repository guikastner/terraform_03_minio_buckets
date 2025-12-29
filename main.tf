locals {
  server_input = trimspace(var.server)
  lower_input  = lower(local.server_input)
  has_https    = startswith(local.lower_input, "https://")
  has_http     = startswith(local.lower_input, "http://")
  normalized_url = local.has_https || local.has_http ? local.server_input : format("https://%s", local.server_input)
  normalized_url_clean = trimsuffix(local.normalized_url, "/")
  normalized_lower = lower(local.normalized_url)
  normalized_https = startswith(local.normalized_lower, "https://")
  normalized_http  = startswith(local.normalized_lower, "http://")

  server_no_scheme = local.normalized_https ? substr(local.normalized_url, 8, length(local.normalized_url) - 8) : (local.normalized_http ? substr(local.normalized_url, 7, length(local.normalized_url) - 7) : local.normalized_url)
  server_host_port = element(split("/", local.server_no_scheme), 0)
  server_parts     = split(":", local.server_host_port)

  minio_host    = local.server_parts[0]
  explicit_port = length(local.server_parts) > 1 ? tonumber(local.server_parts[1]) : null
  scheme_https  = local.normalized_https
  scheme_http   = local.normalized_http

  minio_port    = local.explicit_port != null ? local.explicit_port : (local.scheme_https ? 443 : (local.scheme_http ? 80 : 9000))
  minio_ssl     = local.scheme_https
  minio_server  = format("%s:%d", local.minio_host, local.minio_port)

  bucket_config_file = var.bucket_config_file != "" ? var.bucket_config_file : "${path.module}/buckets.json"
  bucket_config      = jsondecode(file(local.bucket_config_file))
  bucket_list        = try(local.bucket_config.buckets, [])
  bucket_map = {
    for bucket in local.bucket_list :
    bucket.name => {
      folders = tolist(try(bucket.folders, []))
      public  = try(bucket.public, false)
    }
  }

  folder_specs = flatten([
    for bucket_name, bucket in local.bucket_map : [
      for folder in bucket.folders : {
        bucket_name = bucket_name
        folder_name = trimspace(folder)
      } if trimspace(folder) != ""
    ]
  ])

  folder_map = {
    for spec in local.folder_specs :
    format("%s/%s", spec.bucket_name, spec.folder_name) => {
      bucket_name = spec.bucket_name
      folder_name = spec.folder_name
      keep_key    = format("%s/.keep", spec.folder_name)
    }
  }

  public_bucket_map = {
    for bucket_name, bucket in local.bucket_map :
    bucket_name => bucket
    if bucket.public
  }

  html_target_bucket      = try(local.bucket_list[0], null)
  html_target_bucket_name = try(local.html_target_bucket.name, null)
  html_target_folder_raw  = trimspace(try(local.html_target_bucket.folders[0], ""))
  html_target_folder      = local.html_target_folder_raw != "" ? local.html_target_folder_raw : null
  html_target             = local.html_target_bucket_name != null && local.html_target_folder != null ? {
    bucket_name = local.html_target_bucket_name
    object_key  = format("%s/index.html", local.html_target_folder)
  } : null

  html_source = "${path.module}/index.html"

  mc_alias      = format("tf-%s", substr(sha1(local.normalized_url_clean), 0, 8))
  mc_config_dir = "${path.module}/.mc-tf"

}

provider "minio" {
  minio_server = local.minio_server
  minio_ssl    = local.minio_ssl
  minio_user   = var.user
  minio_password = var.password
}

resource "null_resource" "mc_alias" {
  triggers = {
    endpoint        = local.normalized_url_clean
    alias           = local.mc_alias
    access_key_hash = sha256(var.user)
    secret_key_hash = sha256(var.password)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-EOT
      set -euo pipefail
      mc alias set --config-dir "$MC_CONFIG_DIR" ${local.mc_alias} ${local.normalized_url_clean} "$MC_ACCESS_KEY" "$MC_SECRET_KEY"
    EOT

    environment = {
      MC_CONFIG_DIR = local.mc_config_dir
      MC_ACCESS_KEY = var.user
      MC_SECRET_KEY = var.password
    }
  }
}

resource "null_resource" "bucket_create" {
  for_each = local.bucket_map

  triggers = {
    bucket = each.key
    public = tostring(each.value.public)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-EOT
      set -euo pipefail
      mc mb --ignore-existing --config-dir "$MC_CONFIG_DIR" ${local.mc_alias}/${each.key}
      if [ "${each.value.public}" = "true" ]; then
        mc anonymous set download --config-dir "$MC_CONFIG_DIR" ${local.mc_alias}/${each.key}
      fi
    EOT

    environment = {
      MC_CONFIG_DIR = local.mc_config_dir
    }
  }

  depends_on = [null_resource.mc_alias]
}

resource "minio_s3_object" "subfolder" {
  for_each   = local.folder_map
  bucket_name = each.value.bucket_name
  object_name = each.value.keep_key
  content     = "placeholder" # provider exige algum conteúdo para criar o objeto

  depends_on = [null_resource.bucket_create]
}

resource "minio_s3_bucket_policy" "public_read" {
  for_each = local.public_bucket_map
  bucket   = each.key

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowListBucket"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:ListBucket"]
        Resource  = [
          format("arn:aws:s3:::%s", each.key)
        ]
      },
      {
        Sid       = "AllowGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject"]
        Resource = [
          format("arn:aws:s3:::%s", each.key),
          format("arn:aws:s3:::%s/*", each.key)
        ]
      }
    ]
  })

  depends_on = [null_resource.bucket_create]
}

resource "minio_s3_object" "index_html" {
  count       = var.copyhtml && local.html_target != null ? 1 : 0
  bucket_name = local.html_target.bucket_name
  object_name = local.html_target.object_key
  source      = local.html_source
  content_type = "text/html; charset=utf-8"

  depends_on = [null_resource.bucket_create]
}
