// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Currency} from '@uniswap/v4-core/src/types/Currency.sol';
import {PoolId} from '@uniswap/v4-core/src/types/PoolId.sol';
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';
import {Commands} from "@uniswap/universal-router/src/libraries/Commands.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IUniversalRouter} from "@uniswap/universal-router/src/interfaces/IUniversalRouter.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IHooks} from '@uniswap/v4-core/src/libraries/Hooks.sol';
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TransientStateLibrary} from "@uniswap/v4-core/src/libraries/TransientStateLibrary.sol";
import {IPoolManager} from '@uniswap/v4-core/src/interfaces/IPoolManager.sol';
import { TickMath } from "@uniswap/v4-core/src/libraries/TickMath.sol";
import { Currency } from '@uniswap/v4-core/src/types/Currency.sol';

import {AgentLaunchPool} from "../../src/AgentLaunchPool.sol";
import {IAgentLaunchPool} from "../../src/interfaces/IAgentLaunchPool.sol";
import {TokenInfo} from "../../src/types/TokenInfo.sol";
import {LaunchPoolInfo} from "../../src/types/LaunchPoolInfo.sol";
import {UniswapPoolInfo} from "../../src/types/UniswapPoolInfo.sol";
import {AgentDistributionInfo} from "../../src/types/AgentDistributionInfo.sol";
import {UniswapFeeInfo} from "../../src/types/UniswapFeeInfo.sol";
import {AgentFactory} from "../../src/AgentFactory.sol";
import {AgentUniswapHookDeployer} from "../../src/AgentUniswapHookDeployer.sol";
import {AgentUniswapHook} from "../../src/AgentUniswapHook.sol";
import {AgentToken} from "../../src/AgentToken.sol";
import {AgentStaking} from "../../src/AgentStaking.sol";
import {UniswapTestUtils} from "./UniswapTestUtils.sol";

