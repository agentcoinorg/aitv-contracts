// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {IAgentKey} from "../src/IAgentKey.sol";

import {DeployAgentKey} from "../script/DeployAgentKey.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract AgentKeyTest is Test {
    IAgentKey public key;
    address whitelist;
    address beneficiary = makeAddr("beneficiary");
    address control = makeAddr("control");
    address feeCollector = makeAddr("feeCollector");
    address user = makeAddr("user");
    address recipient = makeAddr("recipient");

    function setUp() public {
        DeployAgentKey keyDeployer = new DeployAgentKey();

        (key, whitelist) = keyDeployer.deploy(
            HelperConfig.AgentKeyConfig({
                name: "Agent keys",
                symbol: "KEY",
                priceIncrease: 0.0002 * 1e18,
                investmentReserveBasisPoints: 9000,
                feeBasisPoints: 5000,
                revenueCommitmentBasisPoints: 9500,
                beneficiary: payable(beneficiary),
                control: control,
                feeCollector: payable(feeCollector)
            })
        );
    }

    function test_canBuyTokens() public {
        uint256 amountToSpend = 1 ether;
        uint256 expectedBeneficiaryFee = 0.05 ether;
        uint256 expectedFeeCollectorFee = 0.05 ether;
        uint256 expectedReserve = 0.9 ether;

        vm.deal(user, amountToSpend);

        assertEq(key.balanceOf(user), 0);
        assertEq(beneficiary.balance, 0);
        assertEq(feeCollector.balance, 0);

        vm.startPrank(user);

        uint256 minBuyAmount = key.estimateBuyValue(amountToSpend);
        assertGt(minBuyAmount, 0);

        key.buy{value: amountToSpend}(user, amountToSpend, minBuyAmount);

        uint256 balance = key.balanceOf(user);

        assertGe(balance, minBuyAmount);
        assertEq(key.balanceOf(address(beneficiary)), 0);
        assertEq(key.balanceOf(address(feeCollector)), 0);

        assertEq(beneficiary.balance, expectedBeneficiaryFee);
        assertEq(feeCollector.balance, expectedFeeCollectorFee);

        assertEq(key.totalSupply(), balance);
        assertEq(key.buybackReserve(), expectedReserve);
    }

    function test_curveBehavesAccordingToFormula1() public {
        // Initial price is 100 KEY for 1 ETH
        // Formula: price = (tokens ** 2) / 2 * buySlopeNum / buySlopeDen

        uint256 amountToSpend = 600 ether;

        vm.deal(user, amountToSpend);

        assertEq(key.balanceOf(user), 0);
        assertEq(beneficiary.balance, 0);
        assertEq(feeCollector.balance, 0);

        vm.startPrank(user);

        uint256 minBuyAmount1 = key.estimateBuyValue(100 ether);
        assertEq(minBuyAmount1, 1000 ether);

        key.buy{value: 100 ether}(user, 100 ether, minBuyAmount1);
    }

    function test_curveBehavesAccordingToFormula2() public {
        // Initial price is 100 KEY for 1 ETH
        // Formula: price = (tokens ** 2) / 2 * buySlopeNum / buySlopeDen

        uint256 amountToSpend = 600 ether;

        vm.deal(user, amountToSpend);

        assertEq(key.balanceOf(user), 0);
        assertEq(beneficiary.balance, 0);
        assertEq(feeCollector.balance, 0);

        vm.startPrank(user);

        uint256 minBuyAmount1 = key.estimateBuyValue(1);

        key.buy{value: 1}(user, 1, minBuyAmount1);

        uint256 balance1 = key.balanceOf(user);
        assertEq(balance1, minBuyAmount1);
        uint256 price1 = minBuyAmount1;

        uint256 minBuyAmount2 = key.estimateBuyValue(1);
        uint256 price2 = minBuyAmount2;

        key.buy{value: 1}(user, 1, minBuyAmount2);

        console.logUint(price1);
        console.logUint(price2);

        uint256 minBuyAmount3 = key.estimateBuyValue(1);
        uint256 price3 = minBuyAmount3;
        console.logUint(price3);
    }

    function test_curveBehavesAccordingToFormula3() public {
        // Initial price is 100 KEY for 1 ETH
        // Formula: price = (tokens ** 2) / 2 * buySlopeNum / buySlopeDen

        uint256 amountToSpend = 600 ether;

        vm.deal(user, amountToSpend);

        assertEq(key.balanceOf(user), 0);
        assertEq(beneficiary.balance, 0);
        assertEq(feeCollector.balance, 0);

        vm.startPrank(user);

        uint256 minBuyAmount1 = key.estimateBuyValue(100 ether);
        assertEq(minBuyAmount1, 1000 ether);

        key.buy{value: 100 ether}(user, 100 ether, minBuyAmount1);

        uint256 balance1 = key.balanceOf(user);

        assertEq(balance1, 1000 ether);

        uint256 minBuyAmount2 = key.estimateBuyValue(200 ether);
        assertEq(minBuyAmount2, 732.050807568877293527 ether);

        key.buy{value: 200 ether}(user, 200 ether, minBuyAmount2);

        uint256 balance2 = key.balanceOf(user);

        assertEq(balance2, 1732.050807568877293527 ether);

        uint256 minBuyAmount3 = key.estimateBuyValue(300 ether);
        assertEq(minBuyAmount3, 717.438935214300804669 ether);

        key.buy{value: 300 ether}(user, 300 ether, minBuyAmount3);

        uint256 balance3 = key.balanceOf(user);

        assertEq(balance3, 2449.489742783178098196 ether);

        assertEq(key.totalSupply(), balance3);
    }

    function test_priceIncreasesWhenSupplyIncreases() public {
        uint256 amountToSpend = 1 ether;
        uint256 expectedBeneficiaryFee = 0.05 ether;
        uint256 expectedFeeCollectorFee = 0.05 ether;
        uint256 expectedReserve = 0.9 ether;

        vm.deal(user, amountToSpend);
        vm.startPrank(user);

        uint256 minBuyAmount1 = key.estimateBuyValue(amountToSpend / 2);
        assertGt(minBuyAmount1, 0);

        key.buy{value: amountToSpend / 2}(user, amountToSpend / 2, minBuyAmount1);

        uint256 balance1 = key.balanceOf(user);

        assertGt(balance1, 0);

        assertEq(beneficiary.balance, expectedBeneficiaryFee / 2);
        assertEq(feeCollector.balance, expectedFeeCollectorFee / 2);

        assertEq(key.totalSupply(), balance1);
        assertEq(key.buybackReserve(), expectedReserve / 2);

        uint256 minBuyAmount2 = key.estimateBuyValue(amountToSpend / 2);
        assertGt(minBuyAmount2, 0);
        assertLt(minBuyAmount2, minBuyAmount1);

        key.buy{value: amountToSpend / 2}(user, amountToSpend / 2, minBuyAmount2);

        uint256 balance2 = key.balanceOf(user);

        assertGt(balance2, 0);
        assertGt(balance2 - balance1, 0);
        assertGt(balance2, balance1);
        assertLt(balance2 - balance1, balance1);

        assertEq(beneficiary.balance, expectedBeneficiaryFee);
        assertEq(feeCollector.balance, expectedFeeCollectorFee);

        assertEq(key.totalSupply(), balance2);
        assertEq(key.buybackReserve(), expectedReserve);
    }

    function test_transfersAreDisabled() public {
        uint256 amountToSpend = 1 ether;

        vm.deal(user, amountToSpend);

        uint256 minBuyAmount = key.estimateBuyValue(amountToSpend);
        assertGt(minBuyAmount, 0);

        vm.startPrank(user);
        key.buy{value: amountToSpend}(user, amountToSpend, 1);

        uint256 userBalance = key.balanceOf(user);
        assertGe(userBalance, minBuyAmount);

        vm.expectRevert("TRANSFERS_DISABLED");
        key.transfer(recipient, 1);

        assertEq(key.balanceOf(user), userBalance);
        assertEq(key.totalSupply(), userBalance);

        vm.deal(beneficiary, amountToSpend);
        vm.startPrank(beneficiary);
        key.buy{value: amountToSpend}(beneficiary, amountToSpend, 1);

        uint256 beneficiaryBalance = key.balanceOf(beneficiary);
        assertGe(beneficiaryBalance, key.estimateBuyValue(amountToSpend));

        vm.expectRevert("TRANSFERS_DISABLED");
        key.transfer(recipient, 1);

        assertEq(key.balanceOf(user), userBalance);
        assertEq(key.balanceOf(beneficiary), beneficiaryBalance);
        assertEq(key.totalSupply(), userBalance + beneficiaryBalance);
    }

    function test_canSellTokens() public {
        uint256 amountToSpend = 1 ether;
        uint256 expectedBeneficiaryFee = 0.05 ether;
        uint256 expectedFeeCollectorFee = 0.05 ether;
        uint256 expectedReserve = 0.9 ether;
        // Some of the buybackReserve is left over even after selling all tokens
        // Most likely due to rounding errors or because of the fees
        uint256 expectedMaxReserveAfterSell = 0.001 ether;

        vm.deal(user, amountToSpend);

        uint256 minBuyAmount = key.estimateBuyValue(amountToSpend);
        assertGt(minBuyAmount, 0);

        vm.startPrank(user);
        key.buy{value: amountToSpend}(user, amountToSpend, minBuyAmount);

        uint256 balance = key.balanceOf(user);

        assertGt(balance, 0);

        assertEq(beneficiary.balance, expectedBeneficiaryFee);
        assertEq(feeCollector.balance, expectedFeeCollectorFee);
        assertEq(key.buybackReserve(), expectedReserve);

        key.sell(payable(user), balance, 1);

        assertEq(key.balanceOf(user), 0);

        assertEq(beneficiary.balance, expectedBeneficiaryFee);
        assertEq(feeCollector.balance, expectedFeeCollectorFee);

        assertEq(key.totalSupply(), 0);
        assertLt(key.buybackReserve(), expectedMaxReserveAfterSell);
    }

    function test_priceDecreasesWhenSupplyDecreases() public {
        uint256 amountToSpend = 1 ether;
        uint256 expectedBeneficiaryFee = 0.05 ether;
        uint256 expectedFeeCollectorFee = 0.05 ether;
        uint256 expectedReserve = 0.9 ether;

        vm.deal(user, amountToSpend);
        vm.startPrank(user);

        uint256 minBuyAmount1 = key.estimateBuyValue(amountToSpend / 2);
        assertGt(minBuyAmount1, 0);

        key.buy{value: amountToSpend / 2}(user, amountToSpend / 2, minBuyAmount1);

        uint256 balance1 = key.balanceOf(user);

        assertGt(balance1, 0);

        assertEq(beneficiary.balance, expectedBeneficiaryFee / 2);
        assertEq(feeCollector.balance, expectedFeeCollectorFee / 2);

        assertEq(key.totalSupply(), balance1);
        assertEq(key.buybackReserve(), expectedReserve / 2);

        uint256 minBuyAmount2 = key.estimateBuyValue(amountToSpend / 2);
        assertGt(minBuyAmount2, 0);
        assertLt(minBuyAmount2, minBuyAmount1);

        key.buy{value: amountToSpend / 2}(user, amountToSpend / 2, minBuyAmount2);

        uint256 balance2 = key.balanceOf(user);

        uint256 minBuyAmount3 = key.estimateBuyValue(amountToSpend / 2);
        assertLt(minBuyAmount3, minBuyAmount2);

        key.sell(payable(user), balance2 - balance1, 1);

        assertEq(key.balanceOf(user), balance1);
        assertEq(key.totalSupply(), balance1);

        uint256 minBuyAmount4 = key.estimateBuyValue(amountToSpend / 2);
        assertGt(minBuyAmount4, minBuyAmount3);
    }

    function test_pay() public {
        uint256 amountToPay = 10 ether;
        uint256 revenueFee = amountToPay * 5 / 100; // 5%
        uint256 expectedReserve = 9.5 ether;

        vm.deal(user, amountToPay);

        assertEq(key.totalSupply(), 0);
        assertEq(key.buybackReserve(), 0);
        assertEq(user.balance, amountToPay);

        assertEq(key.balanceOf(address(this)), 0);
        assertEq(beneficiary.balance, 0);
        assertEq(feeCollector.balance, 0);

        vm.startPrank(user);
        key.pay{value: amountToPay}(amountToPay);

        assertEq(key.totalSupply(), 0);
        assertEq(key.buybackReserve(), expectedReserve);

        assertEq(beneficiary.balance, revenueFee);
        assertEq(feeCollector.balance, 0);
        assertEq(user.balance, 0);
    }

    function test_payByTransfer() public {
        uint256 amountToPay = 10 ether;
        uint256 expectedReserve = amountToPay;

        vm.deal(user, amountToPay);

        assertEq(key.totalSupply(), 0);
        assertEq(key.buybackReserve(), 0);

        assertEq(key.balanceOf(address(this)), 0);
        assertEq(beneficiary.balance, 0);
        assertEq(feeCollector.balance, 0);

        vm.startPrank(user);

        payable(address(key)).transfer(amountToPay);

        assertEq(key.totalSupply(), 0);
        assertEq(key.buybackReserve(), expectedReserve);

        assertEq(beneficiary.balance, 0);
        assertEq(feeCollector.balance, 0);
    }

    function test_sellPriceIncreasesAfterPay() public {
        uint256 amountForBuy = 1 ether;
        uint256 amountToPay = 10 ether;

        vm.deal(user, amountForBuy + amountToPay);
        vm.startPrank(user);

        uint256 minBuyAmount = key.estimateBuyValue(amountForBuy);
        assertGt(minBuyAmount, 0);

        key.buy{value: amountForBuy}(user, amountForBuy, minBuyAmount);

        uint256 minSellAmount = key.estimateSellValue(minBuyAmount);
        assertGt(minSellAmount, 0);

        key.pay{value: amountToPay}(amountToPay);

        uint256 minSellAmountAfterPay = key.estimateSellValue(minBuyAmount);
        assertGt(minSellAmountAfterPay, minSellAmount);
    }

    function test_buyPriceRemainsSameAfterPay() public {
        uint256 amountForBuy = 1 ether;
        uint256 amountToPay = 10 ether;

        vm.deal(user, amountForBuy + amountToPay);
        vm.startPrank(user);

        uint256 minBuyAmount = key.estimateBuyValue(amountForBuy);
        assertGt(minBuyAmount, 0);

        key.buy{value: amountForBuy}(user, amountForBuy, minBuyAmount);

        uint256 minBuyAmountBeforePay = key.estimateBuyValue(amountForBuy);
        assertGt(minBuyAmountBeforePay, 0);

        key.pay{value: amountToPay}(amountToPay);

        uint256 minBuyAmountAfterPay = key.estimateBuyValue(amountForBuy);
        assertEq(minBuyAmountAfterPay, minBuyAmountBeforePay);
    }

    function test_onlyBeneficiaryCanClose() public {
        vm.prank(user);
        vm.expectRevert("BENEFICIARY_ONLY");
        key.close();

        vm.prank(control);
        vm.expectRevert("BENEFICIARY_ONLY");
        key.close();

        vm.prank(beneficiary);
        key.close();
    }

    function test_onlyControlCanUpdateConfig() public {
        vm.prank(user);
        vm.expectRevert("CONTROL_ONLY");
        key.updateConfig(whitelist, payable(beneficiary), payable(control), payable(feeCollector), 0, 9500, 1, 0);

        vm.prank(beneficiary);
        vm.expectRevert("CONTROL_ONLY");
        key.updateConfig(whitelist, payable(beneficiary), payable(control), payable(feeCollector), 0, 9500, 1, 0);

        vm.prank(control);
        key.updateConfig(whitelist, payable(beneficiary), payable(control), payable(feeCollector), 0, 9500, 1, 0);
    }

    function test_contractCanBeStopped() public {
        vm.prank(beneficiary);
        key.stopAndTransferReserve(payable(recipient));
        assertEq(key.isStopped(), true);
    }

    function test_buysAndSellsAreDisabledWhenContractIsStopped() public {
        vm.deal(user, 2 ether);
        vm.prank(user);
        uint256 minBuyAmount = key.estimateBuyValue(1 ether);

        key.buy{value: 1 ether}(user, 1 ether, minBuyAmount);

        vm.prank(beneficiary);
        key.stopAndTransferReserve(payable(recipient));

        vm.prank(user);
        vm.expectRevert("Contract is stopped");
        key.buy{value: 1 ether}(user, 1 ether, 1);

        vm.prank(user);
        vm.expectRevert("PRICE_SLIPPAGE"); // Error is PRICE_SLIPPAGE because the reserve check is done before the stopped check
        key.sell(payable(user), 1 ether, 1);
    }

    function test_reserveIsTransferredAfterStop() public {
        vm.deal(user, 2 ether);
        vm.prank(user);
        uint256 minBuyAmount = key.estimateBuyValue(1 ether);

        key.buy{value: 1 ether}(user, 1 ether, minBuyAmount);

        uint256 reserveBefore = key.buybackReserve();

        assertGt(reserveBefore, 0);
        assertEq(address(key).balance, reserveBefore);

        vm.prank(beneficiary);
        key.stopAndTransferReserve(payable(recipient));

        assertEq(key.buybackReserve(), 0);
        assertEq(address(key).balance, 0);

        assertEq(recipient.balance, reserveBefore);
    }

    function test_transfersAreDisabledWhenContractIsStopped() public {
        vm.deal(user, 2 ether);
        vm.prank(user);
        uint256 minBuyAmount = key.estimateBuyValue(1 ether);

        key.buy{value: 1 ether}(user, 1 ether, minBuyAmount);

        vm.prank(beneficiary);
        key.stopAndTransferReserve(payable(recipient));

        vm.prank(user);
        vm.expectRevert("Contract is stopped");
        key.transfer(makeAddr("new-recipient"), minBuyAmount);
    }

    function test_onlyBeneficiaryCanStopTheContract() public {
        assertEq(key.isStopped(), false);

        vm.prank(user);
        vm.expectRevert("BENEFICIARY_ONLY");
        key.stopAndTransferReserve(payable(recipient));

        vm.prank(control);
        vm.expectRevert("BENEFICIARY_ONLY");
        key.stopAndTransferReserve(payable(recipient));

        vm.prank(beneficiary);
        key.stopAndTransferReserve(payable(recipient));

        assertEq(key.isStopped(), true);
    }
}
