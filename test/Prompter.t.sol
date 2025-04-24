// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

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
import {Prompter, Distribution, Action, BurnData, SendData, BuyData, SendAndCall, SendAndCallForBeneficiary, ActionType} from "../src/Prompter.sol";

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
                uniswapPoolManager,
                uniswapPositionManager,
                uniswapUniversalRouter
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

        vm.startPrank(owner);

        MockEscrow escrow = new MockEscrow();
        
        uint256 buyDistId;
        
        {
            address agentRecipient1 = makeAddr("agentRecipient1");
            address agentRecipient2 = makeAddr("agentRecipient2");

            buyDistId = prompter.addDistribution(
                new DistributionBuilder()
                    .send(4000, agentRecipient1)
                    .send(5000, agentRecipient2)
                    .burn(1000)
                    .build(poolKey)
            );
        }
         
        Distribution memory distribution = _dist()
            .send(2000, makeAddr("recipient1"))
            .send(3000, makeAddr("recipient2"))
            .buy(1000, agentToken, buyDistId)
            .sendAndCall(1000, address(escrow), bytes4(keccak256("depositETH()")),, address(0))
            .sendAndCallForBeneficiary(1000, address(escrow), bytes4(keccak256("depositETHFor(address)")), address(0))
            .build(poolKey);

        prompter.bind("gecko", distribution); // onlyOwner

        vm.stopPrank();

        {
            uint256 currentGas = gasleft();

            vm.prank(user);
            prompter.promptWithETH{value: amount}("gecko", user);
            
            uint256 gasUsed = currentGas - gasleft();
            console.log("Gas used: %s", gasUsed);
        }

        assertEq(makeAddr("recipient1").balance, (amount * 2000) / 10000);
        assertEq(makeAddr("recipient2").balance, (amount * 3000) / 10000);
        assertEq(escrow.deposits(address(prompter)), (amount * 1000) / 10000);
        assertEq(escrow.deposits(user), (amount * 1000) / 10000);
        assertGt(IERC20(agentToken).balanceOf(makeAddr("agentRecipient1")), 0);
        assertGt(IERC20(agentToken).balanceOf(makeAddr("agentRecipient2")), 0);
        assertLt(IERC20(agentToken).balanceOf(makeAddr("agentRecipient1")), IERC20(agentToken).balanceOf(makeAddr("agentRecipient2")));
        assertLt(IERC20(agentToken).totalSupply(), startTotalAgentSupply);
    }

    function _dist() internal returns (DistributionBuilder) {
        return new DistributionBuilder();
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
    Distribution internal distribution;
    
    function build(PoolKey memory poolKey) external returns (Distribution memory) {
        distribution.poolKey = poolKey;

        return distribution;
    }

    function burn(
        uint256 basisAmount
    ) external returns (DistributionBuilder) {
        distribution.actions.push(Action({
            actionType: ActionType.Burn,
            dataIndex: distribution.burns.length
        }));
        distribution.burns.push(BurnData({
            basisAmount: basisAmount
        }));
        return this;
    }

    function send(
        uint256 basisAmount,
        address recipient
    ) external returns (DistributionBuilder) {
        distribution.actions.push(Action({
            actionType: ActionType.Send,
            dataIndex: distribution.sends.length
        }));
        distribution.sends.push(SendData({
            recipient: recipient,
            basisAmount: basisAmount
        }));
        return this;
    }

    function buy(
        uint256 _basisAmount,
        address _tokenToBuy,
        uint256 _distributionId
    ) external returns (DistributionBuilder) {
        distribution.actions.push(Action({
            actionType: ActionType.Buy,
            dataIndex: distribution.buys.length
        }));
        distribution.buys.push(BuyData({
            tokenToBuy: _tokenToBuy,
            basisAmount: _basisAmount,
            distributionId: _distributionId
        }));
        return this;
    }

    function sendAndCall(
        uint256 basisAmount,
        address recipient,
        bytes4 signature,
        address recipientOnFailure
    ) external returns (DistributionBuilder) {
        distribution.actions.push(Action({
            actionType: ActionType.SendAndCall,
            dataIndex: distribution.sendAndCalls.length
        }));
        distribution.sendAndCalls.push(SendAndCall({
            recipient: recipient,
            basisAmount: basisAmount,
            signature: signature,
            recipientOnFailure: recipientOnFailure
        }));
        return this;
    }

    function sendAndCallForBeneficiary(
        uint256 basisAmount,
        address recipient,
        bytes4 signature,
        address recipientOnFailure
    ) external returns (DistributionBuilder) {
        distribution.actions.push(Action({
            actionType: ActionType.SendAndCallForBeneficiary,
            dataIndex: distribution.sendAndCallForBeneficiary.length
        }));
        distribution.sendAndCallForBeneficiary.push(SendAndCallForBeneficiary({
            recipient: recipient,
            basisAmount: basisAmount,
            signature: signature,
            recipientOnFailure: recipientOnFailure
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
