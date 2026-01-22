# Contributing to AITV Contracts

Thank you for your interest in contributing to AITV Contracts! This document provides guidelines and information for contributors.

## Getting Started

### Prerequisites

- [Foundry](https://getfoundry.sh/) - Solidity development framework
- Node.js and npm/yarn (for TypeScript utilities in `nfts/` and `airdrop/`)

### Building

```bash
forge build
```

### Running Tests

```bash
forge test
```

## How to Contribute

### Reporting Bugs

1. Check if the bug has already been reported in [Issues](https://github.com/agentcoinorg/aitv-contracts/issues)
2. If not, open a new issue with:
   - A clear description of the bug
   - Steps to reproduce
   - Expected vs actual behavior
   - Relevant logs or error messages

**Security vulnerabilities** should NOT be reported via GitHub Issues. See [SECURITY.md](SECURITY.md) for responsible disclosure guidelines.

### Submitting Pull Requests

1. Fork the repository
2. Create a feature branch from `main`
3. Make your changes following the coding standards below
4. Ensure all tests pass with `forge test`
5. Submit a pull request

### Coding Standards

#### Solidity

- Use Solidity `0.8.28` for new contracts
- Follow the existing code style in the repository
- Add NatSpec documentation for public functions
- Include comprehensive tests for new features

#### TypeScript (nfts/, airdrop/)

- Follow existing patterns in the codebase
- Include proper type annotations
- Document environment variables required

### Testing Requirements

- All new features should include unit tests
- Run the full test suite before submitting: `forge test`
- For integration tests, ensure proper RPC URL configuration

## Project Structure

```
├── src/              # Main Solidity contracts
├── script/           # Deployment scripts
├── test/             # Foundry tests
├── nfts/             # NFT metadata generation and distribution scripts
├── airdrop/          # Airdrop utility scripts
└── deploy.sh         # Deployment helper script
```

## Deployment

See the [README.md](README.md) for deployment instructions using `deploy.sh`.

## Documentation

Full documentation is available at [docs.agentcoin.tv](https://docs.agentcoin.tv/)

## Code of Conduct

Please be respectful and constructive in all interactions. We're all here to build great software together.

## License

By contributing, you agree that your contributions will be licensed under the project's license.
