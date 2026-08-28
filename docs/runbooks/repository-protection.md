# GitHub repository protection

Configure this in GitHub after the first push:

- Protect `main` and disallow direct pushes.
- Require one pull-request approval generally.
- Require both engineers for `contracts/**` changes after both handles are in CODEOWNERS.
- Require `Backend`, `iOS`, and `OpenAPI` checks.
- Require branches to be current before merge.
- Dismiss stale approvals after new commits.
- Block force pushes and branch deletion.

These are host settings and cannot be guaranteed by repository files alone.
