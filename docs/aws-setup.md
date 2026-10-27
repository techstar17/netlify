# Connect GitHub to AWS without sharing keys

**Current status:** the repository contains tested configuration, not provisioned AWS resources. No account credentials have been supplied. Running the Terraform apply steps below creates billable AWS resources. A budget sends notifications; it does not cap spending. Keep the existing GitHub Pages deployment while bringing up AWS.

**Using a training sandbox?** Read [sandbox constraints](sandbox.md) first. Confirm the provider, permitted region/services, and IAM permissions before applying this full account-level stack.

**Current s3 project:** AWS has confirmed an active Free plan in the new experience. Use the [Windows project guide](windows-project.md), not this advanced OIDC walkthrough: managed project policies block creating identity providers.

## 1. Open an authenticated terminal

Sign in to the [AWS Console](https://console.aws.amazon.com/) using an IAM user or an IAM Identity Center role with permission to create S3, CloudFront, IAM OIDC/roles/policies, CloudWatch, SNS, and Budgets resources. Open **CloudShell** (terminal icon). Choose a permitted region for the S3 origin (default **us-east-1**; **us-east-2** is also supported). CloudFront monitoring additionally requires permission for CloudWatch/SNS in us-east-1, regardless of the origin region.

CloudShell supplies temporary AWS credentials. Do not copy them into chat, this repository, GitHub secrets, or a `.tfvars` file. This does not connect the chat's machine to AWS: you will provision the foundation in CloudShell, then GitHub will deploy using OIDC.

```bash
export AWS_REGION=us-east-1  # Set to your permitted S3 region, e.g. us-east-2.
export TF_VAR_aws_region="$AWS_REGION"
aws sts get-caller-identity
# Confirm this is the intended account. The command displays identity, not keys.
git clone https://github.com/techstar17/netlify.git frame
cd frame
bash scripts/install-terraform.sh
export PATH="$HOME/.local/bin:$PATH"
```

If the repository is private, use your normal GitHub authentication in CloudShell or upload a downloaded repository archive. Do not paste a token into a clone URL. For future sessions, use `cd frame && git pull --ff-only` rather than cloning over existing work. Terraform is pinned to 1.12.2; the installer verifies its archive checksum against HashiCorp's HTTPS manifest. Keep CLI and provider versions updated through reviewed changes.

## 2. Create the remote state bucket once

```bash
terraform -chdir=infra/bootstrap init -lockfile=readonly
terraform -chdir=infra/bootstrap plan -out=bootstrap.tfplan
terraform -chdir=infra/bootstrap apply bootstrap.tfplan
STATE_BUCKET=$(terraform -chdir=infra/bootstrap output -raw backend_bucket)
```

The state bucket is private, encrypted, versioned, and protected against Terraform destruction. The bootstrap stack initially has local state. Copy its state into that bucket, then migrate its backend so CloudShell home-directory loss does not lose the foundation:

```bash
aws s3 cp infra/bootstrap/terraform.tfstate "s3://$STATE_BUCKET/bootstrap-initial-state/terraform.tfstate"
cat > infra/bootstrap/backend.tf <<'HCL'
terraform {
  backend "s3" {
    key          = "frame/bootstrap/terraform.tfstate"
    use_lockfile = true
    encrypt      = true
  }
}
HCL
terraform -chdir=infra/bootstrap init -migrate-state \
  -backend-config="bucket=$STATE_BUCKET" -backend-config="region=$AWS_REGION"
```

Answer **yes** when Terraform asks to copy the local state. `backend.tf` is local to this setup; do not commit this generated file. If migration fails, preserve the original local state and the S3 backup, diagnose, and retry; do not apply the bootstrap again against empty state. If recovering in a fresh checkout, recreate `backend.tf` and initialize it against this bucket before planning; alternatively restore the initial backup to local state if migration never completed. The state is sensitive and must remain private.

## 3. Review and provision the app infrastructure

```bash
terraform -chdir=infra/terraform init -lockfile=readonly \
  -backend-config="bucket=$STATE_BUCKET" -backend-config="region=$AWS_REGION"
cp infra/terraform/terraform.tfvars.example infra/terraform/terraform.tfvars
```

Edit `infra/terraform/terraform.tfvars`:

- Set `aws_region` to your permitted S3 origin region, matching `$AWS_REGION`. Do not change the region of an existing stack without a separate migration plan.
- Set `alert_email` to your own address if you want alarm and budget notifications. Email is optional; if omitted, there is no email delivery.
- Check whether your AWS account already has the GitHub OIDC provider:

  ```bash
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  aws iam list-open-id-connect-providers
  # Look for arn:aws:iam::<your-account>:oidc-provider/token.actions.githubusercontent.com
  ```

  If it exists, set `create_github_oidc_provider = false`. Reuse that provider; do not delete it or disturb other repositories. A permission error is not proof the provider is absent. Ask your account administrator if inspection is denied.
- The default CloudFront hostname works without purchasing a domain. For TLS 1.2+ enforcement, supply an existing custom domain and validated ACM certificate in **us-east-1** together. The AWS-managed `*.cloudfront.net` certificate uses AWS's default TLS policy; Terraform cannot strengthen that default certificate policy. See [architecture](architecture.md).

```bash
terraform -chdir=infra/terraform plan -var="aws_region=$AWS_REGION" -out=production.tfplan
# Review all resources and expected account before applying.
terraform -chdir=infra/terraform apply production.tfplan
terraform -chdir=infra/terraform output
```

CloudFront provisioning can take several minutes. Keep the output. No application files exist in the new bucket until the first successful deployment; a 403/404 at this point is expected. Do not replace it with a public S3 website.

For custom domains, add an ALIAS/CNAME to the distribution domain in your DNS service before the live health checks. Route 53/domain registration/ACM issuance are not automated by this stack.

## 4. Configure GitHub's production environment

Open the repository's **Settings → Environments → New environment**, and name it `production`.

Under **Deployment branches and tags**, choose selected branches and allow **main only**. Where your GitHub plan supports it, enable required reviewers and prevent self-review. Branch restriction is essential: AWS trusts this repository/environment pair, so environment protection controls which refs can obtain production credentials. Protect `main` with required reviews and the quality checks when supported. Administrators with bypass permissions still need governance.

Under **Settings → Secrets and variables → Actions → Variables**, create these **repository variables** (not secrets):

| Variable | Terraform output |
| --- | --- |
| `AWS_REGION` | `aws_region` (S3 origin region) |
| `AWS_DEPLOY_ROLE_ARN` | `deploy_role_arn` |
| `SITE_BUCKET` | `site_bucket` |
| `CLOUDFRONT_DISTRIBUTION_ID` | `distribution_id` |
| `SITE_URL` | `site_url` |

Do not add AWS access keys. The pipeline exchanges GitHub's OIDC token for a short-lived AWS role session. The role cannot manage Terraform, IAM, bucket policies, delete releases, or read state/log buckets. Infrastructure changes require your separate authenticated operator session and a reviewed Terraform plan.

## 5. Deploy and verify

Open **Actions → AWS production release → Run workflow**, choose `main`, operation `deploy`, and run it. Approve the production environment review if configured. After the run succeeds, use the **Site** link in its job summary.

If `AWS_DEPLOY_ROLE_ARN` is absent, AWS deployment is deliberately skipped. A green overall run with a skipped release job does **not** mean a live AWS site exists. Missing individual variables fail the release job explicitly.

The workflow runs browser tests locally, verifies stored checksums, switches the root HTML, invalidates CloudFront, then verifies the live release, assets, sample video, and browser interactions. A post-switch failure attempts restoration of the prior entry point and still marks the run failed. The first deployment has no previous entry point to restore.

## 6. Activate monitoring and costs

- Confirm the SNS email subscription sent to `alert_email`; otherwise CloudWatch cannot reach your inbox.
- In **Billing → Cost allocation tags**, activate the user-defined **Project** tag. Tag discovery and cost data are delayed; project budget coverage is incomplete until activation. CloudFront and S3 usage can cost money, including data transfer for sample video.
- Check **CloudWatch → Dashboards → FRAME-production** and both `frame-cloudfront-*` alarms in **us-east-1**. No traffic/missing data does not prove health.
- Generate requests, wait for metrics/log delivery, inspect the private log bucket, and run a controlled SNS alarm notification test (see the runbook).
- Record your verified public URL and successful run in [evidence](evidence.md). Do not claim production deployment before those checks.
