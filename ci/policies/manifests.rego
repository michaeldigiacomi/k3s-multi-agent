package main

deny[msg] {
  input.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
  endswith(container.image, ":latest")
  msg := sprintf("Container %s in %s uses 'latest' tag", [container.name, input.metadata.name])
}

deny[msg] {
  input.kind == "Deployment"
  not input.spec.template.spec.containers[_].readinessProbe
  msg := sprintf("Deployment %s is missing readinessProbe", [input.metadata.name])
}

deny[msg] {
  input.kind == "Deployment"
  not input.spec.template.spec.containers[_].livenessProbe
  msg := sprintf("Deployment %s is missing livenessProbe", [input.metadata.name])
}

deny[msg] {
  input.kind == "Deployment"
  not input.spec.template.spec.securityContext.runAsNonRoot
  msg := sprintf("Deployment %s must set runAsNonRoot", [input.metadata.name])
}

warn[msg] {
  input.kind == "Deployment"
  not input.spec.template.spec.securityContext.fsGroup
  msg := sprintf("Deployment %s should set fsGroup", [input.metadata.name])
}
