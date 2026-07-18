#!/usr/bin/env bash
# theme_preview.sh — Preview console theme elements (dark palette)
# Version: 0.3.0
#
# Run: ./theme_preview.sh
#      FEDORA_THEME=light ./theme_preview.sh
#      FEDORA_THEME_DENSITY=compact ./theme_preview.sh

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${ROOT}/lib/common.sh"

theme_set_lane main
theme_lane_banner "Fedora Workstation Control" main
theme_meta_line "STATE / WARN"
theme_meta_line "HOST / $(hostname 2>/dev/null || echo unknown)"
theme_meta_line "ACTION / Inspect host"
theme_meta_line "WIDTH / $(theme_resolved_width) columns"

theme_section "Control overview"
theme_option 1 "Inspect host" "read-only"
theme_option 2 "Build change plan" "writes plan file"
MENU_LAST_CHOICE=3
theme_option 3 "Verify state" "read-only"
MENU_LAST_CHOICE=""
theme_option 4 "Reset configuration" "destructive · confirmation required" danger
theme_option 0 "Back"

theme_section "Lane index"
theme_option_lane 1 system "System maintenance" "health · updates · logs"
theme_option_lane 2 dev "Developer tools" "toolchains · virtualization"
theme_option_lane 3 android "Android research" "SDK · reverse engineering"
theme_option_lane 4 mobsf "MobSF" "static and dynamic analysis"
theme_option_lane 5 rebuild "Build workflow" "plan · approve · apply"
theme_option_lane 6 audit "Audit and readiness" "verify · report"

theme_section "Diagnostic states"
ok "Required service available"
warn "Reboot recommended"
info "Inspection remains read-only"
theme_msg_absent "adb is not installed"
theme_msg_unavail "GPU sensor did not report"
theme_msg_skip "Database check intentionally deferred"

theme_summary_box "Summary" "Result:  READY" "Next: ./run.sh --inspect"

theme_report_progress 2 8 "Apply approved workstation plan"
theme_report_step 2 8 "Install selected capability" "Approval required before mutation"

theme_report_header "Tool diagnostics" "Semantic state labels remain visible without color"
theme_tool_row ok "Java" "openjdk 21"
theme_tool_row warn "Frida" "no version output"
theme_tool_row absent "adb" "not installed"
theme_tool_row unavail "GPU" "sensor unavailable"
theme_tool_row skip "MariaDB" "migration deferred"
theme_scroll_marker

theme_meta_line "PLAIN / NO_COLOR=1 ./theme_preview.sh"
ok "Theme preview complete"
