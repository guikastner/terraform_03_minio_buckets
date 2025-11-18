output "index_html_url" {
  description = "URL do index.html copiado para o primeiro bucket/pasta, caso copyhtml seja true."
  value       = var.copyhtml && local.html_target != null ? format("%s/%s/%s", local.normalized_url_clean, local.html_target.bucket_name, local.html_target.object_key) : null
}
