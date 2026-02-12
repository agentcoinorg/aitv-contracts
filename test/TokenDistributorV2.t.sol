// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TokenDistributorV2} from "../src/TokenDistributorV2.sol";

contract TokenDistributorV2Test is Test {
    TokenDistributorV2 private executor;

    address private owner = makeAddr("owner");
    address private user = makeAddr("user");

    function setUp() public {
        executor = new TokenDistributorV2(owner);
        vm.deal(user, 100 ether);
    }

    function test_executePlanETH_revertsOnTotalMismatch() public {
        TokenDistributorV2.Plan memory plan = _emptyPlan();
        plan.totalAmount = 1 ether;
        plan.deadline = block.timestamp;
        plan.groups = _groups1(makeAddr("b1"), 1, address(0));
        plan.buckets = _oneSendBucket(address(0), 10_000);

        vm.prank(user);
        vm.expectRevert(TokenDistributorV2.TotalAmountMismatch.selector);
        executor.executePlanETH{value: 2 ether}(plan);
    }

    function test_executePlanERC20_revertsOnPlanTotalMismatch() public {
        MockERC20 payment = new MockERC20("PAY", "PAY", 18);
        payment.mint(user, 100);

        TokenDistributorV2.Plan memory plan = _emptyPlan();
        plan.totalAmount = 1; // mismatched with arg totalAmount below
        plan.deadline = block.timestamp;
        plan.groups = _groups1(makeAddr("b1"), 1, address(0));
        plan.buckets = _oneSendBucket(address(payment), 10_000);

        vm.startPrank(user);
        payment.approve(address(executor), type(uint256).max);
        vm.expectRevert(TokenDistributorV2.TotalAmountMismatch.selector);
        executor.executePlanERC20(address(payment), 2, plan);
        vm.stopPrank();
    }

    function test_executePlanETH_revertsOnEmptyBeneficiaries() public {
        TokenDistributorV2.Plan memory plan = _emptyPlan();
        plan.totalAmount = 1;
        plan.deadline = block.timestamp;
        plan.groups = new TokenDistributorV2.BeneficiaryGroup[](0);
        plan.buckets = _oneSendBucket(address(0), 10_000);

        vm.prank(user);
        vm.expectRevert(TokenDistributorV2.InvalidPlan.selector);
        executor.executePlanETH{value: 1}(plan);
    }

    function test_executePlanETH_revertsOnEmptyBuckets() public {
        TokenDistributorV2.Plan memory plan = _emptyPlan();
        plan.totalAmount = 1;
        plan.deadline = block.timestamp;
        plan.groups = _groups1(makeAddr("b1"), 1, address(0));
        plan.buckets = new TokenDistributorV2.Bucket[](0);

        vm.prank(user);
        vm.expectRevert(TokenDistributorV2.InvalidPlan.selector);
        executor.executePlanETH{value: 1}(plan);
    }

    function test_executePlanETH_revertsOnDeadlinePassed() public {
        TokenDistributorV2.Plan memory plan = _emptyPlan();
        plan.totalAmount = 1;
        plan.deadline = block.timestamp - 1;
        plan.groups = _groups1(makeAddr("b1"), 1, address(0));
        plan.buckets = _oneSendBucket(address(0), 10_000);

        vm.prank(user);
        vm.expectRevert(TokenDistributorV2.DeadlinePassed.selector);
        executor.executePlanETH{value: 1}(plan);
    }

    function test_executePlanETH_revertsOnBucketBpsNotSumTo10000() public {
        TokenDistributorV2.Plan memory plan = _emptyPlan();
        plan.totalAmount = 1;
        plan.deadline = block.timestamp;
        plan.groups = _groups1(makeAddr("b1"), 1, address(0));

        TokenDistributorV2.Bucket[] memory buckets = new TokenDistributorV2.Bucket[](2);
        buckets[0] = _sendBucket(address(0), 4000);
        buckets[1] = _sendBucket(address(0), 4000);
        plan.buckets = buckets;

        vm.prank(user);
        vm.expectRevert(TokenDistributorV2.BasisPointsMustSumTo10000.selector);
        executor.executePlanETH{value: 1}(plan);
    }

    function test_executePlanETH_revertsWhenSameBeneficiaryHasInconsistentFallback() public {
        address b = makeAddr("b");
        address fb = makeAddr("fb");

        TokenDistributorV2.Beneficiary[] memory bens = new TokenDistributorV2.Beneficiary[](2);
        bens[0] = TokenDistributorV2.Beneficiary({beneficiary: b, weight: uint128(1), recipientOnFailure: address(0)});
        bens[1] = TokenDistributorV2.Beneficiary({beneficiary: b, weight: uint128(1), recipientOnFailure: fb});

        TokenDistributorV2.BeneficiaryGroup[] memory groups = new TokenDistributorV2.BeneficiaryGroup[](1);
        groups[0] = TokenDistributorV2.BeneficiaryGroup({beneficiaries: bens});

        TokenDistributorV2.Plan memory plan = _emptyPlan();
        plan.totalAmount = 1;
        plan.deadline = block.timestamp;
        plan.groups = groups;
        plan.buckets = _oneSendBucket(address(0), 10_000);

        vm.prank(user);
        vm.expectRevert(TokenDistributorV2.InvalidPlan.selector);
        executor.executePlanETH{value: 1}(plan);
    }

    function test_executePlanETH_revertsOnBurnETH() public {
        TokenDistributorV2.Plan memory plan = _emptyPlan();
        plan.totalAmount = 1;
        plan.deadline = block.timestamp;
        plan.groups = _groups1(makeAddr("b1"), 1, address(0));

        TokenDistributorV2.Bucket[] memory buckets = new TokenDistributorV2.Bucket[](1);
        buckets[0] = TokenDistributorV2.Bucket({
            sourceToken: address(0),
            actionType: TokenDistributorV2.ActionType.Burn,
            callTarget: address(0),
            selector: bytes4(0),
            callArgsPacked: bytes12(0),
            bucketBps: 10_000,
            groupId: 0
        });
        plan.buckets = buckets;

        vm.prank(user);
        vm.expectRevert(TokenDistributorV2.BurningETHNotAllowed.selector);
        executor.executePlanETH{value: 1}(plan);
    }

    // -----------------------------
    // Allowlist admin
    // -----------------------------

    function test_setAllowlistEnabled_ownerOnly() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        executor.setAllowlistEnabled(true);

        vm.prank(owner);
        executor.setAllowlistEnabled(true);
        assertTrue(executor.allowlistEnabled());
    }

    function test_setSwapAllowlist_ownerOnlyAndValidatesArgs() public {
        vm.prank(owner);
        vm.expectRevert(TokenDistributorV2.InvalidAllowlistEntry.selector);
        executor.setSwapAllowlist(address(0), address(1), true);

        vm.prank(owner);
        vm.expectRevert(TokenDistributorV2.InvalidAllowlistEntry.selector);
        executor.setSwapAllowlist(address(1), address(0), true);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        executor.setSwapAllowlist(address(1), address(2), true);
    }

    // -----------------------------
    // Rescue funds
    // -----------------------------

    function test_rescueFunds_ownerOnly() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        executor.rescueFunds(address(0), user, 1);
    }

    function test_rescueFunds_rescuesETH() public {
        address recipient = makeAddr("recipient");

        vm.prank(user);
        (bool ok, ) = payable(address(executor)).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(executor).balance, 1 ether);

        vm.prank(owner);
        executor.rescueFunds(address(0), recipient, 0.4 ether);

        assertEq(recipient.balance, 0.4 ether);
        assertEq(address(executor).balance, 0.6 ether);
    }

    function test_rescueFunds_rescuesERC20() public {
        MockERC20 token = new MockERC20("DUST", "DUST", 18);
        address recipient = makeAddr("recipient");

        token.mint(address(executor), 100);
        assertEq(token.balanceOf(address(executor)), 100);

        vm.prank(owner);
        executor.rescueFunds(address(token), recipient, 60);

        assertEq(token.balanceOf(recipient), 60);
        assertEq(token.balanceOf(address(executor)), 40);
    }

    function test_executePlanERC20_sendAndCall_canLeaveTokensStuck_andRescueRecovers() public {
        MockERC20 payment = new MockERC20("PAY", "PAY", 18);
        NoSpendCallTarget target = new NoSpendCallTarget();
        address beneficiary = makeAddr("beneficiary");

        payment.mint(user, 100);

        TokenDistributorV2.Plan memory plan = _emptyPlan();
        plan.totalAmount = 100;
        plan.deadline = block.timestamp;
        plan.groups = _groups1(beneficiary, 1, address(0));

        TokenDistributorV2.Bucket[] memory buckets = new TokenDistributorV2.Bucket[](1);
        buckets[0] = TokenDistributorV2.Bucket({
            sourceToken: address(payment),
            actionType: TokenDistributorV2.ActionType.SendAndCall,
            callTarget: address(target),
            selector: NoSpendCallTarget.store.selector,
            callArgsPacked: _encodeCallArgs(TokenDistributorV2.CallArgType.Sender, TokenDistributorV2.CallArgType.Beneficiary, TokenDistributorV2.CallArgType.Amount),
            bucketBps: 10_000,
            groupId: 0
        });
        plan.buckets = buckets;

        vm.startPrank(user);
        payment.approve(address(executor), type(uint256).max);
        executor.executePlanERC20(address(payment), 100, plan);
        vm.stopPrank();

        // Target never pulled allowance, so tokens remain in executor.
        assertEq(payment.balanceOf(address(executor)), 100);

        vm.prank(owner);
        executor.rescueFunds(address(payment), user, 100);

        assertEq(payment.balanceOf(address(executor)), 0);
        assertEq(payment.balanceOf(user), 100);
    }

    // -----------------------------
    // Deterministic pro-rata & dust
    // -----------------------------

    function test_executePlanETH_sendProRata_dustLastGetsRemainder() public {
        address b1 = makeAddr("b1");
        address b2 = makeAddr("b2");
        address b3 = makeAddr("b3");

        // totalWeight = 101
        TokenDistributorV2.Beneficiary[] memory bens = new TokenDistributorV2.Beneficiary[](3);
        bens[0] = TokenDistributorV2.Beneficiary({beneficiary: b1, weight: uint128(50), recipientOnFailure: address(0)});
        bens[1] = TokenDistributorV2.Beneficiary({beneficiary: b2, weight: uint128(50), recipientOnFailure: address(0)});
        bens[2] = TokenDistributorV2.Beneficiary({beneficiary: b3, weight: uint128(1), recipientOnFailure: address(0)});

        TokenDistributorV2.BeneficiaryGroup[] memory groups = new TokenDistributorV2.BeneficiaryGroup[](1);
        groups[0] = TokenDistributorV2.BeneficiaryGroup({beneficiaries: bens});

        TokenDistributorV2.Plan memory plan = _emptyPlan();
        plan.totalAmount = 101;
        plan.deadline = block.timestamp;
        plan.meta = keccak256("META");
        plan.groups = groups;
        plan.buckets = _oneSendBucket(address(0), 10_000);

        uint256 share1 = (uint256(101) * 50) / 101; // 50
        uint256 share2 = (uint256(101) * 50) / 101; // 50
        uint256 share3 = 101 - share1 - share2; // 1 remainder

        vm.prank(user);
        executor.executePlanETH{value: 101}(plan);

        assertEq(b1.balance, share1);
        assertEq(b2.balance, share2);
        assertEq(b3.balance, share3);
        assertEq(address(executor).balance, 0);
    }

    // -----------------------------
    // Aggregation & TokenTransferred events
    // -----------------------------

    function test_executePlanETH_aggregatesAcrossBuckets_oneTransferOneEventPerPair() public {
        address b1 = makeAddr("b1");
        address b2 = makeAddr("b2");

        TokenDistributorV2.Beneficiary[] memory bens = new TokenDistributorV2.Beneficiary[](2);
        bens[0] = TokenDistributorV2.Beneficiary({beneficiary: b1, weight: uint128(1), recipientOnFailure: address(0)});
        bens[1] = TokenDistributorV2.Beneficiary({beneficiary: b2, weight: uint128(1), recipientOnFailure: address(0)});

        TokenDistributorV2.BeneficiaryGroup[] memory groups = new TokenDistributorV2.BeneficiaryGroup[](1);
        groups[0] = TokenDistributorV2.BeneficiaryGroup({beneficiaries: bens});

        // Two buckets both sending ETH. Each pays 50/50 to b1/b2. Aggregation should collapse to 1 transfer per beneficiary.
        TokenDistributorV2.Bucket[] memory buckets = new TokenDistributorV2.Bucket[](2);
        buckets[0] = _sendBucket(address(0), 5000);
        buckets[1] = _sendBucket(address(0), 5000);

        TokenDistributorV2.Plan memory plan = _emptyPlan();
        plan.totalAmount = 10;
        plan.deadline = block.timestamp;
        plan.meta = keccak256("AGG");
        plan.groups = groups;
        plan.buckets = buckets;

        vm.recordLogs();
        vm.prank(user);
        executor.executePlanETH{value: 10}(plan);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        // Each bucket pro-ratas and gives remainder to the last beneficiary, so across 2 buckets:
        // bucketAmount=5 -> b1=2, b2=3; repeated twice -> b1=4, b2=6.
        // Only one event per (ETH, beneficiary) due to aggregation.
        assertEq(b1.balance, 4);
        assertEq(b2.balance, 6);

        bytes32 sig = keccak256("TokenTransferred(address,address,bytes32,address,uint256)");
        uint256 count = 0;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == sig) count++;
        }
        assertEq(count, 2);
    }

    // -----------------------------
    // ETH Send fallback semantics
    // -----------------------------

    function test_executePlanETH_send_ethTransferFailureRedirectsToFallback() public {
        RevertingReceiver bad = new RevertingReceiver();
        address fallbackRecipient = makeAddr("fallback");

        TokenDistributorV2.Beneficiary[] memory bens = new TokenDistributorV2.Beneficiary[](1);
        bens[0] = TokenDistributorV2.Beneficiary({
            beneficiary: address(bad),
            weight: 1,
            recipientOnFailure: fallbackRecipient
        });
        TokenDistributorV2.BeneficiaryGroup[] memory groups = new TokenDistributorV2.BeneficiaryGroup[](1);
        groups[0] = TokenDistributorV2.BeneficiaryGroup({beneficiaries: bens});

        TokenDistributorV2.Plan memory plan = _emptyPlan();
        plan.totalAmount = 1 ether;
        plan.deadline = block.timestamp;
        plan.meta = keccak256("FB");
        plan.groups = groups;
        plan.buckets = _oneSendBucket(address(0), 10_000);

        vm.recordLogs();
        vm.prank(user);
        executor.executePlanETH{value: 1 ether}(plan);

        assertEq(address(bad).balance, 0);
        assertEq(fallbackRecipient.balance, 1 ether);

        // Ensure TokenTransferred recipient is fallback.
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("TokenTransferred(address,address,bytes32,address,uint256)");
        bool found = false;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].topics.length > 2 && logs[i].topics[0] == sig) {
                address recipient = address(uint160(uint256(logs[i].topics[2])));
                if (recipient == fallbackRecipient) {
                    found = true;
                    break;
                }
            }
        }
        assertTrue(found);
    }

    // -----------------------------
    // ERC20 Send fallback semantics (transfer returns false)
    // -----------------------------

    function test_executePlanERC20_send_erc20TransferFalseRedirectsToFallback() public {
        MockFalseReturnERC20 token = new MockFalseReturnERC20();
        address badRecipient = makeAddr("badRecipient");
        address fallbackRecipient = makeAddr("fallbackRecipient");

        token.mint(user, 100);

        TokenDistributorV2.Beneficiary[] memory bens = new TokenDistributorV2.Beneficiary[](1);
        bens[0] = TokenDistributorV2.Beneficiary({
            beneficiary: badRecipient,
            weight: 1,
            recipientOnFailure: fallbackRecipient
        });
        TokenDistributorV2.BeneficiaryGroup[] memory groups = new TokenDistributorV2.BeneficiaryGroup[](1);
        groups[0] = TokenDistributorV2.BeneficiaryGroup({beneficiaries: bens});

        token.setFailRecipient(badRecipient, true);

        TokenDistributorV2.Plan memory plan = _emptyPlan();
        plan.totalAmount = 100;
        plan.deadline = block.timestamp;
        plan.meta = keccak256("ERC20FB");
        plan.groups = groups;
        plan.buckets = _oneSendBucket(address(token), 10_000);

        vm.startPrank(user);
        token.approve(address(executor), type(uint256).max);
        executor.executePlanERC20(address(token), 100, plan);
        vm.stopPrank();

        assertEq(token.balanceOf(badRecipient), 0);
        assertEq(token.balanceOf(fallbackRecipient), 100);
        assertEq(token.balanceOf(address(executor)), 0);
    }

    // -----------------------------
    // SendAndCall failure semantics (fallback converts to Send)
    // -----------------------------

    function test_executePlanETH_sendAndCall_failureRedirectsToFallbackAsSend() public {
        RevertingCallTarget target = new RevertingCallTarget();
        address fallbackRecipient = makeAddr("fallback");
        address beneficiary = makeAddr("beneficiary");

        TokenDistributorV2.Beneficiary[] memory bens = new TokenDistributorV2.Beneficiary[](1);
        bens[0] = TokenDistributorV2.Beneficiary({
            beneficiary: beneficiary,
            weight: uint128(1),
            recipientOnFailure: fallbackRecipient
        });
        TokenDistributorV2.BeneficiaryGroup[] memory groups = new TokenDistributorV2.BeneficiaryGroup[](1);
        groups[0] = TokenDistributorV2.BeneficiaryGroup({beneficiaries: bens});

        TokenDistributorV2.Bucket[] memory buckets = new TokenDistributorV2.Bucket[](1);
        buckets[0] = TokenDistributorV2.Bucket({
            sourceToken: address(0),
            actionType: TokenDistributorV2.ActionType.SendAndCall,
            callTarget: address(target),
            selector: RevertingCallTarget.store.selector,
            callArgsPacked: _encodeCallArgs(TokenDistributorV2.CallArgType.Sender, TokenDistributorV2.CallArgType.Beneficiary, TokenDistributorV2.CallArgType.Amount),
            bucketBps: 10_000,
            groupId: 0
        });

        TokenDistributorV2.Plan memory plan = _emptyPlan();
        plan.totalAmount = 123;
        plan.deadline = block.timestamp;
        plan.meta = keccak256("SAC");
        plan.groups = groups;
        plan.buckets = buckets;

        vm.prank(user);
        executor.executePlanETH{value: 123}(plan);

        assertEq(beneficiary.balance, 0);
        assertEq(fallbackRecipient.balance, 123);
    }

    // -----------------------------
    // Allowlist enforcement + swap correctness
    // -----------------------------

    function test_executePlanERC20_revertsWhenSwapNotAllowlisted() public {
        MockERC20 payment = new MockERC20("PAY", "PAY", 18);
        MockERC20 outToken = new MockERC20("OUT", "OUT", 18);
        MockSwapTarget swapTarget = new MockSwapTarget(payment, outToken);

        payment.mint(user, 100);

        vm.prank(owner);
        executor.setAllowlistEnabled(true);

        TokenDistributorV2.Plan memory plan = _emptyPlan();
        plan.totalAmount = 100;
        plan.deadline = block.timestamp;
        plan.meta = keccak256("SWAP");
        plan.groups = _groups1(makeAddr("b1"), 1, address(0));

        // All funds budgeted to OUT group via bucketBps, so groupBudgetIn(outToken)=100, requiring swapIn sum 100.
        plan.buckets = _oneSendBucket(address(outToken), 10_000);

        plan.swaps = new TokenDistributorV2.SwapStep[](1);
        plan.swaps[0] = TokenDistributorV2.SwapStep({
            tokenIn: address(payment),
            tokenOut: address(outToken),
            amountIn: 100,
            minOut: 1,
            allowanceTarget: address(swapTarget),
            swapTarget: address(swapTarget),
            value: 0,
            callData: abi.encodeCall(MockSwapTarget.swapExactIn, (100, 1))
        });

        vm.startPrank(user);
        payment.approve(address(executor), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(TokenDistributorV2.SwapNotAllowlisted.selector, address(swapTarget), address(swapTarget)));
        executor.executePlanERC20(address(payment), 100, plan);
        vm.stopPrank();
    }

    function test_executePlanERC20_swapMinOutAndExactSpendEnforced() public {
        MockERC20 payment = new MockERC20("PAY", "PAY", 18);
        MockERC20 outToken = new MockERC20("OUT", "OUT", 18);
        MockSwapTarget swapTarget = new MockSwapTarget(payment, outToken);

        payment.mint(user, 100);

        vm.startPrank(owner);
        executor.setAllowlistEnabled(true);
        executor.setSwapAllowlist(address(swapTarget), address(swapTarget), true);
        vm.stopPrank();

        TokenDistributorV2.Plan memory plan = _emptyPlan();
        plan.totalAmount = 100;
        plan.deadline = block.timestamp;
        plan.groups = _groups1(makeAddr("b1"), 1, address(0));
        plan.buckets = _oneSendBucket(address(outToken), 10_000);

        // Case 1: realizedOut < minOut
        plan.swaps = new TokenDistributorV2.SwapStep[](1);
        plan.swaps[0] = TokenDistributorV2.SwapStep({
            tokenIn: address(payment),
            tokenOut: address(outToken),
            amountIn: 100,
            minOut: 50,
            allowanceTarget: address(swapTarget),
            swapTarget: address(swapTarget),
            value: 0,
            callData: abi.encodeCall(MockSwapTarget.swapExactIn, (100, 1)) // outputs 1
        });

        vm.startPrank(user);
        payment.approve(address(executor), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(TokenDistributorV2.SwapMinOutNotMet.selector, 0, 1, 50));
        executor.executePlanERC20(address(payment), 100, plan);
        vm.stopPrank();

        // Case 2: under-spend triggers SwapSpentMismatch
        payment.mint(user, 100);
        swapTarget.setUnderSpend(true);

        plan.swaps[0] = TokenDistributorV2.SwapStep({
            tokenIn: address(payment),
            tokenOut: address(outToken),
            amountIn: 100,
            minOut: 1,
            allowanceTarget: address(swapTarget),
            swapTarget: address(swapTarget),
            value: 0,
            callData: abi.encodeCall(MockSwapTarget.swapExactIn, (100, 1))
        });

        vm.startPrank(user);
        payment.approve(address(executor), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(TokenDistributorV2.SwapSpentMismatch.selector, 0, 99, 100));
        executor.executePlanERC20(address(payment), 100, plan);
        vm.stopPrank();
    }

    // -----------------------------
    // Helpers
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

    function _oneSendBucket(address token, uint16 bps) internal pure returns (TokenDistributorV2.Bucket[] memory buckets) {
        buckets = new TokenDistributorV2.Bucket[](1);
        buckets[0] = _sendBucket(token, bps);
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

    function _encodeCallArgs(
        TokenDistributorV2.CallArgType a0,
        TokenDistributorV2.CallArgType a1,
        TokenDistributorV2.CallArgType a2
    ) internal pure returns (bytes12 packed) {
        bytes memory tmp = new bytes(12);
        tmp[0] = bytes1(uint8(3));
        tmp[1] = bytes1(uint8(a0));
        tmp[2] = bytes1(uint8(a1));
        tmp[3] = bytes1(uint8(a2));
        assembly {
            packed := mload(add(tmp, 32))
        }
    }
}

