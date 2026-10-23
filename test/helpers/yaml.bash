write_standard_plan() {
  {
    printf '%s\n' 'BEGIN_AI_UPGRADER_AXES_TSV'
    printf '%s\n' $'id\tkind\tcurrent\ttarget\tpolicy\tsource_of_truth'
    printf '%s\n' $'runtime\truntime\t1\t2\tupgrade\truntime.txt'
    printf '%s\n' $'framework\tframework\t1\t1\tlocked\tframework.txt'
    printf '%s\n' 'END_AI_UPGRADER_AXES_TSV'
    printf '%s\n' 'BEGIN_AI_UPGRADER_CONSTRAINTS_TSV'
    printf '%s\n' $'left\trelation\tright\tevidence'
    printf '%s\n' 'END_AI_UPGRADER_CONSTRAINTS_TSV'
    printf '%s\n' 'BEGIN_AI_UPGRADER_MILESTONES_TSV'
    printf '%s\n' $'id\taxis\tkind\tfrom\tto\tdepends_on\treview_required'
    printf '%s\n' $'runtime-1\truntime\truntime\t1\t2\t-\ttrue'
    printf '%s\n' 'END_AI_UPGRADER_MILESTONES_TSV'
    standard_gate_block runtime-1 'make runtime-fast' 'make runtime-milestone'
    printf '%s\n' 'BEGIN_AI_UPGRADER_SOURCES_TSV'
    printf '%s\n' $'axis\turl\twhat'
    printf '%s\n' $'runtime\thttps://example.invalid/runtime\topened: runtime 2 is current official target'
    printf '%s\n' $'framework\thttps://example.invalid/framework\topened: framework 1 is current official target'
    printf '%s\n' 'END_AI_UPGRADER_SOURCES_TSV'
  } > "$MOCK_PLAN"
}

standard_gate_block() {
  local milestone="$1" fast="$2" complete="$3"
  printf '%s\n' 'BEGIN_AI_UPGRADER_GATES_TSV'
  printf '%s\n' $'milestone_id\tgate\trequired\tcwd\tcommand\tpass_condition'
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$milestone" fast_gate true . "$fast" exit:0
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$milestone" milestone_gate true . "$complete" exit:0
  printf '%s\n' "$milestone"$'\tfull_ci\tfalse\t-\t-\t-'
  printf '%s\n' "$milestone"$'\tsmoke\tfalse\t-\t-\t-'
  printf '%s\n' 'END_AI_UPGRADER_GATES_TSV'
}

