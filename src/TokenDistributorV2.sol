// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IBurnable} from "./interfaces/IBurnable.sol";

/// @title TokenDistributorV2 (Plan Executor)
/// @notice Generic plan executor for push-based distributions driven entirely by calldata.
contract TokenDistributorV2 is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 internal constant MAX_BPS = 10_000;
    address internal constant ETH = address(0);

    // -----------------------------
    // Enums / Structs
    // -----------------------------

    enum ActionType {
        Send,
        Burn,
        SendAndCall
    }

    enum CallArgType {
        Beneficiary,
        Sender,
        Amount
    }

    struct Beneficiary {
        address beneficiary;
        uint128 weight;
        address recipientOnFailure; // address(0) means hard-fail
    }

    struct BeneficiaryGroup {
        Beneficiary[] beneficiaries;
    }

    /// @notice Opaque swap step executed by calling an allowlisted target.
    /// @dev `tokenIn == address(0)` means ETH. `tokenOut == address(0)` means ETH.
    struct SwapStep {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minOut; // validated via balance delta
        address allowanceTarget; // spender to approve for ERC20 tokenIn
        address swapTarget; // called with callData
        uint256 value; // ETH value forwarded to swapTarget
        bytes callData;
    }

    struct Bucket {
        address sourceToken; // token distributed/burned/called-with; address(0) for ETH
        ActionType actionType;
        address callTarget; // SendAndCall only
        bytes4 selector; // SendAndCall only
        bytes12 callArgsPacked; // SendAndCall only (see CallArgType packing)
        uint16 bucketBps; // bps over the root input amount
        uint16 groupId; // which beneficiary group to distribute to (0-based)
    }

    struct Plan {
        uint256 totalAmount; // root input amount in the payment token
        uint256 deadline;
        bytes32 meta;
        BeneficiaryGroup[] groups;
        SwapStep[] swaps;
        Bucket[] buckets;
    }

    // -----------------------------
    // Errors
    // -----------------------------

    error DeadlinePassed();
    error InvalidPlan();
    error TotalAmountMismatch();
    error InvalidAllowlistEntry();
    error SwapNotAllowlisted(address swapTarget, address allowanceTarget);
    error SwapCallFailed(address swapTarget);
    error SwapSpentMismatch(uint256 index, uint256 spent, uint256 expected);
    error SwapMinOutNotMet(uint256 index, uint256 realizedOut, uint256 minOut);
    error SwapTokenInMismatch(uint256 index, address expectedTokenIn, address gotTokenIn);
    error SwapTokenOutInvalid(uint256 index, address tokenOut);
    error SwapValueMismatch(uint256 index, uint256 expected, uint256 got);
    error SwapAmountInMismatch(address tokenOut, uint256 expected, uint256 got);

    error BasisPointsMustSumTo10000();
    error ZeroAddressNotAllowed();
    error ZeroAmountNotAllowed();
    error TooManyCallArgs();
    error InvalidCallArgType();
    error BurningETHNotAllowed();
    error CallFailed(address target);
    error TransferFailed(address token, address to, uint256 amount);

    // -----------------------------
    // Events
    // -----------------------------

    /// @dev Kept for indexing compatibility with TokenDistributor.sol
    event TokenTransferred(address indexed token, address indexed recipient, bytes32 indexed meta, address sender, uint256 amount);

    event AllowlistEnabledSet(bool enabled);
    event SwapAllowlistSet(address indexed swapTarget, address indexed allowanceTarget, bool allowed);
    event FundsRescued(address indexed token, address indexed to, uint256 amount);

    // -----------------------------
    // Admin config
    // -----------------------------

    bool public allowlistEnabled;
    mapping(address => mapping(address => bool)) public isSwapAllowlisted;

    constructor(address _owner) Ownable(_owner) {}

    receive() external payable {}

    function setAllowlistEnabled(bool enabled) external onlyOwner {
        allowlistEnabled = enabled;
        emit AllowlistEnabledSet(enabled);
    }

    function setSwapAllowlist(address swapTarget, address allowanceTarget, bool allowed) external onlyOwner {
        if (swapTarget == address(0) || allowanceTarget == address(0)) revert InvalidAllowlistEntry();
        isSwapAllowlisted[swapTarget][allowanceTarget] = allowed;
        emit SwapAllowlistSet(swapTarget, allowanceTarget, allowed);
    }

    /// @notice Rescue ETH / ERC20 that are stuck in this contract (e.g., accidental transfers or unspent SendAndCall allowances).
    /// @dev `token == address(0)` means ETH.
    function rescueFunds(address token, address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddressNotAllowed();
        if (amount == 0) revert ZeroAmountNotAllowed();

        if (token == ETH) {
            bool ok = _trySendETH(to, amount);
            if (!ok) revert TransferFailed(token, to, amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }

        emit FundsRescued(token, to, amount);
    }

    // -----------------------------
    // Entry points
    // -----------------------------

    function executePlanETH(Plan calldata plan) external payable nonReentrant {
        if (plan.totalAmount == 0) revert ZeroAmountNotAllowed();
        if (msg.value != plan.totalAmount) revert TotalAmountMismatch();
        _executePlan(ETH, plan.totalAmount, plan);
    }

    function executePlanERC20(address paymentToken, uint256 totalAmount, Plan calldata plan) external nonReentrant {
        if (paymentToken == address(0)) revert ZeroAddressNotAllowed();
        if (totalAmount == 0) revert ZeroAmountNotAllowed();
        if (plan.totalAmount != totalAmount) revert TotalAmountMismatch();

        IERC20(paymentToken).safeTransferFrom(msg.sender, address(this), totalAmount);
        _executePlan(paymentToken, totalAmount, plan);
    }

    // -----------------------------
    // Core execution
    // -----------------------------

    function _executePlan(address paymentToken, uint256 totalAmount, Plan calldata plan) internal {
        if (block.timestamp > plan.deadline) revert DeadlinePassed();
        if (plan.groups.length == 0) revert InvalidPlan();
        if (plan.buckets.length == 0) revert InvalidPlan();

        // 1) Validate all beneficiary groups; compute totalWeight per group; build beneficiary->fallback lookup table.
        uint256 groupCountBeneficiaries = plan.groups.length;
        uint256 totalBeneficiaries = 0;
        for (uint256 g = 0; g < groupCountBeneficiaries; ++g) {
            totalBeneficiaries += plan.groups[g].beneficiaries.length;
        }
        if (totalBeneficiaries == 0) revert InvalidPlan();

        // Beneficiary fallback hash table (open addressing in memory) covering ALL group members.
        // If the same beneficiary appears multiple times, recipientOnFailure must match.
        uint256 benCap = _nextPow2(totalBeneficiaries * 2);
        bytes32[] memory benKeys = new bytes32[](benCap);
        address[] memory benFallback = new address[](benCap);

        uint256[] memory groupTotalWeight = new uint256[](groupCountBeneficiaries);
        uint256[] memory groupBenCount = new uint256[](groupCountBeneficiaries);

        for (uint256 g = 0; g < groupCountBeneficiaries; ++g) {
            Beneficiary[] calldata bens = plan.groups[g].beneficiaries;
            uint256 wSum = 0;
            uint256 n = bens.length;
            groupBenCount[g] = n;

            for (uint256 i = 0; i < n; ++i) {
                Beneficiary calldata b = bens[i];
                if (b.beneficiary == address(0)) revert ZeroAddressNotAllowed();
                if (b.weight == 0) revert ZeroAmountNotAllowed();
                wSum += uint256(b.weight);

                // Enforce consistent fallback for repeated beneficiary addresses.
                (address existing, bool found) = _benGet(benKeys, benFallback, b.beneficiary);
                if (found && existing != b.recipientOnFailure) revert InvalidPlan();
                _benSet(benKeys, benFallback, b.beneficiary, b.recipientOnFailure);
            }
            if (wSum == 0) revert InvalidPlan();
            groupTotalWeight[g] = wSum;
        }

        // 2) Validate buckets; build token groups in order of first appearance.
        uint256 bucketCount = plan.buckets.length;

        address[] memory groupTokens = new address[](bucketCount);
        uint256[] memory groupBps = new uint256[](bucketCount);
        uint256[] memory bucketGroup = new uint256[](bucketCount);
        uint256 groupCount = 0;

        uint256 bpsSum = 0;
        for (uint256 i = 0; i < bucketCount; ++i) {
            Bucket calldata bucket = plan.buckets[i];
            if (bucket.bucketBps == 0) revert ZeroAmountNotAllowed();
            bpsSum += bucket.bucketBps;

            if (bucket.groupId >= groupCountBeneficiaries) revert InvalidPlan();
            if (bucket.actionType != ActionType.Burn && groupBenCount[bucket.groupId] == 0) revert InvalidPlan();

            if (bucket.actionType == ActionType.Burn) {
                if (bucket.sourceToken == ETH) revert BurningETHNotAllowed();
                if (bucket.callTarget != address(0) || bucket.selector != bytes4(0) || bucket.callArgsPacked != bytes12(0)) {
                    revert InvalidPlan();
                }
            } else if (bucket.actionType == ActionType.Send) {
                if (bucket.callTarget != address(0) || bucket.selector != bytes4(0) || bucket.callArgsPacked != bytes12(0)) {
                    revert InvalidPlan();
                }
            } else if (bucket.actionType == ActionType.SendAndCall) {
                if (bucket.callTarget == address(0) || bucket.selector == bytes4(0)) revert InvalidPlan();
            } else {
                revert InvalidPlan();
            }

            // Find or create token group
            uint256 g = type(uint256).max;
            for (uint256 j = 0; j < groupCount; ++j) {
                if (groupTokens[j] == bucket.sourceToken) {
                    g = j;
                    break;
                }
            }
            if (g == type(uint256).max) {
                g = groupCount;
                groupTokens[groupCount] = bucket.sourceToken;
                groupCount++;
            }

            groupBps[g] += bucket.bucketBps;
            bucketGroup[i] = g;
        }
        if (bpsSum != MAX_BPS) revert BasisPointsMustSumTo10000();

        // 3) Compute token-group budgets in root input units (Strategy A) with deterministic remainder.
        uint256[] memory groupBudgetIn = new uint256[](groupCount);
        uint256 groupBudgetSoFar = 0;
        for (uint256 g = 0; g < groupCount; ++g) {
            if (g == groupCount - 1) {
                groupBudgetIn[g] = totalAmount - groupBudgetSoFar;
            } else {
                groupBudgetIn[g] = (totalAmount * groupBps[g]) / MAX_BPS;
                groupBudgetSoFar += groupBudgetIn[g];
            }
        }

        // Count buckets per group (to apply "last bucket gets remainder" within each group).
        uint256[] memory groupBucketCount = new uint256[](groupCount);
        uint256[] memory bucketBudgetIn = new uint256[](bucketCount);
        _fillBucketInputBudgets(totalAmount, plan.buckets, bucketCount, groupCount, bucketGroup, groupBudgetIn, groupBucketCount, bucketBudgetIn);

        // 4) Swaps phase: execute all swaps first; measure realized outputs via balance deltas.
        uint256[] memory groupRealizedOut = new uint256[](groupCount);
        uint256[] memory groupSwapIn = new uint256[](groupCount);

        for (uint256 i = 0; i < plan.swaps.length; ++i) {
            SwapStep calldata s = plan.swaps[i];

            if (s.tokenIn != paymentToken) revert SwapTokenInMismatch(i, paymentToken, s.tokenIn);
            if (s.tokenOut == paymentToken) revert SwapTokenOutInvalid(i, s.tokenOut);
            if (s.tokenIn == ETH && s.tokenOut == ETH) revert SwapTokenOutInvalid(i, s.tokenOut);
            if (s.amountIn == 0) revert ZeroAmountNotAllowed();
            if (s.minOut == 0) revert ZeroAmountNotAllowed();
            if (s.swapTarget == address(0) || s.allowanceTarget == address(0)) revert InvalidPlan();

            if (paymentToken == ETH) {
                if (s.value != s.amountIn) revert SwapValueMismatch(i, s.amountIn, s.value);
            } else {
                if (s.value != 0) revert SwapValueMismatch(i, 0, s.value);
            }

            if (allowlistEnabled && !isSwapAllowlisted[s.swapTarget][s.allowanceTarget]) {
                revert SwapNotAllowlisted(s.swapTarget, s.allowanceTarget);
            }

            uint256 gOut = _findGroupIndex(groupTokens, groupCount, s.tokenOut);
            groupSwapIn[gOut] += s.amountIn;

            uint256 startOut = _balanceOfSelf(s.tokenOut);
            uint256 startIn;
            if (paymentToken != ETH) {
                startIn = IERC20(paymentToken).balanceOf(address(this));
                IERC20(paymentToken).forceApprove(s.allowanceTarget, s.amountIn);
            }

            (bool ok, ) = s.swapTarget.call{value: s.value}(s.callData);

            if (paymentToken != ETH) {
                IERC20(paymentToken).forceApprove(s.allowanceTarget, 0);
            }
            if (!ok) revert SwapCallFailed(s.swapTarget);

            uint256 endOut = _balanceOfSelf(s.tokenOut);
            if (endOut < startOut) revert InvalidPlan();
            uint256 realizedOut = endOut - startOut;
            if (realizedOut < s.minOut) revert SwapMinOutNotMet(i, realizedOut, s.minOut);

            if (paymentToken != ETH) {
                uint256 endIn = IERC20(paymentToken).balanceOf(address(this));
                if (endIn > startIn) revert InvalidPlan();
                uint256 spentIn = startIn - endIn;
                if (spentIn != s.amountIn) revert SwapSpentMismatch(i, spentIn, s.amountIn);
            }

            groupRealizedOut[gOut] += realizedOut;
        }

        // Enforce that swap inputs match the computed group budgets for non-payment-token groups.
        for (uint256 g = 0; g < groupCount; ++g) {
            if (groupTokens[g] == paymentToken) {
                groupRealizedOut[g] = groupBudgetIn[g];
                continue;
            }
            if (groupSwapIn[g] != groupBudgetIn[g]) {
                revert SwapAmountInMismatch(groupTokens[g], groupBudgetIn[g], groupSwapIn[g]);
            }
        }

        // 5) Allocate realized token-group outputs into per-bucket outputs deterministically.
        uint256[] memory groupBucketOutSeen = new uint256[](groupCount);
        uint256[] memory groupBucketOutSoFar = new uint256[](groupCount);
        uint256[] memory bucketAmountOut = new uint256[](bucketCount);

        for (uint256 i = 0; i < bucketCount; ++i) {
            uint256 g = bucketGroup[i];
            groupBucketOutSeen[g]++;

            if (groupBudgetIn[g] == 0) revert InvalidPlan();

            if (groupBucketOutSeen[g] == groupBucketCount[g]) {
                bucketAmountOut[i] = groupRealizedOut[g] - groupBucketOutSoFar[g];
            } else {
                uint256 outAmt = (groupRealizedOut[g] * bucketBudgetIn[i]) / groupBudgetIn[g];
                bucketAmountOut[i] = outAmt;
                groupBucketOutSoFar[g] += outAmt;
            }
        }

        // 6) Build aggregation table for final sends (includes Send buckets + SendAndCall fallbacks).
        uint256 aggCap = _nextPow2(totalBeneficiaries * groupCount * 2);
        bytes32[] memory aggKeys = new bytes32[](aggCap);
        address[] memory aggTokens = new address[](aggCap);
        address[] memory aggRecipients = new address[](aggCap);
        uint256[] memory aggAmounts = new uint256[](aggCap);

        // 7) Execute burns.
        for (uint256 i = 0; i < bucketCount; ++i) {
            Bucket calldata bucket = plan.buckets[i];
            if (bucket.actionType != ActionType.Burn) continue;

            uint256 amt = bucketAmountOut[i];
            if (amt == 0) continue;

            IBurnable(bucket.sourceToken).burn(amt);
        }

        // 8) Execute SendAndCall.
        for (uint256 i = 0; i < bucketCount; ++i) {
            Bucket calldata bucket = plan.buckets[i];
            if (bucket.actionType != ActionType.SendAndCall) continue;

            uint256 totalBucketOut = bucketAmountOut[i];
            if (totalBucketOut == 0) continue;

            Beneficiary[] calldata bens = plan.groups[bucket.groupId].beneficiaries;
            uint256 benCount = bens.length;
            uint256 totalWeight = groupTotalWeight[bucket.groupId];
            CallArgType[] memory callArgs = _decodeCallArgsWithCount(bucket.callArgsPacked);

            uint256 distributed = 0;
            for (uint256 j = 0; j < benCount; ++j) {
                Beneficiary calldata b = bens[j];
                uint256 share;
                if (j == benCount - 1) {
                    share = totalBucketOut - distributed;
                } else {
                    share = (totalBucketOut * uint256(b.weight)) / totalWeight;
                    distributed += share;
                }
                if (share == 0) continue;

                bytes memory callData = _encodeFunctionCall(bucket.selector, callArgs, msg.sender, b.beneficiary, share);

                bool ok;
                if (bucket.sourceToken == ETH) {
                    (ok, ) = bucket.callTarget.call{value: share}(callData);
                } else {
                    IERC20 token = IERC20(bucket.sourceToken);
                    token.forceApprove(bucket.callTarget, share);
                    (ok, ) = bucket.callTarget.call(callData);
                    token.forceApprove(bucket.callTarget, 0);
                }

                if (!ok) {
                    if (b.recipientOnFailure != address(0)) {
                        _aggAdd(aggKeys, aggTokens, aggRecipients, aggAmounts, bucket.sourceToken, b.recipientOnFailure, share);
                    } else {
                        revert CallFailed(bucket.callTarget);
                    }
                }
            }
        }

        // 9) Aggregate Send payouts.
        for (uint256 i = 0; i < bucketCount; ++i) {
            Bucket calldata bucket = plan.buckets[i];
            if (bucket.actionType != ActionType.Send) continue;

            uint256 totalBucketOut = bucketAmountOut[i];
            if (totalBucketOut == 0) continue;

            Beneficiary[] calldata bens = plan.groups[bucket.groupId].beneficiaries;
            uint256 benCount = bens.length;
            uint256 totalWeight = groupTotalWeight[bucket.groupId];

            uint256 distributed = 0;
            for (uint256 j = 0; j < benCount; ++j) {
                Beneficiary calldata b = bens[j];
                uint256 share;
                if (j == benCount - 1) {
                    share = totalBucketOut - distributed;
                } else {
                    share = (totalBucketOut * uint256(b.weight)) / totalWeight;
                    distributed += share;
                }
                if (share == 0) continue;

                _aggAdd(aggKeys, aggTokens, aggRecipients, aggAmounts, bucket.sourceToken, b.beneficiary, share);
            }
        }

        // 10) Execute aggregated sends last, with redirect-on-failure for beneficiaries that have recipientOnFailure.
        for (uint256 i = 0; i < aggCap; ++i) {
            if (aggKeys[i] == bytes32(0)) continue;

            address token = aggTokens[i];
            address recipient = aggRecipients[i];
            uint256 amount = aggAmounts[i];
            if (amount == 0) continue;
            if (recipient == address(0)) revert ZeroAddressNotAllowed();

            bool ok = token == ETH ? _trySendETH(recipient, amount) : _tryERC20Transfer(token, recipient, amount);

            if (!ok) {
                (address fallbackRecipient, bool found) = _benGet(benKeys, benFallback, recipient);
                if (!found || fallbackRecipient == address(0)) revert TransferFailed(token, recipient, amount);

                bool ok2 = token == ETH
                    ? _trySendETH(fallbackRecipient, amount)
                    : _tryERC20Transfer(token, fallbackRecipient, amount);
                if (!ok2) revert TransferFailed(token, fallbackRecipient, amount);

                emit TokenTransferred(token, fallbackRecipient, plan.meta, msg.sender, amount);
            } else {
                emit TokenTransferred(token, recipient, plan.meta, msg.sender, amount);
            }
        }
    }

    // -----------------------------
    // Helpers
    // -----------------------------

    function _balanceOfSelf(address token) internal view returns (uint256) {
        return token == ETH ? address(this).balance : IERC20(token).balanceOf(address(this));
    }

    function _findGroupIndex(address[] memory groupTokens, uint256 groupCount, address token) internal pure returns (uint256) {
        for (uint256 i = 0; i < groupCount;) {
            if (groupTokens[i] == token) return i;
            unchecked {
                ++i;
            }
        }
        revert SwapTokenOutInvalid(type(uint256).max, token);
    }

    function _nextPow2(uint256 x) internal pure returns (uint256) {
        // Minimum table size is 1.
        if (x <= 1) return 1;
        uint256 p = 1;
        while (p < x) {
            p <<= 1;
        }
        return p;
    }

    function _fillBucketInputBudgets(
        uint256 totalAmount,
        Bucket[] calldata buckets,
        uint256 bucketCount,
        uint256 groupCount,
        uint256[] memory bucketGroup,
        uint256[] memory groupBudgetIn,
        uint256[] memory groupBucketCount,
        uint256[] memory bucketBudgetIn
    ) internal pure {
        for (uint256 i = 0; i < bucketCount; ++i) {
            groupBucketCount[bucketGroup[i]]++;
        }

        uint256[] memory groupBucketSeen = new uint256[](groupCount);
        uint256[] memory groupBucketBudgetSoFar = new uint256[](groupCount);
        for (uint256 i = 0; i < bucketCount; ++i) {
            uint256 g = bucketGroup[i];
            groupBucketSeen[g]++;

            if (groupBucketSeen[g] == groupBucketCount[g]) {
                bucketBudgetIn[i] = groupBudgetIn[g] - groupBucketBudgetSoFar[g];
            } else {
                bucketBudgetIn[i] = (totalAmount * uint256(buckets[i].bucketBps)) / MAX_BPS;
                groupBucketBudgetSoFar[g] += bucketBudgetIn[i];
            }
        }
    }

    function _aggAdd(
        bytes32[] memory keys,
        address[] memory tokens,
        address[] memory recipients,
        uint256[] memory amounts,
        address token,
        address recipient,
        uint256 amount
    ) internal pure {
        if (amount == 0) return;
        if (recipient == address(0)) revert ZeroAddressNotAllowed();

        uint256 mask = keys.length - 1;
        bytes32 key = keccak256(abi.encodePacked(token, recipient));
        uint256 idx = uint256(key) & mask;

        while (true) {
            bytes32 cur = keys[idx];
            if (cur == bytes32(0)) {
                keys[idx] = key;
                tokens[idx] = token;
                recipients[idx] = recipient;
                amounts[idx] = amount;
                return;
            }
            if (cur == key) {
                amounts[idx] += amount;
                return;
            }
            idx = (idx + 1) & mask;
        }
    }

    function _benSet(bytes32[] memory keys, address[] memory values, address beneficiary, address fallbackRecipient) internal pure {
        uint256 mask = keys.length - 1;
        bytes32 key = bytes32(uint256(uint160(beneficiary)));
        uint256 idx = uint256(keccak256(abi.encodePacked(key))) & mask;

        while (true) {
            bytes32 cur = keys[idx];
            if (cur == bytes32(0) || cur == key) {
                keys[idx] = key;
                values[idx] = fallbackRecipient;
                return;
            }
            idx = (idx + 1) & mask;
        }
    }

    function _benGet(
        bytes32[] memory keys,
        address[] memory values,
        address beneficiary
    ) internal pure returns (address out, bool found) {
        uint256 mask = keys.length - 1;
        bytes32 key = bytes32(uint256(uint160(beneficiary)));
        uint256 idx = uint256(keccak256(abi.encodePacked(key))) & mask;

        while (true) {
            bytes32 cur = keys[idx];
            if (cur == bytes32(0)) return (address(0), false);
            if (cur == key) return (values[idx], true);
            idx = (idx + 1) & mask;
        }
    }

    function _trySendETH(address to, uint256 amount) internal returns (bool) {
        if (amount == 0) return true;
        (bool ok, ) = to.call{value: amount}("");
        return ok;
    }

    function _tryERC20Transfer(address token, address to, uint256 amount) internal returns (bool) {
        if (amount == 0) return true;
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        if (!ok) return false;
        if (data.length == 0) return true;
        if (data.length == 32) return abi.decode(data, (bool));
        return false;
    }

    function _encodeFunctionCall(
        bytes4 selector,
        CallArgType[] memory callArgs,
        address sender,
        address beneficiary,
        uint256 amount
    ) internal pure returns (bytes memory) {
        bytes memory callData = new bytes(4 + (callArgs.length * 32));
        uint256 selectorWord = uint256(uint32(selector)) << 224;
        /// @solidity memory-safe-assembly
        assembly {
            mstore(add(callData, 32), selectorWord)
        }

        uint256 writeOffset = 4;
        for (uint256 i = 0; i < callArgs.length;) {
            uint256 argValue;
            if (callArgs[i] == CallArgType.Beneficiary) {
                argValue = uint256(uint160(beneficiary));
            } else if (callArgs[i] == CallArgType.Sender) {
                argValue = uint256(uint160(sender));
            } else if (callArgs[i] == CallArgType.Amount) {
                argValue = amount;
            } else {
                revert InvalidCallArgType();
            }

            /// @solidity memory-safe-assembly
            assembly {
                mstore(add(add(callData, 32), writeOffset), argValue)
            }
            unchecked {
                writeOffset += 32;
                ++i;
            }
        }

        return callData;
    }

    function _decodeCallArgsWithCount(bytes12 packed) internal pure returns (CallArgType[] memory args) {
        uint8 count = uint8(packed[0]); // first byte is count
        if (count > 11) revert TooManyCallArgs();

        args = new CallArgType[](count);
        for (uint8 i = 0; i < count;) {
            uint8 val = uint8(packed[i + 1]);
            if (val > uint8(type(CallArgType).max)) revert InvalidCallArgType();
            args[i] = CallArgType(val);
            unchecked {
                ++i;
            }
        }
    }
}
