// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {AgentFactoryTestUtils} from "../helpers/AgentFactoryTestUtils.sol";
import {MockedERC20} from "../helpers/MockedERC20.sol";
import {AgentLaunchPool} from "../../src/AgentLaunchPool.sol";
import {AgentToken} from "../../src/AgentToken.sol";
import {AgentUniswapHook} from "../../src/AgentUniswapHook.sol";
import {AgentStaking} from "../../src/AgentStaking.sol";
import {LaunchPoolProposal} from "../../src/types/LaunchPoolProposal.sol";
import {UniswapFeeInfo} from "../../src/types/UniswapFeeInfo.sol";

contract AgentLaunchPoolLaunchTest is AgentFactoryTestUtils {
    MockedERC20 collateral;

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        _deployDefaultContracts();

        collateral = new MockedERC20();
    }

    function test_launchesWithCorrectConfigWithETHCollateral() public { 
        address user = makeAddr("user");
        vm.deal(user, 10000 ether);

        LaunchPoolProposal memory proposal = _buildDefaultLaunchPoolProposal(address(0));

        uint256 proposalId = factory.addProposal(proposal);

        vm.prank(owner);
        AgentLaunchPool pool = AgentLaunchPool(payable(factory.deployProposal(proposalId)));

        PoolKey memory poolKey = _getPoolKey(pool, proposal);

        assertEq(pool.owner(), owner);

        assertEq(pool.hasLaunched(), false);
        assertEq(pool.launchPoolCreatedOn(), block.timestamp);
        assertEq(pool.totalDeposited(), 0);
        assertEq(pool.agentToken(), address(0));
        assertEq(pool.agentStaking(), address(0));

        address expectedAgentTokenAddress = pool.computeAgentTokenAddress();

        vm.prank(user);
        pool.depositETH{value: 1000 ether}();

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        assertEq(pool.hasLaunched(), true);
        assertNotEq(pool.agentToken(), address(0));
        assertNotEq(pool.agentStaking(), address(0));

        assertEq(pool.totalDeposited(), maxAmountForLaunch);
        assertEq(IERC20(pool.agentToken()).totalSupply(), totalSupply);
        assertEq(IERC20(pool.agentToken()).balanceOf(dao), agentDaoAmount);
        assertEq(IERC20(pool.agentToken()).balanceOf(agentWallet), agentAmount);
        assertEq(IERC20(pool.agentToken()).balanceOf(address(pool)) / 1e15, launchPoolAmount / 1e15); // Rounding because price calculations (unsiwap) are not exact
        assertGt(IERC20(pool.agentToken()).balanceOf(address(pool)), launchPoolAmount); // There's at least launchPoolAmount
        assertEq(pool.agentToken(), expectedAgentTokenAddress);
        assertEq(dao.balance, daoCollateralBasisAmount * maxAmountForLaunch / 1e4);
        assertEq(agentWallet.balance, agentWalletCollateralBasisAmount * maxAmountForLaunch / 1e4);

        assertEq(AgentToken(pool.agentToken()).name(), "Agent Token");
        assertEq(AgentToken(pool.agentToken()).symbol(), "AGENT");

        assertEq(pool.getTokenInfo().owner, proposal.tokenInfo.owner);
        assertEq(pool.getTokenInfo().name, proposal.tokenInfo.name);
        assertEq(pool.getTokenInfo().symbol, proposal.tokenInfo.symbol);
        assertEq(pool.getTokenInfo().totalSupply, proposal.tokenInfo.totalSupply);
        assertEq(pool.getTokenInfo().tokenImplementation, proposal.tokenInfo.tokenImplementation);
        assertEq(pool.getTokenInfo().stakingImplementation, proposal.tokenInfo.stakingImplementation);

        assertEq(pool.getLaunchPoolInfo().collateral, proposal.launchPoolInfo.collateral);
        assertEq(pool.getLaunchPoolInfo().timeWindow, proposal.launchPoolInfo.timeWindow);
        assertEq(pool.getLaunchPoolInfo().minAmountForLaunch, proposal.launchPoolInfo.minAmountForLaunch);
        assertEq(pool.getLaunchPoolInfo().maxAmountForLaunch, proposal.launchPoolInfo.maxAmountForLaunch);
        assertEq(pool.getLaunchPoolInfo().collateralUniswapPoolBasisAmount, proposal.launchPoolInfo.collateralUniswapPoolBasisAmount);
        assertEq(pool.getLaunchPoolInfo().collateralRecipients, proposal.launchPoolInfo.collateralRecipients);
        assertEq(pool.getLaunchPoolInfo().collateralBasisAmounts, proposal.launchPoolInfo.collateralBasisAmounts);

        assertEq(pool.getUniswapPoolInfo().permit2, proposal.uniswapPoolInfo.permit2);
        assertEq(pool.getUniswapPoolInfo().hook, proposal.uniswapPoolInfo.hook);
        assertEq(pool.getUniswapPoolInfo().lpRecipient, proposal.uniswapPoolInfo.lpRecipient);
        assertEq(pool.getUniswapPoolInfo().lpFee, proposal.uniswapPoolInfo.lpFee);
        assertEq(pool.getUniswapPoolInfo().tickSpacing, proposal.uniswapPoolInfo.tickSpacing);

        assertEq(pool.getDistributionInfo().recipients, proposal.distributionInfo.recipients);
        assertEq(pool.getDistributionInfo().basisAmounts, proposal.distributionInfo.basisAmounts);
        assertEq(pool.getDistributionInfo().launchPoolBasisAmount, proposal.distributionInfo.launchPoolBasisAmount);
        assertEq(pool.getDistributionInfo().uniswapPoolBasisAmount, proposal.distributionInfo.uniswapPoolBasisAmount);

        UniswapFeeInfo memory feeInfo1 = hook.getFeesForPair(address(0), pool.agentToken());

        assertEq(feeInfo1.collateral, proposal.uniswapFeeInfo.collateral);
        assertEq(feeInfo1.burnBasisAmount, proposal.uniswapFeeInfo.burnBasisAmount);
        assertEq(feeInfo1.recipients, proposal.uniswapFeeInfo.recipients);
        assertEq(feeInfo1.basisAmounts, proposal.uniswapFeeInfo.basisAmounts);

        // Assert that ordering works
        UniswapFeeInfo memory feeInfo2 = hook.getFeesForPair(pool.agentToken(), address(0));

        assertEq(feeInfo2.collateral, proposal.uniswapFeeInfo.collateral);
        assertEq(feeInfo2.burnBasisAmount, proposal.uniswapFeeInfo.burnBasisAmount);
        assertEq(feeInfo2.recipients, proposal.uniswapFeeInfo.recipients);
        assertEq(feeInfo2.basisAmounts, proposal.uniswapFeeInfo.basisAmounts);


        (uint256 reserveA, uint256 reserveB, uint totalLiquidity) = _getLiquidity(poolKey, address(0), tickSpacing);
        uint256 expectedUniswapCollateral = collateralUniswapPoolBasisAmount * maxAmountForLaunch / 1e4;
        assertEq((expectedUniswapCollateral > reserveA ? expectedUniswapCollateral - reserveA : reserveA - expectedUniswapCollateral) / 1e15, 0); // Rounding
        assertEq((uniswapPoolAmount > reserveB ? uniswapPoolAmount - reserveB : reserveB - uniswapPoolAmount) / 1e15, 0); // Rounding
        assertGt(totalLiquidity, 0);
    }

    function test_launchesWithCorrectConfigWithERC20Collateral() public { 
        address user = makeAddr("user");
        collateral.mint(user, 10000e18);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(collateral));

        address expectedAgentTokenAddress = pool.computeAgentTokenAddress();

        vm.prank(user);
        collateral.approve(address(pool), 1000e18);
        vm.prank(user);
        pool.depositERC20(1000e18);

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        assertEq(pool.hasLaunched(), true);
        assertNotEq(pool.agentToken(), address(0));
        assertNotEq(pool.agentStaking(), address(0));

        assertEq(pool.totalDeposited(), maxAmountForLaunch);
        assertEq(IERC20(pool.agentToken()).totalSupply(), totalSupply);
        assertEq(IERC20(pool.agentToken()).balanceOf(dao), agentDaoAmount);
        assertEq(IERC20(pool.agentToken()).balanceOf(agentWallet), agentAmount);
        assertEq(IERC20(pool.agentToken()).balanceOf(address(pool)) / 1e15, launchPoolAmount / 1e15); // Rounding because price calculations (unsiwap) are not exact
        assertGt(IERC20(pool.agentToken()).balanceOf(address(pool)), launchPoolAmount); // There's at least launchPoolAmount
        assertEq(pool.agentToken(), expectedAgentTokenAddress);
        assertEq(collateral.balanceOf(dao), daoCollateralBasisAmount * maxAmountForLaunch / 1e4);
        assertEq(collateral.balanceOf(agentWallet), agentWalletCollateralBasisAmount * maxAmountForLaunch / 1e4);

        assertEq(AgentToken(pool.agentToken()).name(), "Agent Token");
        assertEq(AgentToken(pool.agentToken()).symbol(), "AGENT");

        (uint256 reserveA, uint256 reserveB, uint totalLiquidity) = _getLiquidity(poolKey, address(collateral), tickSpacing);
        console.logUint(reserveA);
        console.logUint(reserveB);
        uint256 expectedUniswapCollateral = collateralUniswapPoolBasisAmount * maxAmountForLaunch / 1e4;
        assertEq((expectedUniswapCollateral > reserveA ? expectedUniswapCollateral - reserveA : reserveA - expectedUniswapCollateral) / 1e15, 0); // Rounding
        assertEq((uniswapPoolAmount > reserveB ? uniswapPoolAmount - reserveB : reserveB - uniswapPoolAmount) / 1e15, 0); // Rounding
        assertGt(totalLiquidity, 0);
    }

    function test_anyoneCanLaunch() public { 
        address user = makeAddr("user");
        vm.deal(user, 10000 ether);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));

        vm.prank(user);
        pool.depositETH{value: 1000 ether}();

        vm.warp(block.timestamp + timeWindow);

        vm.prank(makeAddr("anon"));
        pool.launch();

        assertEq(pool.hasLaunched(), true);
        assertNotEq(pool.agentToken(), address(0));
        assertNotEq(pool.agentStaking(), address(0));
    }

    function test_canLaunchMultipleAgents() public { 
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);

        collateral.mint(user1, 100e18);
        collateral.mint(user2, 100e18);
        collateral.mint(user3, 100e18);

        (AgentLaunchPool pool1,) = _deployDefaultLaunchPool(address(0));
        (AgentLaunchPool pool2,) = _deployDefaultLaunchPool(address(0));
        (AgentLaunchPool pool3,) = _deployDefaultLaunchPool(address(collateral));

        vm.startPrank(user1); // Deposit to pool1, pool2 and pool3
        pool1.depositETH{value: 1 ether}();
        pool2.depositETH{value: 2 ether}();
        collateral.approve(address(pool3), 3e18);
        pool3.depositERC20(3e18);

        vm.startPrank(user2); // Deposit to pool1 and pool3
        pool1.depositETH{value: 4 ether}();
        collateral.approve(address(pool3), 5e18);
        pool3.depositERC20(5e18);

        vm.startPrank(user3); // Deposit to pool1 and pool2
        pool1.depositETH{value: 6 ether}();
        pool2.depositETH{value: 7 ether}();

        vm.warp(block.timestamp + timeWindow);

        pool1.launch();
        pool2.launch();
        pool3.launch();

        assertEq(pool1.hasLaunched(), true);
        assertNotEq(pool1.agentToken(), address(0));
        assertNotEq(pool1.agentStaking(), address(0));

        assertEq(pool2.hasLaunched(), true);
        assertNotEq(pool2.agentToken(), address(0));
        assertNotEq(pool2.agentStaking(), address(0));

        assertEq(pool3.hasLaunched(), true);
        assertNotEq(pool3.agentToken(), address(0));
        assertNotEq(pool3.agentStaking(), address(0));

        vm.startPrank(user1);
        assertEq(pool1.claim(user1), true);
        assertEq(pool2.claim(user1), true);
        assertEq(pool3.claim(user1), true);

        vm.startPrank(user2);
        assertEq(pool1.claim(user2), true);
        assertEq(pool2.claim(user2), false);
        assertEq(pool3.claim(user2), true);

        vm.startPrank(user3);
        assertEq(pool1.claim(user3), true);
        assertEq(pool2.claim(user3), true);
        assertEq(pool3.claim(user3), false);

        assertGt(IERC20(pool1.agentToken()).balanceOf(user1), 0);
        assertGt(IERC20(pool2.agentToken()).balanceOf(user1), 0);
        assertGt(IERC20(pool3.agentToken()).balanceOf(user1), 0);

        assertGt(IERC20(pool1.agentToken()).balanceOf(user2), 0);
        assertEq(IERC20(pool2.agentToken()).balanceOf(user2), 0);
        assertGt(IERC20(pool3.agentToken()).balanceOf(user2), 0);

        assertGt(IERC20(pool1.agentToken()).balanceOf(user3), 0);
        assertGt(IERC20(pool2.agentToken()).balanceOf(user3), 0);
        assertEq(IERC20(pool3.agentToken()).balanceOf(user3), 0);
    }

    function test_computedAgentTokenAddressIsCorrect() public { 
        address user = makeAddr("user");
        vm.deal(user, 10000 ether);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));

        address futureTokenAddress = pool.computeAgentTokenAddress();

        vm.startPrank(user);
        pool.depositETH{value: 1000 ether}();

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        assertEq(pool.agentToken(), futureTokenAddress);
    }

    function test_forbidsReentrantLaunch() public { 
        address user = makeAddr("user");
        vm.deal(user, 10000 ether);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user);
        pool.depositETH{value: 1000 ether}();

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        vm.expectRevert(AgentLaunchPool.AlreadyLaunched.selector);
        pool.launch();
    }

    function test_forbidsLaunchingMoreThanOnce() public { 
        address user = makeAddr("user");
        vm.deal(user, 10000 ether);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user);
        pool.depositETH{value: 1000 ether}();

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        vm.startPrank(makeAddr("anyone"));
        vm.expectRevert(AgentLaunchPool.AlreadyLaunched.selector);
        pool.launch();
    }

    function test_forbidsLaunchBeforeTimeWindow() public { 
        address user = makeAddr("user");
        vm.deal(user, 10000 ether);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user);
        pool.depositETH{value: 2 ether}(); // More than min amount, less than max amount

        vm.warp(block.timestamp + timeWindow / 2);

        vm.expectRevert(AgentLaunchPool.TimeWindowNotPassed.selector);
        pool.launch();
    }

    function test_forbidsLaunchIfMinAmountNotReached() public { 
        address user = makeAddr("user");
        vm.deal(user, 10000 ether);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user);
        pool.depositETH{value: 0.5 ether}();

        vm.warp(block.timestamp + timeWindow);

        vm.expectRevert(AgentLaunchPool.MinAmountNotReached.selector);
        pool.launch();
    }

    function test_canLaunchDifferentAgentLaunchPoolImpls() public { 
        address depositor = makeAddr("depositor");
        vm.deal(depositor, 2 ether);

        launchPoolImpl = address(new AgentLaunchPoolLaunchDisabled());
        (AgentLaunchPool pool1,) = _deployDefaultLaunchPool(address(0));

        launchPoolImpl = address(new AgentLaunchPoolCollateralMigrator());
        (AgentLaunchPool pool2,) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(depositor);
        pool1.depositETH{value: 1 ether}();
        pool2.depositETH{value: 1 ether}();
        vm.stopPrank();

        vm.warp(block.timestamp + timeWindow);

        vm.expectRevert("Launch disabled");
        pool1.launch();
        vm.expectRevert(AgentLaunchPool.NotLaunched.selector);
        pool1.claim(depositor);
        
        // We don't launch pool2 because we're going to transfer the collateral

        AgentLaunchPoolCollateralMigrator migrator = AgentLaunchPoolCollateralMigrator(payable(address(pool2)));

        address recipient = makeAddr("recipient");

        assertEq(recipient.balance, 0);
        assertEq(address(pool2).balance, 1 ether);

        migrator.migrateCollateral(recipient);

        assertEq(recipient.balance, 1 ether);
        assertEq(address(pool2).balance, 0);
    }

    function test_canLaunchDifferentAgentTokenImpls() public { 
        address depositor = makeAddr("depositor");
        vm.deal(depositor, 2 ether);

        agentTokenImpl = address(new AgentTokenMock());
        (AgentLaunchPool pool1,) = _deployDefaultLaunchPool(address(0));

        agentTokenImpl = address(new AgentTokenMint());
        (AgentLaunchPool pool2,) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(depositor);
        pool1.depositETH{value: 1 ether}();
        pool2.depositETH{value: 1 ether}();
        vm.stopPrank();

        vm.warp(block.timestamp + timeWindow);

        pool1.launch();
        pool2.launch();

        pool1.claim(depositor);
        pool2.claim(depositor);

        uint256 depositorBalance1 = IERC20(pool1.agentToken()).balanceOf(depositor);
        uint256 depositorBalance2 = IERC20(pool2.agentToken()).balanceOf(depositor);

        assertGt(depositorBalance1, 0);
        assertGt(depositorBalance2, 0);

        AgentTokenMock mock = AgentTokenMock(pool1.agentToken());
        assertEq(mock.test(), true);

        AgentTokenMint mint = AgentTokenMint(pool2.agentToken());
        mint.mint(depositor, 1e18);
        assertEq(IERC20(pool2.agentToken()).balanceOf(depositor), depositorBalance2 + 1e18);
    }

    function test_canLaunchDifferentStakingImpls() public { 
        address depositor = makeAddr("depositor");
        vm.deal(depositor, 2 ether);

        agentStakingImpl = address(new AgentStakingDisabled());
        (AgentLaunchPool pool1, PoolKey memory poolKey1) = _deployDefaultLaunchPool(address(0));

        agentStakingImpl = address(new AgentUnstakingDisabled());
        (AgentLaunchPool pool2, PoolKey memory poolKey2) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(depositor);
        pool1.depositETH{value: 1 ether}();
        pool2.depositETH{value: 1 ether}();
        vm.stopPrank();

        vm.warp(block.timestamp + timeWindow);

        pool1.launch();
        pool2.launch();

        pool1.claim(depositor);
        pool2.claim(depositor);

        address user = makeAddr("user");
        vm.deal(user, 2 ether);

        // Pool 1
        {
            address token1 = pool1.agentToken();
        
            _swapETHForERC20ExactIn(user, poolKey1, 1 ether);

            AgentStaking staking1 = AgentStaking(pool1.agentStaking());

            uint256 startingUserBalance1 = IERC20(pool1.agentToken()).balanceOf(user);
            uint256 userAmount1 = startingUserBalance1 / 3;

            vm.startPrank(user);
            IERC20(token1).approve(address(staking1), userAmount1);
            vm.expectRevert("Staking is disabled");
            staking1.stake(userAmount1);
            vm.stopPrank();

            uint256 startingDepositorBalance1 = IERC20(pool1.agentToken()).balanceOf(depositor);
            uint256 depositorAmount1 = startingDepositorBalance1 / 3;

            vm.startPrank(depositor);
            IERC20(token1).approve(address(staking1), depositorAmount1);
            vm.expectRevert("Staking is disabled");
            staking1.stake(depositorAmount1);
            vm.stopPrank();
        
            assertEq(IERC20(token1).balanceOf(user), startingUserBalance1);
            assertEq(staking1.getStakedAmount(user), 0);

            assertEq(IERC20(token1).balanceOf(depositor), startingDepositorBalance1);
            assertEq(staking1.getStakedAmount(depositor), 0);            
        }

        // Pool 2
        address token2 = pool2.agentToken();

        _swapETHForERC20ExactIn(user, poolKey2, 1 ether);

        AgentStaking staking2 = AgentStaking(pool2.agentStaking());

        uint256 startingUserBalance2 = IERC20(pool2.agentToken()).balanceOf(user);
        uint256 userAmount2 = startingUserBalance2 / 3;

        vm.startPrank(user);
        IERC20(token2).approve(address(staking2), userAmount2);
        staking2.stake(userAmount2);
        vm.stopPrank();

        uint256 startingDepositorBalance2 = IERC20(pool2.agentToken()).balanceOf(depositor);
        uint256 depositorAmount2 = startingDepositorBalance2 / 3;

        vm.startPrank(depositor);
        IERC20(token2).approve(address(staking2), depositorAmount2);
        staking2.stake(depositorAmount2);
        vm.stopPrank();
    
        assertEq(IERC20(token2).balanceOf(user), startingUserBalance2 - userAmount2);
        assertEq(staking2.getStakedAmount(user), userAmount2);

        assertEq(IERC20(token2).balanceOf(depositor), startingDepositorBalance2 - depositorAmount2);
        assertEq(staking2.getStakedAmount(depositor), depositorAmount2);

        vm.warp(block.timestamp + 1 days);

        vm.prank(depositor);
        vm.expectRevert("Unstaking is disabled");
        staking2.unstake(depositorAmount2);

        vm.prank(user);
        vm.expectRevert("Unstaking is disabled");
        staking2.unstake(userAmount2);
    }

    function test_canLaunchDifferentUniswapHookImpls() public {
        address hook1 = address(_deployAgentUniswapHook(owner, address(factory), address(new AgentUniswapHookDisableSwap())));
        address hook2 = address(_deployAgentUniswapHook(owner, address(factory), address(new AgentUniswapHookUpgrade())));

        address user = makeAddr("user");
        vm.deal(user, 2 ether);

        (AgentLaunchPool pool1, PoolKey memory poolKey1) = _deployDefaultLaunchPoolWithHook(address(0), hook1);
        (AgentLaunchPool pool2, PoolKey memory poolKey2) = _deployDefaultLaunchPoolWithHook(address(0), hook2);

        vm.startPrank(user);
        pool1.depositETH{value: 1 ether}();
        pool2.depositETH{value: 1 ether}();
        vm.stopPrank();

        vm.warp(block.timestamp + timeWindow);

        pool1.launch();
        pool2.launch();

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 2 ether);

        vm.expectRevert(); // Uniswap wraps the error so no error message
        ExternalSwap.swap(this, buyer, poolKey1, 1 ether); // This is a hack to be able to use expectRevert

        _swapETHForERC20ExactIn(buyer, poolKey2, 1 ether);
    }

    function externalSwap(address buyer, PoolKey memory poolKey, uint256 amount) external {
        _swapETHForERC20ExactIn(buyer, poolKey, amount);
    }
}