write_two_axis_plan() {
  {
    printf '%s\n' 'BEGIN_AI_UPGRADER_AXES_TSV'
    printf '%s\n' $'id\tkind\tcurrent\ttarget\tpolicy\tsource_of_truth'
    printf '%s\n' $'runtime\truntime\t1\t2\tupgrade\truntime.txt'
    printf '%s\n' $'framework\tframework\t1\t2\tupgrade\tframework.txt'
    printf '%s\n' 'END_AI_UPGRADER_AXES_TSV'
    printf '%s\n' 'BEGIN_AI_UPGRADER_CONSTRAINTS_TSV'
    printf '%s\n' $'left\trelation\tright\tevidence'
    printf '%s\n' $'framework\trequires\truntime>=2\tofficial compatibility'
    printf '%s\n' 'END_AI_UPGRADER_CONSTRAINTS_TSV'
    printf '%s\n' 'BEGIN_AI_UPGRADER_MILESTONES_TSV'
    printf '%s\n' $'id\taxis\tkind\tfrom\tto\tdepends_on\treview_required'
    printf '%s\n' $'runtime-1\truntime\truntime\t1\t2\t-\ttrue'
    printf '%s\n' $'framework-1\tframework\tframework\t1\t2\truntime-1\ttrue'
    printf '%s\n' 'END_AI_UPGRADER_MILESTONES_TSV'
    printf '%s\n' 'BEGIN_AI_UPGRADER_GATES_TSV'
    printf '%s\n' $'milestone_id\tgate\trequired\tcwd\tcommand\tpass_condition'
    printf '%s\n' $'runtime-1\tfast_gate\ttrue\t.\tmake runtime-fast\texit:0'
    printf '%s\n' $'runtime-1\tmilestone_gate\ttrue\t.\tmake runtime-milestone\texit:0'
    printf '%s\n' $'runtime-1\tfull_ci\tfalse\t-\t-\t-'
    printf '%s\n' $'runtime-1\tsmoke\tfalse\t-\t-\t-'
    printf '%s\n' $'framework-1\tfast_gate\ttrue\t.\tmake framework-fast\texit:0'
    printf '%s\n' $'framework-1\tmilestone_gate\ttrue\t.\tmake framework-milestone\texit:0'
    printf '%s\n' $'framework-1\tfull_ci\tfalse\t-\t-\t-'
    printf '%s\n' $'framework-1\tsmoke\tfalse\t-\t-\t-'
    printf '%s\n' 'END_AI_UPGRADER_GATES_TSV'
    printf '%s\n' 'BEGIN_AI_UPGRADER_SOURCES_TSV'
    printf '%s\n' $'axis\turl\twhat'
    printf '%s\n' $'runtime\thttps://example.invalid/runtime\topened: runtime 2 is current official target'
    printf '%s\n' $'framework\thttps://example.invalid/framework\topened: framework 2 is current official target'
    printf '%s\n' 'END_AI_UPGRADER_SOURCES_TSV'
  } > "$MOCK_PLAN"
}

write_independent_two_axis_plan() {
  write_two_axis_plan
  awk -F '\t' 'BEGIN{OFS="\t"}
    $1=="framework-1" && $2=="framework" { $6="-"; print; next }
    $1=="framework" && $2=="requires" { next }
    { print }
  ' "$MOCK_PLAN" > "$MOCK_PLAN.tmp"
  mv "$MOCK_PLAN.tmp" "$MOCK_PLAN"
}

write_empty_plan() {
  {
    printf '%s\n' 'BEGIN_AI_UPGRADER_AXES_TSV'
    printf '%s\n' $'id\tkind\tcurrent\ttarget\tpolicy\tsource_of_truth'
    printf '%s\n' $'runtime\truntime\t1\t1\tlocked\truntime.txt'
    printf '%s\n' $'framework\tframework\t1\t1\tlocked\tframework.txt'
    printf '%s\n' 'END_AI_UPGRADER_AXES_TSV'
    printf '%s\n' 'BEGIN_AI_UPGRADER_CONSTRAINTS_TSV'
    printf '%s\n' $'left\trelation\tright\tevidence'
    printf '%s\n' 'END_AI_UPGRADER_CONSTRAINTS_TSV'
    printf '%s\n' 'BEGIN_AI_UPGRADER_MILESTONES_TSV'
    printf '%s\n' $'id\taxis\tkind\tfrom\tto\tdepends_on\treview_required'
    printf '%s\n' 'END_AI_UPGRADER_MILESTONES_TSV'
    printf '%s\n' 'BEGIN_AI_UPGRADER_GATES_TSV'
    printf '%s\n' $'milestone_id\tgate\trequired\tcwd\tcommand\tpass_condition'
    printf '%s\n' 'END_AI_UPGRADER_GATES_TSV'
    printf '%s\n' 'BEGIN_AI_UPGRADER_SOURCES_TSV'
    printf '%s\n' $'axis\turl\twhat'
    printf '%s\n' $'runtime\thttps://example.invalid/runtime\topened: runtime 1 is current official target'
    printf '%s\n' $'framework\thttps://example.invalid/framework\topened: framework 1 is current official target'
    printf '%s\n' 'END_AI_UPGRADER_SOURCES_TSV'
  } > "$MOCK_PLAN"
}

