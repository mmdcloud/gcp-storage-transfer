resource "google_storage_transfer_job" "storage_transfer_service" {
  description = var.description
  transfer_spec {
    transfer_options {
      delete_objects_unique_in_sink = var.delete_objects_unique_in_sink
    }
    gcs_data_source {
      bucket_name = var.source_bucket_name
    }
    gcs_data_sink {
      bucket_name = var.dest_bucket_name
    }
  }
  dynamic "schedule" {
    for_each = length(var.schedule) > 0 ? var.schedule : []
    content {
      schedule_start_date {
        year  = schedule.value["start_year"]
        month = schedule.value["start_month"]
        day   = schedule.value["start_day"]
      }
      schedule_end_date {
        year  = schedule.value["end_year"]
        month = schedule.value["end_month"]
        day   = schedule.value["end_day"]
      }
      start_time_of_day {
        hours   = schedule.value["hours"]
        minutes = schedule.value["minutes"]
        seconds = schedule.value["seconds"]
        nanos   = schedule.value["nanos"]
      }
      repeat_interval = schedule.value["schedule_repeat_interval"]
    }

  }
  dynamic "notification_config" {
    for_each = var.notification_config
    content {
      pubsub_topic   = notification_config.value["pubsub_topic"]
      event_types    = notification_config.value["event_types"]
      payload_format = notification_config.value["payload_format"]
    }
  }
}
