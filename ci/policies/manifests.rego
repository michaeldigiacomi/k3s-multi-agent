package main

# Shared predicate: both Deployment and StatefulSet use the same pod template structure
is_workload(kind) {
  kind == "Deployment"
}
is_workload(kind) {
  kind == "StatefulSet"
}

deny[msg] {
  is_workload(input.kind)
  container := input.spec.template.spec.containers[_]
  endswith(container.image, ":latest")
  msg := sprintf("Container %s in %s %s uses 'latest' tag", [container.name, input.kind, input.metadata.name])
}

deny[msg] {
  is_workload(input.kind)
  not input.spec.template.spec.containers[_].readinessProbe
  msg := sprintf("%s %s is missing readinessProbe", [input.kind, input.metadata.name])
}

deny[msg] {
  is_workload(input.kind)
  not input.spec.template.spec.containers[_].livenessProbe
  msg := sprintf("%s %s is missing livenessProbe", [input.kind, input.metadata.name])
}

deny[msg] {
  is_workload(input.kind)
  not input.spec.template.spec.securityContext.runAsNonRoot
  msg := sprintf("%s %s must set runAsNonRoot", [input.kind, input.metadata.name])
}

warn[msg] {
  is_workload(input.kind)
  not input.spec.template.spec.securityContext.fsGroup
  msg := sprintf("%s %s should set fsGroup", [input.kind, input.metadata.name])
}