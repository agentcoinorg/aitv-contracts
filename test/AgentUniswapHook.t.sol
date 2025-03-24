// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

import {AgentToken} from "../src/AgentToken.sol";
import {AgentLaunchPool} from "../src/AgentLaunchPool.sol";
import {UniswapFeeInfo} from "../src/types/UniswapFeeInfo.sol";
import {AgentFactory} from "../src/AgentFactory.sol";
import {AgentUniswapHook} from "../src/AgentUniswapHook.sol";
import {LaunchPoolProposal} from "../src/types/LaunchPoolProposal.sol";
import {AgentFactoryTestUtils} from "./helpers/AgentFactoryTestUtils.sol";
import {UniswapPoolDeployer} from "../src/UniswapPoolDeployer.sol";
import {MockedERC20} from "./helpers/MockedERC20.sol";

contract AgentUniswapHookTest is  AgentFactoryTestUtils, UniswapPoolDeployer {
    
    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        _deployDefaultContracts();
    }

    function test_ownerCanSetController() public {
        address newController = makeAddr("newController");

        assertNotEq(hook.controller(), newController);

        vm.prank(owner);
        hook.setController(newController);
    }

    function test_forbidsNonOwnerFromSettingController() public { 
        address newController = makeAddr("newController");

        assertNotEq(hook.controller(), newController);
        
        vm.startPrank(makeAddr("anyone"));

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, makeAddr("anyone")));
        hook.setController(newController);
    }

    function test_allowsOwnerAndControllToChangeFees() public {
        (,, IERC20 agent) = _launch(makeAddr("depositor"));

        UniswapFeeInfo memory fees1 = UniswapFeeInfo({
            collateral: address(0),
            burnBasisAmount: 500,
            recipients: new address[](0),
            basisAmounts: new uint256[](0)
        });

        vm.prank(owner);
        hook.setFeesForPair(address(0), address(agent), fees1);

        UniswapFeeInfo memory fees2 = UniswapFeeInfo({
            collateral: address(0),
            burnBasisAmount: 1000,
            recipients: new address[](0),
            basisAmounts: new uint256[](0)
        });

        vm.prank(owner);
        hook.setController(makeAddr("controller"));
    
        vm.prank(makeAddr("controller"));
        hook.setFeesForPair(address(0), address(agent), fees2);
    }

    function test_allowsOwnerAndControllToSetAuthorizedLaunchPool() public {
        address authorizedPool = makeAddr("authorizedPool");

        assertEq(hook.authorizedLaunchPools(authorizedPool), false);

        vm.prank(owner);
        hook.setAuthorizedLaunchPool(authorizedPool, true);

        assertEq(hook.authorizedLaunchPools(authorizedPool), true);

        vm.prank(owner);
        hook.setAuthorizedLaunchPool(authorizedPool, false);

        assertEq(hook.authorizedLaunchPools(authorizedPool), false);

        vm.prank(owner);
        hook.setController(makeAddr("controller"));
    
        vm.prank(makeAddr("controller"));
        hook.setAuthorizedLaunchPool(authorizedPool, true);

        assertEq(hook.authorizedLaunchPools(authorizedPool), true);
    }

    function test_forbidsNonOwnerNonControllerFromSettingAuthorizedLaunchPool() public { 
        address authorizedPool = makeAddr("authorizedPool");

        assertEq(hook.authorizedLaunchPools(authorizedPool), false);

        vm.prank(makeAddr("depositor"));
        vm.expectRevert(AgentUniswapHook.OnlyOwnerOrController.selector);
        hook.setAuthorizedLaunchPool(authorizedPool, true);

        assertEq(hook.authorizedLaunchPools(authorizedPool), false);

        vm.prank(makeAddr("anon"));
        vm.expectRevert(AgentUniswapHook.OnlyOwnerOrController.selector);
        hook.setAuthorizedLaunchPool(authorizedPool, true);

        assertEq(hook.authorizedLaunchPools(authorizedPool), false);
    }

    function test_forbidsNonOwnerNonControllerFromChangingFees() public { 
        (,, IERC20 agent) = _launch(makeAddr("depositor"));

        UniswapFeeInfo memory fees = UniswapFeeInfo({
            collateral: address(0),
            burnBasisAmount: 500,
            recipients: new address[](0),
            basisAmounts: new uint256[](0)
        });

        vm.prank(makeAddr("depositor"));
        vm.expectRevert(AgentUniswapHook.OnlyOwnerOrController.selector);
        hook.setFeesForPair(address(0), address(agent), fees);

        vm.prank(makeAddr("anon"));
        vm.expectRevert(AgentUniswapHook.OnlyOwnerOrController.selector);
        hook.setFeesForPair(address(0), address(agent), fees);
    }

    function test_forbidsUsingInvalidCollateralForFees() public { 
        (,, IERC20 agent) = _launch(makeAddr("depositor"));

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

        _swapETHForERC20ExactIn(buyer, poolKey1, 1 ether);
        _swapERC20ForERC20ExactIn(buyer, poolKey2, 2e18, address(collateral2));
        
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

    function test_canTransferOwnership() public {
        assertEq(hook.owner(), owner);

        vm.prank(owner);
        hook.transferOwnership(makeAddr("newOwner"));

        assertEq(hook.owner(), owner);
       
        vm.prank(makeAddr("newOwner"));
        hook.acceptOwnership();

        assertEq(hook.owner(), makeAddr("newOwner"));
    }

    function test_forbidsNonOwnerFromTransferringOwnership() public {
        vm.expectPartialRevert(OwnableUpgradeable.OwnableUnauthorizedAccount.selector);
        hook.transferOwnership(makeAddr("newOwner"));

        vm.prank(makeAddr("anyone"));
        vm.expectPartialRevert(OwnableUpgradeable.OwnableUnauthorizedAccount.selector);
        hook.transferOwnership(makeAddr("newOwner"));

        assertEq(hook.owner(), owner);
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
