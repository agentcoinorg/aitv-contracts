// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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

interface IRevokeRole {
    function revokeRole(bytes32 role, address account) external;
}

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
        LaunchPoolProposal memory proposal = _buildDefaultLaunchPoolProposal(address(0)); 
        factory.addProposal(proposal);

        vm.prank(owner);
        factory.deployProposal(0);

        LaunchPoolProposal memory savedProposal = factory.getProposal(0);

        assertEq(savedProposal.launchPoolImplementation, proposal.launchPoolImplementation);

        assertEq(savedProposal.tokenInfo.owner, proposal.tokenInfo.owner);
        assertEq(savedProposal.tokenInfo.name, proposal.tokenInfo.name);
        assertEq(savedProposal.tokenInfo.symbol, proposal.tokenInfo.symbol);
        assertEq(savedProposal.tokenInfo.totalSupply, proposal.tokenInfo.totalSupply);
        assertEq(savedProposal.tokenInfo.tokenImplementation, proposal.tokenInfo.tokenImplementation);
        assertEq(savedProposal.tokenInfo.stakingImplementation, proposal.tokenInfo.stakingImplementation);

        assertEq(savedProposal.launchPoolInfo.collateral, proposal.launchPoolInfo.collateral);
        assertEq(savedProposal.launchPoolInfo.timeWindow, proposal.launchPoolInfo.timeWindow);
        assertEq(savedProposal.launchPoolInfo.minAmountForLaunch, proposal.launchPoolInfo.minAmountForLaunch);
        assertEq(savedProposal.launchPoolInfo.maxAmountForLaunch, proposal.launchPoolInfo.maxAmountForLaunch);
        assertEq(savedProposal.launchPoolInfo.collateralUniswapPoolBasisAmount, proposal.launchPoolInfo.collateralUniswapPoolBasisAmount);
        assertEq(savedProposal.launchPoolInfo.collateralRecipients, proposal.launchPoolInfo.collateralRecipients);
        assertEq(savedProposal.launchPoolInfo.collateralBasisAmounts, proposal.launchPoolInfo.collateralBasisAmounts);

        assertEq(savedProposal.uniswapPoolInfo.permit2, proposal.uniswapPoolInfo.permit2);
        assertEq(savedProposal.uniswapPoolInfo.hook, proposal.uniswapPoolInfo.hook);
        assertEq(savedProposal.uniswapPoolInfo.lpRecipient, proposal.uniswapPoolInfo.lpRecipient);
        assertEq(savedProposal.uniswapPoolInfo.lpFee, proposal.uniswapPoolInfo.lpFee);
        assertEq(savedProposal.uniswapPoolInfo.tickSpacing, proposal.uniswapPoolInfo.tickSpacing);

        assertEq(savedProposal.distributionInfo.recipients, proposal.distributionInfo.recipients);
        assertEq(savedProposal.distributionInfo.basisAmounts, proposal.distributionInfo.basisAmounts);
        assertEq(savedProposal.distributionInfo.launchPoolBasisAmount, proposal.distributionInfo.launchPoolBasisAmount);
        assertEq(savedProposal.distributionInfo.uniswapPoolBasisAmount, proposal.distributionInfo.uniswapPoolBasisAmount);

        assertEq(savedProposal.uniswapFeeInfo.collateral, proposal.uniswapFeeInfo.collateral);
        assertEq(savedProposal.uniswapFeeInfo.burnBasisAmount, proposal.uniswapFeeInfo.burnBasisAmount);
        assertEq(savedProposal.uniswapFeeInfo.recipients, proposal.uniswapFeeInfo.recipients);
        assertEq(savedProposal.uniswapFeeInfo.basisAmounts, proposal.uniswapFeeInfo.basisAmounts);
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

    function test_forbidsProposalIfCollateralDistributionOverflow() public { 
        LaunchPoolProposal memory proposal = _getProposalWithCollateralDistributionOverflow();

        vm.expectRevert(DistributionAndPriceChecker.CollateralMustBeFullyDistributed.selector);
        factory.addProposal(proposal);
    }

    function test_forbidsLaunchPoolIfCollateralDistributionOverflow() public { 
        LaunchPoolProposal memory proposal = _getProposalWithCollateralDistributionOverflow();

        vm.prank(owner);
        vm.expectRevert(DistributionAndPriceChecker.CollateralMustBeFullyDistributed.selector);
        factory.deploy(
            proposal.launchPoolImplementation,
            proposal.tokenInfo,
            proposal.launchPoolInfo,
            proposal.uniswapPoolInfo,
            proposal.distributionInfo,
            proposal.uniswapFeeInfo
        );
    }

    function test_forbidsProposalIfCollateralDistributionUnderflow() public { 
        LaunchPoolProposal memory proposal = _getProposalWithCollateralDistributionUnderflow();

        vm.expectRevert(DistributionAndPriceChecker.CollateralMustBeFullyDistributed.selector);
        factory.addProposal(proposal);
    }
    
    function test_forbidsLaunchPoolIfCollateralDistributionUnderflow() public { 
        LaunchPoolProposal memory proposal = _getProposalWithCollateralDistributionUnderflow();

        vm.prank(owner);
        vm.expectRevert(DistributionAndPriceChecker.CollateralMustBeFullyDistributed.selector);
        factory.deploy(
            proposal.launchPoolImplementation,
            proposal.tokenInfo,
            proposal.launchPoolInfo,
            proposal.uniswapPoolInfo,
            proposal.distributionInfo,
            proposal.uniswapFeeInfo
        );
    }

    function test_forbidsProposalIfAgentDistributionOverflow() public { 
        LaunchPoolProposal memory proposal = _getProposalWithAgentDistributionOverflow();

        vm.expectRevert(DistributionAndPriceChecker.AgentTokenMustBeFullyDistributed.selector);
        factory.addProposal(proposal);
    }

    function test_forbidsLaunchPoolIfAgentDistributionOverflow() public { 
        LaunchPoolProposal memory proposal = _getProposalWithAgentDistributionOverflow();

        vm.prank(owner);
        vm.expectRevert(DistributionAndPriceChecker.AgentTokenMustBeFullyDistributed.selector);
        factory.deploy(
            proposal.launchPoolImplementation,
            proposal.tokenInfo,
            proposal.launchPoolInfo,
            proposal.uniswapPoolInfo,
            proposal.distributionInfo,
            proposal.uniswapFeeInfo
        );
    }

    function test_forbidsProposalIfAgentDistributionUnderflow() public { 
        LaunchPoolProposal memory proposal = _getProposalWithAgentDistributionUnderflow();

        vm.expectRevert(DistributionAndPriceChecker.AgentTokenMustBeFullyDistributed.selector);
        factory.addProposal(proposal);
    }
    
    function test_forbidsLaunchPoolIfAgentDistributionUnderflow() public { 
        LaunchPoolProposal memory proposal = _getProposalWithAgentDistributionUnderflow();

        vm.prank(owner);
        vm.expectRevert(DistributionAndPriceChecker.AgentTokenMustBeFullyDistributed.selector);
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

        vm.expectRevert(DistributionAndPriceChecker.PriceLowerAfterLaunch.selector);
        factory.addProposal(proposal);
    }

    function test_forbidsLaunchPoolIfPriceLowerAfterLaunch() public { 
        LaunchPoolProposal memory proposal = _getProposalWithLowerPriceAfterLaunch();

        vm.prank(owner);
        vm.expectRevert(DistributionAndPriceChecker.PriceLowerAfterLaunch.selector);
        factory.deploy(
            proposal.launchPoolImplementation,
            proposal.tokenInfo,
            proposal.launchPoolInfo,
            proposal.uniswapPoolInfo,
            proposal.distributionInfo,
            proposal.uniswapFeeInfo
        );
    }

    function test_allowsDeployingSameProposalTwice() public { 
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
        address impl1 = address(new AgentFactoryDisableDeploy());
        address impl2 = address(new AgentFactoryV2Mock());

        _launch(makeAddr("depositor1"));

        vm.prank(owner);
        factory.upgradeToAndCall(impl1, "");

        LaunchPoolProposal memory proposal = _buildDefaultLaunchPoolProposal(address(0));

        vm.prank(owner);
        vm.expectRevert("Deploy disabled");
        factory.deploy(
            proposal.launchPoolImplementation,
            proposal.tokenInfo,
            proposal.launchPoolInfo,
            proposal.uniswapPoolInfo,
            proposal.distributionInfo,
            proposal.uniswapFeeInfo
        );

        vm.prank(owner);
        factory.upgradeToAndCall(impl2, "");
        
        _launch(makeAddr("depositor2"));
    }

    function test_forbidsThirdPartyAgentFactoryFromUsingHook() public { 
        factory = _deployAgentFactory(makeAddr("anonOwner"));

        LaunchPoolProposal memory proposal = _buildDefaultLaunchPoolProposal(address(0));

        vm.prank(makeAddr("anonOwner"));
        vm.expectRevert(AgentUniswapHook.OnlyOwnerOrController.selector);
        factory.deploy(
            proposal.launchPoolImplementation,
            proposal.tokenInfo,
            proposal.launchPoolInfo,
            proposal.uniswapPoolInfo,
            proposal.distributionInfo,
            proposal.uniswapFeeInfo
        );
    }

    function test_canChangeFactoryContract() public { 
        factory = _deployAgentFactory(makeAddr("newOwner"));

        vm.prank(owner);
        hook.setController(address(factory));

        LaunchPoolProposal memory proposal = _buildDefaultLaunchPoolProposal(address(0));

        vm.prank(makeAddr("newOwner"));
        AgentLaunchPool pool = AgentLaunchPool(factory.deploy(
            proposal.launchPoolImplementation,
            proposal.tokenInfo,
            proposal.launchPoolInfo,
            proposal.uniswapPoolInfo,
            proposal.distributionInfo,
            proposal.uniswapFeeInfo
        ));

        address depositor = makeAddr("depositor");
        vm.deal(depositor, 10 ether);

        vm.prank(depositor);
        pool.depositETH{value: 10 ether}();

        vm.warp(block.timestamp + timeWindow);

        pool.launch();
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

    function _getProposalWithCollateralDistributionOverflow() internal returns (LaunchPoolProposal memory) {
        address collateral = address(0);

        TokenInfo memory tokenInfo = TokenInfo({
            owner: tokenOwner,
            name: tokenName,
            symbol: tokenSymbol,
            totalSupply: totalSupply,
            tokenImplementation: agentTokenImpl,
            stakingImplementation: agentStakingImpl
        });

        address[] memory collateralRecipients = new address[](3);
        collateralRecipients[0] = dao;
        collateralRecipients[1] = agentWallet;
        collateralRecipients[2] = address(0);

        uint256[] memory collateralBasisAmounts = new uint256[](3);
        collateralBasisAmounts[0] = daoCollateralBasisAmount;
        collateralBasisAmounts[1] = agentWalletCollateralBasisAmount;
        collateralBasisAmounts[2] = 1; // Collateral distribution overflow 

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
            launchPoolBasisAmount: launchPoolBasisAmount,
            uniswapPoolBasisAmount: uniswapPoolBasisAmount
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

    function _getProposalWithCollateralDistributionUnderflow() internal returns (LaunchPoolProposal memory) {
        address collateral = address(0);

        TokenInfo memory tokenInfo = TokenInfo({
            owner: tokenOwner,
            name: tokenName,
            symbol: tokenSymbol,
            totalSupply: totalSupply,
            tokenImplementation: agentTokenImpl,
            stakingImplementation: agentStakingImpl
        });

        address[] memory collateralRecipients = new address[](1);
        collateralRecipients[0] = dao;

        // Collateral distribution underflow - missing agent wallet distribution
        uint256[] memory collateralBasisAmounts = new uint256[](1);
        collateralBasisAmounts[0] = daoCollateralBasisAmount; 

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
            launchPoolBasisAmount: launchPoolBasisAmount,
            uniswapPoolBasisAmount: uniswapPoolBasisAmount
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

    function _getProposalWithAgentDistributionOverflow() internal returns (LaunchPoolProposal memory) {
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

        address[] memory recipients = new address[](3);
        recipients[0] = dao;
        recipients[1] = agentWallet;
        recipients[2] = address(0);
        uint256[] memory basisAmounts = new uint256[](3);
        basisAmounts[0] = agentDaoBasisAmount;
        basisAmounts[1] = agentWalletBasisAmount;
        basisAmounts[2] = 1; // Agent distribution overflow

        AgentDistributionInfo memory distributionInfo = AgentDistributionInfo({
            recipients: recipients,
            basisAmounts: basisAmounts,
            launchPoolBasisAmount: launchPoolBasisAmount,
            uniswapPoolBasisAmount: uniswapPoolBasisAmount
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

     function _getProposalWithAgentDistributionUnderflow() internal returns (LaunchPoolProposal memory) {
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

        // Agent distribution underflow - missing agent wallet distribution
        address[] memory recipients = new address[](2);
        recipients[0] = dao;
        uint256[] memory basisAmounts = new uint256[](2);
        basisAmounts[0] = agentDaoBasisAmount;
        
        AgentDistributionInfo memory distributionInfo = AgentDistributionInfo({
            recipients: recipients,
            basisAmounts: basisAmounts,
            launchPoolBasisAmount: launchPoolBasisAmount,
            uniswapPoolBasisAmount: uniswapPoolBasisAmount
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

contract AgentFactoryDisableDeploy is AgentFactory {
    function deploy(
        address,
        TokenInfo memory,
        LaunchPoolInfo memory,
        UniswapPoolInfo memory,
        AgentDistributionInfo memory,
        UniswapFeeInfo memory
    ) public pure override returns(address payable) {
        revert ("Deploy disabled");
    }
}

contract AgentFactoryV2Mock is AgentFactory {
}