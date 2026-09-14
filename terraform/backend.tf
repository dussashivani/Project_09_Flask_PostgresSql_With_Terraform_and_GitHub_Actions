terraform {
  backend "s3" {
    bucket       = "terraform-state-shivani-project9-518216637461"
    key          = "greeting-app/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
