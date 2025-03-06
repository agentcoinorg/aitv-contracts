// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockERC20} from "forge-std/mocks/MockERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {BalanceDelta} from '@uniswap/v4-core/src/types/BalanceDelta.sol';
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from '@uniswap/v4-core/src/types/BeforeSwapDelta.sol';
import {Currency} from '@uniswap/v4-core/src/types/Currency.sol';
import {Hooks, IHooks} from '@uniswap/v4-core/src/libraries/Hooks.sol';
import {IPoolManager} from '@uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {PoolId, PoolIdLibrary} from '@uniswap/v4-core/src/types/PoolId.sol';
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';
import {SafeCast} from '@uniswap/v4-core/src/libraries/SafeCast.sol';
import {StateLibrary} from '@uniswap/v4-core/src/libraries/StateLibrary.sol';
import {IPositionManager} from '@uniswap/v4-periphery/src/interfaces/IPositionManager.sol';
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";
import {Commands } from "@uniswap/universal-router/src/libraries/Commands.sol";
import {IV4Router } from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions } from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IPermit2 } from "permit2/src/interfaces/IPermit2.sol";
import {IUniversalRouter } from "@uniswap/universal-router/src/interfaces/IUniversalRouter.sol";
import {ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {AgentToken} from "../src/AgentToken.sol";
import {AgentStaking} from "../src/AgentStaking.sol";
import {AirdropClaim} from "../src/AirdropClaim.sol";
import {AgentLaunchPool} from "../src/AgentLaunchPool.sol";
import {IAgentLaunchPool} from "../src/IAgentLaunchPool.sol";
import {AgentFactory} from "../src/AgentFactory.sol";
import {AgentFactoryDeployer} from "./AgentFactoryDeployer.sol";
import {FeeInfo} from "../src/types/FeeInfo.sol";

contract AgentFactoryTest is Test, AgentFactoryDeployer {
    address owner = makeAddr("owner");
    address uniswapPoolManager;
    address uniswapPositionManager;
    address agentWallet = makeAddr("agentWallet");
    address uniswapUniversalRouter;
    address dao = makeAddr("dao");
    AgentFactory factory;
    address agentTokenImplementation;
    address agentStakingImplementation;

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));
        uniswapPoolManager = vm.envAddress("BASE_POOL_MANAGER");
        uniswapPositionManager = vm.envAddress("BASE_POSITION_MANAGER");
        uniswapUniversalRouter = vm.envAddress("BASE_UNIVERSAL_ROUTER");

        factory = _deployAgentFactory(owner, uniswapPoolManager, uniswapPositionManager);

        agentTokenImplementation = address(new AgentToken());
        agentStakingImplementation = address(new AgentStaking());
    }

    function test_factory() public {
        address collateral = address(0);

        IAgentLaunchPool.TokenInfo memory tokenInfo = IAgentLaunchPool.TokenInfo({
            owner: owner,
            name: "Agent Token",
            symbol: "AGENT",
            totalSupply: 10_000_000 * 1e18,
            tokenImplementation: agentTokenImplementation,
            stakingImplementation: agentStakingImplementation
        });
        IAgentLaunchPool.LaunchPoolInfo memory launchPoolInfo = IAgentLaunchPool.LaunchPoolInfo({
            collateral: collateral,
            timeWindow: 7 days,
            minAmountForLaunch: 1 ether,
            maxAmountForLaunch: 10 ether
        });

        address[] memory recipients = new address[](2);
        recipients[0] = dao;
        recipients[1] = agentWallet;
        uint256[] memory basisAmounts = new uint256[](2);
        basisAmounts[0] = 500;
        basisAmounts[1] = 500;

        uint256 launchPoolBasisAmount = 7500;
        uint256 uniswapPoolBasisAmount = 1500;

        IAgentLaunchPool.DistributionInfo memory distributionInfo = IAgentLaunchPool.DistributionInfo({
            recipients: recipients,
            basisAmounts: basisAmounts,
            launchPoolBasisAmount: launchPoolBasisAmount,
            uniswapPoolBasisAmount: uniswapPoolBasisAmount
        });

        address[] memory feeRecipients = new address[](2);
        feeRecipients[0] = dao;
        feeRecipients[1] = agentWallet;

        uint256[] memory feeBasisAmounts = new uint256[](2);
        feeBasisAmounts[0] = 50;
        feeBasisAmounts[1] = 50;

        FeeInfo memory feeInfo = FeeInfo({
            collateral: collateral,
            burnBasisAmount: 100,
            recipients: feeRecipients,
            basisAmounts: feeBasisAmounts
        });

        vm.prank(owner);
        address launchPoolImplementation = address(new AgentLaunchPool());

        address pool = factory.deploy(tokenInfo, launchPoolInfo, distributionInfo, feeInfo, launchPoolImplementation); 
    }

    function swapExactInputSingle(
        PoolKey memory key,
        uint128 amountIn,
        uint128 minAmountOut
    ) public payable returns (uint256 amountOut) {
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

contract MockedERC20 is MockERC20 {
    constructor() {
        initialize("MockedERC20", "MERC", 18);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}