abstract contract AgentFactoryTestUtils is Test, AgentUniswapHookDeployer, UniswapTestUtils {
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    
    address public uniswapPositionManager = vm.envAddress("BASE_POSITION_MANAGER");
    address owner = makeAddr("owner");
    address agentWallet = makeAddr("agentWallet");
    address dao = makeAddr("dao");
    address agentTokenImpl;
    address agentStakingImpl;
    AgentFactory factory;
    AgentUniswapHook hook;

    address tokenOwner = dao;
    string tokenName = "Agent Token";
    string tokenSymbol = "AGENT";
    uint256 totalSupply = 10_000_000 * 1e18;
    uint256 daoCollateralBasisAmount = 1_000;
    uint256 agentWalletCollateralBasisAmount = 2_500;
    uint256 timeWindow = 7 days;
    uint256 minAmountForLaunch = 1 ether;
    uint256 maxAmountForLaunch = 10 ether;
    
    uint256 collateralUniswapPoolBasisAmount = 6_500;

    uint24 lpFee = 50;
    int24 tickSpacing = 200;

    uint256 agentDaoBasisAmount = 1_500;
    uint256 agentDaoAmount = 1_500_000 * 1e18; 

    uint256 agentWalletBasisAmount = 2_000;
    uint256 agentAmount = 2_000_000 * 1e18;

    uint256 launchPoolBasisAmount = 4_000;
    uint256 launchPoolAmount = 4_000_000 * 1e18;

    uint256 uniswapPoolBasisAmount = 2_500;
    uint256 uniswapPoolAmount = 2_500_000 * 1e18;

    uint256 burnBasisAmount = 100;
    uint256 daoFeeBasisAmount = 50;
    uint256 agentWalletFeeBasisAmount = 50;

    constructor() {
        uniswapPoolManager = vm.envAddress("BASE_POOL_MANAGER");
        uniswapUniversalRouter = vm.envAddress("BASE_UNIVERSAL_ROUTER");
    }

    function _deployAgentFactory(address _owner) internal returns(AgentFactory) {
        address agentFactoryImpl = address(new AgentFactory());

        return AgentFactory(address(new ERC1967Proxy(
            agentFactoryImpl, 
            abi.encodeCall(AgentFactory.initialize, (
                _owner,
                uniswapPositionManager
            ))
        )));
    }

    function _deployAgentUniswapHook(address _owner, address _controller) internal returns(AgentUniswapHook) {
        return _deployAgentUniswapHook(_owner, _controller, uniswapPoolManager);
    }

    function _deployDefaultContracts() internal {
        agentTokenImpl = address(new AgentToken());
        agentStakingImpl = address(new AgentStaking());
        
        factory = _deployAgentFactory(owner);
        hook = _deployAgentUniswapHook(owner, address(factory));
    }

    function _deployDefaultLaunchPool(address collateral) internal returns (AgentLaunchPool, PoolKey memory) {
        TokenInfo memory tokenInfo = TokenInfo({
            owner: tokenOwner,
            name: tokenName,
            symbol: tokenSymbol,
            totalSupply: totalSupply,
            tokenImplementation: agentTokenImpl,
            stakingImplementation: agentStakingImpl
        });

        address[] memory collateralRecipients = new address[](2);
        collateralRecipients[0] = dao;
        collateralRecipients[1] = agentWallet;

        uint256[] memory collateralBasisAmounts = new uint256[](2);
        collateralBasisAmounts[0] = daoCollateralBasisAmount;
        collateralBasisAmounts[1] = agentWalletCollateralBasisAmount;

        LaunchPoolInfo memory launchPoolInfo = LaunchPoolInfo({
            collateral: collateral,
            timeWindow: timeWindow,
            minAmountForLaunch: minAmountForLaunch,
            maxAmountForLaunch: maxAmountForLaunch,
            collateralUniswapPoolBasisAmount: collateralUniswapPoolBasisAmount,
            collateralRecipients: collateralRecipients,
            collateralBasisAmounts: collateralBasisAmounts
        });

        UniswapPoolInfo memory uniswapPoolInfo = UniswapPoolInfo({
            permit2: permit2,
            hook: address(hook),
            lpRecipient: dao,
            lpFee: lpFee,
            tickSpacing: tickSpacing
        });

        address[] memory recipients = new address[](2);
        recipients[0] = dao;
        recipients[1] = agentWallet;
        uint256[] memory basisAmounts = new uint256[](2);
        basisAmounts[0] = agentDaoBasisAmount;
        basisAmounts[1] = agentWalletBasisAmount;

        AgentDistributionInfo memory distributionInfo = AgentDistributionInfo({
            recipients: recipients,
            basisAmounts: basisAmounts,
            launchPoolBasisAmount: launchPoolBasisAmount,
            uniswapPoolBasisAmount: uniswapPoolBasisAmount
        });

        address[] memory feeRecipients = new address[](2);
        feeRecipients[0] = dao;
        feeRecipients[1] = agentWallet;

        uint256[] memory feeBasisAmounts = new uint256[](2);
        feeBasisAmounts[0] = daoFeeBasisAmount;
        feeBasisAmounts[1] = agentWalletFeeBasisAmount;

        UniswapFeeInfo memory uniswapFeeInfo = UniswapFeeInfo({
            collateral: collateral,
            burnBasisAmount: burnBasisAmount,
            recipients: feeRecipients,
            basisAmounts: feeBasisAmounts
        });

        uint256 proposalId = factory.addProposal(address(new AgentLaunchPool()), tokenInfo, launchPoolInfo, uniswapPoolInfo, distributionInfo, uniswapFeeInfo);

        vm.prank(owner);
        AgentLaunchPool pool = AgentLaunchPool(payable(factory.deployProposal(proposalId)));

        assertEq(pool.owner(), owner);

        assertEq(pool.hasLaunched(), false);
        assertEq(pool.launchPoolCreatedOn(), block.timestamp);
        assertEq(pool.totalDeposited(), 0);
        assertEq(pool.agentToken(), address(0));
        assertEq(pool.agentStaking(), address(0));

        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(launchPoolInfo.collateral < pool.computeAgentTokenAddress() ? launchPoolInfo.collateral : pool.computeAgentTokenAddress()),
            currency1: Currency.wrap(launchPoolInfo.collateral < pool.computeAgentTokenAddress() ? pool.computeAgentTokenAddress() : launchPoolInfo.collateral),
            fee: uniswapPoolInfo.lpFee,
            tickSpacing: uniswapPoolInfo.tickSpacing,
            hooks: IHooks(uniswapPoolInfo.hook)
        });

        return (pool, poolKey);
    }
}