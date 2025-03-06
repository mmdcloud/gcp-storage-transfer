variable "description" {}
variable "delete_objects_unique_in_sink" {}
variable "notification_config" {
  type = list(object({
    pubsub_topic   = string
    event_types    = list(string)
    payload_format = string
  }))
}
variable "source_bucket_name" {}
variable "dest_bucket_name" {}

variable "schedule" {
  type = list(object({
    start_year = number
    start_month = number
    start_day = number

    end_year = number
    end_month = number
    end_day = number

    hours = number
    minutes = number
    seconds = number 
    nanos = number

    schedule_repeat_interval = string
  }))
}