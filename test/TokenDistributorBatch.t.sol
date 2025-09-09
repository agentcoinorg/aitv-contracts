// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IHooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {UniswapVersion} from "../src/types/UniswapVersion.sol";
import {PoolConfig} from "../src/types/PoolConfig.sol";
import {TokenDistributor, DistributionRequest, CallArgType} from "../src/TokenDistributor.sol";
import {DistributionBuilder} from "../src/DistributionBuilder.sol";

import {TokenDistributorTest, MockEscrow} from "./TokenDistributor.t.sol";
import {MockedERC20} from "./helpers/MockedERC20.sol";
import {Vm} from "forge-std/Vm.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
}

contract TokenDistributorBatchTest is TokenDistributorTest {
    function test_batchDistributeETH_splitProportional() public {
        address b1 = makeAddr("b1");
        address b2 = makeAddr("b2");
        address b3 = makeAddr("b3");

        vm.startPrank(owner);
        uint256 distId = distributor.addDistribution(
            new DistributionBuilder().send(10000, address(0)).build()
        );
        distributor.setDistributionId("batch-eth-split", distId);
        vm.stopPrank();

        address user = makeAddr("user");
        vm.deal(user, 10 ether);

        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = b1;
        beneficiaries[1] = b2;
        beneficiaries[2] = b3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 0.1 ether;
        amounts[1] = 0.2 ether;
        amounts[2] = 0.3 ether;

        address[] memory fallbacks = new address[](3);
        fallbacks[0] = address(0);
        fallbacks[1] = address(0);
        fallbacks[2] = address(0);

        DistributionRequest[] memory requests = _buildRequests(beneficiaries, amounts, fallbacks);

        vm.prank(user);
        distributor.batchDistributeETH{value: _sum(amounts)}(
            "batch-eth-split",
            requests,
            _buildMockMinAmountsOut(1),
            block.timestamp,
            keccak256("BATCH")
        );

        assertEq(b1.balance, 0.1 ether);
        assertEq(b2.balance, 0.2 ether);
        assertEq(b3.balance, 0.3 ether);
        assertEq(address(distributor).balance, 0);
    }

    function test_batchDistributeETH_dustHandling_lastGetsRemainder() public {
        address r1 = makeAddr("r1");
        address r2 = makeAddr("r2");
        address r3 = makeAddr("r3");
        address sink = makeAddr("sink");

        vm.startPrank(owner);
        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .send(3333, address(0))
                .send(6667, sink)
                .build()
        );
        distributor.setDistributionId("batch-eth-dust", distId);
        vm.stopPrank();

        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = r1;
        beneficiaries[1] = r2;
        beneficiaries[2] = r3;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 50;
        amounts[1] = 50;
        amounts[2] = 1; // total = 101 wei

        address[] memory fallbacks = new address[](3);
        DistributionRequest[] memory requests = _buildRequests(beneficiaries, amounts, fallbacks);

        // actionTotal = floor(101 * 3333 / 10000) = 33
        uint256 actionTotal = (uint256(101) * 3333) / 10000;
        uint256 share1 = (actionTotal * amounts[0]) / 101; // 16
        uint256 share2 = (actionTotal * amounts[1]) / 101; // 16
        uint256 share3 = actionTotal - share1 - share2;    // 1 (remainder goes to last)

        vm.prank(user);
        distributor.batchDistributeETH{value: 101}(
            "batch-eth-dust",
            requests,
            _buildMockMinAmountsOut(1),
            block.timestamp,
            keccak256("DUST")
        );

        assertEq(r1.balance, share1);
        assertEq(r2.balance, share2);
        assertEq(r3.balance, share3);
        assertEq(address(distributor).balance, 0);
    }

    function test_batchDistributeETH_crossActionRemainder_lastActionGetsRemainder() public {
        address sink1 = makeAddr("sink1");
        address sink2 = makeAddr("sink2");

        vm.startPrank(owner);
        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .send(3333, sink1) // ~33.33%
                .send(6667, sink2) // ~66.67%
                .build()
        );
        distributor.setDistributionId("batch-eth-cross-action-dust", distId);
        vm.stopPrank();

        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        // Single request to avoid recipient-level dust. Total = 101 wei
        address[] memory beneficiaries = new address[](1);
        beneficiaries[0] = makeAddr("b");
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 101;
        address[] memory fallbacks = new address[](1);

        DistributionRequest[] memory requests = _buildRequests(beneficiaries, amounts, fallbacks);

        // First action gets floor(101 * 3333 / 10000) = 33
        uint256 firstAction = (uint256(101) * 3333) / 10000;
        // Last action receives the remainder
        uint256 secondAction = 101 - firstAction; // 68

        vm.prank(user);
        distributor.batchDistributeETH{value: 101}(
            "batch-eth-cross-action-dust",
            requests,
            _buildMockMinAmountsOut(1),
            block.timestamp,
            keccak256("XACT_DUST")
        );

        assertEq(sink1.balance, firstAction);
        assertEq(sink2.balance, secondAction);
        assertEq(address(distributor).balance, 0);
    }

    function test_batchDistributeETH_emptyRequestsReverts() public {
        vm.expectPartialRevert(TokenDistributor.BatchIsEmpty.selector);
        DistributionRequest[] memory empty;
        distributor.batchDistributeETH{value: 0}(
            "unused",
            empty,
            _buildMockMinAmountsOut(1),
            block.timestamp,
            0x0
        );
    }

    function test_batchDistributeETH_totalMismatchLessAndMore() public {
        address b1 = makeAddr("b1");
        address b2 = makeAddr("b2");

        vm.startPrank(owner);
        uint256 distId = distributor.addDistribution(
            new DistributionBuilder().send(10000, address(0)).build()
        );
        distributor.setDistributionId("batch-eth-mismatch", distId);
        vm.stopPrank();

        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = b1;
        beneficiaries[1] = b2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1 ether;
        amounts[1] = 1 ether;
        address[] memory fallbacks = new address[](2);
        DistributionRequest[] memory requests = _buildRequests(beneficiaries, amounts, fallbacks);

        // Less than total
        vm.expectPartialRevert(TokenDistributor.BatchTotalMismatch.selector);
        distributor.batchDistributeETH{value: 1 ether}(
            "batch-eth-mismatch",
            requests,
            _buildMockMinAmountsOut(1),
            block.timestamp,
            0x0
        );

        // Greater than total
        vm.expectPartialRevert(TokenDistributor.BatchTotalMismatch.selector);
        distributor.batchDistributeETH{value: 3 ether}(
            "batch-eth-mismatch",
            requests,
            _buildMockMinAmountsOut(1),
            block.timestamp,
            0x0
        );
    }

    function test_batchDistributeETH_deadlinePassedReverts() public {
        address b1 = makeAddr("b1");
        address b2 = makeAddr("b2");

        vm.startPrank(owner);
        uint256 distId = distributor.addDistribution(
            new DistributionBuilder().send(10000, address(0)).build()
        );
        distributor.setDistributionId("batch-eth-deadline", distId);
        vm.stopPrank();

        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = b1;
        beneficiaries[1] = b2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.1 ether;
        amounts[1] = 0.2 ether;
        address[] memory fallbacks = new address[](2);
        DistributionRequest[] memory requests = _buildRequests(beneficiaries, amounts, fallbacks);

        vm.expectPartialRevert(TokenDistributor.DeadlinePassed.selector);
        distributor.batchDistributeETH{value: _sum(amounts)}(
            "batch-eth-deadline",
            requests,
            _buildMockMinAmountsOut(1),
            block.timestamp - 1,
            0x0
        );
    }

    function test_batchDistributeETH_WETHConversion_distributesProportionally() public {
        address b1 = makeAddr("b1");
        address b2 = makeAddr("b2");

        vm.startPrank(owner);
        uint256 distId = distributor.addDistribution(
            new DistributionBuilder().buy(10000, weth, address(0)).build()
        );
        distributor.setDistributionId("batch-eth-weth", distId);
        vm.stopPrank();

        address user = makeAddr("user");
        vm.deal(user, 10 ether);

        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = b1;
        beneficiaries[1] = b2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.1 ether;
        amounts[1] = 0.3 ether;
        address[] memory fallbacks = new address[](2);

        DistributionRequest[] memory requests = _buildRequests(beneficiaries, amounts, fallbacks);

        vm.prank(user);
        distributor.batchDistributeETH{value: _sum(amounts)}(
            "batch-eth-weth",
            requests,
            _buildMockMinAmountsOut(0),
            block.timestamp,
            0x0
        );

        assertEq(IERC20(weth).balanceOf(b1), amounts[0]);
        assertEq(IERC20(weth).balanceOf(b2), amounts[1]);
        assertEq(IERC20(weth).balanceOf(address(distributor)), 0);
        assertEq(address(distributor).balance, 0);
    }

    function test_batchDistributeETH_sendAndCall_depositETHForMultipleBeneficiaries() public {
        MockEscrow escrow = new MockEscrow();

        vm.startPrank(owner);
        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .sendAndCall(10000, address(escrow), bytes4(keccak256("depositETHFor(address)")), _encodeCallArgs(CallArgType.Beneficiary))
                .build()
        );
        distributor.setDistributionId("batch-eth-sendcall-for", distId);
        vm.stopPrank();

        address b1 = makeAddr("b1");
        address b2 = makeAddr("b2");
        address b3 = makeAddr("b3");
        address user = makeAddr("user");
        vm.deal(user, 10 ether);

        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = b1;
        beneficiaries[1] = b2;
        beneficiaries[2] = b3;
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 0.1 ether;
        amounts[1] = 0.2 ether;
        amounts[2] = 0.3 ether;
        address[] memory fallbacks = new address[](3);

        DistributionRequest[] memory requests = _buildRequests(beneficiaries, amounts, fallbacks);

        vm.prank(user);
        distributor.batchDistributeETH{value: _sum(amounts)}(
            "batch-eth-sendcall-for",
            requests,
            _buildMockMinAmountsOut(1),
            block.timestamp,
            0x0
        );

        assertEq(escrow.deposits(b1), amounts[0]);
        assertEq(escrow.deposits(b2), amounts[1]);
        assertEq(escrow.deposits(b3), amounts[2]);
    }

    function test_batchDistributeETH_sendAndCall_failureWithFallbacks() public {
        MockEscrow escrow = new MockEscrow();

        vm.startPrank(owner);
        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .sendAndCall(10000, address(escrow), bytes4(keccak256("fail()")))
                .build()
        );
        distributor.setDistributionId("batch-eth-sendcall-fallbacks", distId);
        vm.stopPrank();

        address b1 = makeAddr("b1");
        address b2 = makeAddr("b2");
        address b3 = makeAddr("b3");
        address f1 = makeAddr("f1");
        address f2 = makeAddr("f2");
        address f3 = makeAddr("f3");
        address user = makeAddr("user");
        vm.deal(user, 10 ether);

        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = b1;
        beneficiaries[1] = b2;
        beneficiaries[2] = b3;
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 0.1 ether;
        amounts[1] = 0.2 ether;
        amounts[2] = 0.3 ether;
        address[] memory fallbacks = new address[](3);
        fallbacks[0] = f1;
        fallbacks[1] = f2;
        fallbacks[2] = f3;

        DistributionRequest[] memory requests = _buildRequests(beneficiaries, amounts, fallbacks);

        vm.prank(user);
        distributor.batchDistributeETH{value: _sum(amounts)}(
            "batch-eth-sendcall-fallbacks",
            requests,
            _buildMockMinAmountsOut(1),
            block.timestamp,
            0x0
        );

        assertEq(f1.balance, amounts[0]);
        assertEq(f2.balance, amounts[1]);
        assertEq(f3.balance, amounts[2]);
        assertEq(address(distributor).balance, 0);
    }

    function test_batchDistributeETH_sendAndCall_failureWithoutFallbackReverts() public {
        MockEscrow escrow = new MockEscrow();

        vm.startPrank(owner);
        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .sendAndCall(10000, address(escrow), bytes4(keccak256("fail()")))
                .build()
        );
        distributor.setDistributionId("batch-eth-sendcall-revert", distId);
        vm.stopPrank();

        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = makeAddr("b1");
        beneficiaries[1] = makeAddr("b2");
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.1 ether;
        amounts[1] = 0.2 ether;
        address[] memory fallbacks = new address[](2);

        DistributionRequest[] memory requests = _buildRequests(beneficiaries, amounts, fallbacks);

        vm.expectPartialRevert(TokenDistributor.CallFailed.selector);
        distributor.batchDistributeETH{value: _sum(amounts)}(
            "batch-eth-sendcall-revert",
            requests,
            _buildMockMinAmountsOut(1),
            block.timestamp,
            0x0
        );
    }

    function test_batchERC20_splitProportional() public {
        vm.startPrank(owner);
        uint256 distId = distributor.addDistribution(
            new DistributionBuilder().send(10000, address(0)).build()
        );
        distributor.setDistributionId("batch-erc20-split", distId);
        vm.stopPrank();

        address b1 = makeAddr("b1");
        address b2 = makeAddr("b2");
        address b3 = makeAddr("b3");

        address[] memory beneficiaries = new address[](3);
        beneficiaries[0] = b1;
        beneficiaries[1] = b2;
        beneficiaries[2] = b3;
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 0.1 * 1e18;
        amounts[1] = 0.2 * 1e18;
        amounts[2] = 0.3 * 1e18;
        address[] memory fallbacks = new address[](3);

        MockedERC20 erc20 = new MockedERC20();
        address user = makeAddr("user");
        erc20.mint(user, 10 * 1e18);

        DistributionRequest[] memory requests = _buildRequests(beneficiaries, amounts, fallbacks);

        vm.startPrank(user);
        erc20.approve(address(distributor), _sum(amounts));
        distributor.batchDistributeERC20(
            "batch-erc20-split",
            address(erc20),
            requests,
            _buildMockMinAmountsOut(1),
            block.timestamp,
            0x0
        );

        assertEq(erc20.balanceOf(b1), amounts[0]);
        assertEq(erc20.balanceOf(b2), amounts[1]);
        assertEq(erc20.balanceOf(b3), amounts[2]);
        assertEq(erc20.balanceOf(address(distributor)), 0);
    }

    function test_batchERC20_zeroTotalReverts() public {
        vm.startPrank(owner);
        uint256 distId = distributor.addDistribution(
            new DistributionBuilder().send(10000, address(0)).build()
        );
        distributor.setDistributionId("batch-erc20-zero", distId);
        vm.stopPrank();

        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = makeAddr("b1");
        beneficiaries[1] = makeAddr("b2");
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = 0;
        address[] memory fallbacks = new address[](2);
        DistributionRequest[] memory requests = _buildRequests(beneficiaries, amounts, fallbacks);

        MockedERC20 erc20 = new MockedERC20();

        vm.expectPartialRevert(TokenDistributor.ZeroAmountNotAllowed.selector);
        distributor.batchDistributeERC20(
            "batch-erc20-zero",
            address(erc20),
            requests,
            _buildMockMinAmountsOut(1),
            block.timestamp,
            0x0
        );
    }

    function test_batchNestedMultiSwap_minAmountsOutIndexingReverts() public {
        // Configure (ETH -> USDC) and (USDC -> USDT)
        vm.startPrank(owner);
        _addConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(address(0)),
                    currency1: Currency.wrap(usdc),
                    fee: 500,
                    tickSpacing: 10,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V4
            })
        );
        _addConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(usdc),
                    currency1: Currency.wrap(usdt),
                    fee: 100,
                    tickSpacing: 0,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V3
            })
        );

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .buy(
                    10000,
                    usdc,
                    distributor.addDistribution(
                        new DistributionBuilder().buy(10000, usdt, address(0)).build()
                    )
                )
                .build()
        );
        distributor.setDistributionId("batch-minamount-indexing", distId);
        vm.stopPrank();

        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = makeAddr("b1");
        beneficiaries[1] = makeAddr("b2");
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.1 ether;
        amounts[1] = 0.2 ether;
        address[] memory fallbacks = new address[](2);

        DistributionRequest[] memory requests = _buildRequests(beneficiaries, amounts, fallbacks);

        // Only one minAmount provided but two swaps are required → revert at index 1
        uint256[] memory minAmounts = new uint256[](1);
        minAmounts[0] = 1;

        vm.expectPartialRevert(TokenDistributor.MinAmountOutNotSet.selector);
        distributor.batchDistributeETH{value: _sum(amounts)}(
            "batch-minamount-indexing",
            requests,
            minAmounts,
            block.timestamp,
            0x0
        );
    }

    function test_batchERC20_WETHToETH_distributesProportionally() public {
        vm.startPrank(owner);
        uint256 distId = distributor.addDistribution(
            new DistributionBuilder().buy(10000, address(0), address(0)).build()
        );
        distributor.setDistributionId("batch-erc20-weth-to-eth", distId);
        vm.stopPrank();

        address b1 = makeAddr("b1");
        address b2 = makeAddr("b2");
        address user = makeAddr("user");
        vm.deal(user, 10 ether);

        uint256 amount = 0.6 ether;
        vm.startPrank(user);
        IWETH(weth).deposit{value: amount}();
        assertEq(IERC20(weth).balanceOf(user), amount);
        IERC20(weth).approve(address(distributor), amount);

        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = b1;
        beneficiaries[1] = b2;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.1 ether;
        amounts[1] = 0.5 ether;
        address[] memory fallbacks = new address[](2);

        DistributionRequest[] memory requests = _buildRequests(beneficiaries, amounts, fallbacks);

        distributor.batchDistributeERC20(
            "batch-erc20-weth-to-eth",
            weth,
            requests,
            _buildMockMinAmountsOut(0),
            block.timestamp,
            0x0
        );

        assertEq(b1.balance, amounts[0]);
        assertEq(b2.balance, amounts[1]);
        assertEq(IERC20(weth).balanceOf(address(distributor)), 0);
        assertEq(address(distributor).balance, 0);
    }

    function test_batchDistributeETH_dustDeterminismByReordering() public {
        address a = address(new ETHReceiver());
        address b = address(new ETHReceiver());
        address c = address(new ETHReceiver());
        vm.label(a, "a");
        vm.label(b, "b");
        vm.label(c, "c");

        vm.startPrank(owner);
        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .send(5000, address(0))
                .send(5000, makeAddr("sink"))
                .build()
        );
        distributor.setDistributionId("batch-eth-dust-order", distId);
        vm.stopPrank();

        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 50;
        amounts[1] = 50;
        amounts[2] = 1; // total 101

        // Order 1: a, b, c → c should get remainder for the 50% action
        address[] memory beneficiaries1 = new address[](3);
        beneficiaries1[0] = a;
        beneficiaries1[1] = b;
        beneficiaries1[2] = c;
        address[] memory fallbacks = new address[](3);
        DistributionRequest[] memory req1 = _buildRequests(beneficiaries1, amounts, fallbacks);
        vm.prank(user);
        distributor.batchDistributeETH{value: 101}(
            "batch-eth-dust-order",
            req1,
            _buildMockMinAmountsOut(1),
            block.timestamp,
            0x0
        );
        uint256 actionTotal = (uint256(101) * 5000) / 10000; // 50
        uint256 aShare = (actionTotal * 50) / 101; // 24
        uint256 bShare = (actionTotal * 50) / 101; // 24
        uint256 cShare = actionTotal - aShare - bShare; // 2 remainder
        assertEq(a.balance, aShare);
        assertEq(b.balance, bShare);
        assertEq(c.balance, cShare);

        // Reset by deploying fresh distributor state is heavy; instead run again with new order and compare incremental deltas by zeroing addresses
        // Use new addresses to avoid interference
        address a2 = address(new ETHReceiver());
        address b2 = address(new ETHReceiver());
        address c2 = address(new ETHReceiver());
        vm.label(a2, "a2");
        vm.label(b2, "b2");
        vm.label(c2, "c2");

        address[] memory beneficiaries2 = new address[](3);
        beneficiaries2[0] = c2;
        beneficiaries2[1] = a2;
        beneficiaries2[2] = b2;
        DistributionRequest[] memory req2 = _buildRequests(beneficiaries2, amounts, fallbacks);
        vm.prank(user);
        distributor.batchDistributeETH{value: 101}(
            "batch-eth-dust-order",
            req2,
            _buildMockMinAmountsOut(1),
            block.timestamp,
            0x0
        );
        uint256 c2Share = (actionTotal * 50) / 101; // 24
        uint256 a2Share = (actionTotal * 50) / 101; // 24
        uint256 b2Share = actionTotal - c2Share - a2Share; // 2 remainder (now b2 last)
        assertEq(c2.balance, c2Share);
        assertEq(a2.balance, a2Share);
        assertEq(b2.balance, b2Share);
    }

    function _buildRequests(
        address[] memory beneficiaries,
        uint256[] memory amounts,
        address[] memory recipientsOnFailure
    ) internal pure returns (DistributionRequest[] memory) {
        require(
            beneficiaries.length == amounts.length &&
            beneficiaries.length == recipientsOnFailure.length,
            "length mismatch"
        );
        DistributionRequest[] memory requests = new DistributionRequest[](beneficiaries.length);
        for (uint256 i = 0; i < beneficiaries.length; ++i) {
            requests[i] = DistributionRequest({
                beneficiary: beneficiaries[i],
                amount: amounts[i],
                recipientOnFailure: recipientsOnFailure[i]
            });
        }
        return requests;
    }

    function _sum(uint256[] memory arr) internal pure returns (uint256 s) {
        for (uint256 i = 0; i < arr.length; ++i) s += arr[i];
    }
}


contract ETHReceiver {
    receive() external payable {}
}


