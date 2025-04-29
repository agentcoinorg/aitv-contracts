// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUniversalRouter} from "@uniswap/universal-router/src/interfaces/IUniversalRouter.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IHooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

import {AgentToken} from "../src/AgentToken.sol";
import {AgentStaking} from "../src/AgentStaking.sol";
import {AgentLaunchPool} from "../src/AgentLaunchPool.sol";
import {TokenInfo} from "../src/types/TokenInfo.sol";
import {LaunchPoolInfo} from "../src/types/LaunchPoolInfo.sol";
import {UniswapPoolInfo} from "../src/types/UniswapPoolInfo.sol";
import {UniswapFeeInfo} from "../src/types/UniswapFeeInfo.sol";
import {AgentFactory} from "../src/AgentFactory.sol";
import {AgentDistributionInfo} from "../src/types/AgentDistributionInfo.sol";
import {AgentUniswapHook} from "../src/AgentUniswapHook.sol";
import {LaunchPoolProposal} from "../src/types/LaunchPoolProposal.sol";
import {AgentFactoryTestUtils} from "./helpers/AgentFactoryTestUtils.sol";
import {DistributionAndPriceChecker} from "../src/DistributionAndPriceChecker.sol";
import {Prompter, RawAction, ActionType} from "../src/Prompter.sol";
import {MockedERC20} from "./helpers/MockedERC20.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
}

contract PrompterTest is AgentFactoryTestUtils {
    Prompter prompter;

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        _deployDefaultContracts();

        address prompterImpl = address(new Prompter());

        prompter = Prompter(address(new ERC1967Proxy(
            prompterImpl, 
            abi.encodeCall(Prompter.initialize, (
                owner,
                IPositionManager(uniswapPositionManager),
                IUniversalRouter(uniswapUniversalRouter),
                IPermit2(permit2)
            ))
        )));
    }

    function test_prompter() public {
        uint256 amount = 0.01 ether;

        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey,) = _launch(makeAddr("depositor"));
        address agentToken = pool.agentToken();
        uint256 startTotalAgentSupply = IERC20(agentToken).totalSupply();

        address usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        address weth = 0x4200000000000000000000000000000000000006;

        vm.prank(user);
        IWETH(weth).deposit{value: 0.01 ether}();

        vm.startPrank(owner);
        prompter.setPoolKey(agentToken, poolKey);
        prompter.setPoolKey(usdc, PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(usdc),
            fee: 500,
            tickSpacing: 0,
            hooks: IHooks(address(0))
        }));
        // prompter.setPoolKey(weth, PoolKey({
        //     currency0: Currency.wrap(address(0)),
        //     currency1: Currency.wrap(weth),
        //     fee: 0,
        //     tickSpacing: 0,
        //     hooks: IHooks(address(0))
        // }));

        MockEscrow escrow = new MockEscrow();
        
        uint256 buyDistId;
        
        {
            address agentRecipient1 = makeAddr("agentRecipient1");
            address agentRecipient2 = makeAddr("agentRecipient2");

            buyDistId = prompter.addDistribution(
                new DistributionBuilder()
                    .send(5000, agentRecipient1)
                    .send(5000, agentRecipient2)
                    .build()
            );
        }
         
        RawAction[] memory actions = new DistributionBuilder()
            // .send(5000, makeAddr("recipient1"))
            // .send(2000, makeAddr("recipient2"))
            // .buy(5000, agentToken, buyDistId)
            .buy(10000, usdc, buyDistId)
            // .sendAndCall(1000, address(escrow), bytes4(keccak256("depositETH()")), address(0))
            // .sendAndCallForBeneficiary(1000, address(escrow), bytes4(keccak256("depositETHFor(address)")), address(0))
            .build();

        // RawAction[] memory actions = new DistributionBuilder()
        //     .send(10000, makeAddr("recipient1"))
        //     .build();

        uint256 distId = prompter.addDistribution(actions);

        prompter.setPromptDistribution("gecko", distId); // onlyOwner

        vm.stopPrank();

        {
            uint256 currentGas = gasleft();

            // MockedERC20 erc20 = new MockedERC20();
            // erc20.mint(user, amount);

            vm.startPrank(user);
            IERC20(weth).approve(address(prompter), amount);
            prompter.promptWithERC20("gecko", user, amount, address(weth));
            // prompter.promptWithETH{value: amount}("gecko", user);
            
            vm.stopPrank();

            uint256 gasUsed = currentGas - gasleft();
            console.log("Gas used: %s", gasUsed);
        }

        assertEq(makeAddr("recipient1").balance, (amount * 5000) / 10000);
        assertEq(makeAddr("recipient2").balance, (amount * 2000) / 10000);
        assertEq(escrow.deposits(address(prompter)), (amount * 1000) / 10000);
        assertEq(escrow.deposits(user), (amount * 1000) / 10000);
        assertGt(IERC20(agentToken).balanceOf(makeAddr("agentRecipient1")), 0);
        assertGt(IERC20(agentToken).balanceOf(makeAddr("agentRecipient2")), 0);
        assertLt(IERC20(agentToken).balanceOf(makeAddr("agentRecipient1")), IERC20(agentToken).balanceOf(makeAddr("agentRecipient2")));
        assertLt(IERC20(agentToken).totalSupply(), startTotalAgentSupply);
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