write_incompatible_next_step_plan() {
  {
    printf '%s\n' 'BEGIN_AI_UPGRADER_AXES_TSV'
    printf '%s\n' $'id\tkind\tcurrent\ttarget\tpolicy\tsource_of_truth'
    printf '%s\n' $'runtime\truntime\t1\t1\tlocked\truntime.txt'
    printf '%s\n' $'framework\tframework\t1\t1\tlocked\tframework.txt'
    printf '%s\n' 'END_AI_UPGRADER_AXES_TSV'
    printf '%s\n' 'BEGIN_AI_UPGRADER_CONSTRAINTS_TSV'
    printf '%s\n' $'left\trelation\tright\tevidence'
    printf '%s\n' $'runtime\tblocked_at\t2\topened: repo-invoked toolchain cannot take runtime 2'
    printf '%s\n' 'END_AI_UPGRADER_CONSTRAINTS_TSV'
    printf '%s\n' 'BEGIN_AI_UPGRADER_MILESTONES_TSV'
    printf '%s\n' $'id\taxis\tkind\tfrom\tto\tdepends_on\treview_required'
    printf '%s\n' 'END_AI_UPGRADER_MILESTONES_TSV'
    printf '%s\n' 'BEGIN_AI_UPGRADER_GATES_TSV'
    printf '%s\n' $'milestone_id\tgate\trequired\tcwd\tcommand\tpass_condition'
    printf '%s\n' 'END_AI_UPGRADER_GATES_TSV'
    printf '%s\n' 'BEGIN_AI_UPGRADER_SOURCES_TSV'
    printf '%s\n' $'axis\turl\twhat'
    printf '%s\n' $'runtime\thttps://example.invalid/runtime\topened: official latest 2; this repo cannot take it'
    printf '%s\n' $'framework\thttps://example.invalid/framework\topened: framework 1 is current official target'
    printf '%s\n' 'END_AI_UPGRADER_SOURCES_TSV'
  } > "$MOCK_PLAN"
}

write_shared_plan() {
  local locked_id="${1:-framework}" locked_current="${2:-7.2}"
  {
    printf '%s\n' 'BEGIN_AI_UPGRADER_AXES_TSV'
    printf '%s\n' $'id\tkind\tcurrent\ttarget\tpolicy\tsource_of_truth'
    printf '%s\n' $'runtime\truntime\t10\t20\tupgrade\tshared.txt'
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$locked_id" framework "$locked_current" "$locked_current" locked shared.txt
    printf '%s\n' 'END_AI_UPGRADER_AXES_TSV'
    printf '%s\n' 'BEGIN_AI_UPGRADER_CONSTRAINTS_TSV'
    printf '%s\n' $'left\trelation\tright\tevidence'
    printf '%s\n' 'END_AI_UPGRADER_CONSTRAINTS_TSV'
    printf '%s\n' 'BEGIN_AI_UPGRADER_MILESTONES_TSV'
    printf '%s\n' $'id\taxis\tkind\tfrom\tto\tdepends_on\treview_required'
    printf '%s\n' $'runtime-1\truntime\truntime\t10\t20\t-\ttrue'
    printf '%s\n' 'END_AI_UPGRADER_MILESTONES_TSV'
    standard_gate_block runtime-1 'make runtime-fast' 'make runtime-milestone'
    printf '%s\n' 'BEGIN_AI_UPGRADER_SOURCES_TSV'
    printf '%s\n' $'axis\turl\twhat'
    printf '%s\n' $'runtime\thttps://example.invalid/runtime\topened: runtime 20 is current official target'
    printf '%s\thttps://example.invalid/%s\topened: %s %s is current official target\n' "$locked_id" "$locked_id" "$locked_id" "$locked_current"
    printf '%s\n' 'END_AI_UPGRADER_SOURCES_TSV'
  } > "$MOCK_PLAN"
}