contract AgentUniswapHookDisableSwap is AgentUniswapHook {
    function _beforeSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        bytes calldata
    ) internal pure override returns (bytes4, BeforeSwapDelta, uint24) {
        revert ("Swap disabled1");
    }
}

contract AgentUniswapHookUpgrade is AgentUniswapHook {
}

library ExternalSwap {
  function swap(AgentLaunchPoolLaunchTest test, address buyer, PoolKey memory poolKey, uint256 amount) internal {
    test.externalSwap(buyer, poolKey, amount);
  }
}

contract AgentStakingDisabled is AgentStaking {
    function stake(uint256) public pure override {
        revert("Staking is disabled");
    }
}

contract AgentUnstakingDisabled is AgentStaking {
    function unstake(uint256) public pure override {
        revert("Unstaking is disabled");
    }
}

contract AgentTokenMock is AgentToken {
    function test() public pure returns(bool) {
        return true;
    }
}

contract AgentTokenMint is AgentToken {
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract AgentLaunchPoolLaunchDisabled is AgentLaunchPool {
    function launch() external pure override {
        revert ("Launch disabled");
    }
}

contract AgentLaunchPoolCollateralMigrator is AgentLaunchPool {
    using Address for address payable;

    function migrateCollateral(address recipient) external {
        payable(recipient).sendValue(address(this).balance);
    }
}