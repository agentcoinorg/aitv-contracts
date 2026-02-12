// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TokenDistributorV2} from "../src/TokenDistributorV2.sol";

contract TokenDistributorV2RescueTest is Test {
    TokenDistributorV2 private executor;

    address private owner = makeAddr("owner");
    address private user = makeAddr("user");

    function setUp() public {
        executor = new TokenDistributorV2(owner);
        vm.deal(user, 100 ether);
    }

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
    // Helpers (minimal copies)
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

