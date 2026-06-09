#!/usr/bin/env bash
# theme_preview.sh — Preview console theme elements (dark palette)
# Version: 0.1.0
#
# Run: ./theme_preview.sh
#      FEDORA_THEME=light ./theme_preview.sh
#      FEDORA_THEME_DENSITY=compact ./theme_preview.sh

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${ROOT}/lib/common.sh"

for lane in main system dev android mobsf rebuild audit; do
  theme_set_lane "${lane}"
  theme_lane_banner "${lane} lane preview" "${lane}"
  theme_section "Sample section"
  theme_option 1 "Primary action" "hint text"
  theme_option_lane 2 "${lane}" "Lane-accent menu item" "accent on [n] + icon"
  theme_option 0 "Back"
  menu_last_choice=1
  theme_option 1 "Repeat last choice demo" "← last marker"
  MENU_LAST_CHOICE=""
  theme_option 3 "Danger action" "destructive" danger
  ok "Success message"
  warn "Warning message"
  info "Info message"
  theme_msg_miss "missing-tool"
  theme_breadcrumb "Main menu › ${lane} lane › Sample"
  theme_summary_box "Summary" "Result:  READY" "Next: ./run.sh"
  echo
done

theme_set_lane main
theme_plain_banner "Plain banner (no lane icon)"
theme_report_header "Report header" "Meta line one" "Meta line two"
theme_report_step 2 8 "Example rebuild step" "Script: dev/install_vscode.sh"
theme_report_progress 1 3 "Example check step"
theme_kv "Hostname" "$(hostname 2>/dev/null || echo unknown)"
theme_tool_row ok "Java" "openjdk 21"
theme_tool_row warn "Frida" "no version output"
theme_tool_row miss "adb" "not installed"
theme_gauge_bar 42 24
echo
theme_scroll_marker

ok "Theme preview complete"
