resource "grafana_rule_group" "this" {
  for_each = local.alertsfile_map

  name       = each.value.name
  folder_uid = var.folder_uid
  org_id     = var.org_id

  # There is no function supporting Golang's "duration" (format of interval within an alert group)
  # Use timeadd() function which supports it.
  interval_seconds = (
    (parseint(formatdate("s", timeadd("1970-01-01T00:00:00Z", try(each.value.interval, var.default_evaluation_interval_duration))), 10) * 1) +
    (parseint(formatdate("m", timeadd("1970-01-01T00:00:00Z", try(each.value.interval, var.default_evaluation_interval_duration))), 10) * 60) +
    (parseint(formatdate("h", timeadd("1970-01-01T00:00:00Z", try(each.value.interval, var.default_evaluation_interval_duration))), 10) * 3600)
  )

  disable_provenance = var.disable_provenance

  dynamic "rule" {
    for_each = { for rule in each.value.rules : rule.alert => rule }

    content {
      name      = rule.value.alert
      for       = try(rule.value.for, null)
      condition = "QUERY_RESULT"

      annotations = {
        for k, v in merge(rule.value.annotations, try(var.overrides[rule.value.alert].annotations, {})) :
        k => replace(v, "$value", "$values.QUERY_RESULT.Value")
      }
      labels = merge(rule.value.labels, try(var.overrides[rule.value.alert].labels, {}))

      exec_err_state = coalesce(try(var.overrides[rule.value.alert].exec_err_state, null), "Error")
      is_paused      = try(var.overrides[rule.value.alert].is_paused, null)
      no_data_state  = coalesce(try(var.overrides[rule.value.alert].no_data_state, null), "OK")

      data {
        ref_id = "QUERY"
        relative_time_range {
          from = 600
          to   = 0
        }
        datasource_uid = var.datasource_uid
        model = jsonencode({
          editorMode    = "code"
          expr          = coalesce(try(var.overrides[rule.value.alert].expr, null), rule.value.expr)
          intervalMs    = 1000
          maxDataPoints = 43200
          refId         = "QUERY"
        })
      }

      ## Reduce
      data {
        ref_id = "QUERY_RESULT"
        relative_time_range {
          from = 600
          to   = 0
        }
        datasource_uid = "__expr__"
        model = jsonencode({
          "conditions" = [
            {
              "evaluator" = {
                "params" = [0]
                "type"   = "gt"
              }
              "operator" = {
                "type" = "and"
              }
              "query" = {
                "params" = []
              }
              "reducer" = {
                "params" = []
                "type"   = "avg"
              }
              "type" = "query"
            },
          ]
          "datasource" = {
            "name" = "Expression"
            "type" = "__expr__"
            "uid"  = "__expr__"
          }
          "expression"    = "QUERY"
          "intervalMs"    = 1000
          "maxDataPoints" = 43200
          "reducer"       = "last"
          "refId"         = "QUERY_RESULT"
          "type"          = "reduce"
        })
      }

      ## Notification settings
      dynamic "notification_settings" {
        for_each = var.rule_notification_settings != null ? [var.rule_notification_settings] : []

        content {
          contact_point   = notification_settings.value.contact_point
          group_by        = notification_settings.value.group_by
          group_interval  = notification_settings.value.group_interval
          group_wait      = notification_settings.value.group_wait
          mute_timings    = notification_settings.value.mute_timings
          repeat_interval = notification_settings.value.repeat_interval
        }
      }
    }
  }
}
