variable "project_name" {
  description = "Inherited from root — drives resource naming."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,28}[a-z0-9])?$", var.project_name))
    error_message = "project_name must be 1-30 chars: lowercase alphanumeric and hyphens, start/end alphanumeric."
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
  description = "Resource group the function lives in."
  type        = string
}

variable "storage_account_id" {
  description = "Full resource ID of the queue storage account — scope for role assignments."
  type        = string
}

variable "storage_account_name" {
  description = "Name of the queue storage account — used by AzureWebJobsStorage and by application code via the QUEUE_STORAGE_ACCOUNT app setting."
  type        = string
}

variable "storage_account_access_key" {
  description = "Primary access key for the queue storage account. Used by AzureWebJobsStorage (host bookkeeping); application code still authenticates via MI. Phase 5 hardening removes this in favor of full-MI host."
  type        = string
  sensitive   = true
}

variable "inbox_container" {
  description = "Name of the inbox container — the blob trigger watches this."
  type        = string
}

variable "completed_container" {
  description = "Name of the completed container — where processed blobs are moved."
  type        = string
}

variable "table_name" {
  description = "Name of the tickets table — where the function writes ticket records."
  type        = string
}

variable "tags" {
  description = "Tags applied to function resources. Inherits from root composition."
  type        = map(string)
  default     = {}
}