contract DistributionBuilder {
    RawAction[] internal rawActions;
    
    function build() external returns (RawAction[] memory) {
        return rawActions;
    }

    function burn(
        uint256 basisPoints
    ) external returns (DistributionBuilder) {
        rawActions.push(RawAction({
            actionType: ActionType.Burn,
            basisPoints: uint16(basisPoints),
            recipient: address(0),
            token: address(0),
            distributionId: 0,
            selector: bytes4(0),
            recipientOnFailure: address(0)
        }));

        return this;
    }

    function send(
        uint256 basisPoints,
        address recipient
    ) external returns (DistributionBuilder) {
        rawActions.push(RawAction({
            actionType: ActionType.Send,
            basisPoints: uint16(basisPoints),
            recipient: recipient,
            token: address(0),
            distributionId: 0,
            selector: bytes4(0),
            recipientOnFailure: address(0)
        }));

        return this;
    }

    function buy(
        uint256 _basisPoints,
        address _tokenToBuy,
        uint256 _distributionId
    ) external returns (DistributionBuilder) {
        rawActions.push(RawAction({
            actionType: ActionType.Buy,
            basisPoints: uint16(_basisPoints),
            token: _tokenToBuy,
            distributionId: uint32(_distributionId),
            recipient: address(0),
            selector: bytes4(0),
            recipientOnFailure: address(0)
        }));
  
        return this;
    }

    function sendAndCall(
        uint256 _basisPoints,
        address recipient,
        bytes4 selector,
        address recipientOnFailure
    ) external returns (DistributionBuilder) {
        rawActions.push(RawAction({
            actionType: ActionType.SendAndCall,
            basisPoints: uint16(_basisPoints),
            recipient: recipient,
            selector: selector,
            recipientOnFailure: recipientOnFailure,
            token: address(0),
            distributionId: 0
        }));

        return this;
    }

    function sendAndCallForBeneficiary(
        uint256 basisPoints,
        address recipient,
        bytes4 selector,
        address recipientOnFailure
    ) external returns (DistributionBuilder) {
        rawActions.push(RawAction({
            actionType: ActionType.SendAndCallForBeneficiary,
            basisPoints: uint16(basisPoints),
            recipient: recipient,
            selector: selector,
            recipientOnFailure: recipientOnFailure,
            token: address(0),
            distributionId: 0
        }));

        return this;
    }
}

contract MockEscrow {
    mapping(address => uint256) public deposits;

    function depositETH() external payable {
        deposits[msg.sender] += msg.value;
    }

    function depositETHFor(address _beneficiary) external payable {
        deposits[_beneficiary] += msg.value;
    }
}
