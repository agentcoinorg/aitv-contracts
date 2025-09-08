// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniversalRouter} from "@uniswap/universal-router/src/interfaces/IUniversalRouter.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IHooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

import {AgentLaunchPool} from "../src/AgentLaunchPool.sol";
import {AgentFactory} from "../src/AgentFactory.sol";
import {AgentFactoryTestUtils} from "./helpers/AgentFactoryTestUtils.sol";
import {TokenDistributor, Action, ActionType} from "../src/TokenDistributor.sol";
import {MockedERC20} from "./helpers/MockedERC20.sol";
import {UniswapVersion} from "../src/types/UniswapVersion.sol";
import {CallArgType, Swap, DistributionRequest} from "../src/TokenDistributor.sol";
import {PoolConfig} from "../src/types/PoolConfig.sol";
import {DistributionBuilder} from "../src/DistributionBuilder.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
}

contract TokenDistributorTest is AgentFactoryTestUtils {
    TokenDistributor distributor;
    address usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address usdt = 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2;
    address ussi = 0x3a46ed8FCeb6eF1ADA2E4600A522AE7e24D2Ed18;

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        _deployDefaultContracts();

        distributor = new TokenDistributor(
            owner,
            IUniversalRouter(uniswapUniversalRouter),
            IPermit2(permit2),
            weth
        );
    }

    function test_anyoneCanAddDistribution() public {
        Action[] memory actions = new DistributionBuilder()
            .send(10000, makeAddr("recipient"))
            .build();

        vm.prank(makeAddr("user1"));
        uint256 distId1 = distributor.addDistribution(actions);
        assertEq(distId1, 1);

        vm.prank(makeAddr("user2"));
        uint256 distId2 = distributor.addDistribution(actions);
        assertEq(distId2, 2);
    }

    function test_forbidsAddingDistributionWithUnallocatedFunds() public {
        Action[] memory actions = new DistributionBuilder()
            .send(5000, makeAddr("recipient1"))
            .send(2000, makeAddr("recipient2"))
            .build();

        vm.prank(makeAddr("user"));
        vm.expectPartialRevert(TokenDistributor.BasisPointsMustSumTo10000.selector);
        distributor.addDistribution(actions);
    }

    function test_forbidsAddingDistributionWithInvalidActions() public {
        vm.startPrank(makeAddr("user"));

        Action[] memory actions = new Action[](1);

        actions[0] = Action({
            actionType: ActionType.Buy,
            basisPoints: 5000,
            recipient: address(makeAddr("recipient")),
            token: address(makeAddr("some-token")),
            distributionId: 0,
            selector: bytes4(0),
            callArgsPacked: bytes12(0)
        });
        vm.expectPartialRevert(TokenDistributor.BasisPointsMustSumTo10000.selector);
        distributor.addDistribution(actions);

        actions[0] = Action({
            actionType: ActionType.Send,
            basisPoints: 10000,
            recipient: address(makeAddr("recipient")),
            token: address(makeAddr("some-token")),
            distributionId: 0,
            selector: bytes4(0),
            callArgsPacked: bytes12(0)
        });
        vm.expectPartialRevert(TokenDistributor.InvalidActionDefinition.selector);
        distributor.addDistribution(actions);

        actions[0] = Action({
            actionType: ActionType.Buy,
            basisPoints: 10000,
            recipient: address(makeAddr("recipient")),
            token: address(0),
            distributionId: 1,
            selector: bytes4(0),
            callArgsPacked: bytes12(0)
        });
        vm.expectPartialRevert(TokenDistributor.InvalidActionDefinition.selector);
        distributor.addDistribution(actions);

        actions[0] = Action({
            actionType: ActionType.Buy,
            basisPoints: 10000,
            recipient: address(makeAddr("recipient")),
            token: address(makeAddr("some-token")),
            distributionId: 1,
            selector: bytes4(0),
            callArgsPacked: bytes12(0)
        });
        vm.expectPartialRevert(TokenDistributor.InvalidActionDefinition.selector);
        distributor.addDistribution(actions);
    }

    function test_anyoneCanProposePoolConfig() public {
        vm.prank(makeAddr("anon"));
        uint256 configId = distributor.proposePoolConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(weth),
                    currency1: Currency.wrap(usdc),
                    fee: 50,
                    tickSpacing: 200,
                    hooks: IHooks(address(1337))
                }),
                version: UniswapVersion.V4
            })
        );

        PoolConfig memory poolConfig = distributor.getPoolConfigProposal(configId);
        assertEq(Currency.unwrap(poolConfig.poolKey.currency0), weth);
        assertEq(Currency.unwrap(poolConfig.poolKey.currency1), usdc);
        assertEq(poolConfig.poolKey.fee, 50);
        assertEq(address(poolConfig.poolKey.hooks), address(1337));
        assertEq(poolConfig.poolKey.tickSpacing, 200);
        assertEq(uint8(poolConfig.version), uint8(UniswapVersion.V4));
    }

    function test_canSetPoolConfig() public {
        uint256 configId = distributor.proposePoolConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(weth),
                    currency1: Currency.wrap(usdc),
                    fee: 50,
                    tickSpacing: 200,
                    hooks: IHooks(address(1337))
                }),
                version: UniswapVersion.V4
            })
        );

        vm.prank(owner);
        distributor.setPoolConfig(configId);
        PoolConfig memory poolConfig = distributor.getPoolConfig(weth, usdc);
        assertEq(Currency.unwrap(poolConfig.poolKey.currency0), weth);
        assertEq(Currency.unwrap(poolConfig.poolKey.currency1), usdc);
        assertEq(poolConfig.poolKey.fee, 50);
        assertEq(address(poolConfig.poolKey.hooks), address(1337));
        assertEq(poolConfig.poolKey.tickSpacing, 200);
        assertEq(uint8(poolConfig.version), uint8(UniswapVersion.V4));
    }

    function test_canOverridePoolConfig() public {
        uint256 configId1 = distributor.proposePoolConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(weth),
                    currency1: Currency.wrap(usdc),
                    fee: 50,
                    tickSpacing: 200,
                    hooks: IHooks(address(1337))
                }),
                version: UniswapVersion.V4
            })
        );
        uint256 configId2 = distributor.proposePoolConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(weth),
                    currency1: Currency.wrap(usdc),
                    fee: 50,
                    tickSpacing: 0,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V3
            })
        );

        vm.startPrank(owner);
        distributor.setPoolConfig(configId1);
        distributor.setPoolConfig(configId2);
        PoolConfig memory poolConfig = distributor.getPoolConfig(weth, usdc);
        assertEq(Currency.unwrap(poolConfig.poolKey.currency0), weth);
        assertEq(Currency.unwrap(poolConfig.poolKey.currency1), usdc);
        assertEq(poolConfig.poolKey.fee, 50);
        assertEq(address(poolConfig.poolKey.hooks), address(0));
        assertEq(poolConfig.poolKey.tickSpacing, 0);
        assertEq(uint8(poolConfig.version), uint8(UniswapVersion.V3));
    }

    function test_canSetMultiplePoolConfigs() public {
        vm.startPrank(owner);
        _addConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(weth),
                    currency1: Currency.wrap(usdc),
                    fee: 0,
                    tickSpacing: 0,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V2
            })
        );
       _addConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(address(0)),
                    currency1: Currency.wrap(usdc),
                    fee: 150,
                    tickSpacing: 100,
                    hooks: IHooks(address(1337))
                }),
                version: UniswapVersion.V4
            })
        );
        PoolConfig memory poolConfig1 = distributor.getPoolConfig(weth, usdc);
        assertEq(Currency.unwrap(poolConfig1.poolKey.currency0), weth);
        assertEq(Currency.unwrap(poolConfig1.poolKey.currency1), usdc);
        assertEq(poolConfig1.poolKey.fee, 0);
        assertEq(address(poolConfig1.poolKey.hooks), address(0));
        assertEq(poolConfig1.poolKey.tickSpacing, 0);
        assertEq(uint8(poolConfig1.version), uint(UniswapVersion.V2));

        PoolConfig memory poolConfig2 = distributor.getPoolConfig(address(0), usdc);
        assertEq(Currency.unwrap(poolConfig2.poolKey.currency0), address(0));
        assertEq(Currency.unwrap(poolConfig2.poolKey.currency1), usdc);
        assertEq(poolConfig2.poolKey.fee, 150);
        assertEq(address(poolConfig2.poolKey.hooks), address(1337));
        assertEq(poolConfig2.poolKey.tickSpacing, 100);
        assertEq(uint8(poolConfig2.version), uint(UniswapVersion.V4));
    }

    function test_onlyOwnerCanSetPoolConfig() public {
        uint256 configId = distributor.proposePoolConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(weth),
                    currency1: Currency.wrap(usdc),
                    fee: 0,
                    tickSpacing: 0,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V2
            })
        );

        vm.prank(owner);
        distributor.setPoolConfig(configId);

        vm.prank(makeAddr("user"));
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        distributor.setPoolConfig(configId);
    }

    function test_canSetDistributionId() public {
        vm.startPrank(owner);
        Action[] memory actions = new Action[](1);

        actions[0] = Action({
            actionType: ActionType.Send,
            basisPoints: 10000,
            recipient: address(makeAddr("recipient")),
            token: address(0),
            distributionId: 0,
            selector: bytes4(0),
            callArgsPacked: bytes12(0)
        });
        uint256 distId = distributor.addDistribution(actions);

        distributor.setDistributionId("test", distId);
    }

    function test_onlyOwnerCanSetDistributionId() public {
        Action[] memory actions = new Action[](1);

        actions[0] = Action({
            actionType: ActionType.Send,
            basisPoints: 10000,
            recipient: address(makeAddr("recipient")),
            token: address(0),
            distributionId: 0,
            selector: bytes4(0),
            callArgsPacked: bytes12(0)
        });

        vm.prank(owner);
        uint256 distId = distributor.addDistribution(actions);

        vm.prank(makeAddr("user"));
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        distributor.setDistributionId("test", distId);
    }

    function test_canSendETH() public {
        address recipient = makeAddr("recipient");

        vm.startPrank(owner);

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .send(10000, recipient)
                .build()
        );
        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        uint256 amount = 0.3 ether;
        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        vm.prank(user);
        _distributeETH("test", user, address(0), _buildMockMinAmountsOut(1), block.timestamp, amount);

        assertEq(user.balance, 0.7 ether);
        assertEq(recipient.balance, amount);
        assertEq(address(distributor).balance, 0);
    }

    function test_forbidsETHDistributionAfterDeadline() public {
        address recipient = makeAddr("recipient");

        vm.startPrank(owner);

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .send(10000, recipient)
                .build()
        );
        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        uint256 amount = 0.3 ether;
        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        vm.prank(user);
        vm.expectPartialRevert(TokenDistributor.DeadlinePassed.selector);
        _distributeETH("test", user, address(0), _buildMockMinAmountsOut(1), block.timestamp - 1, amount);
    }

    function test_canExecuteSameDistributionMultipleTimes() public {
        address recipient = makeAddr("recipient");

        vm.startPrank(owner);

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .send(10000, recipient)
                .build()
        );
        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        uint256 amount = 0.3 ether;
        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        vm.prank(user);
        _distributeETH("test", user, address(0), _buildMockMinAmountsOut(1), block.timestamp, amount);

        assertEq(user.balance, 0.7 ether);
        assertEq(recipient.balance, amount);
        assertEq(address(distributor).balance, 0);

        vm.prank(user);
        _distributeETH("test", user, address(0), _buildMockMinAmountsOut(1), block.timestamp, amount);

        assertEq(user.balance, 0.4 ether);
        assertEq(recipient.balance, amount * 2);
        assertEq(address(distributor).balance, 0);
    }

    function test_canExecuteMultipleDistributions() public {
        address recipient1 = makeAddr("recipient1");
        address recipient2 = makeAddr("recipient2");

        vm.startPrank(owner);

        distributor.setDistributionId(
            "test1", 
            distributor.addDistribution(
                new DistributionBuilder()
                    .send(10000, recipient1)
                    .build()
            )
        );

        distributor.setDistributionId(
            "test2", 
            distributor.addDistribution(
                new DistributionBuilder()
                    .send(10000, recipient2)
                    .build()
            )
        );

        vm.stopPrank();

        uint256 amount = 0.3 ether;
        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        vm.prank(user);
        _distributeETH("test1", user, address(0), _buildMockMinAmountsOut(1), block.timestamp, amount);

        assertEq(user.balance, 0.7 ether);
        assertEq(recipient1.balance, amount);
        assertEq(address(distributor).balance, 0);

        vm.prank(user);
        _distributeETH("test2", user, address(0), _buildMockMinAmountsOut(1), block.timestamp, amount);

        assertEq(user.balance, 0.4 ether);
        assertEq(recipient2.balance, amount);
        assertEq(address(distributor).balance, 0);
    }

    function test_canSendETHToBeneficiary() public {
        vm.startPrank(owner);

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .send(10000, address(0))
                .build()
        );
        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        uint256 amount = 0.3 ether;
        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        vm.prank(user);
        _distributeETH("test", user, address(0), _buildMockMinAmountsOut(1), block.timestamp, amount);

        assertEq(user.balance, 1 ether);
        assertEq(address(distributor).balance, 0);
    }

    function test_canSendERC20() public {
        address recipient = makeAddr("recipient");

        vm.startPrank(owner);

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .send(10000, recipient)
                .build()
        );
        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        uint256 amount = 0.3 * 1e18;
        MockedERC20 erc20 = new MockedERC20();
        address user = makeAddr("user");
        erc20.mint(user, 1e18);

        vm.startPrank(user);
        erc20.approve(address(distributor), amount);
        _distributeERC20("test", user, amount, address(erc20), address(0), _buildMockMinAmountsOut(1), block.timestamp);

        assertEq(erc20.balanceOf(user), 0.7 * 1e18);
        assertEq(erc20.balanceOf(recipient), amount);
        assertEq(erc20.balanceOf(address(distributor)), 0);
    }

    function test_forbidsERC20DistributionAfterDeadline() public {
        address recipient = makeAddr("recipient");

        vm.startPrank(owner);

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .send(10000, recipient)
                .build()
        );
        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        uint256 amount = 0.3 * 1e18;
        MockedERC20 erc20 = new MockedERC20();
        address user = makeAddr("user");
        erc20.mint(user, 1e18);

        vm.startPrank(user);
        erc20.approve(address(distributor), amount);

        vm.expectPartialRevert(TokenDistributor.DeadlinePassed.selector);
        _distributeERC20("test", user, amount, address(erc20), address(0), _buildMockMinAmountsOut(1), block.timestamp - 1);
    }

    function test_canSendERC20ToBeneficiary() public {
        vm.startPrank(owner);

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .send(10000, address(0))
                .build()
        );
        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        uint256 amount = 0.3 * 1e18;
        MockedERC20 erc20 = new MockedERC20();
        address user = makeAddr("user");
        erc20.mint(user, 1e18);

        vm.startPrank(user);
        erc20.approve(address(distributor), amount);
        _distributeERC20("test", user, amount, address(erc20), address(0), _buildMockMinAmountsOut(1), block.timestamp);

        assertEq(erc20.balanceOf(user), 1e18);
        assertEq(erc20.balanceOf(address(distributor)), 0);
    }

    function test_canSplitETH() public {
        address recipient1 = makeAddr("recipient1");
        address recipient2 = makeAddr("recipient2");

        vm.startPrank(owner);

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .send(7000, recipient1)
                .send(3000, recipient2)
                .build()
        );
        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        uint256 amount = 1 ether;
        address user = makeAddr("user");
        vm.deal(user, 1.1 ether);

        vm.prank(user);
        _distributeETH("test", user, address(0), _buildMockMinAmountsOut(1), block.timestamp, amount);

        assertEq(user.balance, 0.1 ether);
        assertEq(recipient1.balance, amount * 7000 / 10000);
        assertEq(recipient2.balance, amount * 3000 / 10000);
        assertEq(address(distributor).balance, 0);
    }

    function test_canSplitERC20() public {
        address recipient1 = makeAddr("recipient1");
        address recipient2 = makeAddr("recipient2");

        vm.startPrank(owner);

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .send(7000, recipient1)
                .send(3000, recipient2)
                .build()
        );
        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        uint256 amount = 1 * 1e18;
        MockedERC20 erc20 = new MockedERC20();
        address user = makeAddr("user");
        erc20.mint(user, 1.1 * 1e18);

        vm.startPrank(user);
        erc20.approve(address(distributor), amount);
        _distributeERC20("test", user, amount, address(erc20), address(0), _buildMockMinAmountsOut(1), block.timestamp);

        assertEq(erc20.balanceOf(user), 0.1 * 1e18);
        assertEq(erc20.balanceOf(recipient1), amount * 7000 / 10000);
        assertEq(erc20.balanceOf(recipient2), amount * 3000 / 10000);
        assertEq(erc20.balanceOf(address(distributor)), 0);
    }

    function test_canBurnERC20Burnable() public {
        vm.startPrank(owner);

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .burn(10000)
                .build()
        );
        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        uint256 amount = 0.1 * 1e18;
        MockedERC20 erc20 = new MockedERC20();
        address user = makeAddr("user");
        erc20.mint(user, 1e18);

        assertEq(erc20.balanceOf(user), 1e18);
        assertEq(erc20.totalSupply(), 1e18);

        vm.startPrank(user);
        erc20.approve(address(distributor), amount);
        _distributeERC20("test", user, amount, address(erc20), address(0), _buildMockMinAmountsOut(1), block.timestamp);

        assertEq(erc20.balanceOf(user), 0.9 * 1e18);
        assertEq(erc20.totalSupply(), 0.9 * 1e18);
        assertEq(erc20.balanceOf(address(distributor)), 0);
    }

    function test_canSwapETHToWETH() public {
        address recipient = makeAddr("recipient");

        vm.startPrank(owner);

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .buy(10000, weth, recipient)
                .build()
        );
        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        uint256 amount = 0.4 ether;
        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        vm.prank(user);
        _distributeETH("test", user, address(0), _buildMockMinAmountsOut(1), block.timestamp, amount);

        assertEq(IERC20(weth).balanceOf(recipient), 0.4 * 1e18);
        assertEq(user.balance, 0.6 ether);
        assertEq(address(distributor).balance, 0);
        assertEq(IERC20(weth).balanceOf(address(distributor)), 0);
    }

    function test_canSwapWETHToETH() public {
        address recipient = makeAddr("recipient");

        vm.startPrank(owner);

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .buy(10000, address(0), recipient)
                .build()
        );
        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        address user = makeAddr("user");
        vm.startPrank(user);

        vm.deal(user, 1 ether);

        uint256 amount = 0.4 ether;
        IWETH(weth).deposit{value: amount}();

        assertEq(IERC20(weth).balanceOf(user), amount);
        assertEq(user.balance, 0.6 ether);

        IERC20(weth).approve(address(distributor), amount);
        _distributeERC20("test", user, amount, weth, address(0), _buildMockMinAmountsOut(1), block.timestamp);

        assertEq(IERC20(weth).balanceOf(recipient), 0);
        assertEq(user.balance, 0.6 ether);
        assertEq(recipient.balance, amount);
        assertEq(address(distributor).balance, 0);
        assertEq(IERC20(weth).balanceOf(address(distributor)), 0);
    }

    function test_canSwapETHToERC20WithUniV2() public {
        address recipient = makeAddr("recipient");

        vm.startPrank(owner);

        _addConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(weth),
                    currency1: Currency.wrap(usdc),
                    fee: 0,
                    tickSpacing: 0,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V2
            })
        );

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .buy(
                    10000,
                    weth,
                    distributor.addDistribution(
                        new DistributionBuilder()
                            .buy(10000, usdc, recipient)
                            .build()
                    )
                )
                .build()
        );
        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        address user = makeAddr("user");

        uint256 amount = 0.4 ether;
        vm.deal(user, 1 ether);

        vm.startPrank(user);

        _distributeETH("test", user, address(0), _buildMockMinAmountsOut(1), block.timestamp, amount);

        assertEq(user.balance, 0.6 ether);
        assertEq(recipient.balance, 0);
        assertEq(IERC20(weth).balanceOf(user), 0);
        assertEq(IERC20(usdc).balanceOf(user), 0);
        assertEq(IERC20(weth).balanceOf(recipient), 0);
        assertGt(IERC20(usdc).balanceOf(recipient), 0.4 * 1e6);

        assertEq(address(distributor).balance, 0);
        assertEq(IERC20(weth).balanceOf(address(distributor)), 0);
        assertEq(IERC20(usdc).balanceOf(address(distributor)), 0);
    }

    function test_canSwapETHToERC20WithUniV2ForBeneficiary() public {
        vm.startPrank(owner);

        _addConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(weth),
                    currency1: Currency.wrap(usdc),
                    fee: 0,
                    tickSpacing: 0,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V2
            })
        );

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .buy(
                    10000,
                    weth,
                    distributor.addDistribution(
                        new DistributionBuilder()
                            .buy(10000, usdc, address(0))
                            .build()
                    )
                )
                .build()
        );
        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        address user = makeAddr("user");

        uint256 amount = 0.4 ether;
        vm.deal(user, 1 ether);

        vm.startPrank(user);

        _distributeETH("test", user, address(0), _buildMockMinAmountsOut(1), block.timestamp, amount);

        assertEq(user.balance, 0.6 ether);
        assertEq(IERC20(weth).balanceOf(user), 0);
        assertGt(IERC20(usdc).balanceOf(user), 0.4 * 1e6);

        assertEq(address(distributor).balance, 0);
        assertEq(IERC20(weth).balanceOf(address(distributor)), 0);
        assertEq(IERC20(usdc).balanceOf(address(distributor)), 0);
    }

    function test_forbidsOmitingMinAmountOut() public {
        address recipient = makeAddr("recipient");

        vm.startPrank(owner);

        _addConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(weth),
                    currency1: Currency.wrap(usdc),
                    fee: 0,
                    tickSpacing: 0,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V2
            })
        );

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .buy(
                    10000,
                    weth,
                    distributor.addDistribution(
                        new DistributionBuilder()
                            .buy(10000, usdc, recipient)
                            .build()
                    )
                )
                .build()
        );
        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        address user = makeAddr("user");

        uint256 amount = 0.4 ether;
        vm.deal(user, 1 ether);

        vm.startPrank(user);

        uint256[] memory minAmountsOut1 = new uint256[](0);
        uint256[] memory minAmountsOut2 = new uint256[](1);
        minAmountsOut2[0] = 0;

        vm.expectPartialRevert(TokenDistributor.MinAmountOutNotSet.selector);
        _distributeETH("test", user, address(0), minAmountsOut1, block.timestamp, amount);
    
        vm.expectPartialRevert(TokenDistributor.MinAmountOutNotSet.selector);
        _distributeETH("test", user, address(0), minAmountsOut2, block.timestamp, amount);
    }

     function test_forbidsSwappingWithoutPoolConfig() public {
        address recipient = makeAddr("recipient");

        vm.startPrank(owner);

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .buy(
                    10000,
                    weth,
                    distributor.addDistribution(
                        new DistributionBuilder()
                            .buy(10000, usdc, recipient)
                            .build()
                    )
                )
                .build()
        );
        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        address user = makeAddr("user");

        uint256 amount = 0.4 ether;
        vm.deal(user, 1 ether);

        vm.startPrank(user);

        vm.expectPartialRevert(TokenDistributor.PoolConfigNotFound.selector);
        _distributeETH("test", user, address(0), _buildMockMinAmountsOut(1), block.timestamp, amount);
    }

    function test_canSwapERC20ToETHWithUniV2() public {
        address recipient = makeAddr("recipient");

        vm.startPrank(owner);

        _addConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(weth),
                    currency1: Currency.wrap(usdc),
                    fee: 0,
                    tickSpacing: 0,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V2
            })
        );

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .buy(
                    10000,
                    weth,
                    distributor.addDistribution(
                        new DistributionBuilder()
                            .buy(10000, address(0), recipient)
                            .build()
                    )
                )
                .build()
        );
        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        address user = makeAddr("user");

        uint256 amount = 100 * 1e6;
        vm.deal(user, 1 ether);

        _swapETHToUSDCExactOut(user, amount);

        vm.startPrank(user);

        IERC20(usdc).approve(address(distributor), amount);
        _distributeERC20("test", user, amount, usdc, address(0), _buildMockMinAmountsOut(1), block.timestamp);

        assertGt(user.balance, 0 ether);
        assertLt(user.balance, 1 ether);
        assertEq(IERC20(usdc).balanceOf(user), 0);
        assertEq(IERC20(usdc).balanceOf(recipient), 0);
        assertGt(recipient.balance, 0);
        assertLt(recipient.balance, 1 ether);

        assertEq(address(distributor).balance, 0);
        assertEq(IERC20(usdc).balanceOf(address(distributor)), 0);
    }

    function test_canSwapERC20ToERC20WithUniV2() public {
        address recipient = makeAddr("recipient");

        vm.startPrank(owner);

        _addConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(ussi),
                    currency1: Currency.wrap(usdc),
                    fee: 0,
                    tickSpacing: 0,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V2
            })
        );

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .buy(
                    10000,
                    ussi,
                    recipient
                )
                .build()
        );
        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        address user = makeAddr("user");

        uint256 amount = 100 * 1e6;
        vm.deal(user, 1 ether);

        _swapETHToUSDCExactOut(user, amount);

        vm.startPrank(user);

        IERC20(usdc).approve(address(distributor), amount);
        _distributeERC20("test", user, amount, usdc, address(0), _buildMockMinAmountsOut(1), block.timestamp);

        assertGt(user.balance, 0 ether);
        assertLt(user.balance, 1 ether);
        assertEq(IERC20(usdc).balanceOf(user), 0);
        assertEq(IERC20(usdc).balanceOf(recipient), 0);
        assertEq(IERC20(ussi).balanceOf(user), 0);
        assertGt(IERC20(ussi).balanceOf(recipient), 0);

        assertEq(address(distributor).balance, 0);
        assertEq(IERC20(usdc).balanceOf(address(distributor)), 0);
        assertEq(IERC20(ussi).balanceOf(address(distributor)), 0);
    }

    function test_canSwapETHToERC20WithUniV3() public {
        address recipient = makeAddr("recipient");

        vm.startPrank(owner);

        _addConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(weth),
                    currency1: Currency.wrap(usdc),
                    fee: 500,
                    tickSpacing: 0,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V3
            })
        );

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .buy(
                    10000,
                    weth,
                    distributor.addDistribution(
                        new DistributionBuilder()
                            .buy(10000, usdc, recipient)
                            .build()
                    )
                )
                .build()
        );
        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        address user = makeAddr("user");

        uint256 amount = 0.4 ether;
        vm.deal(user, 1 ether);

        vm.startPrank(user);

        _distributeETH("test", user, address(0), _buildMockMinAmountsOut(1), block.timestamp, amount);

        assertEq(user.balance, 0.6 ether);
        assertEq(recipient.balance, 0);
        assertEq(IERC20(weth).balanceOf(user), 0);
        assertEq(IERC20(usdc).balanceOf(user), 0);
        assertEq(IERC20(weth).balanceOf(recipient), 0);
        assertGt(IERC20(usdc).balanceOf(recipient), 0.4 * 1e6);

        assertEq(address(distributor).balance, 0);
        assertEq(IERC20(weth).balanceOf(address(distributor)), 0);
        assertEq(IERC20(usdc).balanceOf(address(distributor)), 0);
    }
    
    function test_canSwapETHToERC20WithUniV3ForBeneficiary() public {
        vm.startPrank(owner);

        _addConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(weth),
                    currency1: Currency.wrap(usdc),
                    fee: 500,
                    tickSpacing: 0,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V3
            })
        );

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .buy(
                    10000,
                    weth,
                    distributor.addDistribution(
                        new DistributionBuilder()
                            .buy(10000, usdc, address(0))
                            .build()
                    )
                )
                .build()
        );
        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        address user = makeAddr("user");

        uint256 amount = 0.4 ether;
        vm.deal(user, 1 ether);

        vm.startPrank(user);

        _distributeETH("test", user, address(0), _buildMockMinAmountsOut(1), block.timestamp, amount);

        assertEq(user.balance, 0.6 ether);
        assertEq(IERC20(weth).balanceOf(user), 0);
        assertGt(IERC20(usdc).balanceOf(user), 0.4 * 1e6);

        assertEq(address(distributor).balance, 0);
        assertEq(IERC20(weth).balanceOf(address(distributor)), 0);
        assertEq(IERC20(usdc).balanceOf(address(distributor)), 0);
    }

    function test_canSwapERC20ToETHWithUniV3() public {
        address recipient = makeAddr("recipient");

        vm.startPrank(owner);

        _addConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(weth),
                    currency1: Currency.wrap(usdc),
                    fee: 500,
                    tickSpacing: 0,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V3
            })
        );

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .buy(
                    10000,
                    weth,
                    distributor.addDistribution(
                        new DistributionBuilder()
                            .buy(10000, address(0), recipient)
                            .build()
                    )
                )
                .build()
        );
        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        address user = makeAddr("user");

        uint256 amount = 100 * 1e6;
        vm.deal(user, 1 ether);

        _swapETHToUSDCExactOut(user, amount);

        vm.startPrank(user);

        IERC20(usdc).approve(address(distributor), amount);
        _distributeERC20("test", user, amount, usdc, address(0), _buildMockMinAmountsOut(1), block.timestamp);

        assertGt(user.balance, 0 ether);
        assertLt(user.balance, 1 ether);
        assertEq(IERC20(usdc).balanceOf(user), 0);
        assertEq(IERC20(usdc).balanceOf(recipient), 0);
        assertGt(recipient.balance, 0);
        assertLt(recipient.balance, 1 ether);

        assertEq(address(distributor).balance, 0);
        assertEq(IERC20(usdc).balanceOf(address(distributor)), 0);
    }


    function test_canSwapERC20ToERC20WithUniV3() public {
        address recipient = makeAddr("recipient");

        vm.startPrank(owner);

        _addConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(usdc),
                    currency1: Currency.wrap(usdt),
                    fee: 100,
                    tickSpacing: 0,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V3
            })
        );

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .buy(
                    10000,
                    usdt,
                    recipient
                )
                .build()
        );
        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        address user = makeAddr("user");

        uint256 amount = 100 * 1e6;
        vm.deal(user, 1 ether);

        _swapETHToUSDCExactOut(user, amount);

        vm.startPrank(user);

        IERC20(usdc).approve(address(distributor), amount);
        _distributeERC20("test", user, amount, usdc, address(0), _buildMockMinAmountsOut(1), block.timestamp);

        assertGt(user.balance, 0 ether);
        assertLt(user.balance, 1 ether);
        assertEq(IERC20(usdc).balanceOf(user), 0);
        assertEq(IERC20(usdc).balanceOf(recipient), 0);
        assertEq(IERC20(usdt).balanceOf(user), 0);
        assertGt(IERC20(usdt).balanceOf(recipient), 0);

        assertEq(address(distributor).balance, 0);
        assertEq(IERC20(usdc).balanceOf(address(distributor)), 0);
        assertEq(IERC20(usdt).balanceOf(address(distributor)), 0);
    }

    function test_canSwapETHToERC20WithUniV4() public {
        address recipient = makeAddr("recipient");

        vm.startPrank(owner);

        _addConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(address(0)),
                    currency1: Currency.wrap(usdc),
                    fee: 500,
                    tickSpacing: 10,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V4
            })
        );

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .buy(
                    10000,
                    usdc,
                    recipient
                )
                .build()
        );
        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        address user = makeAddr("user");

        uint256 amount = 0.4 ether;
        vm.deal(user, 1 ether);

        vm.startPrank(user);

        _distributeETH("test", user, address(0), _buildMockMinAmountsOut(1), block.timestamp, amount);

        assertEq(user.balance, 0.6 ether);
        assertEq(recipient.balance, 0);
        assertEq(IERC20(usdc).balanceOf(user), 0);
        assertGt(IERC20(usdc).balanceOf(recipient), 0.4 * 1e6);

        assertEq(address(distributor).balance, 0);
        assertEq(IERC20(usdc).balanceOf(address(distributor)), 0);
    }

    function test_canSwapETHToERC20WithUniV4ForBeneficiary() public {
        vm.startPrank(owner);

        _addConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(address(0)),
                    currency1: Currency.wrap(usdc),
                    fee: 500,
                    tickSpacing: 10,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V4
            })
        );

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .buy(
                    10000,
                    usdc,
                    address(0)
                )
                .build()
        );
        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        address user = makeAddr("user");

        uint256 amount = 0.4 ether;
        vm.deal(user, 1 ether);

        vm.startPrank(user);

        _distributeETH("test", user, address(0), _buildMockMinAmountsOut(1), block.timestamp, amount);

        assertEq(user.balance, 0.6 ether);
        assertGt(IERC20(usdc).balanceOf(user), 0.4 * 1e6);

        assertEq(address(distributor).balance, 0);
        assertEq(IERC20(usdc).balanceOf(address(distributor)), 0);
    }

    function test_canSwapERC20ToETHWithUniV4() public {
        address recipient = makeAddr("recipient");

        vm.startPrank(owner);

        _addConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(address(0)),
                    currency1: Currency.wrap(usdc),
                    fee: 500,
                    tickSpacing: 10,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V4
            })
        );

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .buy(
                    10000,
                    address(0),
                    recipient
                )
                .build()
        );
        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        address user = makeAddr("user");

        uint256 amount = 100 * 1e6;
        vm.deal(user, 1 ether);

        _swapETHToUSDCExactOut(user, amount);

        assertGt(user.balance, 0 ether);
        assertEq(IERC20(usdc).balanceOf(user), amount);

        vm.startPrank(user);

        IERC20(usdc).approve(address(distributor), amount);
        _distributeERC20("test", user, amount, usdc, address(0), _buildMockMinAmountsOut(1), block.timestamp);

        assertGt(user.balance, 0 ether);
        assertLt(user.balance, 1 ether);
        assertEq(IERC20(usdc).balanceOf(user), 0);
        assertEq(IERC20(usdc).balanceOf(recipient), 0);
        assertGt(recipient.balance, 0);
        assertLt(recipient.balance, 1 ether);

        assertEq(address(distributor).balance, 0);
        assertEq(IERC20(usdc).balanceOf(address(distributor)), 0);
    }

    function test_canSwapERC20ToERC20WithUniV4() public {
        address recipient = makeAddr("recipient");

        vm.startPrank(owner);

        _addConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(usdc),
                    currency1: Currency.wrap(usdt),
                    fee: 7,
                    tickSpacing: 1,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V4
            })
        );

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .buy(
                    10000,
                    usdt,
                    recipient
                )
                .build()
        );
        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        address user = makeAddr("user");

        uint256 amount = 100 * 1e6;
        vm.deal(user, 1 ether);

        _swapETHToUSDCExactOut(user, amount);

        assertGt(user.balance, 0 ether);
        assertEq(IERC20(usdc).balanceOf(user), amount);

        vm.startPrank(user);

        IERC20(usdc).approve(address(distributor), amount);
  
        uint256 gasLeftX = gasleft();

        _distributeERC20("test", user, amount, usdc, address(0), _buildMockMinAmountsOut(1), block.timestamp);

        gasLeftX = gasLeftX - gasleft();
        console.log("Spent %s gas", gasLeftX);

        assertGt(user.balance, 0 ether);
        assertLt(user.balance, 1 ether);
        assertEq(IERC20(usdc).balanceOf(user), 0);
        assertEq(IERC20(usdc).balanceOf(recipient), 0);
        assertEq(recipient.balance, 0);
        assertEq(IERC20(usdt).balanceOf(user), 0);
        assertGt(IERC20(usdt).balanceOf(recipient), 99e6);
        assertLt(IERC20(usdt).balanceOf(recipient), 101e6);

        assertEq(address(distributor).balance, 0);
        assertEq(IERC20(usdc).balanceOf(address(distributor)), 0);
        assertEq(IERC20(usdt).balanceOf(address(distributor)), 0);
    }

    function test_canSwapRecursively() public {
        address recipient = makeAddr("recipient");

        vm.startPrank(owner);

        _addConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(weth),
                    currency1: Currency.wrap(usdc),
                    fee: 0,
                    tickSpacing: 0,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V2
            })
        );

        _addConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(usdc),
                    currency1: Currency.wrap(usdt),
                    fee: 100,
                    tickSpacing: 0,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V3
            })
        );

        uint256 subDistId;
        {
            subDistId = distributor.addDistribution(
                new DistributionBuilder()
                    .buy(
                        10000, 
                        usdc, 
                        distributor.addDistribution(
                            new DistributionBuilder()
                                .buy(10000, usdt, recipient)
                                .build()
                        )
                    )
                    .build()
            );
        }

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .buy(
                    10000,
                    weth,
                    subDistId
                )
                .build()
            );

        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        address user = makeAddr("user");

        vm.deal(user, 1 ether);

        vm.startPrank(user);

        _distributeETH("test", user, address(0), _buildMockMinAmountsOut(2), block.timestamp, 0.4 ether);

        assertEq(user.balance, 0.6 ether);
        assertEq(recipient.balance, 0);
        assertEq(address(distributor).balance, 0);

        assertEq(IERC20(usdc).balanceOf(user), 0);
        assertEq(IERC20(usdc).balanceOf(recipient), 0);
        assertEq(IERC20(usdc).balanceOf(address(distributor)), 0);

        assertEq(IERC20(usdt).balanceOf(user), 0);
        assertEq(IERC20(usdt).balanceOf(address(distributor)), 0);

        assertGt(IERC20(usdt).balanceOf(recipient), 0.4 * 1e6);
    }

    function test_canSendAndCall() public {
        vm.startPrank(owner);

        MockEscrow escrow = new MockEscrow();

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .sendAndCall(10000, address(escrow), bytes4(keccak256("depositETH()")))
                .build()
        );

        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        address user = makeAddr("user");

        vm.deal(user, 1 ether);

        vm.startPrank(user);

        _distributeETH("test", user, address(0), _buildMockMinAmountsOut(1), block.timestamp, 0.4 ether);

        assertEq(user.balance, 0.6 ether);
        assertEq(escrow.deposits(address(distributor)), 0.4 ether);
        assertEq(escrow.deposits(user), 0);
    }

    function test_canSendAndCallForBeneficiary() public {
        vm.startPrank(owner);

        MockEscrow escrow = new MockEscrow();

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .sendAndCall(10000, address(escrow), bytes4(keccak256("depositETHFor(address)")), _encodeCallArgs(CallArgType.Beneficiary))
                .build()
        );

        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        address user = makeAddr("user");

        vm.deal(user, 1 ether);

        vm.startPrank(user);

        _distributeETH("test", user, address(0), _buildMockMinAmountsOut(1), block.timestamp, 0.4 ether);

        assertEq(user.balance, 0.6 ether);
        assertEq(escrow.deposits(address(distributor)), 0);
        assertEq(escrow.deposits(address(user)), 0.4 ether);
    }

    function test_canSendAndCallWithAllArgs() public {
        address beneficiary = makeAddr("beneficiary");

        vm.startPrank(owner);

        MockEscrow escrow = new MockEscrow();

        uint256 distId = distributor.addDistribution(
            new DistributionBuilder()
                .sendAndCall(10000, address(escrow), bytes4(keccak256("store(address,address,uint256)")), _encodeCallArgs(CallArgType.Sender, CallArgType.Beneficiary, CallArgType.Amount))
                .build()
        );

        distributor.setDistributionId("test", distId);

        vm.stopPrank();

        address user = makeAddr("user");

        vm.deal(user, 1 ether);

        vm.startPrank(user);

        _distributeETH("test", beneficiary, address(0), _buildMockMinAmountsOut(1), block.timestamp, 0.4 ether);

        assertEq(user.balance, 0.6 ether);
        assertEq(escrow.sender(), user);
        assertEq(escrow.beneficiary(), beneficiary);
        assertEq(escrow.amount(), 0.4 ether);
        assertEq(escrow.value(), 0.4 ether);
    }

    function test_canFundLaunchPools() public {
        (AgentLaunchPool pool1,) = _deployDefaultLaunchPool(address(0));

        minAmountForLaunch = 100e6;
        (AgentLaunchPool pool2,) = _deployDefaultLaunchPool(usdc);

        vm.startPrank(owner);

        _addConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(weth),
                    currency1: Currency.wrap(usdc),
                    fee: 0,
                    tickSpacing: 0,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V2
            })
        );

        uint256 pool2DistId;
        {
            pool2DistId = distributor.addDistribution(
                new DistributionBuilder()
                    .buy(
                        10000, 
                        usdc, 
                        distributor.addDistribution(
                            new DistributionBuilder()
                                .sendAndCall(10000, address(pool2), bytes4(keccak256("depositERC20For(address,uint256)")), _encodeCallArgs(CallArgType.Beneficiary, CallArgType.Amount))
                                .build()
                        )
                    )
                    .build()
            );
        }

        distributor.setDistributionId(
            "test", 
            distributor.addDistribution(
                new DistributionBuilder()
                    .buy(
                        5000,
                        weth,
                        pool2DistId
                    )
                    .sendAndCall(5000, address(pool1), bytes4(keccak256("depositETHFor(address)")), _encodeCallArgs(CallArgType.Beneficiary))
                    .build()
                )
        );

        vm.stopPrank();

        address user = makeAddr("user");

        vm.deal(user, 10 ether);

        vm.startPrank(user);

        _distributeETH("test", user, address(0), _buildMockMinAmountsOut(1), block.timestamp, 3 ether);

        vm.warp(block.timestamp + timeWindow);

        pool1.launch();
        pool1.claim(user);

        pool2.launch();
        pool2.claim(user);

        assertEq(user.balance, 7 ether);
        assertGt(IERC20(pool1.agentToken()).balanceOf(user), 0);
        assertGt(IERC20(pool2.agentToken()).balanceOf(user), 0);
    }

    function test_canSendComplexDistribution() public {
        address recipient = makeAddr("recipient");

        (AgentLaunchPool pool, PoolKey memory poolKey,) = _launch(makeAddr("depositor"));

        vm.startPrank(owner);

        _addConfig(
            PoolConfig({
                poolKey: poolKey,
                version: UniswapVersion.V4
            })
        );

        _addConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(weth),
                    currency1: Currency.wrap(usdc),
                    fee: 0,
                    tickSpacing: 0,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V2
            })
        );

        _addConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(usdc),
                    currency1: Currency.wrap(usdt),
                    fee: 100,
                    tickSpacing: 0,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V3
            })
        );

        MockEscrow escrow = new MockEscrow();

        distributor.setDistributionId(
            "test", 
            distributor.addDistribution(
                new DistributionBuilder()
                    .send(500, makeAddr("eth-recipient1"))
                    .send(500, makeAddr("eth-recipient2"))
                    .buy(
                        4000,
                        weth,
                        distributor.addDistribution(
                            new DistributionBuilder()
                                .buy(
                                    10000, 
                                    usdc, 
                                    distributor.addDistribution(
                                        new DistributionBuilder()
                                            .send(2000, makeAddr("usdc-recipient"))
                                            .buy(8000, usdt, makeAddr("recipient"))
                                            .build()
                                    )
                                )
                                .build()
                        )
                    )
                    .buy(
                        1000,
                        pool.agentToken(),
                        distributor.addDistribution(
                            new DistributionBuilder()
                                .burn(8000)
                                .send(1000, makeAddr("agent-recipient1"))
                                .send(1000, makeAddr("agent-recipient2"))
                                .build()
                        )
                    )
                    .sendAndCall(1500, address(escrow), bytes4(keccak256("depositETH()")))
                    .sendAndCall(2500, address(escrow), bytes4(keccak256("depositETHFor(address)")), _encodeCallArgs(CallArgType.Beneficiary))
                    .build()
                )
        );

        vm.stopPrank();

        address user = makeAddr("user");

        vm.deal(user, 1 ether);

        uint256 agentTotalSupply = IERC20(pool.agentToken()).totalSupply();

        vm.startPrank(user);

        _distributeETH("test", user, address(0), _buildMockMinAmountsOut(3), block.timestamp, 0.4 ether);

        assertEq(user.balance, 0.6 ether);
        assertEq(recipient.balance, 0);
        assertEq(address(distributor).balance, 0);

        assertEq(IERC20(usdc).balanceOf(user), 0);
        assertEq(IERC20(usdc).balanceOf(recipient), 0);
        assertLt(IERC20(usdc).balanceOf(address(distributor)), 10);

        assertEq(IERC20(usdt).balanceOf(user), 0);
        assertEq(IERC20(usdt).balanceOf(address(distributor)), 0);

        assertGt(IERC20(usdt).balanceOf(recipient), 0.4 * 1e6);

        assertEq(escrow.deposits(address(distributor)), 0.4 ether * 1_500 / 10_000);
        assertEq(escrow.deposits(address(user)), 0.4 ether * 2_500 / 10_000);

        assertLt(IERC20(pool.agentToken()).totalSupply(), agentTotalSupply);

        assertEq(makeAddr("eth-recipient1").balance, 0.4 ether * 500 / 10_000);
        assertEq(makeAddr("eth-recipient2").balance, 0.4 ether * 500 / 10_000);
        assertGt(IERC20(pool.agentToken()).balanceOf(makeAddr("agent-recipient1")), 0);
        assertGt(IERC20(pool.agentToken()).balanceOf(makeAddr("agent-recipient2")), 0);
        assertGt(IERC20(usdc).balanceOf(makeAddr("usdc-recipient")), 0);
    }

    function test_sendToRecipientOnFailure() public {
        address recipient = makeAddr("recipient");

        vm.startPrank(owner);

        MockEscrow escrow = new MockEscrow();

        distributor.setDistributionId(
            "test", 
            distributor.addDistribution(
                new DistributionBuilder()
                    .sendAndCall(10000, address(escrow), bytes4(keccak256("fail()")))
                    .build()
                )
        );

        vm.stopPrank();

        address user = makeAddr("user");

        vm.deal(user, 1 ether);

        vm.startPrank(user);

        _distributeETH("test", user, recipient, _buildMockMinAmountsOut(1), block.timestamp, 0.4 ether);
        assertEq(user.balance, 0.6 ether);
        assertEq(recipient.balance, 0.4 ether);

        MockedERC20 erc20 = new MockedERC20();
        erc20.mint(user, 1e18);

        erc20.approve(address(distributor), 0.4 * 1e18);
        _distributeERC20("test", user, 0.4 * 1e18, address(erc20), recipient, _buildMockMinAmountsOut(1), block.timestamp);
        assertEq(erc20.balanceOf(user), 0.6 * 1e18);
        assertEq(erc20.balanceOf(recipient), 0.4 * 1e18);
    
        vm.expectPartialRevert(TokenDistributor.CallFailed.selector);
        _distributeETH("test", user, address(0), _buildMockMinAmountsOut(1), block.timestamp, 0.4 ether);
        assertEq(user.balance, 0.6 ether); // No change
        assertEq(recipient.balance, 0.4 ether); // No change

        erc20.approve(address(distributor), 0.4 * 1e18);
        vm.expectPartialRevert(TokenDistributor.CallFailed.selector);
        _distributeERC20("test", user, 0.4 * 1e18, address(erc20), address(0), _buildMockMinAmountsOut(1), block.timestamp);
        assertEq(erc20.balanceOf(user), 0.6 * 1e18); // No change
        assertEq(erc20.balanceOf(recipient), 0.4 * 1e18); // No change
    }

    // Upgrade-specific tests removed for non-upgradeable contract

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

    function _deployLaunchPool(address depositor) internal returns(AgentLaunchPool, PoolKey memory, IERC20) {
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

    function _swapETHToUSDCExactOut(
        address user,
        uint256 outAmount
    ) internal {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(usdc),
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(0))
        });

        _swapETHForERC20ExactOut(
            user,
            key,
            outAmount
        );
    }

    function _addConfig(PoolConfig memory config) internal {
        distributor.setPoolConfig(
            distributor.proposePoolConfig(
                config
            )
        );
    }

    function _encodeCallArgs() internal pure returns (bytes12) {
        return bytes12(0);
    }

    function _encodeCallArgs(CallArgType arg1) internal pure returns (bytes12) {
        CallArgType[] memory callArgs = new CallArgType[](1);
        callArgs[0] = arg1;

        return _encodeCallArgs(callArgs);
    }

    function _encodeCallArgs(CallArgType arg1, CallArgType arg2) internal pure returns (bytes12) {
        CallArgType[] memory callArgs = new CallArgType[](2);
        callArgs[0] = arg1;
        callArgs[1] = arg2;
        
        return _encodeCallArgs(callArgs);
    }

    function _encodeCallArgs(CallArgType arg1, CallArgType arg2, CallArgType arg3) internal pure returns (bytes12) {
        CallArgType[] memory callArgs = new CallArgType[](3);
        callArgs[0] = arg1;
        callArgs[1] = arg2;
        callArgs[2] = arg3;
        
        return _encodeCallArgs(callArgs);
    }

    function _encodeCallArgs(CallArgType[] memory args) internal pure returns (bytes12) {
        require(args.length <= 11, "Max 11 call args");

        bytes memory temp = new bytes(12);
        temp[0] = bytes1(uint8(args.length));
        for (uint8 i = 0; i < args.length; i++) {
            temp[i + 1] = bytes1(uint8(args[i]));
        }

        bytes12 result;
        assembly {
            result := mload(add(temp, 32))
        }
        
        return result;
    }

    function _buildMockMinAmountsOut(uint256 count) internal pure returns(uint256[] memory) {
        uint256[] memory minAmountsOut = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            minAmountsOut[i] = 1;
        }
        return minAmountsOut;
    }

    function _distributeETH(
        bytes32 _distributionName, 
        address _beneficiary,
        address _recipientOnFailure,
        uint256[] memory _minAmountsOut,
        uint256 _deadline,
        uint256 _amount
    ) internal {
        DistributionRequest[] memory requests = new DistributionRequest[](1);
        requests[0] = DistributionRequest({
            beneficiary: _beneficiary,
            amount: _amount,
            recipientOnFailure: _recipientOnFailure
        });

        distributor.batchDistributeETH{value: _amount}(_distributionName, requests, _minAmountsOut, _deadline, 0x0);
    }

    function _distributeERC20(
        bytes32 _distributionName, 
        address _beneficiary, 
        uint256 _amount, 
        address _paymentToken,
        address _recipientOnFailure,
        uint256[] memory _minAmountsOut,
        uint256 _deadline
    ) internal {
        DistributionRequest[] memory requests = new DistributionRequest[](1);
        requests[0] = DistributionRequest({
            beneficiary: _beneficiary,
            amount: _amount,
            recipientOnFailure: _recipientOnFailure
        });

        distributor.batchDistributeERC20(_distributionName, _paymentToken, requests, _minAmountsOut, _deadline, 0x0);
    }
}

contract MockEscrow {
    mapping(address => uint256) public deposits;

    address public sender;
    address public beneficiary;
    uint256 public amount;
    uint256 public value;

    function depositETH() external payable {
        deposits[msg.sender] += msg.value;
    }

    function depositETHFor(address _beneficiary) external payable {
        deposits[_beneficiary] += msg.value;
    }

    function fail() external pure {
        revert("Fail");
    }

    function store(address _sender, address _beneficiary, uint256 _amount) external payable {
        sender = _sender;
        beneficiary = _beneficiary;
        amount = _amount;
        value = msg.value;
    }
}

// Upgrade mock removed for non-upgradeable contract