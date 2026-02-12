// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TokenDistributorV2} from "../src/TokenDistributorV2.sol";
import {IPancakeSmartRouter, IV3SwapRouter} from "../src/interfaces/IPancakeSmartRouter.sol";
import {IUniversalRouter} from "@uniswap/universal-router/src/interfaces/IUniversalRouter.sol";
import {Commands} from "@uniswap/universal-router/src/libraries/Commands.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {ActionConstants} from "@uniswap/v4-periphery/src/libraries/ActionConstants.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";

interface IWETH {
    function deposit() external payable;
}

/// @notice Fork E2E tests that mimic the *production distributions* of V1 (TokenDistributor).
contract TokenDistributorV2ForkTest is Test {
    // -----------------------------
    // Shared
    // -----------------------------
    address private owner = makeAddr("owner");

    // -----------------------------
    // BSC (Nimpet)
    // -----------------------------
    address private constant BSC_WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address private constant BSC_USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
    address private constant BSC_USDT = 0x55d398326f99059fF775485246999027B3197955;
    address private constant BSC_NIMPET = 0x87aa6aEb62ff128aAA96E275d7B24cd12a72ABa1; // PUBLIC/NIMPET

    address private pancakeSmartRouterBsc =
        vm.envOr("PANCAKE_SMART_ROUTER_BSC", address(0x13f4EA83D0bd40E75C8222255bc855a974568Dd4));

    // -----------------------------
    // Base (Gloria/Eolas/Sproto)
    // -----------------------------
    address private constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address private constant BASE_WETH = 0x4200000000000000000000000000000000000006;
    address private constant BASE_VIRTUALS = 0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b;
    address private constant BASE_GLORIA = 0x3B313f5615Bbd6b200C71f84eC2f677B94DF8674;
    address private constant BASE_EOLAS = 0xF878e27aFB649744EEC3c5c0d03bc9335703CFE3;
    address private constant BASE_SPROTO = 0x2a06A17CBC6d0032Cac2c6696DA90f29D39a1a29;
    address private constant BASE_GECKO = 0x452867Ec20dC5061056C1613db2801f512dDa1C1;
    address private constant BASE_VILADY = 0x0deE1df0F634dF4792E76816b42002fB2a97c432;
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;

    // Hook used by the VILADY Uniswap V4 pool per `script/AddLatestDistributions.s.sol`.
    address private constant VILADY_HOOK = 0x10c1b4C7b1ac62A0F83458F342C3d6B8D2847fff;

    address private baseUniversalRouter = vm.envOr("BASE_UNIVERSAL_ROUTER", address(0));

    // -----------------------------
    // BSC: recreate AddNimpetDistribution.s.sol end-state
    // -----------------------------
    function test_forkBSC_recreateNimpetDistribution_USDC_to_AITV_and_NIMPET() public {
        uint256 forkId = vm.createFork(vm.envString("BSC_RPC_URL"));
        vm.selectFork(forkId);

        address aitvBsc = vm.envOr("AITV_TOKEN_BSC", address(0));
        require(aitvBsc != address(0), "missing env AITV_TOKEN_BSC");

        address user = makeAddr("user-bsc");

        TokenDistributorV2 executor = new TokenDistributorV2(owner);
        vm.prank(owner);
        executor.setAllowlistEnabled(true);
        vm.prank(owner);
        executor.setSwapAllowlist(pancakeSmartRouterBsc, pancakeSmartRouterBsc, true);

        // Fund user with BNB, wrap to WBNB, then swap to USDC using Pancake (v2-style path)
        vm.deal(user, 5 ether);
        uint256 amountWBNB = 0.2 ether;

        vm.startPrank(user);
        IWETH(BSC_WBNB).deposit{value: amountWBNB}();
        IERC20(BSC_WBNB).approve(pancakeSmartRouterBsc, type(uint256).max);
        address[] memory path = new address[](2);
        path[0] = BSC_WBNB;
        path[1] = BSC_USDC;
        uint256 totalAmount = IPancakeSmartRouter(pancakeSmartRouterBsc).swapExactTokensForTokens(amountWBNB, 0, path, user);
        vm.stopPrank();

        // Distribution semantics (per script):
        // - 20%: USDC -> WBNB (fee=100) -> AITV (fee=2500)
        // - 80%: USDC -> USDT (fee=100) -> NIMPET (fee=100)
        uint256 amtAitvIn = (totalAmount * 2_000) / 10_000;
        uint256 amtNimpetIn = totalAmount - amtAitvIn;

        TokenDistributorV2.Plan memory plan = _emptyPlan();
        plan.totalAmount = totalAmount;
        plan.deadline = block.timestamp;
        plan.meta = keccak256("PROD_NIMPET");
        plan.groups = _groups1(user, 1, address(0));

        TokenDistributorV2.Bucket[] memory buckets = new TokenDistributorV2.Bucket[](2);
        buckets[0] = _sendBucket(aitvBsc, 2_000);
        buckets[1] = _sendBucket(BSC_NIMPET, 8_000);
        plan.buckets = buckets;

        plan.swaps = new TokenDistributorV2.SwapStep[](2);
        plan.swaps[0] = _pancakeV3ExactInput_USDC_to_AITV_BSC(executor, amtAitvIn, 1, aitvBsc);
        plan.swaps[1] = _pancakeV3ExactInput_USDC_to_NIMPET_BSC(executor, amtNimpetIn, 1);

        uint256 startAitv = IERC20(aitvBsc).balanceOf(user);
        uint256 startNimpet = IERC20(BSC_NIMPET).balanceOf(user);

        vm.startPrank(user);
        IERC20(BSC_USDC).approve(address(executor), type(uint256).max);
        executor.executePlanERC20(BSC_USDC, totalAmount, plan);
        vm.stopPrank();

        uint256 endAitv = IERC20(aitvBsc).balanceOf(user);
        uint256 endNimpet = IERC20(BSC_NIMPET).balanceOf(user);

        assertGt(endAitv - startAitv, 0, "user should receive some AITV");
        assertGt(endNimpet - startNimpet, 0, "user should receive some NIMPET");
        assertEq(IERC20(aitvBsc).balanceOf(address(executor)), 0, "no leftover AITV");
        assertEq(IERC20(BSC_NIMPET).balanceOf(address(executor)), 0, "no leftover NIMPET");
        assertEq(IERC20(BSC_USDC).balanceOf(address(executor)), 0, "no leftover USDC");
    }

    // -----------------------------
    // Base: recreate AddGloriaAndOtherDistributions.s.sol end-state
    // -----------------------------
    function test_forkBase_recreateGloriaEolasSprotoDistributions_WETH_to_AITV_and_token() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        address aitvBase = vm.envOr("AITV_TOKEN_BASE", address(0));
        require(aitvBase != address(0), "missing env AITV_TOKEN_BASE");
        require(baseUniversalRouter != address(0), "missing env BASE_UNIVERSAL_ROUTER");

        address user = makeAddr("user-base");
        vm.deal(user, 5 ether);

        TokenDistributorV2 executor = new TokenDistributorV2(owner);
        vm.prank(owner);
        executor.setAllowlistEnabled(true);

        UniversalRouterSwapper swapper = new UniversalRouterSwapper(IUniversalRouter(baseUniversalRouter));
        vm.prank(owner);
        executor.setSwapAllowlist(address(swapper), address(swapper), true);

        // Run the three production distributions with the same 20/80 split:
        // - GLORIA distribution: 20% AITV, 80% GLORIA (via VIRTUALS in prod)
        // - EOLAS distribution: 20% AITV, 80% EOLAS
        // - SPROTO distribution: 20% AITV, 80% SPROTO
        _executeBaseSplitPlan_WETH(executor, swapper, user, aitvBase, BASE_GLORIA, keccak256("PROD_GLORIA"));
        _executeBaseSplitPlan_WETH(executor, swapper, user, aitvBase, BASE_EOLAS, keccak256("PROD_EOLAS"));
        _executeBaseSplitPlan_WETH(executor, swapper, user, aitvBase, BASE_SPROTO, keccak256("PROD_SPROTO"));
    }

    function test_forkBase_recreateGeckoDistribution_WETH_to_AITV_and_GECKO_with_burnSplit() public {
        // Mirrors `deployGeckoDistribution()` in `script/AddLatestDistributions.s.sol`:
        // - Parent: 20% AITV, 80% WETH -> GECKO
        // - Child: GECKO sent 90% to beneficiary, 10% to DEAD
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        address aitvBase = vm.envOr("AITV_TOKEN_BASE", address(0));
        require(aitvBase != address(0), "missing env AITV_TOKEN_BASE");
        require(baseUniversalRouter != address(0), "missing env BASE_UNIVERSAL_ROUTER");

        address user = makeAddr("user-base-gecko");
        vm.deal(user, 5 ether);

        TokenDistributorV2 executor = new TokenDistributorV2(owner);
        vm.prank(owner);
        executor.setAllowlistEnabled(true);
        UniversalRouterSwapper swapper = new UniversalRouterSwapper(IUniversalRouter(baseUniversalRouter));
        vm.prank(owner);
        executor.setSwapAllowlist(address(swapper), address(swapper), true);

        uint256 totalAmount = 0.2 ether;
        uint256 amtAitvIn = (totalAmount * 2_000) / 10_000;
        uint256 amtGeckoIn = totalAmount - amtAitvIn;

        TokenDistributorV2.Plan memory plan = _emptyPlan();
        plan.totalAmount = totalAmount;
        plan.deadline = block.timestamp;
        plan.meta = keccak256("PROD_GECKO");

        // groups[0] => AITV recipient (user)
        // groups[1] => GECKO recipients (user 90%, burn 10%)
        TokenDistributorV2.BeneficiaryGroup[] memory groups = new TokenDistributorV2.BeneficiaryGroup[](2);
        {
            TokenDistributorV2.Beneficiary[] memory aitvBens = new TokenDistributorV2.Beneficiary[](1);
            aitvBens[0] = TokenDistributorV2.Beneficiary({beneficiary: user, weight: 1, recipientOnFailure: address(0)});
            groups[0] = TokenDistributorV2.BeneficiaryGroup({beneficiaries: aitvBens});

            TokenDistributorV2.Beneficiary[] memory geckoBens = new TokenDistributorV2.Beneficiary[](2);
            geckoBens[0] = TokenDistributorV2.Beneficiary({beneficiary: user, weight: 9000, recipientOnFailure: address(0)});
            geckoBens[1] = TokenDistributorV2.Beneficiary({beneficiary: DEAD, weight: 1000, recipientOnFailure: address(0)});
            groups[1] = TokenDistributorV2.BeneficiaryGroup({beneficiaries: geckoBens});
        }
        plan.groups = groups;

        TokenDistributorV2.Bucket[] memory buckets = new TokenDistributorV2.Bucket[](2);
        buckets[0] = TokenDistributorV2.Bucket({
            sourceToken: aitvBase,
            actionType: TokenDistributorV2.ActionType.Send,
            callTarget: address(0),
            selector: bytes4(0),
            callArgsPacked: bytes12(0),
            bucketBps: 2_000,
            groupId: 0
        });
        buckets[1] = TokenDistributorV2.Bucket({
            sourceToken: BASE_GECKO,
            actionType: TokenDistributorV2.ActionType.Send,
            callTarget: address(0),
            selector: bytes4(0),
            callArgsPacked: bytes12(0),
            bucketBps: 8_000,
            groupId: 1
        });
        plan.buckets = buckets;

        plan.swaps = new TokenDistributorV2.SwapStep[](2);
        plan.swaps[0] = _uniRouterSwapV3ExactInFromWETH(
            executor,
            swapper,
            amtAitvIn,
            1,
            aitvBase,
            _encodeV3Path(_addrPath3(BASE_WETH, BASE_USDC, aitvBase), _feePath2(500, 3000))
        );
        plan.swaps[1] = _uniRouterSwapV2ExactInFromWETH(
            executor,
            swapper,
            amtGeckoIn,
            1,
            BASE_GECKO,
            _addrPath2(BASE_WETH, BASE_GECKO)
        );

        uint256 startAitv = IERC20(aitvBase).balanceOf(user);
        uint256 startGeckoUser = IERC20(BASE_GECKO).balanceOf(user);
        uint256 startGeckoBurn = IERC20(BASE_GECKO).balanceOf(DEAD);

        vm.startPrank(user);
        IWETH(BASE_WETH).deposit{value: totalAmount}();
        IERC20(BASE_WETH).approve(address(executor), type(uint256).max);
        executor.executePlanERC20(BASE_WETH, totalAmount, plan);
        vm.stopPrank();

        uint256 endAitv = IERC20(aitvBase).balanceOf(user);
        uint256 endGeckoUser = IERC20(BASE_GECKO).balanceOf(user);
        uint256 endGeckoBurn = IERC20(BASE_GECKO).balanceOf(DEAD);

        assertGt(endAitv - startAitv, 0, "user should receive some AITV");
        assertGt(endGeckoUser - startGeckoUser, 0, "user should receive some GECKO");
        assertGt(endGeckoBurn - startGeckoBurn, 0, "DEAD should receive some GECKO");
        assertEq(IERC20(aitvBase).balanceOf(address(executor)), 0, "no leftover AITV");
        assertEq(IERC20(BASE_GECKO).balanceOf(address(executor)), 0, "no leftover GECKO");
        assertEq(IERC20(BASE_WETH).balanceOf(address(executor)), 0, "no leftover WETH");
    }

    function test_forkBase_recreateViladyDistribution_WETH_to_AITV_and_VILADY() public {
        // Mirrors `deployViladyDistribution()` in `script/AddLatestDistributions.s.sol`:
        // - Parent: 20% AITV, 80% WETH -> (unwrap to ETH) -> VILADY via Uniswap V4 pool
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        address aitvBase = vm.envOr("AITV_TOKEN_BASE", address(0));
        require(aitvBase != address(0), "missing env AITV_TOKEN_BASE");
        require(baseUniversalRouter != address(0), "missing env BASE_UNIVERSAL_ROUTER");

        address user = makeAddr("user-base-vilady");
        vm.deal(user, 5 ether);

        TokenDistributorV2 executor = new TokenDistributorV2(owner);
        vm.prank(owner);
        executor.setAllowlistEnabled(true);
        UniversalRouterSwapper swapper = new UniversalRouterSwapper(IUniversalRouter(baseUniversalRouter));
        vm.prank(owner);
        executor.setSwapAllowlist(address(swapper), address(swapper), true);

        uint256 totalAmount = 0.2 ether;
        uint256 amtAitvIn = (totalAmount * 2_000) / 10_000;
        uint256 amtViladyIn = totalAmount - amtAitvIn;

        TokenDistributorV2.Plan memory plan = _emptyPlan();
        plan.totalAmount = totalAmount;
        plan.deadline = block.timestamp;
        plan.meta = keccak256("PROD_VILADY");
        plan.groups = _groups1(user, 1, address(0));

        TokenDistributorV2.Bucket[] memory buckets = new TokenDistributorV2.Bucket[](2);
        buckets[0] = _sendBucket(aitvBase, 2_000);
        buckets[1] = _sendBucket(BASE_VILADY, 8_000);
        plan.buckets = buckets;

        plan.swaps = new TokenDistributorV2.SwapStep[](2);
        plan.swaps[0] = _uniRouterSwapV3ExactInFromWETH(
            executor,
            swapper,
            amtAitvIn,
            1,
            aitvBase,
            _encodeV3Path(_addrPath3(BASE_WETH, BASE_USDC, aitvBase), _feePath2(500, 3000))
        );
        plan.swaps[1] = _uniRouterSwapV4ViladyFromWETH(executor, swapper, amtViladyIn, 1);

        uint256 startAitv = IERC20(aitvBase).balanceOf(user);
        uint256 startVilady = IERC20(BASE_VILADY).balanceOf(user);

        vm.startPrank(user);
        IWETH(BASE_WETH).deposit{value: totalAmount}();
        IERC20(BASE_WETH).approve(address(executor), type(uint256).max);
        executor.executePlanERC20(BASE_WETH, totalAmount, plan);
        vm.stopPrank();

        uint256 endAitv = IERC20(aitvBase).balanceOf(user);
        uint256 endVilady = IERC20(BASE_VILADY).balanceOf(user);

        assertGt(endAitv - startAitv, 0, "user should receive some AITV");
        assertGt(endVilady - startVilady, 0, "user should receive some VILADY");
        assertEq(IERC20(aitvBase).balanceOf(address(executor)), 0, "no leftover AITV");
        assertEq(IERC20(BASE_VILADY).balanceOf(address(executor)), 0, "no leftover VILADY");
        assertEq(IERC20(BASE_WETH).balanceOf(address(executor)), 0, "no leftover WETH");
    }

    // -----------------------------
    // Base helpers
    // -----------------------------
    function _executeBaseSplitPlan_WETH(
        TokenDistributorV2 executor,
        UniversalRouterSwapper swapper,
        address user,
        address aitvBase,
        address outToken,
        bytes32 meta
    ) internal {
        uint256 totalAmount = 0.2 ether;
        uint256 amtAitvIn = (totalAmount * 2_000) / 10_000;
        uint256 amtOutIn = totalAmount - amtAitvIn;

        TokenDistributorV2.Plan memory plan = _emptyPlan();
        plan.totalAmount = totalAmount;
        plan.deadline = block.timestamp;
        plan.meta = meta;
        plan.groups = _groups1(user, 1, address(0));

        TokenDistributorV2.Bucket[] memory buckets = new TokenDistributorV2.Bucket[](2);
        buckets[0] = _sendBucket(aitvBase, 2_000);
        buckets[1] = _sendBucket(outToken, 8_000);
        plan.buckets = buckets;

        // Swaps are executed by the Universal Router, pre-funded with WETH via the `swapper`.
        plan.swaps = new TokenDistributorV2.SwapStep[](2);
        plan.swaps[0] = _uniRouterSwapV3ExactInFromWETH(
            executor,
            swapper,
            amtAitvIn,
            1,
            aitvBase,
            _encodeV3Path(_addrPath3(BASE_WETH, BASE_USDC, aitvBase), _feePath2(500, 3000))
        );

        if (outToken == BASE_SPROTO) {
            plan.swaps[1] = _uniRouterSwapV3ExactInFromWETH(
                executor,
                swapper,
                amtOutIn,
                1,
                outToken,
                _encodeV3Path(_addrPath3(BASE_WETH, BASE_USDC, outToken), _feePath2(500, 10_000))
            );
        } else if (outToken == BASE_EOLAS) {
            plan.swaps[1] = _uniRouterSwapV2ExactInFromWETH(
                executor, swapper, amtOutIn, 1, outToken, _addrPath2(BASE_WETH, outToken)
            );
        } else if (outToken == BASE_GLORIA) {
            plan.swaps[1] = _uniRouterSwapV2ExactInFromWETH(
                executor, swapper, amtOutIn, 1, outToken, _addrPath3(BASE_WETH, BASE_VIRTUALS, outToken)
            );
        } else {
            revert("unsupported outToken");
        }

        uint256 startAitv = IERC20(aitvBase).balanceOf(user);
        uint256 startOut = IERC20(outToken).balanceOf(user);

        vm.startPrank(user);
        IWETH(BASE_WETH).deposit{value: totalAmount}();
        IERC20(BASE_WETH).approve(address(executor), type(uint256).max);
        executor.executePlanERC20(BASE_WETH, totalAmount, plan);
        vm.stopPrank();

        uint256 endAitv = IERC20(aitvBase).balanceOf(user);
        uint256 endOut = IERC20(outToken).balanceOf(user);

        assertGt(endAitv - startAitv, 0, "user should receive some AITV");
        assertGt(endOut - startOut, 0, "user should receive some outToken");
        assertEq(IERC20(aitvBase).balanceOf(address(executor)), 0, "no leftover AITV");
        assertEq(IERC20(outToken).balanceOf(address(executor)), 0, "no leftover outToken");
        assertEq(IERC20(BASE_WETH).balanceOf(address(executor)), 0, "no leftover WETH");
    }

    function _uniRouterSwapV3ExactInFromWETH(
        TokenDistributorV2 executor,
        UniversalRouterSwapper swapper,
        uint256 amountIn,
        uint256 minOut,
        address tokenOut,
        bytes memory v3Path
    ) internal pure returns (TokenDistributorV2.SwapStep memory s) {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.V3_SWAP_EXACT_IN)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(executor), amountIn, minOut, v3Path, false /* payerIsUser */);

        bytes memory callData = abi.encodeCall(UniversalRouterSwapper.swap, (commands, inputs, BASE_WETH, amountIn));

        s = TokenDistributorV2.SwapStep({
            tokenIn: BASE_WETH,
            tokenOut: tokenOut,
            amountIn: amountIn,
            minOut: minOut,
            allowanceTarget: address(swapper),
            swapTarget: address(swapper),
            value: 0,
            callData: callData
        });
    }

    function _uniRouterSwapV2ExactInFromWETH(
        TokenDistributorV2 executor,
        UniversalRouterSwapper swapper,
        uint256 amountIn,
        uint256 minOut,
        address tokenOut,
        address[] memory v2Path
    ) internal pure returns (TokenDistributorV2.SwapStep memory s) {
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.V2_SWAP_EXACT_IN)));
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(address(executor), amountIn, minOut, v2Path, false /* payerIsUser */);

        bytes memory callData = abi.encodeCall(UniversalRouterSwapper.swap, (commands, inputs, BASE_WETH, amountIn));

        s = TokenDistributorV2.SwapStep({
            tokenIn: BASE_WETH,
            tokenOut: tokenOut,
            amountIn: amountIn,
            minOut: minOut,
            allowanceTarget: address(swapper),
            swapTarget: address(swapper),
            value: 0,
            callData: callData
        });
    }

    function _addrPath2(address a, address b) internal pure returns (address[] memory p) {
        p = new address[](2);
        p[0] = a;
        p[1] = b;
    }

    function _addrPath3(address a, address b, address c) internal pure returns (address[] memory p) {
        p = new address[](3);
        p[0] = a;
        p[1] = b;
        p[2] = c;
    }

    function _feePath2(uint24 f0, uint24 f1) internal pure returns (uint24[] memory f) {
        f = new uint24[](2);
        f[0] = f0;
        f[1] = f1;
    }

    function _uniRouterSwapV4ViladyFromWETH(
        TokenDistributorV2 executor,
        UniversalRouterSwapper swapper,
        uint256 amountInWETH,
        uint256 minOut
    ) internal pure returns (TokenDistributorV2.SwapStep memory s) {
        // Commands: unwrap router's WETH into ETH, then run a V4 swap with payer=router (payerIsUser=false).
        bytes memory commands = abi.encodePacked(bytes1(uint8(Commands.UNWRAP_WETH)), bytes1(uint8(Commands.V4_SWAP)));
        bytes[] memory inputs = new bytes[](2);

        // UNWRAP_WETH: keep ETH inside the router (recipient = ADDRESS_THIS).
        inputs[0] = abi.encode(ActionConstants.ADDRESS_THIS, 0);

        // V4 swap ETH -> VILADY, then settle from router and take output to the executor.
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(BASE_VILADY),
            fee: 0,
            tickSpacing: 200,
            hooks: IHooks(VILADY_HOOK)
        });

        bytes memory swapExactSingleParams = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: key,
                zeroForOne: true, // ETH (currency0) -> VILADY (currency1)
                amountIn: uint128(amountInWETH),
                amountOutMinimum: uint128(minOut),
                hookData: bytes("")
            })
        );

        bytes memory actions = abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE), uint8(Actions.TAKE));

        bytes[] memory params = new bytes[](3);
        params[0] = swapExactSingleParams;
        // SETTLE: settle full debt in ETH from the router (payerIsUser=false => payer=address(this) == router)
        params[1] = abi.encode(Currency.wrap(address(0)), uint256(ActionConstants.OPEN_DELTA), false);
        // TAKE: take full credit in VILADY to the executor
        params[2] = abi.encode(Currency.wrap(BASE_VILADY), address(executor), uint256(ActionConstants.OPEN_DELTA));

        inputs[1] = abi.encode(actions, params);

        bytes memory callData = abi.encodeCall(UniversalRouterSwapper.swap, (commands, inputs, BASE_WETH, amountInWETH));

        s = TokenDistributorV2.SwapStep({
            tokenIn: BASE_WETH,
            tokenOut: BASE_VILADY,
            amountIn: amountInWETH,
            minOut: minOut,
            allowanceTarget: address(swapper),
            swapTarget: address(swapper),
            value: 0,
            callData: callData
        });
    }

    // -----------------------------
    // Pancake (BSC) helpers
    // -----------------------------
    function _pancakeV3ExactInput_USDC_to_AITV_BSC(
        TokenDistributorV2 executor,
        uint256 amountIn,
        uint256 minOut,
        address aitvBsc
    ) internal view returns (TokenDistributorV2.SwapStep memory s) {
        // Script config:
        // - USDC <-> WBNB fee=100
        // - WBNB <-> AITV fee=2500
        address[] memory tokens = new address[](3);
        tokens[0] = BSC_USDC;
        tokens[1] = BSC_WBNB;
        tokens[2] = aitvBsc;

        uint24[] memory fees = new uint24[](2);
        fees[0] = 100;
        fees[1] = 2500;

        bytes memory path = _encodeV3Path(tokens, fees);

        IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter.ExactInputParams({
            path: path,
            recipient: address(executor),
            amountIn: amountIn,
            amountOutMinimum: minOut
        });

        bytes memory callData = abi.encodeCall(IPancakeSmartRouter.exactInput, (params));

        s = TokenDistributorV2.SwapStep({
            tokenIn: BSC_USDC,
            tokenOut: aitvBsc,
            amountIn: amountIn,
            minOut: minOut,
            allowanceTarget: pancakeSmartRouterBsc,
            swapTarget: pancakeSmartRouterBsc,
            value: 0,
            callData: callData
        });
    }

    function _pancakeV3ExactInput_USDC_to_NIMPET_BSC(
        TokenDistributorV2 executor,
        uint256 amountIn,
        uint256 minOut
    ) internal view returns (TokenDistributorV2.SwapStep memory s) {
        address[] memory tokens = new address[](3);
        tokens[0] = BSC_USDC;
        tokens[1] = BSC_USDT;
        tokens[2] = BSC_NIMPET;

        uint24[] memory fees = new uint24[](2);
        fees[0] = 100;
        fees[1] = 100;

        bytes memory path = _encodeV3Path(tokens, fees);

        IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter.ExactInputParams({
            path: path,
            recipient: address(executor),
            amountIn: amountIn,
            amountOutMinimum: minOut
        });

        bytes memory callData = abi.encodeCall(IPancakeSmartRouter.exactInput, (params));

        s = TokenDistributorV2.SwapStep({
            tokenIn: BSC_USDC,
            tokenOut: BSC_NIMPET,
            amountIn: amountIn,
            minOut: minOut,
            allowanceTarget: pancakeSmartRouterBsc,
            swapTarget: pancakeSmartRouterBsc,
            value: 0,
            callData: callData
        });
    }

    function _pancakeV3ExactInputSingle_BSC(
        TokenDistributorV2 executor,
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint256 minOut
    ) internal view returns (TokenDistributorV2.SwapStep memory s) {
        IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: address(executor),
            amountIn: amountIn,
            amountOutMinimum: minOut,
            sqrtPriceLimitX96: 0
        });

        bytes memory callData = abi.encodeCall(IPancakeSmartRouter.exactInputSingle, (params));

        s = TokenDistributorV2.SwapStep({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            minOut: minOut,
            allowanceTarget: pancakeSmartRouterBsc,
            swapTarget: pancakeSmartRouterBsc,
            value: 0,
            callData: callData
        });
    }

    function _encodeV3Path(address[] memory tokens, uint24[] memory fees) internal pure returns (bytes memory path) {
        require(tokens.length >= 2, "path tokens too short");
        require(tokens.length == fees.length + 1, "path length mismatch");
        path = abi.encodePacked(tokens[0]);
        for (uint256 i = 0; i < fees.length; ++i) {
            path = bytes.concat(path, abi.encodePacked(fees[i]), abi.encodePacked(tokens[i + 1]));
        }
    }

    // -----------------------------
    // Common plan helpers
    // -----------------------------
    function _emptyPlan() internal pure returns (TokenDistributorV2.Plan memory plan) {
        plan.totalAmount = 0;
        plan.deadline = 0;
        plan.meta = bytes32(0);
        plan.groups = new TokenDistributorV2.BeneficiaryGroup[](0);
        plan.swaps = new TokenDistributorV2.SwapStep[](0);
        plan.buckets = new TokenDistributorV2.Bucket[](0);
    }

    function _groups1(address b, uint128 w, address fb) internal pure returns (TokenDistributorV2.BeneficiaryGroup[] memory groups) {
        TokenDistributorV2.Beneficiary[] memory bens = new TokenDistributorV2.Beneficiary[](1);
        bens[0] = TokenDistributorV2.Beneficiary({beneficiary: b, weight: w, recipientOnFailure: fb});
        groups = new TokenDistributorV2.BeneficiaryGroup[](1);
        groups[0] = TokenDistributorV2.BeneficiaryGroup({beneficiaries: bens});
    }

    function _sendBucket(address token, uint16 bps) internal pure returns (TokenDistributorV2.Bucket memory) {
        return TokenDistributorV2.Bucket({
            sourceToken: token,
            actionType: TokenDistributorV2.ActionType.Send,
            callTarget: address(0),
            selector: bytes4(0),
            callArgsPacked: bytes12(0),
            bucketBps: bps,
            groupId: 0
        });
    }
}

/// @dev Adapter to use Uniswap Universal Router without Permit2 by pre-funding the router with `tokenIn`.
contract UniversalRouterSwapper {
    IUniversalRouter internal immutable router;

    constructor(IUniversalRouter _router) {
        router = _router;
    }

    function swap(bytes calldata commands, bytes[] calldata inputs, address tokenIn, uint256 amountIn) external {
        if (amountIn != 0) {
            // Pull tokenIn from TokenDistributorV2 (msg.sender) and pre-fund the router. The router will then pay
            // from its own balance when payerIsUser=false in the swap command inputs.
            (bool ok, bytes memory data) =
                tokenIn.call(abi.encodeWithSelector(IERC20.transferFrom.selector, msg.sender, address(router), amountIn));
            require(ok && (data.length == 0 || abi.decode(data, (bool))), "transferFrom tokenIn failed");
        }
        router.execute(commands, inputs, block.timestamp);
    }
}

