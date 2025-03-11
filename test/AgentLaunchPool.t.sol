// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';

import {AgentToken} from "../src/AgentToken.sol";
import {AgentStaking} from "../src/AgentStaking.sol";
import {AgentLaunchPool} from "../src/AgentLaunchPool.sol";
import {AgentFactoryTestUtils} from "./helpers/AgentFactoryTestUtils.sol";

contract AgentLaunchPoolTest is AgentFactoryTestUtils {
    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        _deployDefaultContracts();
    }

    function test_canDeposit() public {
        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(0));

        assertEq(pool.canDeposit(), true);

        vm.startPrank(user);
        pool.depositETH{value: 1 ether}();

        assertEq(pool.deposits(user), 1 ether);
    }

    function test_canDepositBySendingETH() public {
        address user = makeAddr("user");
        vm.deal(user, 2 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(0));

        assertEq(pool.canDeposit(), true);

        vm.startPrank(user);
        address(pool).call{value: 1 ether}("");

        assertEq(pool.deposits(user), 1 ether);

        address(pool).call{value: 1 ether}("");
        assertEq(pool.deposits(user), 2 ether);
    }

    function test_canDepositForBeneficiary() public {
        address user = makeAddr("user");
        address beneficiary = makeAddr("beneficiary");

        vm.deal(user, 1 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(0));

        assertEq(pool.canDeposit(), true);

        vm.startPrank(user);
        pool.depositETHFor{value: 1 ether}(beneficiary);

        assertEq(pool.deposits(beneficiary), 1 ether);
        assertEq(pool.deposits(user), 0);
    }

    function test_sameUserCanDepositMultipleTimes() public {
        address user = makeAddr("user");
        vm.deal(user, 1.5 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user);
        pool.depositETH{value: 1 ether}();

        assertEq(pool.deposits(user), 1 ether);
        assertEq(pool.totalDeposited(), 1 ether);

        pool.depositETH{value: 0.5 ether}();

        assertEq(pool.deposits(user), 1.5 ether);
        assertEq(pool.totalDeposited(), 1.5 ether);
    }

    function test_multipleUsersCanDeposit() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        vm.deal(user1, 1 ether);
        vm.deal(user2, 2 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user1);
        pool.depositETH{value: 1 ether}();

        assertEq(pool.deposits(user1), 1 ether);
        assertEq(pool.deposits(user2), 0);
        assertEq(pool.totalDeposited(), 1 ether);

        vm.startPrank(user2);
        pool.depositETH{value: 2 ether}();

        assertEq(pool.deposits(user1), 1 ether);
        assertEq(pool.deposits(user2), 2 ether);
        assertEq(pool.totalDeposited(), 3 ether);
    }

    function test_forbidsDepositAfterTimeWindow() public {
        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user);

        vm.warp(block.timestamp + timeWindow);
        
        assertEq(pool.canDeposit(), false);

        vm.expectPartialRevert(AgentLaunchPool.DepositsClosed.selector);
        pool.depositETH{value: 1 ether}();

        vm.expectPartialRevert(AgentLaunchPool.DepositsClosed.selector);
        pool.depositETHFor{value: 1 ether}(makeAddr("beneficiary"));
    }

    function test_canLaunch() public {
        address user = makeAddr("user");
        vm.deal(user, 10000 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user);
        pool.depositETH{value: 1000 ether}();

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        assertEq(pool.hasLaunched(), true);
        assertNotEq(pool.agentToken(), address(0));
        assertNotEq(pool.agentStaking(), address(0));

        assertEq(IERC20(pool.agentToken()).totalSupply(), totalSupply);
        assertEq(IERC20(pool.agentToken()).balanceOf(dao), agentDaoAmount);
        assertEq(IERC20(pool.agentToken()).balanceOf(agentWallet), agentAmount);
        assertEq(IERC20(pool.agentToken()).balanceOf(address(pool)) / 1e15, launchPoolAmount / 1e15); // Rounding because price calculations (unsiwap) are not exact
        assertGt(IERC20(pool.agentToken()).balanceOf(address(pool)), launchPoolAmount);

        assertEq(AgentToken(pool.agentToken()).name(), "Agent Token");
        assertEq(AgentToken(pool.agentToken()).symbol(), "AGENT");

        (uint256 reserveA, uint256 reserveB, uint totalLiquidity) = _getLiquidity(poolKey, address(0), pool.agentToken(), tickSpacing);
        uint256 expectedUniswapCollateral = collateralUniswapPoolBasisAmount * pool.totalDeposited() / 1e4;
        assertEq((expectedUniswapCollateral > reserveA ? expectedUniswapCollateral - reserveA : reserveA - expectedUniswapCollateral) / 1e15, 0); // Rounding
        assertEq((uniswapPoolAmount > reserveB ? uniswapPoolAmount - reserveB : reserveB - uniswapPoolAmount) / 1e15, 0); // Rounding
        assertGt(totalLiquidity, 0);
    }

    function test_anyoneCanLaunch() public {
        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user);
        pool.depositETH{value: 1 ether}();

        vm.warp(block.timestamp + timeWindow);

        vm.startPrank(makeAddr("anyone"));
        pool.launch();
    }

    function test_forbidsDepositAfterLaunch() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user1);
        pool.depositETH{value: 1 ether}();

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        assertEq(pool.canDeposit(), false);

        vm.startPrank(user2);

        vm.expectPartialRevert(AgentLaunchPool.DepositsClosed.selector);
        pool.depositETH{value: 1 ether}();

        vm.expectPartialRevert(AgentLaunchPool.DepositsClosed.selector);
        pool.depositETHFor{value: 1 ether}(makeAddr("beneficiary"));
    }

    function test_launchFailsIfMinAmountNotReached() public {
        address user = makeAddr("user");
        vm.deal(user, 0.2 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user);
        pool.depositETH{value: 0.2 ether}();

        vm.warp(block.timestamp + timeWindow);

        vm.expectPartialRevert(AgentLaunchPool.MinAmountNotReached.selector);
        pool.launch();
    }

    function test_canReclaimDepositsIfLaunchFails() public {
        address user = makeAddr("user");
        vm.deal(user, 0.2 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user);
        pool.depositETH{value: 0.2 ether}();

        vm.warp(block.timestamp + timeWindow);

        vm.expectPartialRevert(AgentLaunchPool.MinAmountNotReached.selector);
        pool.launch();

        assertEq(pool.totalDeposited(), 0.2 ether);
        assertEq(pool.deposits(user), 0.2 ether);
        assertEq(user.balance, 0);
        
        pool.reclaimDepositsFor(payable(user));

        assertEq(pool.totalDeposited(), 0.2 ether);
        assertEq(pool.deposits(user), 0);
        assertEq(user.balance, 0.2 ether);
    }

    function test_canClaimForSelf() public {
        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user);
        pool.depositETH{value: 1 ether}();

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        pool.claim(user);

        assertEq(pool.totalDeposited(), 1 ether);
        assertEq(IERC20(pool.agentToken()).balanceOf(user), 1 ether * launchPoolAmount / 1 ether);
    }

    function test_canClaimForRecipient() public {
        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user);
        pool.depositETH{value: 1 ether}();

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        vm.startPrank(makeAddr("anon"));
        pool.claim(user);

        assertEq(pool.totalDeposited(), 1 ether);
        assertEq(IERC20(pool.agentToken()).balanceOf(user), launchPoolAmount);
    }

    function test_beneficiaryCanClaim() public {
        address user = makeAddr("user");
        address beneficiary = makeAddr("beneficiary");
        vm.deal(user, 1 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user);
        pool.depositETHFor{value: 1 ether}(beneficiary);

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        pool.claim(beneficiary);

        assertEq(pool.totalDeposited(), 1 ether);
        assertEq(IERC20(pool.agentToken()).balanceOf(beneficiary), launchPoolAmount);
        assertEq(IERC20(pool.agentToken()).balanceOf(user), 0);
    }

    function test_canMultiClaim() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        
        vm.deal(user1, 1 ether);
        vm.deal(user2, 2 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user1);
        pool.depositETH{value: 1 ether}();

        vm.startPrank(user2);
        pool.depositETH{value: 2 ether}();

        assertEq(pool.deposits(user1), 1 ether);
        assertEq(pool.deposits(user2), 2 ether);
        assertEq(pool.deposits(user3), 0);

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        address[] memory recipients = new address[](3);
        recipients[0] = user1;
        recipients[1] = user2;
        recipients[2] = user3;

        pool.multiClaim(recipients);

        assertEq(pool.totalDeposited(), 3 ether);
        assertEq(IERC20(pool.agentToken()).balanceOf(user1), 1 ether * launchPoolAmount / 3 ether);
        assertEq(IERC20(pool.agentToken()).balanceOf(user2), 2 ether * launchPoolAmount / 3 ether);
        assertEq(IERC20(pool.agentToken()).balanceOf(user3), 0);
    }

    function test_forbidsClaimingBeforeLaunch() public {
        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user);
        pool.depositETH{value: 1 ether}();

        vm.warp(block.timestamp + timeWindow - 1 days);

        vm.expectPartialRevert(AgentLaunchPool.NotLaunched.selector);
        pool.claim(user);
    }

    function test_forbidsMultiClaimingBeforeLaunch() public {
        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user);
        pool.depositETH{value: 1 ether}();

        vm.warp(block.timestamp + timeWindow - 1 days);

        address[] memory recipients = new address[](1);
        recipients[0] = user;

        vm.expectPartialRevert(AgentLaunchPool.NotLaunched.selector);
        pool.multiClaim(recipients);
    }

    function test_canBuyTokensOnUniswapAfterLaunch() public {
        (AgentLaunchPool pool, PoolKey memory poolKey) = _launch();

        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        assertEq(IERC20(pool.agentToken()).balanceOf(user), 0);

        vm.startPrank(user);
        _swapETHForERC20(user, poolKey, 1 ether);
        
        assertGt(IERC20(pool.agentToken()).balanceOf(user), 0);
    }

    function test_canSellTokensOnUniswapAfterLaunch() public {
        (AgentLaunchPool pool, PoolKey memory poolKey) = _launch();

        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        vm.startPrank(user);
       
        _swapETHForERC20(user, poolKey, 1 ether);

        uint256 tokenBalance = IERC20(pool.agentToken()).balanceOf(user);
        uint256 amountToSell = tokenBalance / 3;
        uint256 ethBalance = user.balance;

        assertGt(tokenBalance, 0);

        _swapERC20ForETH(user, poolKey, amountToSell);

        assertEq(IERC20(pool.agentToken()).balanceOf(user), tokenBalance - amountToSell);
        assertGt(user.balance, ethBalance);
    }

    function test_canStakeAfterLaunch() public {
        (AgentLaunchPool pool, PoolKey memory poolKey) = _launch();

        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        address token = pool.agentToken();

        vm.startPrank(user);
        
        _swapETHForERC20(user, poolKey, 1 ether);

        AgentStaking staking = AgentStaking(pool.agentStaking());

        uint256 startingBalance = IERC20(pool.agentToken()).balanceOf(user);
        uint256 amount = startingBalance / 3;

        IERC20(token).approve(address(staking), amount);
        staking.stake(amount);
    
        assertEq(IERC20(token).balanceOf(user), startingBalance - amount);
        assertEq(staking.getStakedAmount(user), amount);
    }

    function _launch() internal returns (AgentLaunchPool, PoolKey memory) {
        address depositor = makeAddr("depositor");
        vm.deal(depositor, 1 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey)= _deployDefaultLaunchPool(address(0));

        vm.prank(depositor);
        pool.depositETH{value: 1 ether}();

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        return (pool, poolKey);
    }
}
