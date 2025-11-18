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
}

provider "minio" {
  minio_server = local.minio_server
  minio_ssl    = local.minio_ssl
  minio_user   = var.user
  minio_password = var.password
}

resource "minio_s3_bucket" "this" {
  for_each = local.bucket_map
  bucket   = each.key
  acl      = each.value.public ? "public-read" : "private"
}

resource "minio_s3_object" "subfolder" {
  for_each   = local.folder_map
  bucket_name = minio_s3_bucket.this[each.value.bucket_name].bucket
  object_name = each.value.keep_key
  content     = "placeholder" # provider exige algum conteúdo para criar o objeto
}

resource "minio_s3_bucket_policy" "public_read" {
  for_each = local.public_bucket_map
  bucket   = minio_s3_bucket.this[each.key].bucket

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
}

resource "minio_s3_object" "index_html" {
  count       = var.copyhtml && local.html_target != null ? 1 : 0
  bucket_name = minio_s3_bucket.this[local.html_target.bucket_name].bucket
  object_name = local.html_target.object_key
  source      = local.html_source
  content_type = "text/html; charset=utf-8"
}
