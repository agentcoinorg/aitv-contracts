// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPositionManager} from '@uniswap/v4-periphery/src/interfaces/IPositionManager.sol';
import {IPoolManager} from '@uniswap/v4-core/src/interfaces/IPoolManager.sol';
import {Currency} from '@uniswap/v4-core/src/types/Currency.sol';
import {Hooks, IHooks} from '@uniswap/v4-core/src/libraries/Hooks.sol';
import {PoolId} from '@uniswap/v4-core/src/types/PoolId.sol';
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

import {AgentFactoryTestUtils} from "../helpers/AgentFactoryTestUtils.sol";
import {AgentUniswapHook} from "../../src/AgentUniswapHook.sol";
import {AgentLaunchPool} from "../../src/AgentLaunchPool.sol";
import {UniswapFeeInfo} from "../../src/types/UniswapFeeInfo.sol";
import {MockedERC20} from "../helpers/MockedERC20.sol";
import {LaunchPoolProposal} from "../../src/types/LaunchPoolProposal.sol";
import {UniswapPoolDeployer} from "../../src/UniswapPoolDeployer.sol";

contract AgentLaunchPoolUniswapWithETHCollateralTest is AgentFactoryTestUtils, UniswapPoolDeployer {
    
    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        _deployDefaultContracts();
    }

    function test_canBuyTokensExactInputAfterLaunch() public { 
        address user = makeAddr("user");
        vm.deal(user, 10000 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(0));

        vm.prank(user);
        pool.depositETH{value: 1000 ether}();

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        IERC20 agent = IERC20(pool.agentToken());

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 1000 ether);
        
        assertEq(buyer.balance, 1000 ether);
        assertEq(agent.balanceOf(buyer), 0);

        _swapETHForERC20(buyer, poolKey, 1 ether);

        assertGt(agent.balanceOf(buyer), 0);
        assertEq(buyer.balance, 1000 ether - 1 ether);
    }

    function test_canBuyTokensExactOutputAfterLaunch() public { 
    }

    function test_canSellTokensExactInputAfterLaunch() public { 
        address user = makeAddr("user");
        vm.deal(user, 10000 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(0));

        vm.prank(user);
        pool.depositETH{value: 1000 ether}();

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        pool.claim(user);

        IERC20 agent = IERC20(pool.agentToken());

        uint256 userEtherBalance = user.balance;
        uint256 userAgentTokenBalance = agent.balanceOf(user);

        _swapERC20ForETH(user, poolKey, userAgentTokenBalance);

        assertGt(user.balance, userEtherBalance);
        assertEq(agent.balanceOf(user), 0);

        address anon = makeAddr("anon");
        vm.deal(anon, 1000 ether);

        uint256 anonEtherBalance = anon.balance;
        uint256 anonAgentTokenBalance = agent.balanceOf(anon);
        
        assertEq(anonEtherBalance, 1000 ether);
        assertEq(anonAgentTokenBalance, 0);

        _swapETHForERC20(anon, poolKey, 1 ether);

        uint256 lastAnonAgentTokenBalance = agent.balanceOf(anon);

        assertGt(lastAnonAgentTokenBalance, 0);
        assertEq(anon.balance, anonEtherBalance - 1 ether);

        _swapERC20ForETH(anon, poolKey, lastAnonAgentTokenBalance);

        assertGt(anon.balance, anonEtherBalance - 1 ether);
        assertEq(agent.balanceOf(anon), 0);
    }

    function test_canSellTokensExactOutputAfterLaunch() public { 
    }

    function test_feeRecipientsReceiveFees() public returns(AgentLaunchPool, PoolKey memory) { 
        address user = makeAddr("user");
        vm.deal(user, 10000 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(0));

        vm.prank(user);
        pool.depositETH{value: 1000 ether}();

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        pool.claim(user);

        IERC20 agent = IERC20(pool.agentToken());

        uint256 daoEtherBalance = dao.balance;
        uint256 daoAgentTokenBalance = agent.balanceOf(dao);
        
        uint256 agentEtherBalance = agentWallet.balance;
        uint256 agentAgentTokenBalance = agent.balanceOf(agentWallet);
        
        address buyer = makeAddr("buyer");
        vm.deal(buyer, 1000 ether);

        _swapETHForERC20(buyer, poolKey, 2 ether);

        assertGt(dao.balance, daoEtherBalance);
        assertEq(dao.balance, daoEtherBalance + 2 ether * daoFeeBasisAmount / 1e4);
        assertEq(agent.balanceOf(dao), daoAgentTokenBalance);

        assertGt(agentWallet.balance, agentEtherBalance);
        assertEq(agentWallet.balance, agentEtherBalance + 2 ether * agentWalletFeeBasisAmount / 1e4);
        assertEq(agent.balanceOf(agentWallet), agentAgentTokenBalance);

        return (pool, poolKey);
    }

    function test_agentTokenIsPartiallyBurnedOnSell() public { 
        address user = makeAddr("user");
        vm.deal(user, 10000 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(0));

        vm.prank(user);
        pool.depositETH{value: 1000 ether}();

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        pool.claim(user);

        IERC20 agent = IERC20(pool.agentToken());

        uint256 userAgentTokenBalance = agent.balanceOf(user);
        uint256 totalAgentSupply = agent.totalSupply();

        _swapERC20ForETH(user, poolKey, userAgentTokenBalance);

        assertLt(agent.totalSupply(), totalAgentSupply);
        assertEq(agent.totalSupply(), totalAgentSupply - userAgentTokenBalance * 1 / 100);
    }

    function test_canChangeBurnFeeAfterLaunch() public { 
        address user = makeAddr("user");
        vm.deal(user, 10000 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(0));

        vm.prank(user);
        pool.depositETH{value: 1000 ether}();

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        pool.claim(user);

        IERC20 agent = IERC20(pool.agentToken());

        uint256 initalAgentSupply = agent.totalSupply();

        uint256 userAgentTokenBalance = agent.balanceOf(user);
       
        _swapERC20ForETH(user, poolKey, userAgentTokenBalance / 10);

        assertLt(agent.totalSupply(), initalAgentSupply);
        assertEq(agent.totalSupply(), initalAgentSupply - userAgentTokenBalance / 10 * 1 / 100);

        UniswapFeeInfo memory fees = UniswapFeeInfo({
            collateral: address(0),
            burnBasisAmount: 200,
            recipients: new address[](0),
            basisAmounts: new uint256[](0)
        });

        vm.prank(owner);
        hook.setFeesForPair(address(0), address(agent), fees);

        _swapERC20ForETH(user, poolKey, userAgentTokenBalance / 10);

        assertLt(agent.totalSupply(), initalAgentSupply);
        assertEq(agent.totalSupply(), initalAgentSupply - userAgentTokenBalance / 10 * 3 / 100); // 1% + 2% fee
    }

    function test_canChangeFeesAfterLaunch() public { 
        address recipient1 = makeAddr("recipient1");
        address recipient2 = makeAddr("recipient2");

        (AgentLaunchPool pool, PoolKey memory poolKey) = test_feeRecipientsReceiveFees();

        IERC20 agent = IERC20(pool.agentToken());
       
        {
            UniswapFeeInfo memory fees;
            
            address[] memory recipients = new address[](2);
            recipients[0] = recipient1;
            recipients[1] = recipient2;

            uint256[] memory basisAmounts = new uint256[](2);
            basisAmounts[0] = 100;
            basisAmounts[1] = 200;

            fees = UniswapFeeInfo({
                collateral: address(0),
                burnBasisAmount: 100,
                recipients: recipients,
                basisAmounts: basisAmounts
            });

            vm.prank(owner);
            hook.setFeesForPair(address(0), address(agent), fees);
        }

        uint256 daoEtherBalance = dao.balance;
        uint256 daoAgentTokenBalance = agent.balanceOf(dao);
        
        uint256 agentEtherBalance = agentWallet.balance;
        uint256 agentAgentTokenBalance = agent.balanceOf(agentWallet);

        uint256 recipient1EtherBalance = recipient1.balance;
        uint256 recipient2EtherBalance = recipient2.balance;

        uint256 recipient1AgentTokenBalance = agent.balanceOf(recipient1);
        uint256 recipient2AgentTokenBalance = agent.balanceOf(recipient2);
        
        {
            address buyer = makeAddr("buyer");
            vm.deal(buyer, 1000 ether);

            _swapETHForERC20(buyer, poolKey, 2 ether);
        }

        assertEq(dao.balance, daoEtherBalance);
        assertEq(agent.balanceOf(dao), daoAgentTokenBalance);

        assertEq(agentWallet.balance, agentEtherBalance);
        assertEq(agent.balanceOf(agentWallet), agentAgentTokenBalance);

        assertGt(recipient1.balance, recipient1EtherBalance);
        assertEq(recipient1.balance, recipient1EtherBalance + 2 ether * 100 / 1e4);
        assertEq(agent.balanceOf(recipient1), recipient1AgentTokenBalance);

        assertGt(recipient2.balance, recipient2EtherBalance);
        assertEq(recipient2.balance, recipient2EtherBalance + 2 ether * 200 / 1e4);
        assertEq(agent.balanceOf(recipient2), recipient2AgentTokenBalance);
    }

    function test_forbidsNonOwnerFromChangingFees() public { 
        address user = makeAddr("user");
        vm.deal(user, 10000 ether);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));

        vm.prank(user);
        pool.depositETH{value: 1000 ether}();

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        pool.claim(user);

        IERC20 agent = IERC20(pool.agentToken());

        UniswapFeeInfo memory fees = UniswapFeeInfo({
            collateral: address(0),
            burnBasisAmount: 500,
            recipients: new address[](0),
            basisAmounts: new uint256[](0)
        });

        vm.prank(makeAddr("user"));
        vm.expectRevert(AgentUniswapHook.OnlyOwnerOrController.selector);
        hook.setFeesForPair(address(0), address(agent), fees);

        vm.prank(makeAddr("anon"));
        vm.expectRevert(AgentUniswapHook.OnlyOwnerOrController.selector);
        hook.setFeesForPair(address(0), address(agent), fees);
    }

    function test_forbidsUsingInvalidCollateralForFees() public { 
        address user = makeAddr("user");
        vm.deal(user, 10000 ether);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));

        vm.prank(user);
        pool.depositETH{value: 1000 ether}();

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        pool.claim(user);

        IERC20 agent = IERC20(pool.agentToken());

        UniswapFeeInfo memory fees = UniswapFeeInfo({
            collateral: address(1), // Invalid collateral
            burnBasisAmount: 500,
            recipients: new address[](0),
            basisAmounts: new uint256[](0)
        });

        vm.prank(owner);
        vm.expectRevert(AgentUniswapHook.InvalidCollateral.selector);
        hook.setFeesForPair(address(0), address(agent), fees);
    }

    function test_multipleAgentsCanUseSameUniswapHook() public {
        MockedERC20 collateral2 = new MockedERC20();

        vm.startPrank(owner);

        IERC20 agent1;
        IERC20 agent2;
        PoolKey memory poolKey1;
        PoolKey memory poolKey2;

        {
            LaunchPoolProposal memory proposal1 = _buildDefaultLaunchPoolProposal(address(0));
            LaunchPoolProposal memory proposal2 = _buildDefaultLaunchPoolProposal(address(collateral2));

            factory.addProposal(proposal1);
            factory.addProposal(proposal2);

            AgentLaunchPool pool1 = AgentLaunchPool(payable(factory.deployProposal(0)));
            AgentLaunchPool pool2 = AgentLaunchPool(payable(factory.deployProposal(1)));

            address user = makeAddr("user");
            vm.deal(user, 1 ether);
            collateral2.mint(user, 1e18);

            vm.startPrank(user);
            pool1.depositETH{value: 1 ether}();
            collateral2.approve(address(pool2), 1e18);
            pool2.depositERC20(1e18);

            vm.warp(block.timestamp + timeWindow);

            pool1.launch();
            pool2.launch();

            agent1 = IERC20(pool1.agentToken());
            agent2 = IERC20(pool2.agentToken());

            poolKey1 = _getPoolKey(pool1, proposal1);
            poolKey2 = _getPoolKey(pool2, proposal2);
        }

        uint256 daoCollateral1Balance = dao.balance;
        uint256 daoAgentToken1Balance = agent1.balanceOf(dao);
        
        uint256 daoCollateral2Balance = collateral2.balanceOf(dao);
        uint256 daoAgentToken2Balance = agent2.balanceOf(dao);

        address buyer = makeAddr("buyer");

        vm.deal(buyer, 10 ether);
        collateral2.mint(buyer, 10e18);

        _swapETHForERC20(buyer, poolKey1, 1 ether);
        _swapERC20ForERC20(buyer, poolKey2, 2e18, address(collateral2));
        
        assertGt(dao.balance, daoCollateral1Balance);
        assertEq(dao.balance, daoCollateral1Balance + 1 ether * daoFeeBasisAmount / 1e4);
        assertEq(agent1.balanceOf(dao), daoAgentToken1Balance);

        assertGt(collateral2.balanceOf(dao), daoCollateral2Balance);
        assertEq(collateral2.balanceOf(dao), daoCollateral2Balance + 2 ether * daoFeeBasisAmount / 1e4);
        assertEq(agent2.balanceOf(dao), daoAgentToken2Balance);
    }

    function test_forbidsAnyoneFromUsingUniswapHook() public { 
        MockedERC20 fakeAgent = new MockedERC20();
        
        address user = makeAddr("user");
        vm.deal(user, 100 ether);
        fakeAgent.mint(user, 100e18);

        uint160 sqrtPrice_1_1 = 79228162514264337593543950336;
        
        vm.startPrank(user);
        PoolInfo memory poolInfo = PoolInfo({
            poolManager: IPoolManager(uniswapPoolManager),
            positionManager: IPositionManager(uniswapPositionManager),
            collateral: address(0),
            agentToken: address(fakeAgent),
            collateralAmount: 10 ether,
            agentTokenAmount: 10e18,
            lpRecipient: user,
            lpFee: 0,
            tickSpacing: 200,
            startingPrice: sqrtPrice_1_1,
            hook: address(hook),
            permit2: permit2
        });

        PoolKey memory pool = PoolKey({
            currency0: Currency.wrap(poolInfo.collateral < poolInfo.agentToken ? poolInfo.collateral : poolInfo.agentToken),
            currency1: Currency.wrap(poolInfo.collateral < poolInfo.agentToken ? poolInfo.agentToken : poolInfo.collateral),
            fee: poolInfo.lpFee,
            tickSpacing: poolInfo.tickSpacing,
            hooks: IHooks(poolInfo.hook)
        });

        vm.expectRevert(); // Can't specify exact error because PoolManager wraps it
        poolInfo.poolManager.initialize(pool, poolInfo.startingPrice);
    }

    function test_defaultDeploymentPriceHigherAfterLaunch() public { 
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        vm.deal(user1, 1000 ether);
        vm.deal(user2, 1000 ether);
        vm.deal(user3, 1000 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(0));

        vm.prank(user1);
        pool.depositETH{value: 2 ether}();
        vm.prank(user2);
        pool.depositETH{value: 3 ether}();
        vm.prank(user3);
        pool.depositETH{value: 4 ether}();

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        IERC20 agent = IERC20(pool.agentToken());
      
        assertEq(agent.balanceOf(user1), 0);
        assertEq(agent.balanceOf(user2), 0);
        assertEq(agent.balanceOf(user3), 0);
      
        pool.claim(user1);
        pool.claim(user2);
        pool.claim(user3);

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 1 ether);

        assertEq(agent.balanceOf(buyer), 0);
       
        _swapETHForERC20(buyer, poolKey, 0.1 ether);

        assertGt(agent.balanceOf(user1), 0);
        assertGt(agent.balanceOf(user2), 0);
        assertGt(agent.balanceOf(user3), 0);

        // We calculate reverse prices because of integer division

        uint256 expectedReversePrice1 = agent.balanceOf(user1) / 2 ether;
        uint256 expectedReversePrice2 = agent.balanceOf(user2) / 3 ether;
        uint256 expectedReversePrice3 = agent.balanceOf(user3) / 4 ether;

        assertEq(expectedReversePrice1, expectedReversePrice2);
        assertEq(expectedReversePrice2, expectedReversePrice3);

        assertGt(agent.balanceOf(buyer), 0);

        uint256 buyerReversePrice = agent.balanceOf(buyer) / 0.1 ether;

        assertLt(buyerReversePrice, expectedReversePrice1); // Buyer reverse price will be lower, which means the actual buyer price is higher
        assertLt((expectedReversePrice1 - buyerReversePrice) * 100 / expectedReversePrice1, 10); // Assert there's less than 10% difference
    }

    function test_canAddLiquidityAfterLaunch() public { 
        address user = makeAddr("user");

        vm.deal(user, 100 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(0));

        vm.prank(user);
        pool.depositETH{value: 2 ether}();
     
        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        IERC20 agent = IERC20(pool.agentToken());
     
        address provider = makeAddr("provider");
        vm.deal(provider, 100 ether);

        _swapETHForERC20(provider, poolKey, 10 ether);

        vm.startPrank(provider);

        uint160 sqrtPrice_1_1 = 79228162514264337593543950336;

        uint256 amount0Max = 10 ether;
        uint256 amount1Max = 10000 * 1e18;

        console.log(provider.balance);
        console.log(agent.balanceOf(provider));

        uint256 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPrice_1_1,
            TickMath.getSqrtPriceAtTick(TickMath.minUsableTick(200)),
            TickMath.getSqrtPriceAtTick(TickMath.maxUsableTick(200)),
            amount0Max,
            amount1Max
        );

        bytes[] memory mintParams = new bytes[](2);

        mintParams[0] = abi.encode(
            poolKey,
            TickMath.getSqrtPriceAtTick(TickMath.minUsableTick(200)),
            TickMath.getSqrtPriceAtTick(TickMath.maxUsableTick(200)),
            liquidity,
            amount0Max,
            amount1Max,
            provider,
            ""
        );
        mintParams[1] = abi.encode(poolKey.currency0, poolKey.currency1);

        bytes memory actions = abi.encodePacked(uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR));

        agent.approve(address(permit2), type(uint256).max);
        IAllowanceTransfer(permit2).approve(
            address(agent),
            uniswapPositionManager,
            type(uint160).max,
            type(uint48).max
        );

        IPositionManager(uniswapPositionManager).modifyLiquidities{value: amount0Max}(abi.encode(actions, mintParams), block.timestamp);
    }

    function test_canRemoveLiquidityAfterLaunch() public { 
        fail();
    }

    function test_liquidityProviderReceivesNoFees() public { 
        fail();
    }
}

