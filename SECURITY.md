# Security Policy

## Reporting a Vulnerability

The AITV team takes security seriously. If you've found a security vulnerability in AITV Contracts, please report it responsibly.

### How to Report

**Do NOT report security vulnerabilities via public GitHub Issues.**

Instead, please send an email to the team with:

1. A detailed description of the vulnerability
2. Steps to reproduce the issue
3. Potential impact assessment
4. A proof-of-concept exploit (if possible)

### What to Include

When reporting a vulnerability, please include:

- The specific contract(s) affected
- The type of vulnerability (reentrancy, access control, arithmetic, etc.)
- Step-by-step instructions to reproduce
- Any relevant transaction hashes or test cases
- Suggested fixes (optional but appreciated)

## Responsible Disclosure

Please:

- Give us reasonable time to address the issue before public disclosure
- Do not exploit the vulnerability beyond what is necessary to demonstrate it
- Do not access or modify data belonging to other users
- Act in good faith to avoid privacy violations, data destruction, or service disruption

## Scope

The following are in scope for security reports:

- Smart contracts in the `src/` directory
- Deployment scripts that could affect contract security
- Access control and permission issues
- Token handling and transfer logic
- Integration vulnerabilities with external protocols (Uniswap, etc.)

## Out of Scope

- Issues in third-party dependencies (report these upstream)
- Issues in test files that don't affect production code
- Gas optimization suggestions (unless they cause DoS)
- Frontend or off-chain infrastructure issues

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| Latest  | :white_check_mark: |

## Recognition

We appreciate security researchers who help keep AITV Contracts safe. Responsible disclosure of valid vulnerabilities will be acknowledged.

## Contact

For security-related inquiries, please reach out through the appropriate channels listed in the project documentation at [docs.agentcoin.tv](https://docs.agentcoin.tv/).
