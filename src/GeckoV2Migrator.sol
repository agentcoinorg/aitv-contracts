// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IERC20} from "@uniswap/v2-periphery/contracts/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {AgentToken} from "./AgentToken.sol";
import {AirdropClaim} from "./AirdropClaim.sol";
import {IAgentKey} from "./IAgentKey.sol";


/// @title GeckoV2Migrator
/// @notice The following is a contract that migrates the Gecko V1 token to V2
/// The contract will:
/// - Deploy the new Gecko V2 token contract
/// - Deploy an airdrop contract for holders of V1 to claim the new token
/// - Create and fund a liquidity pool on Uniswap
/// - Distribute tokens to the AgentCoin DAO, Agent Wallet, and the pool
contract GeckoV2Migrator is Ownable {
    error AlreadyDeployed();
    error NoEthToDeploy();
    error NoTokensToDeploy();
    error AlreadyMigrated();
    error V1NotStopped();

    IUniswapV2Router02 public immutable uniswapRouter;

    uint256 public immutable agentAmount;
    uint256 public immutable daoAmount;
    uint256 public immutable airdropAmount;
    uint256 public immutable poolAmount;
    address public immutable agentcoinDao;
    address public immutable agentWalletAddress;
    string public geckoV2Name;
    string public geckoV2Symbol;

    address public immutable geckoV1;
    address public geckoV2;
    address public airdrop;

    bool public hasMigrated;

    constructor(
        address owner, 
        string memory _name, 
        string memory _symbol, 
        address _agentcoinDao,
        address _agentWalletAddress, 
        uint256 _daoAmount, 
        uint256 _agentAmount, 
        uint256 _airdropAmount, 
        uint256 _poolAmount, 
        address _geckoV1, 
        address _uniswapRouter
    ) Ownable(owner) {
        geckoV2Name = _name;
        geckoV2Symbol = _symbol;
        agentcoinDao = _agentcoinDao;
        agentWalletAddress = _agentWalletAddress;
        daoAmount = _daoAmount;
        agentAmount = _agentAmount;
        airdropAmount = _airdropAmount;
        poolAmount = _poolAmount;
        geckoV1 = _geckoV1;
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
    }

    /// @notice Migrate the tokens from Gecko V1 to V2
    /// The contract will deploy the new Gecko V2 token, an airdrop contract for holders to claim the new token, and create a liquidity pool on Uniswap
    /// It will also distribute tokens to the AgentCoin DAO, Agent Wallet, and the pool
    /// @dev This function can only be called once
    function migrate() external onlyOwner {
        if (hasMigrated) {
            revert AlreadyMigrated();
        }

        if (!IAgentKey(geckoV1).isStopped()) { 
            revert V1NotStopped();
        }

        hasMigrated = true;

        // Deploy the airdrop contract
        airdrop = address(new AirdropClaim(geckoV1));

        // Deploy the new Gecko V2 token contract
        address geckoV2Address = _deployGeckoV2();

        // Deposit some of the v2 tokens to the airdrop contract
        IERC20(geckoV2Address).approve(airdrop, airdropAmount);
        AirdropClaim(airdrop).deposit(geckoV2Address, airdropAmount);

        // Deploy the ETH from the Gecko V1 bonding curve and a portion of the V2 tokens to the Uniswap pair to create liquidity
        _addLiquidity();
    }

    /// @notice Deploys the Gecko V2 token contract and initializes it
    /// @return The address of the deployed contract
    function _deployGeckoV2() internal returns (address) {
        if (geckoV2 != address(0)) {
            revert AlreadyDeployed();
        }

        // Deploy the implementation contract
        AgentToken implementation = new AgentToken();

        address[] memory recipients = new address[](3);
        recipients[0] = agentcoinDao;
        recipients[1] = agentWalletAddress;
        recipients[2] = address(this);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = daoAmount;
        amounts[1] = agentAmount;
        // This contract (GeckoV2Migrator) will receive the funds for the pool and the airdrop
        // It will use them to fund the pool and the airdrop contract in this transaction
        amounts[2] = poolAmount + airdropAmount;

        // Deploy the proxy contract
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation), abi.encodeCall(AgentToken.initialize, (geckoV2Name, geckoV2Symbol, agentcoinDao, recipients, amounts))
        );

        geckoV2 = address(proxy);

        return address(proxy);
    }

    /// @notice Add liquidity to the Uniswap pair
    /// The contract must have the V2 tokens and ETH in its balance
    /// @dev We burn the LP tokens by sending them to the 0 address
    function _addLiquidity() internal {
        uint256 v2Balance = IERC20(geckoV2).balanceOf(address(this));
        uint256 ethBalance = address(this).balance;
        if (v2Balance == 0) {
            revert NoTokensToDeploy();
        }

        if (ethBalance == 0) {
            revert NoEthToDeploy();
        }

        IERC20(geckoV2).approve(address(uniswapRouter), v2Balance);
        uniswapRouter.addLiquidityETH{value: ethBalance}(
            geckoV2,              // ERC20 token address
            v2Balance,            // All ERC20 tokens held by the contract
            0,                    // Accept any amount of tokens (minToken)
            0,                    // Accept any amount of ETH (minETH)
            address(0),           // NULL address receives the LP tokens
            block.timestamp       // Deadline
        );
    }

    receive() external payable {}
}