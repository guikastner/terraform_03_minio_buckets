variable "server" {
  description = "Host MinIO (aceita http(s)://host:porta ou apenas um domínio/host)."
  type        = string
}

variable "user" {
  description = "Usuário/Access key do MinIO."
  type        = string
}

variable "password" {
  description = "Senha/Secret key do MinIO."
  type        = string
  sensitive   = true
}

variable "copyhtml" {
  description = "Se true, envia o arquivo index.html para a subpasta criada."
  type        = bool
  default     = false
}

variable "bucket_config_file" {
  description = "Caminho para o JSON com a lista de buckets e pastas de primeiro nível."
  type        = string
  default     = ""
}
