// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {AgentFactory} from "../src/AgentFactory.sol";
import {LaunchPoolProposal} from "../src/types/LaunchPoolProposal.sol";

contract DeployAgentFactoryScript is Script {
    function run() public {
        address uniswapPoolManager = vm.envAddress("BASE_POOL_MANAGER");
        address uniswapPositionManager = vm.envAddress("BASE_POSITION_MANAGER");
        address permit2 = vm.envAddress("PERMIT2");

        address dao = vm.envAddress("DAO_ADDRESS");
        address agentWallet = vm.envAddress("AGENT_WALLET");
        
        AgentFactory factory = AgentFactory(vm.envAddress("AGENT_FACTORY"));
        address hook = AgentFactory(vm.envAddress("AGENT_UNISWAP_HOOK"));
        address agentTokenImpl = vm.envAddress("AGENT_TOKEN_IMPL");
        address agentStakingImpl = vm.envAddress("AGENT_STAKING_IMPL");

        address collateral = address(0);

        TokenInfo memory tokenInfo = TokenInfo({
            owner: dao,
            name: "Agent Token",
            symbol: "AGENT",
            totalSupply: 10_000_000,
            tokenImplementation: agentTokenImpl,
            stakingImplementation: agentStakingImpl
        });

        address[] memory collateralRecipients = new address[](2);
        collateralRecipients[0] = dao;
        collateralRecipients[1] = agentWallet;

        uint256[] memory collateralBasisAmounts = new uint256[](2);
        collateralBasisAmounts[0] = 1_000;
        collateralBasisAmounts[1] = 2_500;

        LaunchPoolInfo memory launchPoolInfo = LaunchPoolInfo({
            collateral: collateral,
            timeWindow: 7 days,
            minAmountForLaunch: 10 ether,
            maxAmountForLaunch: 1000 ether,
            collateralUniswapPoolBasisAmount: 6_500_00,
            collateralRecipients: collateralRecipients,
            collateralBasisAmounts: collateralBasisAmounts
        });

        UniswapPoolInfo memory uniswapPoolInfo = UniswapPoolInfo({
            permit2: permit2,
            hook: address(hook),
            lpRecipient: dao,
            lpFee: 0,
            tickSpacing: 200
        });

        address[] memory recipients = new address[](2);
        recipients[0] = dao;
        recipients[1] = agentWallet;
        uint256[] memory basisAmounts = new uint256[](2);
        basisAmounts[0] = 1_500;
        basisAmounts[1] = 2_000;

        AgentDistributionInfo memory distributionInfo = AgentDistributionInfo({
            recipients: recipients,
            basisAmounts: basisAmounts,
            launchPoolBasisAmount: 4_000,
            uniswapPoolBasisAmount: 2_000
        });

        address[] memory feeRecipients = new address[](2);
        feeRecipients[0] = dao;
        feeRecipients[1] = agentWallet;

        uint256[] memory feeBasisAmounts = new uint256[](2);
        feeBasisAmounts[0] = 50;
        feeBasisAmounts[1] = 50;

        UniswapFeeInfo memory uniswapFeeInfo = UniswapFeeInfo({
            collateral: collateral,
            burnBasisAmount: 100,
            recipients: feeRecipients,
            basisAmounts: feeBasisAmounts
        });

        LaunchPoolProposal memory proposal = LaunchPoolProposal({
            launchPoolImplementation: launchPoolImpl,
            tokenInfo: tokenInfo,
            launchPoolInfo: launchPoolInfo,
            uniswapPoolInfo: uniswapPoolInfo,
            distributionInfo: distributionInfo,
            uniswapFeeInfo: uniswapFeeInfo
        });
       
        vm.startBroadcast();
        uint256 proposalId = factory.addProposal(proposal);
        vm.stopBroadcast();

        console.log("Added proposal %s", proposalId);
    }
}
