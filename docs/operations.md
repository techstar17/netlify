# Operations and recovery runbook

## Deployment

Push a reviewed commit to `main`, or run **AWS production release → deploy**. Verify the release job ran (not skipped), the live checks passed, and the summary lists the expected SHA and public URL. A local build or green quality job is not deployment evidence. Infrastructure changes are separate: run a reviewed Terraform plan/apply using your operator session and locked remote state.

## Roll back without rebuilding

1. Identify a known-good full 40-character commit SHA from a successful AWS release run. Confirm its `releases/<sha>/release.json` still exists.
2. Run **AWS production release** on `main`, choose `rollback`, and enter that SHA.
3. The job verifies all stored files, switches only the root HTML, invalidates the entry points, and tests live behavior. It never deletes newer releases.
4. Verify the job summary/public release identity and browser behavior. Investigate the regression before the next automatic deployment on main.

A failure after activation attempts to restore the exact prior HTML and invalidate again; the deployment still fails. If invalidation or restoration also fails, it is an incident requiring operator intervention. A first deployment has no previous entry point. Current browser tests must remain compatible with the rollback target; update them carefully as UI behavior evolves.

### Emergency operator procedure

Use a trusted authenticated AWS session. Set values from Terraform outputs, choose a **verified completed release**, and serialize with GitHub deployments (wait for any active run and pause subsequent deployments). Do not run both concurrently.

```bash
export SITE_BUCKET=YOUR_TERRAFORM_SITE_BUCKET
export CLOUDFRONT_DISTRIBUTION_ID=YOUR_DISTRIBUTION_ID
export SITE_URL=https://YOUR_DISTRIBUTION.cloudfront.net
# Use the public custom domain instead if configured.
python3 scripts/release.py rollback FULL_40_CHARACTER_SHA
```

This invokes HTTP smoke checks; add `--browser-check` after `npm ci` and `npx playwright install --with-deps chromium` to include the browser suite. If root HTML was accidentally damaged and no normal release is available, inspect S3 version history with an operator and restore a known-good version to a temporary file, verify it, then put it back with `Content-Type: text/html` and `Cache-Control: no-cache,no-store,must-revalidate`, and invalidate `/` and `/index.html`. Never make the bucket public to resolve an origin error.

## Incident triage

| Symptom | Checks and response |
| --- | --- |
| Site shows 403/404 before first AWS deploy | Check release job wasn't skipped; the new bucket initially has no index. |
| CloudFront 403 after deployment | Check bucket policy SourceArn, OAC, object existence, and distribution status. Reconcile drift with a reviewed Terraform plan. |
| Blank page / assets fail | Inspect browser console/network. Confirm root HTML references the intended `/releases/<sha>/` prefix and the release manifest verifies. Roll back. |
| 4xx/5xx alarm | Check us-east-1 dashboard and access logs. Distinguish user invalid paths from missing release assets/origin permission failures. |
| OIDC AccessDenied | Verify exact repository/environment subject, main-only environment rules, STS audience, role ARN, and existing account OIDC provider. Don't add long-lived keys as a workaround. |
| No email notifications | Confirm alert_email was configured, SNS email subscription was confirmed, topic policy, alarm state history, and spam folder. |
| Failed automatic restoration | Preserve workflow logs, stop new releases, use authenticated operator recovery above; verify publicly before resolving. |
| State lock contention | Check for an actual running Terraform operation. Don't force-unlock an active writer. Restore state from a verified version only with the operator's review. |
| Budget stays zero | Activate Project cost allocation tag and allow for Billing data latency; inspect unfiltered account costs independently. |

## Monitor and test notifications

Proposed availability objective: **99.9% successful user requests per calendar month**. Proposed recovery target: **15 minutes** from detection to a publicly verified rollback. Neither is an achieved result. CDN 5xx-rate metrics alone don't measure full user experience or all 4xx failures; define eligible request populations and add independent continuous synthetic checks before claiming an SLO.

- Inspect Requests, BytesDownloaded, 4xxErrorRate, and 5xxErrorRate in `FRAME-production` in us-east-1.
- Confirm access logs arrive under `cloudfront/` in the log bucket. Delivery is delayed; logs include sensitive request metadata and must stay private.
- To test the notification route without breaking the app, use a controlled alarm-state test during a maintenance window after SNS confirmation:

  ```bash
  aws cloudwatch set-alarm-state --region us-east-1 \
    --alarm-name frame-cloudfront-server-errors \
    --state-value ALARM --state-reason 'Controlled notification delivery test'
  # Confirm receipt, record timestamp, and return it to OK.
  aws cloudwatch set-alarm-state --region us-east-1 \
    --alarm-name frame-cloudfront-server-errors \
    --state-value OK --state-reason 'Notification test complete'
  ```

  CloudWatch's next evaluation can replace the test state. This checks notification delivery, not actual metric ingestion or error detection. Record those separately.

## State and teardown

Never commit state, plans, account-specific variables, access keys, or downloaded logs. Keep the bootstrap state in its remote backend and preserve the initial private backup. Operators must retain state-bucket access separately from deployment-role access.

To stop costs, review `terraform plan -destroy` for the app stack. S3 buckets have `force_destroy=false`: inspect and back up needed data, then intentionally remove objects/versions using an authorized operator before deletion. Destruction removes the deployment role, CDN, monitoring, and site/log buckets. The bootstrap state bucket has prevent_destroy and remains separate. Do not blindly destroy it or remove its protection to bypass a failure. Budget notifications do not stop resources or charges.
