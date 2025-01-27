// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {DeployAgentKey} from "../script/DeployAgentKey.s.sol";
import {IAgentKey} from "../src/IAgentKey.sol";
import {AgentKeyV2} from "../src/AgentKeyV2.sol";
import {AgentStaking} from "../src/AgentStaking.sol";
import {AirdropClaim} from "../src/AirdropClaim.sol";
import {GeckoV2Migrator} from "../src/GeckoV2Migrator.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract GeckoMigrationTest is Test {
    GeckoV2Migrator public migrator;

    IAgentKey public geckoV1;
    IERC20 public geckoV2;
    address control = makeAddr("control");
    address feeCollector = makeAddr("feeCollector");
    address user = makeAddr("user");
    address recipient = makeAddr("recipient");

    address agentCoinDao = makeAddr("agentCoinDao");
    address uniswapRouter;
    address agentWallet = makeAddr("agentWallet");
    uint256 agentAmount = 300_000 * 1e18;
    uint256 daoAmount = 700_000 * 1e18;
    uint256 airdropAmount = 2_500_000 * 1e18;
    uint256 poolAmount = 6_500_000 * 1e18;

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        DeployAgentKey keyDeployer = new DeployAgentKey();

        IAgentKey key;

        (key,) = keyDeployer.deploy(
            HelperConfig.AgentKeyConfig({
                name: "Agent keys",
                symbol: "KEY",
                priceIncrease: 0.0002 * 1e18,
                investmentReserveBasisPoints: 9000,
                feeBasisPoints: 5000,
                revenueCommitmentBasisPoints: 9500,
                beneficiary: payable(agentCoinDao),
                control: control,
                feeCollector: payable(feeCollector)
            })
        );

        uniswapRouter = vm.envAddress("BASE_UNISWAP_ROUTER");

        string memory name = "Gecko";
        string memory symbol = "GECKO";
        migrator = new GeckoV2Migrator(agentCoinDao, name, symbol, agentWallet, daoAmount, agentAmount, airdropAmount, poolAmount, address(key), uniswapRouter);

        geckoV1 = key;
    }

    function test_canMigrate() public {
        _migrate();
    }

    function test_forbidsMigratingMoreThanOnce() public {
        _migrate();

        vm.startPrank(agentCoinDao);        
        vm.expectRevert(GeckoV2Migrator.AlreadyMigrated.selector);
        migrator.migrate();
    }

    function test_forbidsNonOwnerFromMigrating() public {
        vm.startPrank(agentCoinDao);        
        geckoV1.stopAndTransferReserve(payable(address(migrator)));
        vm.stopPrank();

        vm.startPrank(makeAddr("anon"));

        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        migrator.migrate();
    }

    function test_canClaimV2TokensAfterMigration() public {
        _migrate();

        assertEq(geckoV2.balanceOf(user), 0);

        uint256 v1Balance = geckoV1.balanceOf(user);

        vm.startPrank(user);
        AirdropClaim airdrop = AirdropClaim(migrator.airdrop());
        airdrop.claim(user);

        assertEq(geckoV2.balanceOf(user), airdropAmount * v1Balance / geckoV1.totalSupply());
    }

    function test_multipleUsersCanClaimV2TokensAfterMigration() public {
        _migrate();

        address user2 = makeAddr("user2");

        assertEq(geckoV2.balanceOf(user), 0);
        assertEq(geckoV2.balanceOf(user2), 0);


        uint256 u1V1Balance = geckoV1.balanceOf(user);
        uint256 u2V1Balance = geckoV1.balanceOf(user2);

        vm.startPrank(user);
        AirdropClaim airdrop = AirdropClaim(migrator.airdrop());
        airdrop.claim(user);

        assertGt(geckoV2.balanceOf(user), 0);

        vm.startPrank(user2);
        airdrop.claim(user2);

        assertEq(geckoV2.balanceOf(user), airdropAmount * u1V1Balance / geckoV1.totalSupply());
        assertEq(geckoV2.balanceOf(user2), airdropAmount * u2V1Balance / geckoV1.totalSupply());
    }

    function test_nonHoldersClaimingV2TokensDontGetTokens() public {
        address otherUser = makeAddr("otherUser");

        _migrate();

        assertEq(geckoV2.balanceOf(otherUser), 0);

        vm.startPrank(otherUser);
        AirdropClaim airdrop = AirdropClaim(migrator.airdrop());
        airdrop.claim(otherUser);

        assertEq(geckoV2.balanceOf(otherUser), 0);
    }

    function test_canBuyV2TokensAfterMigration() public {
        _migrate();

        address user3 = makeAddr("user3");
        vm.deal(user3, 1 ether);

        assertEq(geckoV2.balanceOf(user3), 0);

        IUniswapV2Router02 router = IUniswapV2Router02(uniswapRouter);

        address[] memory path = new address[](2);
        path[0] = router.WETH();

        console.logAddress(path[0]);
        path[1] = address(geckoV2);

        uint256 amountOutMin = 0.6 ether;

        vm.startPrank(user3);
        router.swapExactETHForTokens{value: amountOutMin}(
            0,
            path,
            user3,
            block.timestamp
        );

        assertGt(geckoV2.balanceOf(user3), 0);
        assertEq(user3.balance, 0.4 ether);
    }

    function test_canSellV2TokensAfterMigration() public {
        _migrate();

        address user2 = makeAddr("user2");
        vm.deal(user2, 1 ether);

        IUniswapV2Router02 router = IUniswapV2Router02(uniswapRouter);

        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(geckoV2);

        uint256 amountIn = 1 ether;
        uint256 amountOutMin = 0.6 ether;

        geckoV2.approve(address(router), amountIn);

        vm.startPrank(user2);
        router.swapExactETHForTokens{value: amountOutMin}(
            0,
            path,
            user2,
            block.timestamp
        );

        assertGt(geckoV2.balanceOf(user2), 0);
        assertEq(user2.balance, 0.4 ether);

        uint256 tokenBalance = geckoV2.balanceOf(user2);

        geckoV2.approve(uniswapRouter, tokenBalance);

        path[0] = address(geckoV2);
        path[1] = router.WETH();

        router.swapExactTokensForETH(
            tokenBalance,
            0,
            path,
            user2,
            block.timestamp
        );

        assertEq(geckoV2.balanceOf(user2), 0);
        assertGt(user2.balance, 0.99 ether);
    }

    function _migrate() internal {
        address user2 = makeAddr("user2");

        uint256 user1V1Amount = _buyV1Tokens(user, 1 ether);
        uint256 user2V1Amount = _buyV1Tokens(user2, 2 ether);
        
        assertEq(geckoV1.totalSupply(), user1V1Amount + user2V1Amount);
        assertEq(geckoV1.balanceOf(user), user1V1Amount);
        assertEq(geckoV1.balanceOf(user2), user2V1Amount);

        uint256 curveReserve = address(geckoV1).balance;

        vm.startPrank(agentCoinDao);        
        geckoV1.stopAndTransferReserve(payable(address(migrator)));

        migrator.migrate();

        assertEq(geckoV1.isStopped(), true);
        assertEq(migrator.hasMigrated(), true);
    
        assertNotEq(migrator.geckoV2(), address(0));
        assertNotEq(migrator.airdrop(), address(0));

        geckoV2 = IERC20(migrator.geckoV2());
        assertEq(geckoV2.totalSupply(), daoAmount + agentAmount + poolAmount + airdropAmount);
        assertEq(geckoV2.balanceOf(agentCoinDao), daoAmount);
        assertEq(geckoV2.balanceOf(agentWallet), agentAmount);
        assertEq(geckoV2.balanceOf(migrator.airdrop()), airdropAmount);

        assertEq(geckoV2.balanceOf(user), 0);
        assertEq(geckoV2.balanceOf(user2), 0);

        (uint112 reserveA, uint112 reserveB, uint totalLiquidity) = _getLiquidity(address(geckoV2), IUniswapV2Router02(uniswapRouter).WETH());
        assertEq(reserveA, poolAmount);
        assertEq(reserveB, curveReserve);
        assertGt(totalLiquidity, 0);
    }

    function _getLiquidity(address tokenA, address tokenB) internal view returns (uint112 reserveA, uint112 reserveB, uint totalLiquidity) {
        address factory = IUniswapV2Router02(uniswapRouter).factory();
        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);
        require(pair != address(0), "Pair does not exist");

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        uint totalSupply = IUniswapV2Pair(pair).totalSupply();

        // Return correct reserve order based on token order
        (reserveA, reserveB) = tokenA < tokenB ? (reserve0, reserve1) : (reserve1, reserve0);
        totalLiquidity = totalSupply;
    }

    function _buyV1Tokens(address account, uint256 amountInEth) internal returns(uint256) {
        vm.deal(account, amountInEth);

        vm.startPrank(account);

        uint256 minBuyAmount = geckoV1.estimateBuyValue(amountInEth);
        assertGt(minBuyAmount, 0);

        geckoV1.buy{value: amountInEth}(account, amountInEth, minBuyAmount);

        assertGt(geckoV1.balanceOf(account), 0);

        return geckoV1.balanceOf(account);
    }

    function _deployAgentKey(address _owner) internal returns(address) {
        string memory name = "AgentKey";
        string memory symbol = "KEY";

        AgentKeyV2 implementation = new AgentKeyV2();

        address[] memory recipients = new address[](1);
        recipients[0] = _owner;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10_000_000;

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation), abi.encodeCall(AgentKeyV2.initialize, (name, symbol, _owner, recipients, amounts))
        );

        return address(proxy);
    }
}
