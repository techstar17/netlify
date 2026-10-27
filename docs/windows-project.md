# Deploy from Windows to the new AWS experience

This path is for the `s3` project, selected Region **us-east-2**, using the local AWS CLI profile **frame-cloud-engineer**. AWS reports an active Free plan. Plan status/credits are not a promise of zero resource costs. The Windows login does not authenticate the ChatGPT cloud machine; commands here run in your own PowerShell terminal. Do not paste keys, authorization codes, or cached credentials into chat or GitHub.

## Why this differs from the advanced AWS reference

AWS's [supported-service list](https://docs.aws.amazon.com/accounts/latest/reference/supported-services-sign-up-new.html) includes S3, CloudFront, CloudWatch, SNS and Budgets on the Free plan. But its [managed project policies](https://docs.aws.amazon.com/accounts/latest/reference/scps-and-rcps-for-projects.html) deny IAM identity-provider operations (`iam:*Provider*`). This rules out creating the proposed GitHub OIDC provider in this experience. An upgrade from Free to Paid alone does not remove that restriction; do not upgrade as a workaround.

The project configuration therefore disables the OIDC provider, GitHub deployment role/policy, and us-east-1 SNS/CloudWatch alarm creation. It retains private S3, CloudFront/OAC, logs, state, a dashboard, and the cost budget. The dashboard is created through the selected-Region endpoint; its CloudFront metric widgets read us-east-1, using read operations that AWS's regional policy lists as exceptions. Actual permissions and metrics still need live verification. AWS regional resources remain in us-east-2. Global CloudFront/Budgets operations use their appropriate service endpoints.

CI on GitHub remains available, but AWS delivery is initially an operator action from the authenticated Windows session. There is no AWS alarm-email delivery in this project mode. Optional `alert_email` configures budget emails only. Use AWS Settings for project billing/spend limits; a Terraform budget notification is not a spending cap. The unrestricted reference configuration and OIDC pipeline remain in the repository for a compatible advanced AWS experience.

## 1. Download the repository and prepare a state-bucket plan

Run in PowerShell from a parent directory where you keep projects. If `frame-cloud-portfolio` already exists, enter it, inspect local changes with `git status`, and use `git pull --ff-only` instead of cloning over it.

```powershell
git clone https://github.com/techstar17/netlify.git frame-cloud-portfolio
Set-Location frame-cloud-portfolio
$env:AWS_PROFILE = "frame-cloud-engineer"
$env:AWS_REGION = "us-east-2"
terraform -chdir=infra/bootstrap init -lockfile=readonly
terraform -chdir=infra/bootstrap plan -var="aws_region=us-east-2" -out=bootstrap.tfplan
```

Terraform 1.15.4 is compatible with this repository's version requirement. The plan makes read calls but creates no AWS resources. Review the identity, Region and proposed changes before applying. If login expires, use the newer CLI at `$env:LOCALAPPDATA\Programs\Amazon\AWSCLIV2\aws.exe` to run `login --region us-east-2 --profile frame-cloud-engineer` again. Do not run `aws configure` to create static keys.

## 2. Create state storage and migrate bootstrap state

The following apply creates billable AWS resources. Run only after reviewing the saved plan:

```powershell
terraform -chdir=infra/bootstrap apply bootstrap.tfplan
$frameStateBucket = terraform -chdir=infra/bootstrap output -raw backend_bucket
if ($LASTEXITCODE -ne 0) { throw "Cannot read state bucket" }
$frameAws = "$env:LOCALAPPDATA\Programs\Amazon\AWSCLIV2\aws.exe"
& $frameAws s3 cp infra/bootstrap/terraform.tfstate "s3://$frameStateBucket/bootstrap-initial-state/terraform.tfstate" --region us-east-2 --profile frame-cloud-engineer
if ($LASTEXITCODE -ne 0) { throw "State backup failed; do not migrate yet" }
@'
terraform {
  backend "s3" {
    key          = "frame/bootstrap/terraform.tfstate"
    use_lockfile = true
    encrypt      = true
  }
}
'@ | Set-Content -Encoding ascii infra/bootstrap/backend.tf
terraform -chdir=infra/bootstrap init -migrate-state "-backend-config=bucket=$frameStateBucket" "-backend-config=region=us-east-2"
```

