variable "gcp_project_id" {
  type = string
}

variable "gcp_region" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_name" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "subnet_cidr" {
  type = string
}

variable "tags" {
  type = map(string)
  default = {}
}
