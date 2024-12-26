terraform {
  backend "s3" {
    bucket = "kriday-bucket"        # Your S3 bucket name
    key    = "terraform/statefile.tfstate"  # The key path for the state file in the bucket
    region = "ap-northeast-1"              # The region where the S3 bucket is located
  }
}
