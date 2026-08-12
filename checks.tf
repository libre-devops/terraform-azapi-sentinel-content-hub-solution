# Advisory: a Content Hub solution installs as a single ARM deployment, so its template is bound by
# the ARM template limit of 4 MB. The biggest first-party solutions are already a meaningful fraction
# of that (Microsoft Defender XDR ships 374 content templates at roughly 1.9 MB), so warn while there
# is still headroom rather than letting a future version fail the apply outright.
check "solution_template_within_arm_limits" {
  assert {
    condition     = length(local.oversized_solutions) == 0
    error_message = "These solution templates are within 25 percent of the ARM template limit of 4 MB and may fail to deploy as they grow: ${join(", ", local.oversized_solutions)} (advisory)."
  }
}
