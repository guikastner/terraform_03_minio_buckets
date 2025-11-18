# MinIO Buckets with OpenTofu

This repository ships an OpenTofu configuration that provisions one or more MinIO buckets plus top-level folders. It relies on the official `aminueza/minio` provider, so everything runs directly against your self-hosted MinIO endpoint—no AWS provider required.

## Features
- Creates a bucket for every entry in the JSON manifest (`bucket_config_file`).
- Generates `.keep` placeholder objects for all requested folders so the directory tree appears immediately.
- Optionally uploads the bundled `index.html` page to the first folder of the first bucket when `copyhtml = true`.
- Applies `public-read` ACLs and read/list bucket policies only to buckets marked as `public: true`.
- Exposes the `index_html_url` output so you know where the HTML was uploaded.

## Prerequisites
- [OpenTofu](https://opentofu.org/) v1.6 or greater (`tofu` CLI available in PATH).
- A reachable MinIO server (HTTP or HTTPS) plus valid access/secret keys with permission to create buckets and objects.

## Configuration Steps
1. Copy `terraform.tfvars.example` to `terraform.tfvars` and edit the following values:
   - `server`: MinIO endpoint. Both `https://host:port` and plain hostnames are accepted (HTTPS is assumed when the scheme is omitted).
   - `user` / `password`: MinIO access key and secret key.
   - `bucket_config_file`: Path to the JSON manifest (defaults to `buckets.json`).
   - `copyhtml`: Boolean flag controlling whether `index.html` is copied.
2. Customize the JSON manifest referenced above. Example:
   ```json
   {
     "buckets": [
       {
         "name": "data-app",
         "folders": ["incoming", "processed"],
         "public": true
       },
       {
         "name": "logs-app",
         "folders": ["errors"],
         "public": false
       }
     ]
   }
   ```
   - `name` – Bucket identifier.
   - `folders` – Array of first-level folders to create. Empty strings are ignored.
   - `public` – Optional boolean (default `false`). When `true`, the bucket receives `public-read` ACLs and policies so anonymous users can list and read.
   When `copyhtml = true`, only the first folder of the first bucket receives the HTML file; all other folders get only the `.keep` placeholder.

## Running OpenTofu
```bash
tofu init    # download providers and set up .terraform
tofu plan    # preview resources
tofu apply   # type 'yes' to create buckets and folders
```
After `tofu apply`, look for the `index_html_url` output if you enabled the HTML copy.

## Repository Layout
- `main.tf` – Provider configuration, locals, bucket/folder resources, and optional HTML upload logic.
- `variables.tf` – Input variables consumed by the configuration.
- `outputs.tf` – Declares the `index_html_url` output.
- `buckets.json` – Default manifest you can edit or replace.
- `index.html` – Basic landing page that can be uploaded to MinIO.
- `terraform.tfvars.example` – Template with all required inputs; the actual `terraform.tfvars` file is gitignored to keep secrets safe.

## Additional Notes
- Buckets are created with `force_destroy = false` for safety. Delete objects manually (or change the setting) before destroying buckets with data.
- Because the configuration only depends on `aminueza/minio`, it works in air-gapped environments as long as the provider plugin is available locally.
