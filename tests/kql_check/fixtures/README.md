# KQL checker fixtures

`broken/` mirrors the repository layout (`detections/<tier>/<rule>/rule.kql`) with queries that
are deliberately invalid. `make kql` and the `kql` job in `ci.yml` run the checker on it with
`--expect-errors` and fail if any of them parses. This proves the syntax gate can go red, so a
green KQL job means something.

These folders are outside `detections/`, so Terraform, the static tests and the real KQL check
never see them.
