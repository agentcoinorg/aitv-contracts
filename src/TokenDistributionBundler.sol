// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITokenDistributor} from "./interfaces/ITokenDistributor.sol";

contract TokenDistributionBundler {
    address public immutable distributor;

    struct ETHDistributionParams {
        bytes32 distributionName;
        address beneficiary;
        address recipientOnFailure;
        uint256[] minAmountsOut;
        uint256 deadline;
        uint256 value;
    }

    struct ERC20DistributionParams {
        bytes32 distributionName;
        address beneficiary;
        uint256 amount;
        address paymentToken;
        address recipientOnFailure;
        uint256[] minAmountsOut;
        uint256 deadline;
    }

    ETHDistributionParams[] public ethDistributions;
    ERC20DistributionParams[] public erc20Distributions;

    constructor(address _distributor) {
        distributor = _distributor;
    }

    // === ETH Distribution ===

    function addETHDistribution(
        bytes32 _distributionName,
        address _beneficiary,
        address _recipientOnFailure,
        uint256[] calldata _minAmountsOut,
        uint256 _deadline
    ) external payable {
        require(msg.value > 0, "Zero ETH sent");

        ethDistributions.push(ETHDistributionParams({
            distributionName: _distributionName,
            beneficiary: _beneficiary,
            recipientOnFailure: _recipientOnFailure,
            minAmountsOut: _minAmountsOut,
            deadline: _deadline,
            value: msg.value
        }));
    }

    function executeETHDistributions(uint256 maxCount) external {
        uint256 executed = 0;
        uint256 i = 0;

        while (i < ethDistributions.length && executed < maxCount) {
            ETHDistributionParams memory params = ethDistributions[i];

            if (block.timestamp > params.deadline) {
                _removeETHDistribution(i);
                continue;
            }

            try ITokenDistributor(distributor).distributeETH{value: params.value}(
                params.distributionName,
                params.beneficiary,
                params.recipientOnFailure,
                params.minAmountsOut,
                params.deadline
            ) {
                _removeETHDistribution(i);
                executed++;
            } catch {
                i++;
            }
        }
    }

    function _removeETHDistribution(uint256 index) internal {
        uint256 last = ethDistributions.length - 1;
        if (index != last) {
            ethDistributions[index] = ethDistributions[last];
        }
        ethDistributions.pop();
    }

    // === ERC20 Distribution ===

    function addERC20Distribution(
        bytes32 _distributionName,
        address _beneficiary,
        uint256 _amount,
        address _paymentToken,
        address _recipientOnFailure,
        uint256[] calldata _minAmountsOut,
        uint256 _deadline
    ) external {
        require(_amount > 0, "Amount must be greater than zero");

        IERC20(_paymentToken).transferFrom(msg.sender, address(this), _amount);

        erc20Distributions.push(ERC20DistributionParams({
            distributionName: _distributionName,
            beneficiary: _beneficiary,
            amount: _amount,
            paymentToken: _paymentToken,
            recipientOnFailure: _recipientOnFailure,
            minAmountsOut: _minAmountsOut,
            deadline: _deadline
        }));
    }

    function executeERC20Distributions(uint256 maxCount) external {
        uint256 executed = 0;
        uint256 i = 0;

        while (i < erc20Distributions.length && executed < maxCount) {
            ERC20DistributionParams memory params = erc20Distributions[i];

            if (block.timestamp > params.deadline) {
                _removeERC20Distribution(i);
                continue;
            }

            try IERC20(params.paymentToken).approve(distributor, params.amount) {
                try ITokenDistributor(distributor).distributeERC20(
                    params.distributionName,
                    params.beneficiary,
                    params.amount,
                    params.paymentToken,
                    params.recipientOnFailure,
                    params.minAmountsOut,
                    params.deadline
                ) {
                    _removeERC20Distribution(i);
                    executed++;
                } catch {
                    i++;
                }
            } catch {
                i++;
            }
        }
    }

    function _removeERC20Distribution(uint256 index) internal {
        uint256 last = erc20Distributions.length - 1;
        if (index != last) {
            erc20Distributions[index] = erc20Distributions[last];
        }
        erc20Distributions.pop();
    }

    // === View ===

    function getETHDistributionCount() external view returns (uint256) {
        return ethDistributions.length;
    }

    function getERC20DistributionCount() external view returns (uint256) {
        return erc20Distributions.length;
    }
}
