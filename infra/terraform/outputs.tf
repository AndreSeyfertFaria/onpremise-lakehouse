# 1. List the name of all created buckets (Bronze, Silver, Gold)
output "lakehouse_buckets" {
  description = "Names of the buckets created for the Data Lake"
  value       = { for k, v in aws_s3_bucket.lakehouse_layers : k => v.bucket }
}

# 2. Displays the LocalStack test endpoint (for reference)
output "localstack_endpoint" {
  description = "Endpoint used for local AWS services"
  value       = "http://localhost:4566"
}