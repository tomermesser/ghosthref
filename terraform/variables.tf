variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.2.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the single public subnet"
  type        = string
  default     = "10.2.1.0/24"
}

variable "my_ip_cidr" {
  description = "Your IP address (with /32) allowed to reach SSH, the site, Jenkins, and Kibana"
  type        = string
  default     = "0.0.0.0/32" # CHANGE to your real public IP before applying
}

variable "instance_type_small" {
  description = "Instance type for the k3s server and Jenkins"
  type        = string
  default     = "t3.small"
}

variable "instance_type_data" {
  description = "Instance type for the data host (Postgres, Redis, Elasticsearch, Kibana)"
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair in your account"
  type        = string
  default     = "ghosthref-key"
}

variable "github_webhook_cidrs" {
  description = "GitHub's published webhook-delivery IP ranges (api.github.com/meta -> hooks), IPv4 only"
  type        = list(string)
  default = [
    "192.30.252.0/22",
    "185.199.108.0/22",
    "140.82.112.0/20",
    "143.55.64.0/20",
  ]
}

variable "alert_email" {
  description = "Email address for the AWS Budget alarm"
  type        = string
}