// -----------------------------
// Test mocks
// -----------------------------

contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 a = allowance[from][msg.sender];
        require(a >= amount, "allowance");
        if (a != type(uint256).max) allowance[from][msg.sender] = a - amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "balance");
        unchecked {
            balanceOf[from] -= amount;
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
    }
}

contract MockFalseReturnERC20 is IERC20 {
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => bool) public failRecipient;

    function setFailRecipient(address to, bool fail) external {
        failRecipient[to] = fail;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        if (failRecipient[to]) return false;
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 a = allowance[from][msg.sender];
        require(a >= amount, "allowance");
        if (a != type(uint256).max) allowance[from][msg.sender] = a - amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "balance");
        unchecked {
            balanceOf[from] -= amount;
            balanceOf[to] += amount;
        }
        emit Transfer(from, to, amount);
    }
}

contract MockSwapTarget {
    IERC20 public immutable tokenIn;
    MockERC20 public immutable tokenOut;
    bool public underSpend;

    constructor(IERC20 _tokenIn, MockERC20 _tokenOut) {
        tokenIn = _tokenIn;
        tokenOut = _tokenOut;
    }

    function setUnderSpend(bool v) external {
        underSpend = v;
    }

    function swapExactIn(uint256 amountIn, uint256 amountOut) external {
        uint256 toSpend = underSpend ? amountIn - 1 : amountIn;
        require(tokenIn.transferFrom(msg.sender, address(this), toSpend), "transferFrom");
        tokenOut.mint(msg.sender, amountOut);
    }
}

contract RevertingReceiver {
    receive() external payable {
        revert("nope");
    }
}

contract RevertingCallTarget {
    function store(address, address, uint256) external payable {
        revert("fail");
    }
}

contract NoSpendCallTarget {
    address public lastSender;
    address public lastBeneficiary;
    uint256 public lastAmount;

    function store(address sender, address beneficiary, uint256 amount) external payable {
        lastSender = sender;
        lastBeneficiary = beneficiary;
        lastAmount = amount;
    }
}