replace_plan_text() {
  local from="$1" to="$2" temp="$MOCK_PLAN.tmp"
  awk -v from="$from" -v to="$to" '{gsub(from,to); print}' "$MOCK_PLAN" > "$temp"
  mv "$temp" "$MOCK_PLAN"
}

write_stack_plan() {
  local rid="$1" rkind="$2" rfrom="$3" rto="$4" rpath="$5"
  local fid="$6" fkind="$7" ffrom="$8" fto="$9" fpath="${10}"
  local rpolicy=upgrade fpolicy=locked
  [ "$rfrom" != "$rto" ] || rpolicy=locked
  [ "$ffrom" = "$fto" ] || fpolicy=upgrade
  {
    printf '%s\n' 'BEGIN_AI_UPGRADER_AXES_TSV'
    printf '%s\n' $'id\tkind\tcurrent\ttarget\tpolicy\tsource_of_truth'
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$rid" "$rkind" "$rfrom" "$rto" "$rpolicy" "$rpath"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$fid" "$fkind" "$ffrom" "$fto" "$fpolicy" "$fpath"
    printf '%s\n' 'END_AI_UPGRADER_AXES_TSV'
    printf '%s\n' 'BEGIN_AI_UPGRADER_CONSTRAINTS_TSV'
    printf '%s\n' $'left\trelation\tright\tevidence'
    printf '%s\n' 'END_AI_UPGRADER_CONSTRAINTS_TSV'
    printf '%s\n' 'BEGIN_AI_UPGRADER_MILESTONES_TSV'
    printf '%s\n' $'id\taxis\tkind\tfrom\tto\tdepends_on\treview_required'
    if [ "$rpolicy" = upgrade ]; then
      printf '%s-1\t%s\t%s\t%s\t%s\t-\ttrue\n' "$rid" "$rid" "$rkind" "$rfrom" "$rto"
    fi
    if [ "$fpolicy" = upgrade ]; then
      dep='-'
      [ "$rpolicy" = upgrade ] && dep="${rid}-1"
      printf '%s-1\t%s\t%s\t%s\t%s\t%s\ttrue\n' "$fid" "$fid" "$fkind" "$ffrom" "$fto" "$dep"
    fi
    printf '%s\n' 'END_AI_UPGRADER_MILESTONES_TSV'
    printf '%s\n' 'BEGIN_AI_UPGRADER_GATES_TSV'
    printf '%s\n' $'milestone_id\tgate\trequired\tcwd\tcommand\tpass_condition'
    if [ "$rpolicy" = upgrade ]; then
      printf '%s-1\tfast_gate\ttrue\t.\tmake runtime-fast\texit:0\n' "$rid"
      printf '%s-1\tmilestone_gate\ttrue\t.\tmake runtime-milestone\texit:0\n' "$rid"
      printf '%s-1\tfull_ci\tfalse\t-\t-\t-\n' "$rid"
      printf '%s-1\tsmoke\tfalse\t-\t-\t-\n' "$rid"
    fi
    if [ "$fpolicy" = upgrade ]; then
      printf '%s-1\tfast_gate\ttrue\t.\tmake framework-fast\texit:0\n' "$fid"
      printf '%s-1\tmilestone_gate\ttrue\t.\tmake framework-milestone\texit:0\n' "$fid"
      printf '%s-1\tfull_ci\tfalse\t-\t-\t-\n' "$fid"
      printf '%s-1\tsmoke\tfalse\t-\t-\t-\n' "$fid"
    fi
    printf '%s\n' 'END_AI_UPGRADER_GATES_TSV'
    printf '%s\n' 'BEGIN_AI_UPGRADER_SOURCES_TSV'
    printf '%s\n' $'axis\turl\twhat'
    printf '%s\thttps://example.invalid/%s\topened: current official target\n' "$rid" "$rid"
    printf '%s\thttps://example.invalid/%s\topened: current official target\n' "$fid" "$fid"
    printf '%s\n' 'END_AI_UPGRADER_SOURCES_TSV'
  } > "$MOCK_PLAN"
}
