// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";

import {TokenInfo} from "../src/types/TokenInfo.sol";
import {LaunchPoolInfo} from "../src/types/LaunchPoolInfo.sol";
import {UniswapPoolInfo} from "../src/types/UniswapPoolInfo.sol";
import {AgentDistributionInfo} from "../src/types/AgentDistributionInfo.sol";
import {LaunchPoolProposal} from "../src/types/LaunchPoolProposal.sol";
import {UniswapFeeInfo} from "../src/types/UniswapFeeInfo.sol";
import {AgentFactory} from "../src/AgentFactory.sol";
import {LaunchPoolProposal} from "../src/types/LaunchPoolProposal.sol";

contract AddLaunchPoolProposalScript is Script {
    function run() public {
        AgentFactory factory = AgentFactory(vm.envAddress("AGENT_FACTORY"));
        LaunchPoolProposal memory proposal;
        {
            address collateral = address(0);

            address permit2 = vm.envAddress("PERMIT2");

            address dao = vm.envAddress("DAO_ADDRESS");
            address agentWallet = vm.envAddress("AGENT_WALLET");

            address hook = vm.envAddress("AGENT_UNISWAP_HOOK");
            address agentLaunchPoolImpl = vm.envAddress("AGENT_LAUNCH_POOL_IMPL");
            
            TokenInfo memory tokenInfo;
            {
                string memory agentTokenName = vm.envString("AGENT_TOKEN_NAME");
                string memory agentTokenSymbol = vm.envString("AGENT_TOKEN_SYMBOL");
                address agentTokenImpl = vm.envAddress("AGENT_TOKEN_IMPL");
                address agentStakingImpl = vm.envAddress("AGENT_STAKING_IMPL");

                tokenInfo = TokenInfo({
                    owner: dao,
                    name: agentTokenName,
                    symbol: agentTokenSymbol,
                    totalSupply: 10_000_000 * 1e18,
                    tokenImplementation: agentTokenImpl,
                    stakingImplementation: agentStakingImpl
                });
            }
            
            LaunchPoolInfo memory launchPoolInfo;
            {
                address[] memory collateralRecipients = new address[](2);
                collateralRecipients[0] = dao;
                collateralRecipients[1] = agentWallet;

                uint256[] memory collateralBasisAmounts = new uint256[](2);
                collateralBasisAmounts[0] = 1_000;
                collateralBasisAmounts[1] = 2_500;

                launchPoolInfo = LaunchPoolInfo({
                    collateral: collateral,
                    timeWindow: 7 days,
                    minAmountForLaunch: 14 ether,
                    maxAmountForLaunch: 70 ether,
                    collateralUniswapPoolBasisAmount: 6_500,
                    collateralRecipients: collateralRecipients,
                    collateralBasisAmounts: collateralBasisAmounts
                });
            }
            
            UniswapPoolInfo memory uniswapPoolInfo = UniswapPoolInfo({
                permit2: permit2,
                hook: hook,
                lpRecipient: dao,
                lpFee: 0,
                tickSpacing: 200
            });

            AgentDistributionInfo memory distributionInfo;
            {
                address[] memory recipients = new address[](2);
                recipients[0] = dao;
                recipients[1] = agentWallet;
                uint256[] memory basisAmounts = new uint256[](2);
                basisAmounts[0] = 1_500;
                basisAmounts[1] = 2_000;

                distributionInfo = AgentDistributionInfo({
                    recipients: recipients,
                    basisAmounts: basisAmounts,
                    launchPoolBasisAmount: 4_000,
                    uniswapPoolBasisAmount: 2_500
                });
            }

            UniswapFeeInfo memory uniswapFeeInfo;
            {
                address[] memory feeRecipients = new address[](2);
                feeRecipients[0] = dao;
                feeRecipients[1] = agentWallet;

                uint256[] memory feeBasisAmounts = new uint256[](2);
                feeBasisAmounts[0] = 50;
                feeBasisAmounts[1] = 50;

                uniswapFeeInfo = UniswapFeeInfo({
                    collateral: collateral,
                    burnBasisAmount: 100,
                    recipients: feeRecipients,
                    basisAmounts: feeBasisAmounts
                });
            }

            proposal = LaunchPoolProposal({
                launchPoolImplementation: agentLaunchPoolImpl,
                tokenInfo: tokenInfo,
                launchPoolInfo: launchPoolInfo,
                uniswapPoolInfo: uniswapPoolInfo,
                distributionInfo: distributionInfo,
                uniswapFeeInfo: uniswapFeeInfo
            });
        }
       
        vm.startBroadcast();
        uint256 proposalId = factory.addProposal(proposal);
        vm.stopBroadcast();

        console.log("Added proposal %s", proposalId);
    }
}
