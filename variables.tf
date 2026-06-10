variable "project_name" {
  description = "Short identifier used to name all resources (rg-<name>, st<name>, etc.). Lowercase alphanumeric + hyphens, 1-30 chars, start/end alphanumeric."
  type        = string
  default     = "azure-pipeline-lab"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,28}[a-z0-9])?$", var.project_name))
    error_message = "project_name must be 1-30 chars: lowercase alphanumeric and hyphens, must start and end with alphanumeric (Azure resource naming compatibility)."
  }
}

variable "location" {
  description = "Azure region for all resources. Match the region used for bootstrap to avoid cross-region egress."
  type        = string
  default     = "centralus"

  validation {
    condition     = can(regex("^[a-z0-9]+$", var.location))
    error_message = "location must be a valid Azure region name (lowercase alphanumeric, no spaces). Examples: centralus, eastus, westus2."
  }
}
