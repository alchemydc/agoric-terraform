# Stackdriver Monitoring Dashboard

There presently is no support for creating Stackdriver monitoring dashboards via Terraform
So instead we have use the gcloud cli to import the dashboard from a json file

`gcloud monitoring dashboards create --config-from-file=hud.json`

If you make changes in the UI and want to export them as JSON, you can 

`gcloud monitoring dashboards list`
`gcloud monitoring dashboards describe projects/$PROJECT_ID/dashboards/$DASHBOARD_ID --format=json > dashboard.json`

