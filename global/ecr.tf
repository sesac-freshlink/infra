module "ecr" {
  source = "../modules/ecr"

  repositories = var.ecr_repositories
}
