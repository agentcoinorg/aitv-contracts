// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

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
    uint256 agentCoinDaoAmount = 1_000_000;
    uint256 airdropAmount = 1_000_000;
    uint256 poolAmount = 8_000_000;

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

        migrator = new GeckoV2Migrator(agentCoinDao, agentCoinDaoAmount, airdropAmount, poolAmount, address(key), uniswapRouter);

        geckoV1 = key;
    }

    function test_canMigrate() public {
        _migrate();
    }

    function test_canClaimV2TokensAfterMigration() public {
        _migrate();

        assertEq(geckoV2.balanceOf(user), 0);

        vm.startPrank(user);
        AirdropClaim airdrop = AirdropClaim(migrator.airdrop());
        airdrop.claim(user);

        assertGt(geckoV2.balanceOf(user), 0);
    }

    function test_canBuyV2TokensAfterMigration() public {
        _migrate();

        address user2 = makeAddr("user2");
        vm.deal(user2, 1 ether);

        assertEq(geckoV2.balanceOf(user), 0);

        IUniswapV2Router02 router = IUniswapV2Router02(uniswapRouter);

        address[] memory path = new address[](2);
        path[0] = router.WETH();

        console.logAddress(path[0]);
        path[1] = address(geckoV2);

        uint256 amountOutMin = 0.01 ether;

        vm.startPrank(user2);
        router.swapExactETHForTokens{value: amountOutMin}(
            0,
            path,
            user2,
            block.timestamp
        );

        assertGt(geckoV2.balanceOf(user2), 0);
    }

    function _migrate() internal {
        _buyV1Tokens();
        
        assertGt(geckoV1.totalSupply(), 0);
        assertGt(geckoV1.balanceOf(user), 0);

        vm.startPrank(agentCoinDao);        
        geckoV1.stopAndTransferReserve(payable(address(migrator)));
        migrator.migrate();

        assertEq(geckoV1.isStopped(), true);
        assertEq(migrator.hasMigrated(), true);
    
        assertNotEq(migrator.geckoV2(), address(0));
        assertNotEq(migrator.airdrop(), address(0));

        geckoV2 = IERC20(migrator.geckoV2());
        assertGt(geckoV2.totalSupply(), 0);

        AirdropClaim airdrop = AirdropClaim(migrator.airdrop());
        assertEq(geckoV2.balanceOf(address(airdrop)), airdropAmount);

        assertEq(geckoV2.balanceOf(user), 0);

        (uint112 reserveA, uint112 reserveB, uint totalLiquidity) = _getLiquidity(address(geckoV2), IUniswapV2Router02(uniswapRouter).WETH());
        assertGt(reserveA, 0);
        assertGt(reserveB, 0);
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

    function _buyV1Tokens() internal {
        uint256 amountToSpend = 10 ether;

        vm.deal(user, amountToSpend);

        vm.startPrank(user);

        uint256 minBuyAmount = geckoV1.estimateBuyValue(amountToSpend);
        assertGt(minBuyAmount, 0);

        geckoV1.buy{value: amountToSpend}(user, amountToSpend, minBuyAmount);
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
