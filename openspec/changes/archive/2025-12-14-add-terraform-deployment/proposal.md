# Change: Add Terraform Deployment Infrastructure and Makefile

## Why
The project currently lacks standardized deployment automation for its Terraform infrastructure. Developers need a simple, consistent way to deploy and tear down infrastructure across environments without manual Terraform commands, reducing deployment friction and potential for errors.

## What Changes
- Add Terraform configuration for the complete event-driven infrastructure
- Create a Makefile with standardized targets for deployment operations
- Add environment-specific configuration support
- Include initialization, validation, plan, apply, and destroy workflows

## Impact
- Affected specs: New infrastructure capability
- Affected code: Project root (Makefile, new terraform/ directory)
- **BREAKING**: New deployment workflow that changes how infrastructure is managed