// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

import {AgentFactoryTestUtils} from "../helpers/AgentFactoryTestUtils.sol";
import {AgentLaunchPool} from "../../src/AgentLaunchPool.sol";
import {UniswapFeeInfo} from "../../src/types/UniswapFeeInfo.sol";

contract AgentLaunchPoolUniswapWithETHCollateralTest is AgentFactoryTestUtils {
    
    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        _deployDefaultContracts();
    }

    function test_canBuyTokensExactInputAfterLaunch() public { 
        (, PoolKey memory poolKey, IERC20 agent) = _launch(makeAddr("depositor"));

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 2 ether);
        
        assertEq(buyer.balance, 2 ether);
        assertEq(agent.balanceOf(buyer), 0);

        uint256 agentReceived = _swapETHForERC20ExactIn(buyer, poolKey, 1 ether);

        assertGt(agentReceived, 0);
        assertEq(agent.balanceOf(buyer), agentReceived);
        assertEq(buyer.balance, 2 ether - 1 ether);
    }

    function test_canBuyTokensExactOutputAfterLaunch() public { 
        (, PoolKey memory poolKey, IERC20 agent) = _launch(makeAddr("depositor"));

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 10 ether);
        
        assertEq(buyer.balance, 10 ether);
        assertEq(agent.balanceOf(buyer), 0);

        uint256 collateralSpent = _swapETHForERC20ExactOut(buyer, poolKey, 1e18);

        assertEq(agent.balanceOf(buyer), 1e18);
        assertEq(buyer.balance, 10 ether - collateralSpent);
        assertGt(collateralSpent, 0);
        assertLt(collateralSpent, 10 ether);
    }

    function test_canSellTokensExactInputAfterLaunch() public { 
        address depositor = makeAddr("depositor");
        
        (, PoolKey memory poolKey, IERC20 agent) = _launch(depositor);

        // Depositor can sell tokens

        uint256 depositorCollateralBalance = depositor.balance;
        uint256 depositorAgentTokenBalance = agent.balanceOf(depositor);

        uint256 depositorCollateralReceived = _swapERC20ForETHExactIn(depositor, poolKey, depositorAgentTokenBalance);

        assertGt(depositor.balance, depositorCollateralBalance);
        assertEq(depositor.balance, depositorCollateralBalance + depositorCollateralReceived);
        assertGt(depositorCollateralReceived, 0);
        assertEq(agent.balanceOf(depositor), 0);

        // Post launch buyer can sell tokens

        address anon = makeAddr("anon");
        vm.deal(anon, 10 ether);

        uint256 anonCollateralBalance = anon.balance;
        uint256 anonAgentTokenBalance = agent.balanceOf(anon);
        
        assertEq(anonCollateralBalance, 10 ether);
        assertEq(anonAgentTokenBalance, 0);

        // First buy so that anon has some agent tokens to sell
        uint256 anonAgentReceived = _swapETHForERC20ExactIn(anon, poolKey, 1 ether);

        uint256 lastAnonCollateralBalance = anon.balance;
        uint256 lastAnonAgentTokenBalance = agent.balanceOf(anon);

        assertGt(anonAgentReceived, 0);
        assertEq(lastAnonAgentTokenBalance, anonAgentReceived);
        assertEq(lastAnonCollateralBalance, anonCollateralBalance - 1 ether);

        // Sell the agent tokens

        uint256 anonCollateralReceived = _swapERC20ForETHExactIn(anon, poolKey, lastAnonAgentTokenBalance);

        assertGt(anonCollateralReceived, 0);
        assertEq(anon.balance, lastAnonCollateralBalance + anonCollateralReceived);
        assertEq(agent.balanceOf(anon), 0);
    }

    function test_canSellTokensExactOutputAfterLaunch() public { 
        address depositor = makeAddr("depositor");
        
        (, PoolKey memory poolKey, IERC20 agent) = _launch(depositor);

        // Depositor can sell tokens

        uint256 depositorCollateralBalance = depositor.balance;
        uint256 depositorAgentTokenBalance = agent.balanceOf(depositor);

        uint256 depositorAgentSpent = _swapERC20ForETHExactOut(depositor, poolKey, 1 ether);

        assertEq(depositor.balance, depositorCollateralBalance + 1 ether);
        assertGt(depositorAgentSpent, 0);
        assertEq(agent.balanceOf(depositor), depositorAgentTokenBalance - depositorAgentSpent);

        // Post launch buyer can sell tokens

        address anon = makeAddr("anon");
        vm.deal(anon, 10 ether);

        uint256 anonCollateralBalance = anon.balance;
        uint256 anonAgentTokenBalance = agent.balanceOf(anon);
        
        assertEq(anonCollateralBalance, 10 ether);
        assertEq(anonAgentTokenBalance, 0);

        // First buy so that anon has some agent tokens to sell
       
        uint256 anonAgentReceived = _swapETHForERC20ExactIn(anon, poolKey, 2 ether);

        uint256 lastAnonCollateralBalance = anon.balance;
        uint256 lastAnonAgentTokenBalance = agent.balanceOf(anon);

        assertGt(anonAgentReceived, 0);
        assertEq(lastAnonAgentTokenBalance, anonAgentReceived);
        assertEq(lastAnonCollateralBalance, anonCollateralBalance - 2 ether);

        // Sell the agent tokens
       
        uint256 anonAgentSpent = _swapERC20ForETHExactOut(anon, poolKey, 1 ether);

        assertGt(anonAgentSpent, 0);
        assertEq(anon.balance, lastAnonCollateralBalance + 1 ether);
        assertEq(agent.balanceOf(anon), lastAnonAgentTokenBalance - anonAgentSpent);
    }

    function test_feeRecipientsReceiveFeesWhenBuyingAgentWithExactIn() public returns(AgentLaunchPool, PoolKey memory) { 
        (AgentLaunchPool pool, PoolKey memory poolKey, IERC20 agent) = _launch(makeAddr("depositor"));

        uint256 daoCollateralBalance = dao.balance;
        uint256 daoAgentTokenBalance = agent.balanceOf(dao);
        
        uint256 agentCollateralBalance = agentWallet.balance;
        uint256 agentAgentTokenBalance = agent.balanceOf(agentWallet);
        
        address buyer = makeAddr("buyer");
        vm.deal(buyer, 10 ether);

        uint256 totalSupply = agent.totalSupply();

        _swapETHForERC20ExactIn(buyer, poolKey, 2 ether);

        // There should be no burning of agent in this scenario
        assertEq(agent.totalSupply(), totalSupply); 

        assertGt(dao.balance, daoCollateralBalance);
        assertEq(dao.balance, daoCollateralBalance + 2 ether * daoFeeBasisAmount / 1e4);
        assertEq(agent.balanceOf(dao), daoAgentTokenBalance);

        assertGt(agentWallet.balance, agentCollateralBalance);
        assertEq(agentWallet.balance, agentCollateralBalance + 2 ether * agentWalletFeeBasisAmount / 1e4);
        assertEq(agent.balanceOf(agentWallet), agentAgentTokenBalance);

        return (pool, poolKey);
    }

    function test_feeRecipientsReceiveFeesWhenSellingAgentWithExactOut() public returns(AgentLaunchPool, PoolKey memory) { 
        (AgentLaunchPool pool, PoolKey memory poolKey, IERC20 agent) = _launch(makeAddr("depositor"));
      
        address buyer = makeAddr("buyer");
        vm.deal(buyer, 10 ether);

        uint256 totalSupply1 = agent.totalSupply();

        _swapETHForERC20ExactIn(buyer, poolKey, 2 ether);

        uint256 totalSupply2 = agent.totalSupply();
        // There should be no burning of agent in this scenario
        assertEq(totalSupply2, totalSupply1);
       
        uint256 daoCollateralBalance = dao.balance;
        uint256 daoAgentTokenBalance = agent.balanceOf(dao);
        
        uint256 agentCollateralBalance = agentWallet.balance;
        uint256 agentAgentTokenBalance = agent.balanceOf(agentWallet);

        _swapERC20ForETHExactOut(buyer, poolKey, 1 ether);

       // There should be no burning of agent in this scenario
        assertEq(agent.totalSupply(), totalSupply2);

        assertGt(dao.balance, daoCollateralBalance);
        assertEq(dao.balance, daoCollateralBalance + 1 ether * daoFeeBasisAmount / 1e4);
        assertEq(agent.balanceOf(dao), daoAgentTokenBalance);

        assertGt(agentWallet.balance, agentCollateralBalance);
        assertEq(agentWallet.balance, agentCollateralBalance + 1 ether * agentWalletFeeBasisAmount / 1e4);
        assertEq(agent.balanceOf(agentWallet), agentAgentTokenBalance);

        return (pool, poolKey);
    }

    function test_agentTokenIsPartiallyBurnedWhenSellingWithExactIn() public { 
        address depositor = makeAddr("depositor");

        (, PoolKey memory poolKey, IERC20 agent) = _launch(depositor);

        // Depositor fees when selling

        uint256 depositorAgentTokenBalance = agent.balanceOf(depositor);
        uint256 totalAgentSupply = agent.totalSupply();

        assertGt(depositorAgentTokenBalance, 0);

        _swapERC20ForETHExactIn(depositor, poolKey, depositorAgentTokenBalance);

        assertLt(agent.totalSupply(), totalAgentSupply);
        assertEq(agent.totalSupply(), totalAgentSupply - depositorAgentTokenBalance * burnBasisAmount / 1e4);

        // Post launch buyer, fees when selling

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 1 ether);

        // Buy agent tokens so that buyer has some to sell

        _swapETHForERC20ExactIn(buyer, poolKey, 1 ether);

        uint256 buyerAgentTokenBalance = agent.balanceOf(buyer);
        totalAgentSupply = agent.totalSupply();

        uint256 daoCollateralBalance = dao.balance;
        uint256 daoAgentTokenBalance = agent.balanceOf(dao);
        uint256 agentCollateralBalance = agentWallet.balance;
        uint256 agentAgentTokenBalance = agent.balanceOf(agentWallet);

        // Sell agent tokens

        _swapERC20ForETHExactIn(buyer, poolKey, buyerAgentTokenBalance);

        assertLt(agent.totalSupply(), totalAgentSupply);
        assertEq(agent.totalSupply(), totalAgentSupply - buyerAgentTokenBalance * burnBasisAmount / 1e4);

        // There should be no fees
        assertEq(dao.balance, daoCollateralBalance);
        assertEq(agent.balanceOf(dao), daoAgentTokenBalance);
        assertEq(agentWallet.balance, agentCollateralBalance);
        assertEq(agent.balanceOf(agentWallet), agentAgentTokenBalance);
    }

    function test_agentTokenIsPartiallyBurnedWhenBuyingWithExactOut() public { 
        (, PoolKey memory poolKey, IERC20 agent) = _launch(makeAddr("depositor"));

        uint256 agentTokenAmountToBuy = 100e18;
        uint256 totalAgentSupply = agent.totalSupply();

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 1 ether);

        uint256 daoCollateralBalance = dao.balance;
        uint256 daoAgentTokenBalance = agent.balanceOf(dao);
        uint256 agentCollateralBalance = agentWallet.balance;
        uint256 agentAgentTokenBalance = agent.balanceOf(agentWallet);

        _swapETHForERC20ExactOut(buyer, poolKey, agentTokenAmountToBuy);

        assertLt(agent.totalSupply(), totalAgentSupply);
        assertEq(agent.totalSupply(), totalAgentSupply - agentTokenAmountToBuy * burnBasisAmount / 1e4);

        // There should be no fees
        assertEq(dao.balance, daoCollateralBalance);
        assertEq(agent.balanceOf(dao), daoAgentTokenBalance);
        assertEq(agentWallet.balance, agentCollateralBalance);
        assertEq(agent.balanceOf(agentWallet), agentAgentTokenBalance);
    }

    function test_canChangeBurnFeeAfterLaunch() public { 
        address depositor = makeAddr("depositor");

        (, PoolKey memory poolKey, IERC20 agent) = _launch(depositor);

        uint256 agentSupply1 = agent.totalSupply();

        uint256 depositorAgentTokenBalance = agent.balanceOf(depositor);
       
        // Inital burn for exact in

        _swapERC20ForETHExactIn(depositor, poolKey, depositorAgentTokenBalance / 10);

        assertLt(agent.totalSupply(), agentSupply1);
        assertEq(agent.totalSupply(), agentSupply1 - depositorAgentTokenBalance / 10 * burnBasisAmount / 1e4);

        uint256 agentSupply2 = agent.totalSupply();

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 1 ether);

        // Inital burn for exact out

        _swapETHForERC20ExactOut(buyer, poolKey, 10e18);

        assertLt(agent.totalSupply(), agentSupply2);
        assertEq(agent.totalSupply(), agentSupply2 - 10e18 * burnBasisAmount / 1e4);

        UniswapFeeInfo memory fees = UniswapFeeInfo({
            collateral: address(0),
            burnBasisAmount: 200,
            recipients: new address[](0),
            basisAmounts: new uint256[](0)
        });

        vm.prank(owner);
        hook.setFeesForPair(address(0), address(agent), fees);

        uint256 agentSupply3 = agent.totalSupply();
       
        // Changed burn exact in 

        _swapERC20ForETHExactIn(depositor, poolKey, depositorAgentTokenBalance / 10);

        assertLt(agent.totalSupply(), agentSupply3);
        assertEq(agent.totalSupply(), agentSupply3 - depositorAgentTokenBalance / 10 * 200 / 1e4); 

        uint256 agentSupply4 = agent.totalSupply();

        // Changed burn exact out

        _swapETHForERC20ExactOut(buyer, poolKey, 20e18);

        assertLt(agent.totalSupply(), agentSupply4);
        assertEq(agent.totalSupply(), agentSupply4 - 20e18 * 200 / 1e4);
    }

    function test_canChangeFeesAfterLaunch() public { 
        address recipient1 = makeAddr("recipient1");
        address recipient2 = makeAddr("recipient2");

        (AgentLaunchPool pool, PoolKey memory poolKey) = test_feeRecipientsReceiveFeesWhenBuyingAgentWithExactIn();

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

        // Test exact in
        {
            uint256 daoCollateralBalance = dao.balance;
            uint256 daoAgentTokenBalance = agent.balanceOf(dao);
            
            uint256 agentCollateralBalance = agentWallet.balance;
            uint256 agentAgentTokenBalance = agent.balanceOf(agentWallet);

            uint256 recipient1CollateralBalance = recipient1.balance;
            uint256 recipient2CollateralBalance = recipient2.balance;

            uint256 recipient1AgentTokenBalance = agent.balanceOf(recipient1);
            uint256 recipient2AgentTokenBalance = agent.balanceOf(recipient2);
            
            {
                address buyer = makeAddr("buyer");
                vm.deal(buyer, 1000 ether);

                _swapETHForERC20ExactIn(buyer, poolKey, 2 ether);
            }

            assertEq(dao.balance, daoCollateralBalance);
            assertEq(agent.balanceOf(dao), daoAgentTokenBalance);

            assertEq(agentWallet.balance, agentCollateralBalance);
            assertEq(agent.balanceOf(agentWallet), agentAgentTokenBalance);

            assertGt(recipient1.balance, recipient1CollateralBalance);
            assertEq(recipient1.balance, recipient1CollateralBalance + 2 ether * 100 / 1e4);
            assertEq(agent.balanceOf(recipient1), recipient1AgentTokenBalance);

            assertGt(recipient2.balance, recipient2CollateralBalance);
            assertEq(recipient2.balance, recipient2CollateralBalance + 2 ether * 200 / 1e4);
            assertEq(agent.balanceOf(recipient2), recipient2AgentTokenBalance);
        }

        // Test exact out

        {
            uint256 daoCollateralBalance = dao.balance;
            uint256 daoAgentTokenBalance = agent.balanceOf(dao);
            
            uint256 agentCollateralBalance = agentWallet.balance;
            uint256 agentAgentTokenBalance = agent.balanceOf(agentWallet);

            uint256 recipient1CollateralBalance = recipient1.balance;
            uint256 recipient2CollateralBalance = recipient2.balance;

            uint256 recipient1AgentTokenBalance = agent.balanceOf(recipient1);
            uint256 recipient2AgentTokenBalance = agent.balanceOf(recipient2);
            
            {
                address buyer = makeAddr("buyer");
                vm.deal(buyer, 1000 ether);

                _swapERC20ForETHExactOut(buyer, poolKey, 1 ether);
            }

            assertEq(dao.balance, daoCollateralBalance);
            assertEq(agent.balanceOf(dao), daoAgentTokenBalance);

            assertEq(agentWallet.balance, agentCollateralBalance);
            assertEq(agent.balanceOf(agentWallet), agentAgentTokenBalance);

            assertGt(recipient1.balance, recipient1CollateralBalance);
            assertEq(recipient1.balance, recipient1CollateralBalance + 1 ether * 100 / 1e4);
            assertEq(agent.balanceOf(recipient1), recipient1AgentTokenBalance);

            assertGt(recipient2.balance, recipient2CollateralBalance);
            assertEq(recipient2.balance, recipient2CollateralBalance + 1 ether * 200 / 1e4);
            assertEq(agent.balanceOf(recipient2), recipient2AgentTokenBalance);
        }
    }

    function test_priceHigherAfterLaunch() public { 
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
        vm.deal(user3, 10 ether);

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
       
        _swapETHForERC20ExactIn(buyer, poolKey, 0.1 ether);

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
        (, PoolKey memory poolKey, IERC20 agent) = _launch(makeAddr("depositor"));

        address provider = makeAddr("provider");
        vm.deal(provider, 100 ether);

        _swapETHForERC20ExactIn(provider, poolKey, 10 ether);

        uint256 startingCollateralBalance = provider.balance;
        uint256 startingAgentBalance = agent.balanceOf(provider);

        uint256 amount0Max = 10 ether;
        uint256 amount1Max = 10 * 1e18;

        ReservesAndLiquidity memory ral;

        (ral.reserveA, ral.reserveB, ral.totalLiquidity) = _getLiquidity(poolKey, address(0), 200);
        _mintLiquidityPosition(provider, poolKey, amount0Max, amount1Max, 200);

        assertLt(provider.balance, startingCollateralBalance);
        assertGe(provider.balance, startingCollateralBalance - amount0Max);
        assertLt(agent.balanceOf(provider), startingAgentBalance);
        assertGe(agent.balanceOf(provider), startingAgentBalance - amount1Max);

        (uint256 newReserveA, uint256 newReserveB, uint newTotalLiquidity) = _getLiquidity(poolKey, address(0), 200);

        assertGt(newReserveA, ral.reserveA);
        assertGt(newReserveB, ral.reserveB);
        assertGt(newTotalLiquidity, ral.totalLiquidity);
    }

    function test_canRemoveLiquidityAfterLaunch() public { 
        (, PoolKey memory poolKey,) = _launch(makeAddr("depositor"));

        address provider = makeAddr("provider");
        vm.deal(provider, 100 ether);

        _swapETHForERC20ExactIn(provider, poolKey, 10 ether);

        uint256 amount0Max = 10 ether;
        uint256 amount1Max = 100e18;

        ReservesAndLiquidity memory ral1;
        (ral1.reserveA, ral1.reserveB, ral1.totalLiquidity) = _getLiquidity(poolKey, address(0), 200);

        uint256 tokenId = _mintLiquidityPosition(provider, poolKey, amount0Max, amount1Max, 200);

        ReservesAndLiquidity memory ral2;
        (ral2.reserveA, ral2.reserveB, ral2.totalLiquidity) = _getLiquidity(poolKey, address(0), 200);

        PositionDetails memory info = _getPositionDetails(tokenId);

        bytes memory actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(tokenId, info.liquidity, uint128(info.amount0), uint128(info.amount1), "");
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1, provider);

        vm.prank(provider);
        IPositionManager(uniswapPositionManager).modifyLiquidities(abi.encode(actions, params), block.timestamp);

        ReservesAndLiquidity memory ral3;
        (ral3.reserveA, ral3.reserveB, ral3.totalLiquidity) = _getLiquidity(poolKey, address(0), 200);

        assertGt(ral2.reserveA, ral1.reserveA);
        assertGt(ral2.reserveB, ral1.reserveB);
        assertGt(ral2.totalLiquidity, ral1.totalLiquidity);

        assertEq(ral3.reserveA, ral1.reserveA);
        assertEq(ral3.reserveB, ral1.reserveB);
        assertEq(ral3.totalLiquidity, ral1.totalLiquidity);
    }

    function test_liquidityProviderReceivesNoFeesWhenNoLPFeeSet() public { 
        (, PoolKey memory poolKey,) = _launch(makeAddr("depositor"));

        address provider = makeAddr("provider");
        vm.deal(provider, 100 ether);

        _swapETHForERC20ExactIn(provider, poolKey, 10 ether);

        uint256 amount0Max = 10 ether;
        uint256 amount1Max = 10e18;

        uint256 tokenId = _mintLiquidityPosition(provider, poolKey, amount0Max, amount1Max, 200);

        uint256 providerBalance = provider.balance;

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 1 ether);

        _swapETHForERC20ExactIn(buyer, poolKey, 1 ether);

        _collectLiquidityProviderFees(provider, tokenId, poolKey);

        assertEq(provider.balance, providerBalance);
    }

    function test_liquidityProviderReceivesFeesWhenLPFeeSet() public { 
        lpFee = 500;

        (, PoolKey memory poolKey,) = _launch(makeAddr("depositor"));

        address provider = makeAddr("provider");
        vm.deal(provider, 100 ether);

        _swapETHForERC20ExactIn(provider, poolKey, 10 ether);

        uint256 amount0Max = 10 ether;
        uint256 amount1Max = 10e18;
        
        uint256 tokenId = _mintLiquidityPosition(provider, poolKey, amount0Max, amount1Max, 200);

        uint256 providerBalance = provider.balance;

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 10 ether);

        _swapETHForERC20ExactIn(buyer, poolKey, 10 ether);

        _collectLiquidityProviderFees(provider, tokenId, poolKey);

        assertGt(provider.balance, providerBalance);
    }

    function _launch(address depositor) internal returns(AgentLaunchPool, PoolKey memory, IERC20) {
        vm.deal(depositor, 10 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(0));

        vm.prank(depositor);
        pool.depositETH{value: 10 ether}();

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        pool.claim(depositor);

        IERC20 agent = IERC20(pool.agentToken());

        return (pool, poolKey, agent);
    }
}

struct ReservesAndLiquidity {
    uint256 reserveA;
    uint256 reserveB;
    uint256 totalLiquidity;
}

