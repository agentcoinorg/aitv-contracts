// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title AgentStaking
/// @notice The following is a contract for staking agent tokens
/// Tokens can be unstaked, but will be locked for a period of time (1 day) before they can be claimed
contract AgentStaking is OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    
    error EmptyAmount();
    error InsufficientStakedBalance();
    error NoLockedWithdrawalsFound();

    IERC20 public agentToken;

    struct LockedWithdrawal {
        uint256 amount;
        uint256 lockedUntil;
    }

    mapping(address => uint256) internal stakes;

    // Queue of withdrawals
    // Withdrawals are pushed to the end of the queue
    // withdrawalQueueStartIndexes is used to track the start of the queue since were using an array
    // This is to avoid shifting the array every time a withdrawal is claimed
    mapping(address => LockedWithdrawal[]) internal withdrawalQueue;
    mapping(address => uint256) internal withdrawalQueueStartIndexes;

    event Stake(address indexed account, uint256 amount, uint256 totalStaked);
    event Unstake(address indexed account, uint256 amount, uint256 unlocksAt, uint256 totalStaked);
    event Claim(address indexed account, uint256 amount, address recipient);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner, address _agentToken) public initializer {
        __Ownable_init(owner);
        __UUPSUpgradeable_init();

        agentToken = IERC20(_agentToken);
    }

    /// @notice Stake agent tokens
    /// @param amount The amount of tokens to stake
    function stake(uint256 amount) public virtual {
        if (amount == 0) {
            revert EmptyAmount();
        }

        agentToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 totalStaked = stakes[msg.sender] + amount;
        stakes[msg.sender] = totalStaked;
        emit Stake(msg.sender, amount, totalStaked);
    }

    /// @notice Unstake agent tokens
    /// @param amount The amount of tokens to unstake
    /// @dev Tokens will be locked for a period of time (1 day) before they can be claimed
    function unstake(uint256 amount) public virtual {
        if (amount == 0) {
            revert EmptyAmount();
        }

        if (amount > stakes[msg.sender]) {
            revert InsufficientStakedBalance();
        }

        uint256 totalStaked = stakes[msg.sender] - amount; 
        stakes[msg.sender] = totalStaked;

        uint256 unlocksAt = block.timestamp + unlock_time();

        withdrawalQueue[msg.sender].push(LockedWithdrawal(amount, unlocksAt));
        emit Unstake(msg.sender, amount, unlocksAt, totalStaked);
    }

    /// @notice Claim unlocked agent tokens
    /// @param count The number of 'unlocked' withdrawals to claim
    function claim(uint256 count, address recipient) public virtual {
        uint256 start = withdrawalQueueStartIndexes[msg.sender];

        uint256 length = withdrawalQueue[msg.sender].length;

        if (start >= length) {
            revert NoLockedWithdrawalsFound();
        }

        // Handle out of bounds
        uint256 end = start + count > length ? length : start + count;

        uint256 amountToTransfer = 0;
        for (; start < end; start++) {
            if (withdrawalQueue[msg.sender][start].amount == 0) {
                revert EmptyAmount();
            }
            // We've reached a locked withdrawal, the rest have an even later lockedUntil time (since it's a queue)
            if (block.timestamp < withdrawalQueue[msg.sender][start].lockedUntil) {
                break;
            }
            amountToTransfer += withdrawalQueue[msg.sender][start].amount;
            delete withdrawalQueue[msg.sender][start];
        }

        if (amountToTransfer > 0) {
            withdrawalQueueStartIndexes[msg.sender] = start;
            agentToken.safeTransfer(recipient, amountToTransfer);

            emit Claim(msg.sender, amountToTransfer, recipient);
        }
    }

    /// @notice Get the amount of agent tokens staked by an account
    /// @param account The account to get the staked amount for
    function getStakedAmount(address account) public virtual view returns (uint256) {
        return stakes[account];
    }

    /// @notice Get the locked withdrawals for an account
    /// @param account The account to get the withdrawals for
    /// @param start The start index of the withdrawals
    /// @param count The number of withdrawals to get
    function getWithdrawals(address account, uint256 start, uint256 count) public virtual view returns (LockedWithdrawal[] memory) {
        start = withdrawalQueueStartIndexes[account] + start;
        uint256 length = withdrawalQueue[account].length;

        if (start >= length) {
            return new LockedWithdrawal[](0);
        }

        uint256 end = start + count > length ? length : start + count;

        count = end - start;

        LockedWithdrawal[] memory result = new LockedWithdrawal[](count);

        for (uint256 i = 0; i < count; i++) {
            result[i] = withdrawalQueue[account][start + i];
        }

        return result;
    }

    /// @notice Get the number of locked withdrawals for an account
    /// @param account The account to get the number of withdrawals for
    function getWithdrawalCount(address account) public virtual view returns (uint256) {
        return withdrawalQueue[account].length - withdrawalQueueStartIndexes[account];
    }

    /// @notice Get the unlock time
    function unlock_time() public virtual view returns (uint256) {
        return 1 days;
    }

    /// @dev Only the owner can upgrade the contract
    function _authorizeUpgrade(address) internal virtual override onlyOwner {}
}
