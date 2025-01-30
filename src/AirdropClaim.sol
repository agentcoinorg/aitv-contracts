// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title AirdropClaim
/// @notice The following is a contract to migrate Gecko V1 tokens to V2
/// Users that hold Gecko V1 tokens can claim a proportional amount of Gecko V2 tokens
contract AirdropClaim {
    using SafeERC20 for IERC20;

    error AlreadyDeposited();

    event Claim(address indexed recipient, address claimer, uint256 fromBalance, uint256 amountClaimed);

    IERC20 public immutable fromToken;
    IERC20 public toToken;

    uint256 public totalAmountForClaim;

    mapping(address => bool) public claimed;

    constructor(address _fromToken) {
        fromToken = IERC20(_fromToken);
    }

    /// @notice Deposit tokens to be claimed by holders of Gecko V1
    /// @dev This will be called in the same transaction as contract creation, so no need for authorization checks
    /// @param _toToken The address of the token to be claimed (Gecko V2)
    /// @param _totalAmountForClaim The total amount of tokens to be claimed
    function deposit(address _toToken, uint256 _totalAmountForClaim) external {
        if (totalAmountForClaim != 0) {
            revert AlreadyDeposited();
        }

        toToken = IERC20(_toToken);
        toToken.safeTransferFrom(msg.sender, address(this), _totalAmountForClaim);

        totalAmountForClaim = _totalAmountForClaim;
    }

    function multiClaim(address[] calldata _recipients) external {
        for (uint256 i = 0; i < _recipients.length; i++) {
            claim(_recipients[i]);
        }
    }

    /// @notice Claim tokens for the recipient that will be transferred from the contract to the recipient
    /// @param _recipient The address of the recipient
    /// @return If the claim was successful or not
    function claim(address _recipient) public returns (bool) {
        if (claimed[_recipient]) {
            return false;
        }
        uint256 balance = fromToken.balanceOf(_recipient);

        if (balance == 0) {
            return false;
        }

        uint256 amountToTransfer = totalAmountForClaim  * balance / fromToken.totalSupply();

        claimed[_recipient] = true;
        toToken.safeTransfer(_recipient, amountToTransfer);

        emit Claim(_recipient, msg.sender, balance, amountToTransfer);

        return true;
    }

    /// @notice Check if the recipient can claim tokens
    /// @param _recipient The address of the recipient
    function canClaim(address _recipient) public view returns (bool) {
        return !claimed[_recipient] && fromToken.balanceOf(_recipient) > 0;
    }
}
