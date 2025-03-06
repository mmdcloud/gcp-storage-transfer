resource "google_storage_bucket" "bucket" {
  name          = var.bucket_name
  storage_class = var.storage_class
  location      = var.location
  force_destroy = var.force_destroy
}

resource "google_storage_bucket_object" "objects" {
  count  = length(var.objects)
  bucket = google_storage_bucket.bucket.name
  name   = var.objects[count.index].name
  source = var.objects[count.index].source
}
