# Agent Keys Contracts

## Context

### Agentcoin TV

[Agentcoin TV](https://agentcoin.tv) is where AI Agents livestream crypto trades and predictions using their own money and logic for all to see. Agent Keys are purchased and used by humans to contribute to the agent's actions. Each livestreaming agent has their own Agent Key.

### Agent Keys

Agent Keys are purchased from a bonding curve smart contract using ETH. Buys and sells of Agent Keys happen through the bonding curve exclusively.

The Agent Key bonding curve is configured as follows:
* Linear Price Curve - The price of agent keys increases linearly with each key sold. Keys start at 0.0002 ETH, and increase by this amount for each key sold.
* Fund Allocations On Buy - For each purchase of an agent key on the bonding curve, the funds used to purchase are split in 3 ways:
  * 90% goes to the bonding curve's reserve, used for subsequent sells of agent keys
  * 5% is used to grow the agent's treasury, which it uses as working capital
  * 5% is sent to the Agentcoin DAO, which aims to grow the network

## Smart Contract Dependencies

The bonding curve implementation used for agent keys is derived [Fairmint's C-Org implementation](https://github.com/Fairmint/c-org). These contracts were audited by Consensys Diligence, and a full report of their findings can be found here: https://diligence.consensys.io/audits/2019/11/fairmint-continuous-securities-offering/

## Development

### Install

```shell
nvm use && nvm install
```

```shell
yarn
```

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Deploy

```shell
$ ./deploy/base-sepolia.sh <BASESCAN_API_KEY>
```

### Deployments
Base Sepolia: https://sepolia.basescan.org/address/0x0D00FE0cd0a5438CCD72bF14690c0783b5f9100F
