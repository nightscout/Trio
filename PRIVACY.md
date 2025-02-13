# Privacy Policy for Trio Debug Data Collection
*A Nightscout Foundation Project*

## Purpose and Scope
This privacy policy outlines the principles and practices for collecting, using, and protecting debug data in Trio, an open source insulin dosing algorithm project of the Nightscout Foundation. Our primary goal is to ensure algorithm safety and accuracy while maintaining the highest standards of user privacy.

## Data Collection Principles

### 1. Minimal Collection
- We collect only the mathematical differences between JavaScript and Swift algorithm implementations
- No personal identifiers, device information, or timestamps are collected
- No actual insulin doses, blood glucose values, or other medical data are stored
- Data collected is limited strictly to algorithm debugging purposes

### 2. Anonymization
- All data is anonymized at the source before transmission
- Device identification uses Apple's vendor ID system, which:
  - Allows users to reset their device identifier at any time
  - Provides consistent identification only until user reset
  - Cannot be used to track across different apps
- No IP addresses are stored
- No geographic or temporal information is retained
- No personal user information is collected

### 3. Transparency
- All data collection code is [open source](https://github.com/kingst/trio-oref-logs) and available for community review
- The specific data points being collected are documented in the source code
- Any changes to data collection must go through public code review
- Regular reports on data usage will be published to the community

## Data Usage

### Permitted Uses
- Identifying mathematical discrepancies between implementations
- Validating algorithm consistency across platforms
- Debugging edge cases in calculations
- Improving algorithm accuracy and safety

### Prohibited Uses
- No commercial use or sharing with third parties
- No attempt to re-identify or correlate data points
- No use for marketing, analytics, or user behavior analysis
- No combination with other data sources

### Use in research publications
- We will maintain aggregate statistics, like invocation rates and average timing differences between Javascript and Swift for use in research publications
- We will not use individual records

## Data Protection

### Security Measures
- Data is encrypted in transit and rest using industry-standard protocols
- Access to collected data is strictly limited to core algorithm developers
- Data is stored in a secure, isolated environment
- Regular security audits are performed

### Data Retention
- Debug data is retained only for the duration necessary for verification
- Maximum retention period of 90 days
- Automatic deletion after the retention period
- Option for immediate deletion upon request

## Community Oversight

### Transparency Reports
- Monthly reports on:
  - Volume of data collected
  - How the data was used
  - Any findings or improvements made
  - Confirmation of data deletion

### Community Control
- Data collection can be disabled by users at any time
- Community voting required for any changes to this policy
- Annual review of data collection necessity
- Public issue tracker for privacy-related concerns

## User Rights

### Control and Consent
- Explicit opt-in required for data collection
- Right to opt-out at any time
- Right to reset device identifier through iOS settings
- Right to request verification of data deletion

### Communication
- 48-hour response time commitment for privacy concerns
- Regular updates on privacy-related improvements
- Clear documentation of all privacy features

## Updates to This Policy
- Changes require community discussion period
- Minimum 90-day notice before any changes
- All historical versions maintained in repository
- Change log with justifications maintained

## Contact Information
- Dedicated privacy contacts listed in DATA_MAINTAINERS.md
- Public discussion in GitHub issues
- Optional private communication channel for sensitive concerns

This policy is maintained in the Trio project repository at `/PRIVACY.md` and is governed by the same open source principles as the rest of the project. As a Nightscout Foundation project, Trio adheres to the Foundation's commitment to transparency, security, and patient privacy in diabetes technology.