// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";

import {AgentFactoryTestUtils} from "../helpers/AgentFactoryTestUtils.sol";
import {AgentLaunchPool} from "../../src/AgentLaunchPool.sol";
import {UniswapFeeInfo} from "../../src/types/UniswapFeeInfo.sol";
import {MockedERC20} from "../helpers/MockedERC20.sol";
import {UniswapPoolDeployer} from "../../src/UniswapPoolDeployer.sol";

contract AgentLaunchPoolUniswapWithERC20CollateralTest is AgentFactoryTestUtils, UniswapPoolDeployer {
    MockedERC20 collateral;
    
    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        _deployDefaultContracts();
   
        collateral = new MockedERC20();
    }

    function test_canBuyTokensExactInputAfterLaunch() public { 
        (, PoolKey memory poolKey, IERC20 agent) = _launch(makeAddr("depositor"));

        address buyer = makeAddr("buyer");
        collateral.mint(buyer, 2e18);
        
        assertEq(collateral.balanceOf(buyer), 2e18);
        assertEq(agent.balanceOf(buyer), 0);

        uint256 agentReceived = _swapERC20ForERC20ExactIn(buyer, poolKey, 1e18, address(collateral));

        assertGt(agentReceived, 0);
        assertEq(agent.balanceOf(buyer), agentReceived);
        assertEq(collateral.balanceOf(buyer), 2e18 - 1e18);
    }

    function test_canBuyTokensExactOutputAfterLaunch() public { 
        (, PoolKey memory poolKey, IERC20 agent) = _launch(makeAddr("depositor"));

        address buyer = makeAddr("buyer");
        collateral.mint(buyer, 10e18);
        
        assertEq(collateral.balanceOf(buyer), 10e18);
        assertEq(agent.balanceOf(buyer), 0);

        uint256 collateralSpent = _swapERC20ForERC20ExactOut(buyer, poolKey, 1e18, address(collateral));

        assertEq(agent.balanceOf(buyer), 1e18);
        assertEq(collateral.balanceOf(buyer), 10e18 - collateralSpent);
        assertGt(collateralSpent, 0);
        assertLt(collateralSpent, 10e18);
    }

    function test_canSellTokensExactInputAfterLaunch() public { 
        address depositor = makeAddr("depositor");
        
        (, PoolKey memory poolKey, IERC20 agent) = _launch(depositor);

        // Depositor can sell tokens

        uint256 depositorCollateralBalance = collateral.balanceOf(depositor);
        uint256 depositorAgentTokenBalance = agent.balanceOf(depositor);

        uint256 depositorCollateralReceived = _swapERC20ForERC20ExactIn(depositor, poolKey, depositorAgentTokenBalance, address(agent));

        assertGt(collateral.balanceOf(depositor), depositorCollateralBalance);
        assertEq(collateral.balanceOf(depositor), depositorCollateralBalance + depositorCollateralReceived);
        assertGt(depositorCollateralReceived, 0);
        assertEq(agent.balanceOf(depositor), 0);

        // Post launch buyer can sell tokens

        address anon = makeAddr("anon");
        collateral.mint(anon, 10e18);

        uint256 anonCollateralBalance = collateral.balanceOf(anon);
        uint256 anonAgentTokenBalance = agent.balanceOf(anon);
        
        assertEq(anonCollateralBalance, 10e18);
        assertEq(anonAgentTokenBalance, 0);

        // First buy so that anon has some agent tokens to sell
        uint256 anonAgentReceived = _swapERC20ForERC20ExactIn(anon, poolKey, 1e18, address(collateral));

        uint256 lastAnonCollateralBalance = collateral.balanceOf(anon);
        uint256 lastAnonAgentTokenBalance = agent.balanceOf(anon);

        assertGt(anonAgentReceived, 0);
        assertEq(lastAnonAgentTokenBalance, anonAgentReceived);
        assertEq(lastAnonCollateralBalance, anonCollateralBalance - 1e18);

        // Sell the agent tokens

        uint256 anonCollateralReceived = _swapERC20ForERC20ExactIn(anon, poolKey, lastAnonAgentTokenBalance, address(agent));

        assertGt(anonCollateralReceived, 0);
        assertEq(collateral.balanceOf(anon), lastAnonCollateralBalance + anonCollateralReceived);
        assertEq(agent.balanceOf(anon), 0);
    }

    function test_canSellTokensExactOutputAfterLaunch() public { 
        address depositor = makeAddr("depositor");
        
        (, PoolKey memory poolKey, IERC20 agent) = _launch(depositor);

        // Depositor can sell tokens

        uint256 depositorCollateralBalance = collateral.balanceOf(depositor);
        uint256 depositorAgentTokenBalance = agent.balanceOf(depositor);

        uint256 depositorAgentSpent = _swapERC20ForERC20ExactOut(depositor, poolKey, 1e18, address(agent));

        assertEq(collateral.balanceOf(depositor), depositorCollateralBalance + 1e18);
        assertGt(depositorAgentSpent, 0);
        assertEq(agent.balanceOf(depositor), depositorAgentTokenBalance - depositorAgentSpent);

        // Post launch buyer can sell tokens

        address anon = makeAddr("anon");
        collateral.mint(anon, 10e18);

        uint256 anonCollateralBalance = collateral.balanceOf(anon);
        uint256 anonAgentTokenBalance = agent.balanceOf(anon);
        
        assertEq(anonCollateralBalance, 10e18);
        assertEq(anonAgentTokenBalance, 0);

        // First buy so that anon has some agent tokens to sell
       
        uint256 anonAgentReceived = _swapERC20ForERC20ExactIn(anon, poolKey, 2e18, address(collateral));

        uint256 lastAnonCollateralBalance = collateral.balanceOf(anon);
        uint256 lastAnonAgentTokenBalance = agent.balanceOf(anon);

        assertGt(anonAgentReceived, 0);
        assertEq(lastAnonAgentTokenBalance, anonAgentReceived);
        assertEq(lastAnonCollateralBalance, anonCollateralBalance - 2e18);

        // Sell the agent tokens
       
        uint256 anonAgentSpent = _swapERC20ForERC20ExactOut(anon, poolKey, 1e18, address(agent));

        assertGt(anonAgentSpent, 0);
        assertEq(collateral.balanceOf(anon), lastAnonCollateralBalance + 1e18);
        assertEq(agent.balanceOf(anon), lastAnonAgentTokenBalance - anonAgentSpent);
    }

    function test_feeRecipientsReceiveFeesWhenBuyingAgentWithExactIn() public returns(AgentLaunchPool, PoolKey memory) { 
        (AgentLaunchPool pool, PoolKey memory poolKey, IERC20 agent) = _launch(makeAddr("depositor"));

        uint256 daoCollateralBalance = collateral.balanceOf(dao);
        uint256 daoAgentTokenBalance = agent.balanceOf(dao);
        
        uint256 agentCollateralBalance = collateral.balanceOf(agentWallet);
        uint256 agentAgentTokenBalance = agent.balanceOf(agentWallet);
        
        address buyer = makeAddr("buyer");
        collateral.mint(buyer, 10e18);

        uint256 totalSupply = agent.totalSupply();

        _swapERC20ForERC20ExactIn(buyer, poolKey, 2e18, address(collateral));

        // There should be no burning of agent in this scenario
        assertEq(agent.totalSupply(), totalSupply); 

        assertGt(collateral.balanceOf(dao), daoCollateralBalance);
        assertEq(collateral.balanceOf(dao), daoCollateralBalance + 2e18 * daoFeeBasisAmount / 1e4);
        assertEq(agent.balanceOf(dao), daoAgentTokenBalance);

        assertGt(collateral.balanceOf(agentWallet), agentCollateralBalance);
        assertEq(collateral.balanceOf(agentWallet), agentCollateralBalance + 2e18 * agentWalletFeeBasisAmount / 1e4);
        assertEq(agent.balanceOf(agentWallet), agentAgentTokenBalance);

        return (pool, poolKey);
    }

    function test_feeRecipientsReceiveFeesWhenSellingAgentWithExactOut() public returns(AgentLaunchPool, PoolKey memory) { 
        (AgentLaunchPool pool, PoolKey memory poolKey, IERC20 agent) = _launch(makeAddr("depositor"));
      
        address buyer = makeAddr("buyer");
        collateral.mint(buyer, 10e18);

        uint256 totalSupply1 = agent.totalSupply();

        _swapERC20ForERC20ExactIn(buyer, poolKey, 2e18, address(collateral));

        uint256 totalSupply2 = agent.totalSupply();
        // There should be no burning of agent in this scenario
        assertEq(totalSupply2, totalSupply1);
       
        uint256 daoCollateralBalance = collateral.balanceOf(dao);
        uint256 daoAgentTokenBalance = agent.balanceOf(dao);
        
        uint256 agentCollateralBalance = collateral.balanceOf(agentWallet);
        uint256 agentAgentTokenBalance = agent.balanceOf(agentWallet);

        _swapERC20ForERC20ExactOut(buyer, poolKey, 1e18, address(agent));

       // There should be no burning of agent in this scenario
        assertEq(agent.totalSupply(), totalSupply2);

        assertGt(collateral.balanceOf(dao), daoCollateralBalance);
        assertEq(collateral.balanceOf(dao), daoCollateralBalance + 1e18 * daoFeeBasisAmount / 1e4);
        assertEq(agent.balanceOf(dao), daoAgentTokenBalance);

        assertGt(collateral.balanceOf(agentWallet), agentCollateralBalance);
        assertEq(collateral.balanceOf(agentWallet), agentCollateralBalance + 1e18 * agentWalletFeeBasisAmount / 1e4);
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

        _swapERC20ForERC20ExactIn(depositor, poolKey, depositorAgentTokenBalance, address(agent));

        assertLt(agent.totalSupply(), totalAgentSupply);
        assertEq(agent.totalSupply(), totalAgentSupply - depositorAgentTokenBalance * burnBasisAmount / 1e4);

        // Post launch buyer, fees when selling

        address buyer = makeAddr("buyer");
        collateral.mint(buyer, 1e18);

        // Buy agent tokens so that buyer has some to sell

        _swapERC20ForERC20ExactIn(buyer, poolKey, 1e18, address(collateral));

        uint256 buyerAgentTokenBalance = agent.balanceOf(buyer);
        totalAgentSupply = agent.totalSupply();

        uint256 daoCollateralBalance = collateral.balanceOf(dao);
        uint256 daoAgentTokenBalance = agent.balanceOf(dao);
        uint256 agentCollateralBalance = collateral.balanceOf(agentWallet);
        uint256 agentAgentTokenBalance = agent.balanceOf(agentWallet);

        // Sell agent tokens

        _swapERC20ForERC20ExactIn(buyer, poolKey, buyerAgentTokenBalance, address(agent));

        assertLt(agent.totalSupply(), totalAgentSupply);
        assertEq(agent.totalSupply(), totalAgentSupply - buyerAgentTokenBalance * burnBasisAmount / 1e4);

        // There should be no fees
        assertEq(collateral.balanceOf(dao), daoCollateralBalance);
        assertEq(agent.balanceOf(dao), daoAgentTokenBalance);
        assertEq(collateral.balanceOf(agentWallet), agentCollateralBalance);
        assertEq(agent.balanceOf(agentWallet), agentAgentTokenBalance);
    }

    function test_agentTokenIsPartiallyBurnedWhenBuyingWithExactOut() public { 
        (, PoolKey memory poolKey, IERC20 agent) = _launch(makeAddr("depositor"));

        uint256 agentTokenAmountToBuy = 100e18;
        uint256 totalAgentSupply = agent.totalSupply();

        address buyer = makeAddr("buyer");
        collateral.mint(buyer, 1000e18);

        uint256 daoCollateralBalance = collateral.balanceOf(dao);
        uint256 daoAgentTokenBalance = agent.balanceOf(dao);
        uint256 agentCollateralBalance = collateral.balanceOf(agentWallet);
        uint256 agentAgentTokenBalance = agent.balanceOf(agentWallet);

        _swapERC20ForERC20ExactOut(buyer, poolKey, agentTokenAmountToBuy, address(collateral));

        assertLt(agent.totalSupply(), totalAgentSupply);
        assertEq(agent.totalSupply(), totalAgentSupply - agentTokenAmountToBuy * burnBasisAmount / 1e4);

        // There should be no fees
        assertEq(collateral.balanceOf(dao), daoCollateralBalance);
        assertEq(agent.balanceOf(dao), daoAgentTokenBalance);
        assertEq(collateral.balanceOf(agentWallet), agentCollateralBalance);
        assertEq(agent.balanceOf(agentWallet), agentAgentTokenBalance);
    }

    function test_canChangeBurnFeeAfterLaunch() public { 
        address depositor = makeAddr("depositor");

        (, PoolKey memory poolKey, IERC20 agent) = _launch(depositor);

        uint256 agentSupply1 = agent.totalSupply();

        uint256 depositorAgentTokenBalance = agent.balanceOf(depositor);
       
        // Inital burn for exact in

        _swapERC20ForERC20ExactIn(depositor, poolKey, depositorAgentTokenBalance / 10, address(agent));

        assertLt(agent.totalSupply(), agentSupply1);
        assertEq(agent.totalSupply(), agentSupply1 - depositorAgentTokenBalance / 10 * burnBasisAmount / 1e4);

        uint256 agentSupply2 = agent.totalSupply();

        address buyer = makeAddr("buyer");
        collateral.mint(buyer, 1e18);

        // Inital burn for exact out

        _swapERC20ForERC20ExactOut(buyer, poolKey, 10e18, address(collateral));

        assertLt(agent.totalSupply(), agentSupply2);
        assertEq(agent.totalSupply(), agentSupply2 - 10e18 * burnBasisAmount / 1e4);

        UniswapFeeInfo memory fees = UniswapFeeInfo({
            collateral: address(collateral),
            burnBasisAmount: 200,
            recipients: new address[](0),
            basisAmounts: new uint256[](0)
        });

        vm.prank(owner);
        hook.setFeesForPair(address(collateral), address(agent), fees);

        uint256 agentSupply3 = agent.totalSupply();
       
        // Changed burn exact in 

        _swapERC20ForERC20ExactIn(depositor, poolKey, 100e18, address(agent));

        assertLt(agent.totalSupply(), agentSupply3);
        assertEq(agent.totalSupply(), agentSupply3 - 100e18 * 200 / 1e4); 

        uint256 agentSupply4 = agent.totalSupply();

        // Changed burn exact out

        _swapERC20ForERC20ExactOut(buyer, poolKey, 20e18, address(collateral));

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
                collateral: address(collateral),
                burnBasisAmount: 100,
                recipients: recipients,
                basisAmounts: basisAmounts
            });

            vm.prank(owner);
            hook.setFeesForPair(address(collateral), address(agent), fees);
        }

        // Test exact in
        {
            uint256 daoCollateralBalance = collateral.balanceOf(dao);
            uint256 daoAgentTokenBalance = agent.balanceOf(dao);
            
            uint256 agentCollateralBalance = collateral.balanceOf(agentWallet);
            uint256 agentAgentTokenBalance = agent.balanceOf(agentWallet);

            uint256 recipient1CollateralBalance = collateral.balanceOf(recipient1);
            uint256 recipient2CollateralBalance = collateral.balanceOf(recipient2);

            uint256 recipient1AgentTokenBalance = agent.balanceOf(recipient1);
            uint256 recipient2AgentTokenBalance = agent.balanceOf(recipient2);
            
            {
                address buyer = makeAddr("buyer");
                collateral.mint(buyer, 1000 ether);

                _swapERC20ForERC20ExactIn(buyer, poolKey, 2e18, address(collateral));
            }

            assertEq(collateral.balanceOf(dao), daoCollateralBalance);
            assertEq(agent.balanceOf(dao), daoAgentTokenBalance);

            assertEq(collateral.balanceOf(agentWallet), agentCollateralBalance);
            assertEq(agent.balanceOf(agentWallet), agentAgentTokenBalance);

            assertGt(collateral.balanceOf(recipient1), recipient1CollateralBalance);
            assertEq(collateral.balanceOf(recipient1), recipient1CollateralBalance + 2e18 * 100 / 1e4);
            assertEq(agent.balanceOf(recipient1), recipient1AgentTokenBalance);

            assertGt(collateral.balanceOf(recipient2), recipient2CollateralBalance);
            assertEq(collateral.balanceOf(recipient2), recipient2CollateralBalance + 2e18 * 200 / 1e4);
            assertEq(agent.balanceOf(recipient2), recipient2AgentTokenBalance);
        }

        // Test exact out

        {
            uint256 daoCollateralBalance = collateral.balanceOf(dao);
            uint256 daoAgentTokenBalance = agent.balanceOf(dao);
            
            uint256 agentCollateralBalance = collateral.balanceOf(agentWallet);
            uint256 agentAgentTokenBalance = agent.balanceOf(agentWallet);

            uint256 recipient1CollateralBalance = collateral.balanceOf(recipient1);
            uint256 recipient2CollateralBalance = collateral.balanceOf(recipient2);

            uint256 recipient1AgentTokenBalance = agent.balanceOf(recipient1);
            uint256 recipient2AgentTokenBalance = agent.balanceOf(recipient2);
            
            {
                address buyer = makeAddr("buyer");
                collateral.mint(buyer, 1000 ether);

                _swapERC20ForERC20ExactOut(buyer, poolKey, 1e18, address(agent));
            }

            assertEq(collateral.balanceOf(dao), daoCollateralBalance);
            assertEq(agent.balanceOf(dao), daoAgentTokenBalance);

            assertEq(collateral.balanceOf(agentWallet), agentCollateralBalance);
            assertEq(agent.balanceOf(agentWallet), agentAgentTokenBalance);

            assertGt(collateral.balanceOf(recipient1), recipient1CollateralBalance);
            assertEq(collateral.balanceOf(recipient1), recipient1CollateralBalance + 1e18 * 100 / 1e4);
            assertEq(agent.balanceOf(recipient1), recipient1AgentTokenBalance);

            assertGt(collateral.balanceOf(recipient2), recipient2CollateralBalance);
            assertEq(collateral.balanceOf(recipient2), recipient2CollateralBalance + 1e18 * 200 / 1e4);
            assertEq(agent.balanceOf(recipient2), recipient2AgentTokenBalance);
        }
    }

    function test_priceHigherAfterLaunch() public { 
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        collateral.mint(user1, 10e18);
        collateral.mint(user2, 10e18);
        collateral.mint(user3, 10e18);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(collateral));

        vm.prank(user1);
        collateral.approve(address(pool), 2e18);
        vm.prank(user1);
        pool.depositERC20(2e18);

        vm.prank(user2);
        collateral.approve(address(pool), 3e18);
        vm.prank(user2);
        pool.depositERC20(3e18);

        vm.prank(user3);
        collateral.approve(address(pool), 4e18);
        vm.prank(user3);
        pool.depositERC20(4e18);

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
        collateral.mint(buyer, 1e18);

        assertEq(agent.balanceOf(buyer), 0);
       
        _swapERC20ForERC20ExactIn(buyer, poolKey, 0.1 * 1e18, address(collateral));

        assertGt(agent.balanceOf(user1), 0);
        assertGt(agent.balanceOf(user2), 0);
        assertGt(agent.balanceOf(user3), 0);

        // We calculate reverse prices because of integer division

        uint256 expectedReversePrice1 = agent.balanceOf(user1) / 2e18;
        uint256 expectedReversePrice2 = agent.balanceOf(user2) / 3 ether;
        uint256 expectedReversePrice3 = agent.balanceOf(user3) / 4 ether;

        assertEq(expectedReversePrice1, expectedReversePrice2);
        assertEq(expectedReversePrice2, expectedReversePrice3);

        assertGt(agent.balanceOf(buyer), 0);

        uint256 buyerReversePrice = agent.balanceOf(buyer) / (0.1 * 1e18);

        assertLt(buyerReversePrice, expectedReversePrice1); // Buyer reverse price will be lower, which means the actual buyer price is higher
        assertLt((expectedReversePrice1 - buyerReversePrice) * 100 / expectedReversePrice1, 10); // Assert there's less than 10% difference
    }

    function test_canAddLiquidityAfterLaunch() public { 
        (, PoolKey memory poolKey, IERC20 agent) = _launch(makeAddr("depositor"));

        address provider = makeAddr("provider");
        collateral.mint(provider, 100e18);

        _swapERC20ForERC20ExactIn(provider, poolKey, 10e18, address(collateral));

        uint256 startingCollateralBalance = collateral.balanceOf(provider);
        uint256 startingAgentBalance = agent.balanceOf(provider);

        uint256 amount0Max = 10e18;
        uint256 amount1Max = 10e18;

        ReservesAndLiquidity memory ral;

        (ral.reserveA, ral.reserveB, ral.totalLiquidity) = _getLiquidity(poolKey, address(collateral), 200);
        _mintLiquidityPosition(provider, poolKey, amount0Max, amount1Max, 200);

        assertLt(collateral.balanceOf(provider), startingCollateralBalance);
        assertGe(collateral.balanceOf(provider), startingCollateralBalance - amount0Max);
        assertLt(agent.balanceOf(provider), startingAgentBalance);
        assertGe(agent.balanceOf(provider), startingAgentBalance - amount1Max);

        (uint256 newReserveA, uint256 newReserveB, uint newTotalLiquidity) = _getLiquidity(poolKey, address(collateral), 200);

        assertGt(newReserveA, ral.reserveA);
        assertGt(newReserveB, ral.reserveB);
        assertGt(newTotalLiquidity, ral.totalLiquidity);
    }

    function test_canRemoveLiquidityAfterLaunch() public { 
        (, PoolKey memory poolKey,) = _launch(makeAddr("depositor"));

        address provider = makeAddr("provider");
        collateral.mint(provider, 100e18);

        _swapERC20ForERC20ExactIn(provider, poolKey, 10e18, address(collateral));

        uint256 amount0Max = 10e18;
        uint256 amount1Max = 100e18;

        ReservesAndLiquidity memory ral1;
        (ral1.reserveA, ral1.reserveB, ral1.totalLiquidity) = _getLiquidity(poolKey, address(collateral), 200);

        uint256 tokenId = _mintLiquidityPosition(provider, poolKey, amount0Max, amount1Max, 200);

        ReservesAndLiquidity memory ral2;
        (ral2.reserveA, ral2.reserveB, ral2.totalLiquidity) = _getLiquidity(poolKey, address(collateral), 200);

        PositionDetails memory info = _getPositionDetails(tokenId);

        bytes memory actions = abi.encodePacked(uint8(Actions.DECREASE_LIQUIDITY), uint8(Actions.TAKE_PAIR));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(tokenId, info.liquidity, uint128(info.amount0), uint128(info.amount1), "");
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1, provider);

        vm.prank(provider);
        IPositionManager(uniswapPositionManager).modifyLiquidities(abi.encode(actions, params), block.timestamp);

        ReservesAndLiquidity memory ral3;
        (ral3.reserveA, ral3.reserveB, ral3.totalLiquidity) = _getLiquidity(poolKey, address(collateral), 200);

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
        collateral.mint(provider, 100e18);

        _swapERC20ForERC20ExactIn(provider, poolKey, 10e18, address(collateral));

        uint256 amount0Max = 10e18;
        uint256 amount1Max = 10e18;

        uint256 tokenId = _mintLiquidityPosition(provider, poolKey, amount0Max, amount1Max, 200);

        uint256 providerBalance = collateral.balanceOf(provider);

        address buyer = makeAddr("buyer");
        collateral.mint(buyer, 1e18);

        _swapERC20ForERC20ExactIn(buyer, poolKey, 1e18, address(collateral));

        _collectLiquidityProviderFees(provider, tokenId, poolKey);

        assertEq(collateral.balanceOf(provider), providerBalance);
    }

    function test_liquidityProviderReceivesFeesWhenLPFeeSet() public { 
        lpFee = 500;

        (, PoolKey memory poolKey,) = _launch(makeAddr("depositor"));

        address provider = makeAddr("provider");
        collateral.mint(provider, 100e18);

        _swapERC20ForERC20ExactIn(provider, poolKey, 10e18, address(collateral));

        uint256 amount0Max = 10e18;
        uint256 amount1Max = 10e18;
        
        uint256 tokenId = _mintLiquidityPosition(provider, poolKey, amount0Max, amount1Max, 200);

        uint256 providerBalance = collateral.balanceOf(provider);

        address buyer = makeAddr("buyer");
        collateral.mint(buyer, 10e18);

        _swapERC20ForERC20ExactIn(buyer, poolKey, 10e18, address(collateral));

        _collectLiquidityProviderFees(provider, tokenId, poolKey);

        assertGt(collateral.balanceOf(provider), providerBalance);
    }

    function _launch(address depositor) internal returns(AgentLaunchPool, PoolKey memory, IERC20) {
        collateral.mint(depositor, 10e18);

        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(collateral));

        vm.startPrank(depositor);
        collateral.approve(address(pool), 10e18);
        pool.depositERC20(10e18);
        vm.stopPrank();

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

