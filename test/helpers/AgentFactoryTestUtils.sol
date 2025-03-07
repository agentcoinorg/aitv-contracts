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

abstract contract AgentFactoryTestUtils is Test, AgentUniswapHookDeployer {
    address public uniswapPoolManager = vm.envAddress("BASE_POOL_MANAGER");
    address public uniswapPositionManager = vm.envAddress("BASE_POSITION_MANAGER");
    address public uniswapUniversalRouter = vm.envAddress("BASE_UNIVERSAL_ROUTER");
    address owner = makeAddr("owner");
    address agentWallet = makeAddr("agentWallet");
    address dao = makeAddr("dao");
    address agentTokenImpl;
    address agentStakingImpl;
    address permit2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    AgentFactory factory;
    AgentUniswapHook hook;

    address tokenOwner = dao;
    string tokenName = "Agent Token";
    string tokenSymbol = "AGENT";
    uint256 totalSupply = 10_000_000 * 1e18;
    uint256 daoCollateralBasisAmount = 1000;
    uint256 agentWalletCollateralBasisAmount = 2500;
    uint256 timeWindow = 7 days;
    uint256 minAmountForLaunch = 1 ether;
    uint256 maxAmountForLaunch = 10 ether;
    uint256 collateralUniswapPoolBasisAmount = 6500;
    uint24 lpFee = 50;
    int24 tickSpacing = 200;
    uint256 agentDaoBasisAmount = 1500;
    uint256 agentWalletBasisAmount = 2000;
    uint256 launchPoolBasisAmount = 2500;
    uint256 uniswapPoolBasisAmount = 4000;
    uint256 burnBasisAmount = 100;
    uint256 daoFeeBasisAmount = 50;
    uint256 agentWalletFeeBasisAmount = 50;

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

    function _deployDefaultLaunchPool(address collateral) internal returns (AgentLaunchPool) {
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
            tickSpacing: tickSpacing,
            startingPrice: 1 * 2**96
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

        address launchPoolImplementation = address(new AgentLaunchPool());

        uint256 proposalId = factory.addProposal(launchPoolImplementation, tokenInfo, launchPoolInfo, uniswapPoolInfo, distributionInfo, uniswapFeeInfo);

        vm.prank(owner);
        AgentLaunchPool pool = AgentLaunchPool(payable(factory.deployProposal(proposalId)));

        assertEq(pool.tokenInfo(), tokenInfo);
        assertEq(pool.launchPoolInfo(), launchPoolInfo);
        assertEq(pool.uniswapPoolInfo(), uniswapPoolInfo);
        assertEq(pool.distributionInfo(), distributionInfo);
        assertEq(pool.owner(), owner);

        assertEq(pool.hasLaunched(), false);
        assertEq(pool.launchPoolCreatedOn(), block.timestamp);
        assertEq(pool.totalDeposited(), 0);
        assertEq(pool.agentToken(), address(0));
        assertEq(pool.agentStaking(), address(0));

        return pool;
    }

    function _buyOnUniswap(address user, uint256 ethAmount, address token) internal {
        IUniswapV2Router02 router = IUniswapV2Router02(uniswapRouter);

        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = token;

        uint256 startEthBalance = user.balance;
        uint256 startTokenBalance = IERC20(token).balanceOf(user);

        vm.startPrank(user);
        router.swapExactETHForTokens{value: ethAmount}(
            0,
            path,
            user,
            block.timestamp
        );

        uint256 endEthBalance = user.balance;
        uint256 endTokenBalance = IERC20(token).balanceOf(user);

        assertEq(endEthBalance, startEthBalance - ethAmount);
        assertGt(endTokenBalance, startTokenBalance);

        vm.stopPrank();
    }

    function _sellOnUniswap(address user, uint256 tokenAmount, address token) internal {
        IUniswapV2Router02 router = IUniswapV2Router02(uniswapRouter);

        uint256 startEthBalance = user.balance;
        uint256 startTokenBalance = IERC20(token).balanceOf(user);

        vm.startPrank(user);
        IERC20(token).approve(uniswapRouter, tokenAmount);

        address[] memory path = new address[](2);

        path[0] = address(token);
        path[1] = router.WETH();

        router.swapExactTokensForETH(
            tokenAmount,
            0,
            path,
            user,
            block.timestamp
        );

        uint256 endEthBalance = user.balance;
        uint256 endTokenBalance = IERC20(token).balanceOf(user);

        assertGt(endEthBalance, startEthBalance);
        assertEq(endTokenBalance, startTokenBalance - tokenAmount);
  
        vm.stopPrank();
    }

    function _swapExactInputSingle(
        PoolKey memory key,
        uint128 amountIn,
        uint128 minAmountOut
    ) internal returns (uint256 amountOut) {
        // Encode the Universal Router command
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);

        // Encode V4Router actions
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        // Prepare parameters for each action
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: true,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(key.currency0, amountIn);
        params[2] = abi.encode(key.currency1, minAmountOut);

        // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);

        // Execute the swap
        IUniversalRouter(uniswapUniversalRouter).execute{value: amountIn}(commands, inputs, block.timestamp);

        // Verify and return the output amount
        amountOut = IERC20(Currency.unwrap(key.currency1)).balanceOf(address(this));
        require(amountOut >= minAmountOut, "Insufficient output amount");
        return amountOut;
    }
}