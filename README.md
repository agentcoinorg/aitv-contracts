## Agent Contracts

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Deploy

To deploy AgentKey (Version 1 of the agent token contract)
```shell
$ ./deploy/base.sh pk 
```

To deploy the migration contract for Gecko token
```shell
$ ./deploy/gecko-migration-base.sh pk
```

To deploy AgentStaking
```shell
$ ./deploy/agent-staking-base.sh pk
```

### Contracts
#### AgentToken
This contract is the second version of the agent token contract (previous being AgentKey). It is an upgradeable ERC20 token with snapshot functionality.

#### AgentStaking
This contract is used to stake AgentTokenV2 tokens. A user can stake or unstake any amount of tokens at any time.
Unstaking tokens will lock the tokens for 1 day before they can be claimed. The user can claim the tokens after the lock period is over.

#### GeckoV2Migrator
This contract is used to migrate the old Gecko token to the new Gecko token. 
The old token contract is AgentKey and the new token contract is AgentTokenV2.
It deploys the new Gecko token contract, an airdrop contract for holders of the old token to claim the new token, creates and funds a liquidity pool on Uniswap, and distributes tokens to the AgentCoin DAO, Gecko's cold wallet, and the pool.
There will be 10 million new Gecko tokens minted and distributed as follows:
- 700,000 to the AgentCoin DAO
- 300,000 to the Gecko cold wallet
- 2,500,000 to the airdrop contract for holders of the old Gecko token
- 6,500,000 to the Uniswap pool

##### Migration process
1. Deploy the GeckoV2Migrator contract
2. Call the stopAndTransferReserve function on the old Gecko token contract to stop the token and transfer the reserves to the new contract
3. Call the migrate function on the GeckoV2Migrator contract to start the migration process
2. and 3. will be done within the same transaction by the DAO's Gnosis Safe

#### AirdopClaim
This contract is used to claim the new Gecko token for holders of the old Gecko token. The contract is funded by the GeckoV2Migrator contract and the user can claim the new token by calling the claim function.
Anyone can call the claim function for any address, but that address can only claim once.
