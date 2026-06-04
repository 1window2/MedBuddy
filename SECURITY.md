# Security Policy

## Project Status

MedBuddy is currently in active pre-release development. We have not published a
stable tagged version yet, so there is no versioned support matrix at this time.

Security fixes are applied to the active development branch that is being used
for the next release. After the project publishes its first stable version, this
file should be updated with a clear supported-version table.

## Reporting a Vulnerability

Please do not report security vulnerabilities through public GitHub issues,
pull requests, discussions, or screenshots.

If you believe you have found a vulnerability, report it by email:

pretax.rescues.8n@icloud.com

Please include:

- A short description of the vulnerability
- Steps to reproduce the issue
- The affected component, endpoint, screen, or configuration file
- The potential impact
- Any relevant logs with secrets, tokens, and personal information removed

We will acknowledge receipt within 72 hours when possible and provide follow-up
updates as the issue is triaged.

## Secret Handling

Never commit API keys, `.env` files, database dumps, private certificates, or
access tokens to the repository. Local secrets should stay in ignored files such
as `backend/.env`.

If a secret is accidentally exposed in a commit, issue, pull request, terminal
log, or screenshot, rotate or revoke the credential immediately. Removing the
text from the repository after exposure is not sufficient by itself.

## Local Data Files

The local medication catalog database can be large and may be generated from
public data sources. Do not commit generated database files such as
`backend/medbuddy.db`. Keep generated data files local, and document any
required rebuild or refresh process before relying on it in a release branch.
