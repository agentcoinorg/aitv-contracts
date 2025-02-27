// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {AgentToken} from "../src/AgentToken.sol";
import {AgentStaking} from "../src/AgentStaking.sol";
import {AirdropClaim} from "../src/AirdropClaim.sol";
import {AgentLaunchPool} from "../src/AgentLaunchPool.sol";

contract AgentLaunchPoolTest is Test {
    address owner = makeAddr("owner");
    address uniswapRouter;
    address agentWallet = makeAddr("agentWallet");
    uint256 agentAmount = 300_000 * 1e18;
    uint256 ownerAmount = 700_000 * 1e18;
    uint256 launchPoolAmount = 2_500_000 * 1e18;
    uint256 uniswapPoolAmount = 6_500_000 * 1e18;
    uint256 totalSupply = 10_000_000 * 1e18;
    uint256 timeWindow = 7 days;
    uint256 minAmountForLaunch = 0.5 ether;
    uint256 maxAmountForLaunch = 10 ether;

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));
        uniswapRouter = vm.envAddress("BASE_UNISWAP_ROUTER");
    }

    function test_canCreateLaunchPool() public {
        _deployLaunchPool();
    }

    function test_canDeposit() public {
        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        AgentLaunchPool pool = _deployLaunchPool();

        assertEq(pool.canDeposit(), true);

        vm.startPrank(user);
        pool.depositETH{value: 1 ether}();

        assertEq(pool.deposits(user), 1 ether);
    }

    function test_canDepositBySendingETH() public {
        address user = makeAddr("user");
        vm.deal(user, 2 ether);

        AgentLaunchPool pool = _deployLaunchPool();

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

        AgentLaunchPool pool = _deployLaunchPool();

        assertEq(pool.canDeposit(), true);

        vm.startPrank(user);
        pool.depositETHFor{value: 1 ether}(beneficiary);

        assertEq(pool.deposits(beneficiary), 1 ether);
        assertEq(pool.deposits(user), 0);
    }

    function test_sameUserCanDepositMultipleTimes() public {
        address user = makeAddr("user");
        vm.deal(user, 1.5 ether);

        AgentLaunchPool pool = _deployLaunchPool();

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

        AgentLaunchPool pool = _deployLaunchPool();

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

        AgentLaunchPool pool = _deployLaunchPool();

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
        vm.deal(user, 1 ether);

        AgentLaunchPool pool = _deployLaunchPool();

        vm.startPrank(user);
        pool.depositETH{value: 1 ether}();

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        assertEq(pool.hasLaunched(), true);
        assertNotEq(pool.agentToken(), address(0));
        assertNotEq(pool.agentStaking(), address(0));

        assertEq(IERC20(pool.agentToken()).totalSupply(), totalSupply);
        assertEq(IERC20(pool.agentToken()).balanceOf(owner), ownerAmount);
        assertEq(IERC20(pool.agentToken()).balanceOf(agentWallet), agentAmount);
        assertEq(IERC20(pool.agentToken()).balanceOf(address(pool)), launchPoolAmount);

        assertEq(AgentToken(pool.agentToken()).name(), "Agent");
        assertEq(AgentToken(pool.agentToken()).symbol(), "AGENT");

        (uint112 reserveA, uint112 reserveB, uint totalLiquidity) = _getLiquidity(pool.agentToken(), IUniswapV2Router02(uniswapRouter).WETH());
        assertEq(reserveA, uniswapPoolAmount);
        assertEq(reserveB, pool.totalDeposited());
        assertGt(totalLiquidity, 0);
    }

    function test_anyoneCanLaunch() public {
        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        AgentLaunchPool pool = _deployLaunchPool();

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

        AgentLaunchPool pool = _deployLaunchPool();

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

        AgentLaunchPool pool = _deployLaunchPool();

        vm.startPrank(user);
        pool.depositETH{value: 0.2 ether}();

        vm.warp(block.timestamp + timeWindow);

        vm.expectPartialRevert(AgentLaunchPool.MinAmountNotReached.selector);
        pool.launch();
    }

    function test_canReclaimDepositsIfLaunchFails() public {
        address user = makeAddr("user");
        vm.deal(user, 0.2 ether);

        AgentLaunchPool pool = _deployLaunchPool();

        vm.startPrank(user);
        pool.depositETH{value: 0.2 ether}();

        vm.warp(block.timestamp + timeWindow);

        vm.expectPartialRevert(AgentLaunchPool.MinAmountNotReached.selector);
        pool.launch();

        assertEq(pool.totalDeposited(), 0.2 ether);
        assertEq(pool.deposits(user), 0.2 ether);
        assertEq(user.balance, 0);
        
        pool.reclaimDeposits();

        assertEq(pool.totalDeposited(), 0.2 ether);
        assertEq(pool.deposits(user), 0);
        assertEq(user.balance, 0.2 ether);
    }

    function test_canClaimForSelf() public {
        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        AgentLaunchPool pool = _deployLaunchPool();

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

        AgentLaunchPool pool = _deployLaunchPool();

        vm.startPrank(user);
        pool.depositETH{value: 1 ether}();

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        vm.startPrank(makeAddr("anon"));
        pool.claim(user);

        assertEq(pool.totalDeposited(), 1 ether);
        assertEq(IERC20(pool.agentToken()).balanceOf(user), 1 ether * launchPoolAmount / 1 ether);
    }

    function test_beneficiaryCanClaim() public {
        address user = makeAddr("user");
        address beneficiary = makeAddr("beneficiary");
        vm.deal(user, 1 ether);

        AgentLaunchPool pool = _deployLaunchPool();

        vm.startPrank(user);
        pool.depositETHFor{value: 1 ether}(beneficiary);

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        pool.claim(beneficiary);

        assertEq(pool.totalDeposited(), 1 ether);
        assertEq(IERC20(pool.agentToken()).balanceOf(beneficiary), 1 ether * launchPoolAmount / 1 ether);
        assertEq(IERC20(pool.agentToken()).balanceOf(user), 0);
    }

    function test_canMultiClaim() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        
        vm.deal(user1, 1 ether);
        vm.deal(user2, 2 ether);

        AgentLaunchPool pool = _deployLaunchPool();

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

        AgentLaunchPool pool = _deployLaunchPool();

        vm.startPrank(user);
        pool.depositETH{value: 1 ether}();

        vm.warp(block.timestamp + timeWindow - 1 days);

        vm.expectPartialRevert(AgentLaunchPool.NotLaunched.selector);
        pool.claim(user);
    }

    function test_forbidsMultiClaimingBeforeLaunch() public {
        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        AgentLaunchPool pool = _deployLaunchPool();

        vm.startPrank(user);
        pool.depositETH{value: 1 ether}();

        vm.warp(block.timestamp + timeWindow - 1 days);

        address[] memory recipients = new address[](1);
        recipients[0] = user;

        vm.expectPartialRevert(AgentLaunchPool.NotLaunched.selector);
        pool.multiClaim(recipients);
    }

    function test_canBuyTokensOnUniswapAfterLaunch() public {
        AgentLaunchPool pool = _launch();

        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        assertEq(IERC20(pool.agentToken()).balanceOf(user), 0);

        _buyOnUniswap(user, 1 ether, pool.agentToken());
        
        assertGt(IERC20(pool.agentToken()).balanceOf(user), 0);
    }

    function test_canSellTokensOnUniswapAfterLaunch() public {
        AgentLaunchPool pool = _launch();

        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        _buyOnUniswap(user, 1 ether, pool.agentToken());

        uint256 tokenBalance = IERC20(pool.agentToken()).balanceOf(user);
        uint256 amountToSell = tokenBalance / 3;
        uint256 ethBalance = user.balance;

        assertGt(tokenBalance, 0);

        _sellOnUniswap(user, amountToSell, pool.agentToken());

        assertEq(IERC20(pool.agentToken()).balanceOf(user), tokenBalance - amountToSell);
        assertGt(user.balance, ethBalance);
    }

    function test_canStakeAfterLaunch() public {
        AgentLaunchPool pool = _launch();

        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        address token = pool.agentToken();

        _buyOnUniswap(user, 1 ether, token);

        AgentStaking staking = AgentStaking(pool.agentStaking());

        uint256 startingBalance = IERC20(pool.agentToken()).balanceOf(user);
        uint256 amount = startingBalance / 3;

        vm.startPrank(user);
        IERC20(token).approve(address(staking), amount);
        staking.stake(amount);
    
        assertEq(IERC20(token).balanceOf(user), startingBalance - amount);
        assertEq(staking.getStakedAmount(user), amount);
    }

    function _deployLaunchPool() internal returns (AgentLaunchPool) {
        address[] memory recipients = new address[](2);
        recipients[0] = owner;
        recipients[1] = agentWallet;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = ownerAmount;
        amounts[1] = agentAmount;

        string memory name = "Agent";
        string memory symbol = "AGENT";

        AgentLaunchPool.TokenMetadata memory tokenMetadata = AgentLaunchPool.TokenMetadata(
            owner,
            name,
            symbol
        );

        AgentLaunchPool pool = new AgentLaunchPool(
            tokenMetadata,
            timeWindow,
            minAmountForLaunch,
            maxAmountForLaunch,
            address(0),
            launchPoolAmount,
            uniswapPoolAmount,
            uniswapRouter,
            recipients,
            amounts
        );

        assertEq(pool.launchPoolAmount(), launchPoolAmount);
        assertEq(pool.uniswapPoolAmount(), uniswapPoolAmount);
        assertEq(pool.recipients(0), owner);
        assertEq(pool.recipients(1), agentWallet);
        assertEq(pool.amounts(0), ownerAmount);
        assertEq(pool.amounts(1), agentAmount);
        assertEq(pool.tokenName(), name);
        assertEq(pool.tokenSymbol(), symbol);
        assertEq(pool.owner(), owner);
        assertEq(pool.timeWindow(), timeWindow);

        assertEq(pool.hasLaunched(), false);
        assertEq(pool.launchPoolCreatedOn(), block.timestamp);
        assertEq(pool.totalDeposited(), 0);
        assertEq(pool.agentToken(), address(0));
        assertEq(pool.agentStaking(), address(0));

        return pool;
    }

    function _launch() internal returns (AgentLaunchPool) {
        address depositor = makeAddr("depositor");
        vm.deal(depositor, 1 ether);

        AgentLaunchPool pool = _deployLaunchPool();

        vm.startPrank(depositor);
        pool.depositETH{value: 1 ether}();

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        return pool;
    }

    function _getLiquidity(address tokenA, address tokenB) internal view returns (uint112 reserveA, uint112 reserveB, uint totalLiquidity) {
        address factory = IUniswapV2Router02(uniswapRouter).factory();
        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        require(pair != address(0), "Pair does not exist");

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        totalLiquidity = IUniswapV2Pair(pair).totalSupply();

        // Return correct reserve order based on token order
        (reserveA, reserveB) = tokenA < tokenB ? (reserve0, reserve1) : (reserve1, reserve0);
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
}
