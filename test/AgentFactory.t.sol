// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {AgentToken} from "../src/AgentToken.sol";
import {AgentStaking} from "../src/AgentStaking.sol";
import {AgentLaunchPool} from "../src/AgentLaunchPool.sol";
import {IAgentLaunchPool} from "../src/interfaces/IAgentLaunchPool.sol";
import {TokenInfo} from "../src/types/TokenInfo.sol";
import {LaunchPoolInfo} from "../src/types/LaunchPoolInfo.sol";
import {UniswapPoolInfo} from "../src/types/UniswapPoolInfo.sol";
import {UniswapFeeInfo} from "../src/types/UniswapFeeInfo.sol";
import {AgentFactory} from "../src/AgentFactory.sol";
import {AgentDistributionInfo} from "../src/types/AgentDistributionInfo.sol";
import {AgentUniswapHook} from "../src/AgentUniswapHook.sol";
import {LaunchPoolProposal} from "../src/types/LaunchPoolProposal.sol";
import {AgentFactoryTestUtils} from "./helpers/AgentFactoryTestUtils.sol";

contract AgentFactoryTest is AgentFactoryTestUtils {
    
    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        _deployDefaultContracts();
    }

    function test_anyoneCanAddProposals() public { 
        vm.prank(makeAddr("anyone1"));
        factory.addProposal(_buildDefaultLaunchPoolProposal(address(0)));

        vm.prank(makeAddr("anyone2"));
        factory.addProposal(_buildDefaultLaunchPoolProposal(address(1)));
    }

    function test_canDeployProposal() public { 
        factory.addProposal(_buildDefaultLaunchPoolProposal(address(0)));

        vm.prank(owner);
        factory.deployProposal(0);
    }

    function test_canDeployLaunchPool() public { 
        LaunchPoolProposal memory proposal = _buildDefaultLaunchPoolProposal(address(0));

        vm.prank(owner);
        factory.deploy(
            proposal.launchPoolImplementation,
            proposal.tokenInfo,
            proposal.launchPoolInfo,
            proposal.uniswapPoolInfo,
            proposal.distributionInfo,
            proposal.uniswapFeeInfo
        );
    }

    function test_canDeployManyProposals() public { 
        factory.addProposal(_buildDefaultLaunchPoolProposal(address(0)));
        factory.addProposal(_buildDefaultLaunchPoolProposal(address(1)));
        factory.addProposal(_buildDefaultLaunchPoolProposal(address(2)));

        vm.startPrank(owner);

        factory.deployProposal(0);
        factory.deployProposal(1);
        factory.deployProposal(2);
    }

    function test_canDeployManyLaunchPools() public { 
        LaunchPoolProposal memory proposal1 = _buildDefaultLaunchPoolProposal(address(0));
        LaunchPoolProposal memory proposal2 = _buildDefaultLaunchPoolProposal(address(1));
        LaunchPoolProposal memory proposal3 = _buildDefaultLaunchPoolProposal(address(3));

        vm.startPrank(owner);

        factory.deploy(
            proposal1.launchPoolImplementation,
            proposal1.tokenInfo,
            proposal1.launchPoolInfo,
            proposal1.uniswapPoolInfo,
            proposal1.distributionInfo,
            proposal1.uniswapFeeInfo
        );

        factory.deploy(
            proposal2.launchPoolImplementation,
            proposal2.tokenInfo,
            proposal2.launchPoolInfo,
            proposal2.uniswapPoolInfo,
            proposal2.distributionInfo,
            proposal2.uniswapFeeInfo
        );

        factory.deploy(
            proposal3.launchPoolImplementation,
            proposal3.tokenInfo,
            proposal3.launchPoolInfo,
            proposal3.uniswapPoolInfo,
            proposal3.distributionInfo,
            proposal3.uniswapFeeInfo
        );
    }

    function test_forbidsNonOwnerFromDeployingProposal() public { 
        LaunchPoolProposal memory proposal = _buildDefaultLaunchPoolProposal(address(0));

        factory.addProposal(proposal);

        vm.startPrank(makeAddr("anyone"));

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, makeAddr("anyone")));
        factory.deployProposal(0);
    }

    function test_forbidsNonOwnerFromDeployingLaunchPool() public { 
        LaunchPoolProposal memory proposal = _buildDefaultLaunchPoolProposal(address(0));

        vm.startPrank(makeAddr("anyone"));

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, makeAddr("anyone")));
        factory.deploy(
            proposal.launchPoolImplementation,
            proposal.tokenInfo,
            proposal.launchPoolInfo,
            proposal.uniswapPoolInfo,
            proposal.distributionInfo,
            proposal.uniswapFeeInfo
        );
    }

    function test_forbidsProposalIfPriceLowerAfterLaunch() public { 
        LaunchPoolProposal memory proposal = _getProposalWithLowerPriceAfterLaunch();

        vm.expectRevert(AgentFactory.PriceLowerAfterLaunch.selector);
        factory.addProposal(proposal);
    }

    function test_forbidsLaunchPoolIfPriceLowerAfterLaunch() public { 
        LaunchPoolProposal memory proposal = _getProposalWithLowerPriceAfterLaunch();

        vm.prank(owner);
        vm.expectRevert(AgentFactory.PriceLowerAfterLaunch.selector);
        factory.deploy(
            proposal.launchPoolImplementation,
            proposal.tokenInfo,
            proposal.launchPoolInfo,
            proposal.uniswapPoolInfo,
            proposal.distributionInfo,
            proposal.uniswapFeeInfo
        );
    }

    function test_forbidsDeployingSameProposalTwice() public { 
        factory.addProposal(_buildDefaultLaunchPoolProposal(address(0)));

        vm.startPrank(owner);

        factory.deployProposal(0);
        factory.deployProposal(0);
    }

    function test_canUpgradeAgentFactory() public { 
        AgentFactory newImplementation = new AgentFactory();
    
        vm.prank(owner);
        factory.upgradeToAndCall(address(newImplementation), "");
    }

    function test_forbidsNonOwnerFromUpgradingAgentFactory() public { 
        AgentFactory newImplementation = new AgentFactory();
    
        vm.expectPartialRevert(OwnableUpgradeable.OwnableUnauthorizedAccount.selector);
        factory.upgradeToAndCall(address(newImplementation), "");
    }

    function test_upgradedAgentFactoryWorks() public { 
        AgentFactory newImplementation = new AgentFactoryDisableDeploy();
    
        vm.prank(owner);
        factory.upgradeToAndCall(address(newImplementation), "");

        vm.prank(owner);

        LaunchPoolProposal memory proposal = _buildDefaultLaunchPoolProposal(address(0));

        vm.expectRevert("Deploy disabled");
        factory.deploy(
            proposal.launchPoolImplementation,
            proposal.tokenInfo,
            proposal.launchPoolInfo,
            proposal.uniswapPoolInfo,
            proposal.distributionInfo,
            proposal.uniswapFeeInfo
        );
    }

    function _getProposalWithLowerPriceAfterLaunch() internal returns (LaunchPoolProposal memory) {
        address collateral = address(0);

        TokenInfo memory tokenInfo = TokenInfo({
            owner: tokenOwner,
            name: tokenName,
            symbol: tokenSymbol,
            totalSupply: totalSupply,
            tokenImplementation: agentTokenImpl,
            stakingImplementation: agentStakingImpl
        });

        address[] memory collateralRecipients = new address[](2);
        collateralRecipients[0] = dao;
        collateralRecipients[1] = agentWallet;

        uint256[] memory collateralBasisAmounts = new uint256[](2);
        collateralBasisAmounts[0] = daoCollateralBasisAmount;
        collateralBasisAmounts[1] = agentWalletCollateralBasisAmount;

        LaunchPoolInfo memory launchPoolInfo = LaunchPoolInfo({
            collateral: collateral,
            timeWindow: timeWindow,
            minAmountForLaunch: minAmountForLaunch,
            maxAmountForLaunch: maxAmountForLaunch,
            collateralUniswapPoolBasisAmount: collateralUniswapPoolBasisAmount,
            collateralRecipients: collateralRecipients,
            collateralBasisAmounts: collateralBasisAmounts
        });

        UniswapPoolInfo memory uniswapPoolInfo = UniswapPoolInfo({
            permit2: permit2,
            hook: address(hook),
            lpRecipient: dao,
            lpFee: lpFee,
            tickSpacing: tickSpacing
        });

        address[] memory recipients = new address[](2);
        recipients[0] = dao;
        recipients[1] = agentWallet;
        uint256[] memory basisAmounts = new uint256[](2);
        basisAmounts[0] = agentDaoBasisAmount;
        basisAmounts[1] = agentWalletBasisAmount;

        AgentDistributionInfo memory distributionInfo = AgentDistributionInfo({
            recipients: recipients,
            basisAmounts: basisAmounts,
            launchPoolBasisAmount: 2_500,
            uniswapPoolBasisAmount: 4_000
        });

        address[] memory feeRecipients = new address[](2);
        feeRecipients[0] = dao;
        feeRecipients[1] = agentWallet;

        uint256[] memory feeBasisAmounts = new uint256[](2);
        feeBasisAmounts[0] = daoFeeBasisAmount;
        feeBasisAmounts[1] = agentWalletFeeBasisAmount;

        UniswapFeeInfo memory uniswapFeeInfo = UniswapFeeInfo({
            collateral: collateral,
            burnBasisAmount: burnBasisAmount,
            recipients: feeRecipients,
            basisAmounts: feeBasisAmounts
        });

        return LaunchPoolProposal({
            launchPoolImplementation: address(new AgentLaunchPool()),
            tokenInfo: tokenInfo,
            launchPoolInfo: launchPoolInfo,
            uniswapPoolInfo: uniswapPoolInfo,
            distributionInfo: distributionInfo,
            uniswapFeeInfo: uniswapFeeInfo
        });
    }
}

contract AgentFactoryDisableDeploy is AgentFactory {
    function deploy(
        address _launchPoolImplementation,
        TokenInfo memory _tokenInfo,
        LaunchPoolInfo memory _launchPoolInfo,
        UniswapPoolInfo memory _uniswapPoolInfo,
        AgentDistributionInfo memory _distributionInfo,
        UniswapFeeInfo memory _uniswapFeeInfo
    ) public override returns(address) {
        revert ("Deploy disabled");
    }
}