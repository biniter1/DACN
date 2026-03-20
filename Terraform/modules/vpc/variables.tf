# Project
variable "name_project" {
  type = string
}

variable "Environment" {
  type = string
}


# VPC
variable "cidr_vpc" {
  type = string
}
variable "azs" {
  type = list(string)
}
variable "public_subnets" {
  type = list(string)
}
variable "private_subnets" {
  type = list(string)
}