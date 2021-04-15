output internal_ip_addresses {
  value = google_compute_address.validator_internal.*.address
}

output ip_addresses {
  value = google_compute_address.validator.*.address
}

output self_links {
  value = google_compute_instance.validator.*.self_link
}
