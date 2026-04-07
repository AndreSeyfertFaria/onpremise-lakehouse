# 1. Create Data Lake layers in S3
# We use for_each to avoid code repetition
resource "aws_s3_bucket" "lakehouse_layers" {
  for_each = toset(["bronze", "silver", "gold"])
  
  bucket = "data-lakehouse-${each.key}"

  # Ensures that the bucket and data are removed when running 'terraform destroy'
  force_destroy = true 
}

