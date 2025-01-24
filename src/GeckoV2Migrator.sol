// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {AgentKeyV2} from "./AgentKeyV2.sol";
import {AirdropClaim} from "./AirdropClaim.sol";

contract GeckoV2Migrator is Ownable {
    error AlreadyDeployed();
    error NoEthToDeploy();
    error NoTokensToDeploy();
    error AlreadyMigrated();

    event LiquidityPoolCreated(address pair);

    IUniswapV2Router02 public immutable uniswapRouter;

    uint256 public immutable agentcoinDaoAmount;
    uint256 public immutable airdropAmount;
    uint256 public immutable poolAmount;
    string public constant name = "Gecko";
    string public constant symbol = "GECKO";

    address public immutable geckoV1;
    address public geckoV2;
    address public airdrop;

    bool public hasMigrated;

    constructor(address owner, uint256 _agentCoinDaoAmount, uint256 _airdropAmount, uint256 _poolAmount, address _geckoV1, address _uniswapRouter) Ownable(owner) {
        agentcoinDaoAmount = _agentCoinDaoAmount;
        airdropAmount = _airdropAmount;
        poolAmount = _poolAmount;
        geckoV1 = _geckoV1;
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
    }

    function migrate() external onlyOwner {
        if (hasMigrated) {
            revert AlreadyMigrated();
        }

        hasMigrated = true;

        airdrop = address(new AirdropClaim(geckoV1));

        address geckoV2Address = _deployGeckoV2(owner());

        IERC20(geckoV2Address).approve(airdrop, airdropAmount);
        AirdropClaim(airdrop).deposit(geckoV2Address, airdropAmount);

        _createPair();
        _deployLiquidity();
    }

    function _deployGeckoV2(address agentcoinDao) internal returns (address) {
        if (geckoV2 != address(0)) {
            revert AlreadyDeployed();
        }

        AgentKeyV2 implementation = new AgentKeyV2();

        address[] memory recipients = new address[](2);
        recipients[0] = agentcoinDao;
        recipients[1] = address(this);

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = agentcoinDaoAmount;
        amounts[1] = poolAmount + airdropAmount;

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation), abi.encodeCall(AgentKeyV2.initialize, (name, symbol, agentcoinDao, recipients, amounts))
        );

        geckoV2 = address(proxy);

        return address(proxy);
    }

    function _createPair() internal {
        address uniswapV2Pair = IUniswapV2Factory(uniswapRouter.factory()).getPair(
            geckoV2,
            uniswapRouter.WETH()
        );

        if (uniswapV2Pair == address(0)) {
            uniswapV2Pair = IUniswapV2Factory(uniswapRouter.factory())
                .createPair(geckoV2, geckoV1);

            emit LiquidityPoolCreated(uniswapV2Pair);
        }
    }

    function _deployLiquidity() internal {
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