Answer **yes** to migrate the existing local bootstrap state. Stop and investigate any error before proceeding. The generated `backend.tf`, local state, and plans are ignored by Git. Preserve the private initial backup; never share it. After a terminal restart, reselect the profile and recover the state bucket name from the saved output (or reinitialize the bootstrap backend before reading outputs); do not create fresh bootstrap state accidentally.

## 3. Prepare and review the project infrastructure plan

```powershell
terraform -chdir=infra/terraform init -lockfile=readonly "-backend-config=bucket=$frameStateBucket" "-backend-config=region=us-east-2"
terraform -chdir=infra/terraform plan -var-file=project.tfvars.example -out=project.tfplan
```

Always select **project.tfvars.example** (or a reviewed local copy of it), not the advanced default variable set. The plan must not create an OIDC provider, a GitHub deploy role, or SNS/CloudWatch alarms in us-east-1. Stop if it does. To add a budget email, copy `project.tfvars.example` to an ignored local `.tfvars` file, set your address, and select that file instead. The private buckets must stay private.

After reviewing the actual plan:

```powershell
terraform -chdir=infra/terraform apply project.tfplan
terraform -chdir=infra/terraform output
```

CloudFront setup can take several minutes. The new distribution initially has no application entry point, so its URL will not work until a release is uploaded. No live resource or delivery claim is established by the mock Terraform tests.

## 4. Build and publish from the authenticated session

Requires Node.js 22.12+ (Node 24 recommended) and a working Python 3 installation for the release script. Check `node --version`, `npm --version`, and `python --version` first; install missing tools from their official distributions rather than exposing AWS credentials elsewhere.

```powershell
$env:SITE_BUCKET = terraform -chdir=infra/terraform output -raw site_bucket
$env:CLOUDFRONT_DISTRIBUTION_ID = terraform -chdir=infra/terraform output -raw distribution_id
$env:SITE_URL = terraform -chdir=infra/terraform output -raw site_url
$env:RELEASE_ID = git rev-parse HEAD
$env:ASSET_BASE = "/releases/$env:RELEASE_ID/"
$env:PATH = "$env:LOCALAPPDATA\Programs\Amazon\AWSCLIV2;$env:PATH"
npm ci
if ($LASTEXITCODE -ne 0) { throw "Dependency installation failed" }
npm run build
if ($LASTEXITCODE -ne 0) { throw "Build failed" }
npx playwright install chromium
if ($LASTEXITCODE -ne 0) { throw "Browser installation failed" }
python scripts/release.py deploy $env:RELEASE_ID --browser-check
```

Check every Terraform output and Git SHA was read successfully before publishing. The release script verifies stored checksums, activates the root HTML, invalidates the CDN entry point, and checks the public release and browser behavior. It attempts restoration of previous HTML on post-switch failure; the first deployment has no previous release. Record the successful run and public URL. S3-origin requests must remain private while CloudFront serves the site.

For rollback, in the same authenticated/configured session, run `python scripts/release.py rollback FULL_KNOWN_GOOD_COMMIT_SHA --browser-check`. See [operations](operations.md) for recovery limitations. Keep a timed record of a real rollback drill before claiming a recovery target.

## 5. Verify project operations

- Open CloudWatch's `FRAME-production` dashboard and generate requests; metric availability must be verified, not inferred from configuration.
- Inspect fresh CloudFront log objects in the private logs bucket after delivery delay.
- Set any project spend limits in AWS Settings; only the project owner can change them.
- Activate the Project cost-allocation tag for the filtered budget. Confirm any budget email subscriptions/notifications and inspect unfiltered project costs too.
- Decide whether to keep the created resources for the portfolio demo or clean them up using the reviewed teardown procedure. Do not remove state or logs blindly.

A Free plan credit balance does not make the site permanent: project plan expiration or spend limits may stop access. The existing GitHub Pages frontend is independent of AWS project lifetime.
