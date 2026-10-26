# Using a training or project sandbox

A sandbox is useful for a cloud engineering exercise, but its permissions and lifetime differ from an account you administer. The AWS session chooser alone does not identify the provider, allowed region, or enabled services.

If your console displays **Connect your AI coding agent to AWS**, its **Copy agent prompt** button provides the project-specific setup instructions. Review those instructions without sharing passwords, raw keys, or session tokens. A connection route supported by a local CLI is not automatically available in this hosted chat; verify the available integration before claiming account access.

1. Start the lab/sandbox from the training provider's portal. Wait for its active session and use its supplied console link.
2. Read the lab's permitted services, regions, roles, session duration, and resource-cleanup policy. Do not assume the region in a sign-in URL is the deployment region.
3. If CloudShell/CLI is provided, run `aws sts get-caller-identity` to confirm a working session. Do not paste access keys, session tokens, or credential files into chat/GitHub.
4. Identify whether S3, CloudFront/OAC, IAM OIDC/role creation, CloudWatch, SNS, and Budgets are allowed. An AccessDenied response is a permission boundary, not a reason to try elevated credentials or bypass the sandbox.
5. Before using the full [AWS setup guide](aws-setup.md), confirm those prerequisites with the provider. The full stack defaults to a us-east-1 origin (configurable, including us-east-2), needs account-level IAM/budget permissions, and requires us-east-1 access for CloudFront monitoring. Do not apply it unchanged when the sandbox restricts global monitoring services or only provides a fixed lab role.

If IAM/OIDC creation is prohibited, the GitHub-to-AWS deployment role cannot be bootstrapped in that sandbox. Use an instructor-provided approved role if one exists, or run a separately scoped deployment from the authorized lab terminal after adapting the infrastructure to its allowed services. Do not store temporary sandbox credentials in GitHub to work around the restriction. The full production stack remains a tested reference design until a compatible account is available.

Sandbox resources and credentials may expire or be deleted at session end. Record the architecture, Terraform plan, allowed deployment evidence, and recovery results, but do not promise persistent public hosting. GitHub Pages remains a separate option for a durable frontend demo, subject to its repository settings.

Once the provider/allowed region are known, the next step is to adapt and validate only the supported components, then perform a real plan before any resource creation. Credentials available in your browser's sandbox console are not automatically available to the machine running this chat.
