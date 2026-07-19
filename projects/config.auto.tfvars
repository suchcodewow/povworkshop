# Non-secret config for the projects factory. Committed and auto-loaded, so a
# fresh clone needs no local tfvars.
#
# parent, billing_account, attendee_emails and shared_editor_emails are NOT here
# on purpose — they come from Secret Manager via workshop.py
# (TF_VAR_*). Setting them here would override those secrets.

prefix = "prj"
