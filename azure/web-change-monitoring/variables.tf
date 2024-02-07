variable "my_ip" {
  type        = string
  description = "IP to be used for SSH access"
  default     = "x.x.x.x"
}
variable "domain" {
  type        = string
  description = "Domain name for the VM"
  default     = "example.com"
}
variable "subdomain" {
  type        = string
  description = "Subdomain name for the VM"
  default     = "nginx"
}
variable "username" {
  type        = string
  description = "username for nginx"
  default     = "username"
}
variable "password" {
  type        = string
  description = "password for nginx"
  default     = "password"
}
variable "email" {
  type        = string
  description = "email for certbot"
  default     = "webmaster@domain.com"
}
