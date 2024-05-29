
variable "location" {
    description = "Specifies the supported Azure location where the resource exists. Changing this forces a new resource to be created."
    type        = string
}

variable "rg_name" {
    description = "The name of the resource group."
    type        = string
}

variable "image_version" {
    description = "Version of the image."
    type        = string
}

######
# Tags
######

variable "tags" {
  description = "A mapping of labels to assign to all resources"
  type        = map(string)
}

variable "tags_sa" {
  description = "A mapping of labels to assign to all resources"
  type        = map(string)
}