# Agent Contracts

## Documentation
Agentcoin.tv documentation can be found [here](https://docs.agentcoin.tv/)

## Build

```shell
$ forge build
```

## Test

```shell
$ forge test
```

## Deploy

E.g. to deploy AgentFactory on Base
```shell
$ ./deploy.sh pk base DeployAgentFactory
```
deploy.sh is a script that takes the auth option (pk or account), network, and script name as arguments

## Contracts
### AgentToken
This contract is the token contract for Agents. It is an upgradeable ERC20 token with snapshot and burn functionality.

### AgentStaking
This contract is used to stake AgentToken tokens. A user can stake or unstake any amount of tokens at any time.
Unstaking tokens will lock the tokens for 1 day before they can be claimed. The user can claim the tokens after the lock period is over.

### AgentFactory
This contract is used to deploy Agent Launch Pool contracts. It is a factory contract that deploys a new Agent Launch Pool contract for each new agent.
Anyone can propose a configuration for the new launch pool. 
The configuration includes information about the token, launch pool, agent token distribution, collateral distribution, and uniswap pool creation.
Only the owner can deploy a proposal or a configuration directly.

### AgentLaunchPool
The following is a contract to launch Agent Tokens.
The contract will:
- Allow users to deposit ETH or ERC20 collateral (depending on configuration) to receive Agent Tokens after the launch 
On launch it will:
- Deploy the Agent Token contract
- Deploy the Agent Token Staking contract
- Allow users to claim their agent tokens
- Create and fund a liquidity pool on Uniswap V4
- Distribute agent tokens to the specified recipients (this happens as part of Agent Token deployment) and the depositors of the pool
- Distribute collateral to the specified recipients
If the launch fails, users can reclaim their deposits
The launch fails if the minimum amount is not reached by the end of the launch window.  
More information about the launch pool can be found [here](https://docs.agentcoin.tv/curating-fair-launches#launch-pools)

### AgentUniswapHook
The hook contract for the Uniswap V4 pool.
It takes fees from collateral and burns agent tokens on swap.
If collateral amount is known, then collateral fee is taken and no agent tokens are burned.
If the agent token amount is known, then the agent token fee is burned and collateral is not taken.
The following is the list of cases:
- Buying agent tokens with specified input collateral amount - collateral fee is taken
- Buying agent tokens with specified output agent token amount - agent token fee is burned
- Selling agent tokens with specified input agent token amount - agent token fee is burned
- Selling agent tokens with specified output collateral amount - collateral fee is taken  
More information about the fee structure can be found [here](https://docs.agentcoin.tv/interactive-viewership#fee-distribution)

### TokenDistributor
This contract handles flexible and programmable distributions of ETH or ERC20 tokens. 
It supports sending, burning, swapping via Uniswap (V2/V3/V4), and calling external contracts with encoded arguments. 
Distributions are composed of modular actions and can be nested to enable complex flows like funding, liquidity provisioning, and launch pool participation.
A distribution needs to be paired with a human readable name (bytes32) before it can be executed.