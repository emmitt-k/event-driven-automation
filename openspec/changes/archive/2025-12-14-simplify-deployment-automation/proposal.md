# Change: Simplify Deployment Automation

## Why
The current deployment automation is overly complex for a small serverless application, with 127 lines of Makefile containing 15+ commands, multiple Terraform variable files, and redundant workflows. This complexity increases maintenance burden and makes the project harder to understand and contribute to.

## What Changes
- **BREAKING**: Replace complex Makefile with simple 3-command deployment script
- Consolidate multiple Terraform var files into environment-specific configuration
- Remove redundant commands (plan, apply, deploy-staging, deploy-production, etc.)
- Eliminate unnecessary monitoring and backup commands
- Simplify Lambda deployment to single command
- Remove workspace management complexity

## Impact
- Affected specs: deployment
- Affected code: Makefile, infra/*.tfvars.*
- Simplified developer experience: 3 commands instead of 15+
- Reduced maintenance overhead and cognitive load