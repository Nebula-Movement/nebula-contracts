# Prompt Marketplace Smart Contract

A Move smart contract for creating and managing an NFT-based prompt marketplace on the Movement blockchain.

## Project Structure

```
├── sources/             # Smart contract source code
│   └── prompt_marketplace.move
├── scripts/             # Deployment and utility scripts
│   └── deploy.ts
├── build/              # Compiled contract artifacts
└── Move.toml           # Move package manifest
```

## Prerequisites

- Node.js and npm installed
- Movement CLI installed
- TypeScript
- An Movement account with funds (for deployment)

## Setup

1. Install dependencies:

```bash
npm install
```

2. Set up your environment variables:

```bash
cp .env.example .env
```

3. Edit `.env` and add your deployer account's private key.

## Deployment

1. First, compile the Move contract:

```bash
aptos move compile
```

2. Deploy the contract:

```bash
npm run deploy
```

## License

MIT
