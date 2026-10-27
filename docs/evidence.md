# Portfolio evidence and honest scope

## Implemented in the repository

- Private S3 / CloudFront architecture defined in Terraform, with OAC and browser security headers.
- Versioned, encrypted remote state and native S3 locking, plus bootstrap/migration guidance.
- Repository/environment-scoped GitHub OIDC trust and a restricted deployment role.
- Quality-gated releases, immutable asset prefixes, checksummed manifests, live smoke/browser checks, and rollback with automatic previous-entry-point restoration on failure.
- CloudWatch dashboard/error alarms, SNS notification configuration, access-log retention, and project cost budget.
- Recovery, incident-response, security, cost, and setup documentation.

## Validation record

Local validation passed: four Playwright browser scenarios on both the normal production build and a simulated versioned-release host; fifteen release/health-check unit tests; seven Terraform mock-provider runs; validation of both Terraform stacks; actionlint workflow validation; npm audit with zero reported vulnerabilities; and Gitleaks scanning of history/new changes. Terraform's mock-provider tests exercise configuration without creating AWS resources; deployment unit tests simulate S3/CloudFront and failure handling. They do not prove real AWS permission, OIDC, logging, or notification delivery. CI workflows are defined, but a workflow file is not proof of a successful hosted run.

## Evidence to capture after provisioning

| Claim | Required evidence | Status before account connection |
| --- | --- | --- |
| AWS hosting works | Public CloudFront/custom-domain URL and successful live browser checks | Not verified |
| CI/CD works on GitHub | Successful hosted Quality and security / AWS release run links | Not verified |
| No stored AWS deploy keys | OIDC trust/role policy and credential step; account review | Configured, runtime unverified |
| Origin is private | Direct S3 request denied while CloudFront requests succeed | Not verified |
| Logs and metrics work | Fresh access-log object and dashboard traffic | Not verified |
| Alerts work | Confirmed SNS subscription and timed notification test | Not verified |
| Rollback works in AWS | Two successful releases, rollback run, and restored release marker | Simulated locally, AWS unverified |
| Costs are controlled | Active Project tag, budget screenshot, and observed billing | Not verified; budget is not a cap |
| Recovery target is met | Timed recovery drill with start/end and run links | Not measured |

## Suggested portfolio description

Before live deployment: **“Built a React workload and an AWS delivery platform in code: Terraform, private S3/CloudFront, GitHub OIDC, automated quality gates, versioned releases, rollback, and monitoring configuration. Validated infrastructure with mock-provider tests and exercised release failure paths locally.”**

After the table is backed by actual evidence, update the description with the public URL, run links, observed recovery time, and costs. Do not claim production uptime, alert delivery, zero downtime, completed cloud deployment, or a recovery SLO based only on configuration files.

## New-experience project limitation

AWS reports an active Free-plan project in us-east-2, with successful operator login on Windows. Managed policies block OIDC identity-provider creation and out-of-region alarm writes. The tested project variant disables those resources and uses operator deployment; automated AWS OIDC delivery and AWS alarm emails must not be claimed for this mode. GitHub CI, private hosting, logs, dashboard and budget configuration remain. Windows Terraform 1.15.4 satisfies the version requirement, but a real AWS plan/apply and public verification are still outstanding.
