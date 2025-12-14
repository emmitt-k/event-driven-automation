## ADDED Requirements
### Requirement: Simple Deployment Interface
The system SHALL provide exactly three deployment commands for all environments.

#### Scenario: Deploy infrastructure
- **WHEN** developer runs `./deploy.sh infra [env]`
- **THEN** Terraform infrastructure is deployed to specified environment
- **AND** All AWS resources are created or updated

#### Scenario: Update code
- **WHEN** developer runs `./deploy.sh code [env]`
- **THEN** Lambda function code is updated without infrastructure changes
- **AND** New code is deployed within 30 seconds

#### Scenario: Local testing
- **WHEN** developer runs `./deploy.sh test`
- **THEN** All unit tests are executed
- **AND** Integration tests run with LocalStack if available

## REMOVED Requirements
### Requirement: Complex Makefile Commands
**Reason**: Overly complex for small application, creates maintenance burden
**Migration**: Replace with simple 3-command deploy.sh script

### Requirement: Terraform Workspace Management
**Reason**: Unnecessary complexity for simple 2-environment setup
**Migration**: Use environment-specific variable files instead

### Requirement: Backup and Restore Commands
**Reason**: Terraform state backup is handled by AWS backend automatically
**Migration**: Remove manual backup/restore commands

### Requirement: Monitoring Commands
**Reason**: Developers can use AWS Console directly for monitoring
**Migration**: Remove logs-* commands from Makefile