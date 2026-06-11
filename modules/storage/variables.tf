variable "project_name" {
  description = "Inherited from root — drives resource naming (hyphens stripped for storage account)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,28}[a-z0-9])?$", var.project_name))
    error_message = "project_name must be 1-30 chars: lowercase alphanumeric and hyphens, start/end alphanumeric."
  }

  # Storage account name formula: "st" + replace(project_name, "-", "") + 6-char
  # random suffix. Azure caps storage account names at 24 chars (2 + 6 = 8 of
  # those are fixed), so the stripped project_name must fit in 16 chars or apply
  # fails at the Azure API with a cryptic error.
  validation {
    condition     = length(replace(var.project_name, "-", "")) <= 16
    error_message = "project_name with hyphens stripped must be <= 16 chars (Azure storage account names cap at 24: 'st' + stripped + 6-char random suffix)."
  }
}

variable "location" {
  description = "Azure region."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.location))
    error_message = "location must be a valid Azure region name (lowercase alphanumeric, no spaces)."
  }
}

variable "resource_group_name" {
  description = "Resource group the storage account lives in."
  type        = string
}

variable "tags" {
  description = "Tags applied to the storage account. Inherits from root composition."
  type        = map(string)
  default     = {}
}
