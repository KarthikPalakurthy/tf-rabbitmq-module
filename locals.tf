#For any resource created, tags are mandatory
locals {
  common_tags = {
    env= var.env
    project = "roboshop"
    business_unit = "ecommerce"
    owner = "ecommerce-project"
  }
}