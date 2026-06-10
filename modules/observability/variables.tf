variable "project_name" {
  description = "Inherited from root."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,28}[a-z0-9])?$", var.project_name))
    error_message = "project_name must be 1-30 chars: lowercase alphanumeric and hyphens, start/end alphanumeric."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group the observability resources live in."
  type        = string
}
