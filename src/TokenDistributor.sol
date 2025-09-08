// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniversalRouter} from "@uniswap/universal-router/src/interfaces/IUniversalRouter.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IBurnable} from "./interfaces/IBurnable.sol";
import {UniSwapper} from "./libraries/UniSwapper.sol";
import {PoolConfig} from "./types/PoolConfig.sol";
import {UniswapVersion} from "./types/UniswapVersion.sol";

enum ActionType {
    Burn,
    Send,
    Buy,
    SendAndCall
}

struct Action {
    uint256 distributionId;
    address token;
    bytes4 selector;
    uint16 basisPoints;
    ActionType actionType;
    address recipient;
    bytes12 callArgsPacked;
}

enum CallArgType {
    Beneficiary,
    Sender,
    Amount
}

struct Swap {
    address tokenIn;
    address tokenOut;
}

struct DistributionRequest {
    address beneficiary;
    uint256 amount;
    address recipientOnFailure;
}

struct BatchContext {
    uint256 initialTotalAmount;
    uint256 minAmountsOutIndex;
    uint256 deadline;
    bytes32 meta;
}

struct DistributionContext {
    uint256 distributionId;
    uint256 amount;
    address paymentToken;
    uint256 distributedSoFar;
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
}

/// @title TokenDistributor
/// @notice Contract for complex distributions and conversions of tokens 
contract TokenDistributor is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address payable;

    uint256 internal constant MAX_BASIS_POINTS = 10_000;
    
    error ZeroAddressNotAllowed();
    error CurrenciesNotInOrder();
    error DistributionNotFound(uint256 distributionId);
    error ZeroAmountNotAllowed();
    error BurningETHNotAllowed();
    error BasisPointsMustSumTo10000();
    error CallFailed(address);
    error InvalidActionDefinition();
    error InvalidActionType();
    error TooManyCallArgs();
    error InvalidCallArgType();
    error DeadlinePassed();
    error MinAmountOutNotSet(uint256 index);
    error PoolConfigNotFound(address tokenIn, address tokenOut);
    error BatchTotalMismatch();
    error BatchIsEmpty();

    event PoolConfigProposed(
        uint256 proposalId,
        bytes32 key,
        address indexed currency0,
        address indexed currency1,
        address indexed hooks,
        uint24 fee,
        int24 tickSpacing,
        UniswapVersion version
    );
    event PoolConfigSet(
        uint256 proposalId,
        bytes32 key,
        address indexed currency0,
        address indexed currency1,
        address indexed hooks,
        uint24 fee,
        int24 tickSpacing,
        UniswapVersion version
    );
    event DistributionAdded(uint256 indexed distributionId, address indexed sender);
    event DistributionIdSet(bytes32 indexed distributionName, uint256 indexed distributionId);
    event Distribution(
        bytes32 indexed distributionName,
        address indexed sender,
        uint256 distributionId,
        uint256 amount,
        address paymentToken
    );
    event TokenTransferred(address indexed token, address indexed recipient, bytes32 indexed meta, address sender, uint256 amount);
    
    IUniversalRouter public uniswapUniversalRouter;
    IPermit2 public permit2;
    address public weth;

    mapping(bytes32 distributionName => uint256 distributionId) internal distributionNameToId;
    PoolConfig[] internal poolProposals;
    mapping(bytes32 key => PoolConfig config) internal pools;
    mapping(uint256 distributionId => bytes distribution) internal distributions;
    uint256 internal lastDistributionId;
    
    /// @notice Initializes the contract
    /// @param _owner The owner of the contract
    /// @param _uniswapUniversalRouter The address of the universal router
    /// @param _permit2 The address of the permit2 contract
    /// @param _weth The address of the WETH contract
    constructor(
        address _owner,
        IUniversalRouter _uniswapUniversalRouter,
        IPermit2 _permit2,
        address _weth
    ) Ownable(_owner) {
        if (address(_uniswapUniversalRouter) == address(0) || address(_permit2) == address(0) || _weth == address(0)) {
            revert ZeroAddressNotAllowed();
        }

        uniswapUniversalRouter = _uniswapUniversalRouter;
        permit2 = _permit2;
        weth = _weth;
    }

    /// @notice Adds a distribution to the contract
    /// @dev The actions must sum to 10,000 basis points (100%)
    /// @param _actions The actions to be executed
    /// @return distributionId The id of the distribution
    function addDistribution(Action[] calldata _actions) external returns (uint256 distributionId) {
        // Sum up all basisPoints they must equal exactly 10,000 (100%)
        uint256 totalBasis;
        for (uint256 i = 0; i < _actions.length; ++i) {
            Action memory action = _actions[i];
            
            if (action.basisPoints == 0) {
                revert ZeroAmountNotAllowed();
            }

            if (action.actionType == ActionType.Burn) {
                _validateBurnAction(action);
            } else if (action.actionType == ActionType.Send) {
                _validateSendAction(action);
            } else if (action.actionType == ActionType.Buy) {
                _validateBuyAction(action);
            } else if (action.actionType == ActionType.SendAndCall) {
                _validateSendAndCallAction(action);
            } else {
                revert InvalidActionType();
            }

            totalBasis += _actions[i].basisPoints;
        }
        if (totalBasis != MAX_BASIS_POINTS) {
            revert BasisPointsMustSumTo10000();
        }

        distributionId = ++lastDistributionId;
        distributions[distributionId] = abi.encode(_actions);

        emit DistributionAdded(distributionId, msg.sender);
    }

    /// @notice Gets a distribution by id
    /// @param _distributionId The id of the distribution
    /// @return actions The actions of the distribution
    function getDistributionById(uint256 _distributionId) external view returns (Action[] memory) {
        return _getDistributionById(_distributionId);
    }

    /// @notice Proposes a pool config for a given pool
    /// @param _config The proposed pool config
    /// @dev The pool key must have currencies in the correct order (currency0 < currency1)
    function proposePoolConfig(PoolConfig calldata _config) external returns(uint256) {
        if (_config.poolKey.currency0 >= _config.poolKey.currency1) {
            revert CurrenciesNotInOrder();
        }

        bytes32 key = keccak256(abi.encodePacked(_config.poolKey.currency0, _config.poolKey.currency1));

        poolProposals.push(_config);

        uint256 id = poolProposals.length - 1;

        emit PoolConfigProposed(
            id,
            key,
            Currency.unwrap(_config.poolKey.currency0),
            Currency.unwrap(_config.poolKey.currency1),
            address(_config.poolKey.hooks),
            _config.poolKey.fee,
            _config.poolKey.tickSpacing,
            _config.version
        );

        return id;
    }

    /// @notice Gets the pool config proposal by id
    /// @param _proposalId The id of the pool config proposal
    /// @return config The pool config
    function getPoolConfigProposal(uint256 _proposalId) external view returns (PoolConfig memory) {
        PoolConfig memory config = poolProposals[_proposalId];

        return config;
    }

    /// @notice Sets the pool config for a given pool from a proposal
    /// @param _proposalId The id of the pool config proposal
    function setPoolConfig(uint256 _proposalId) external onlyOwner {
        PoolConfig memory config = poolProposals[_proposalId];

        bytes32 key = keccak256(abi.encodePacked(config.poolKey.currency0, config.poolKey.currency1));

        pools[key] = config;

        emit PoolConfigSet(
            _proposalId,
            key,
            Currency.unwrap(config.poolKey.currency0),
            Currency.unwrap(config.poolKey.currency1),
            address(config.poolKey.hooks),
            config.poolKey.fee,
            config.poolKey.tickSpacing,
            config.version
        );
    }

    /// @notice Gets the pool config for a given pool
    /// @param _tokenA The address of the first token
    /// @param _tokenB The address of the second token
    /// @return config The pool config
    function getPoolConfig(address _tokenA, address _tokenB) external view returns (PoolConfig memory) {
        bytes32 key = _getSwapPairKey(_tokenA, _tokenB);
        return pools[key];
    }

    /// @notice Gets the pool config for a given pool
    /// @param _key The key of the pool
    /// @return config The pool config
    function getPoolConfigByKey(bytes32 _key) external view returns (PoolConfig memory) {
        return pools[_key];
    }

    /// @notice Sets the distribution id for a given name
    /// @param _distributionName The name of the distribution
    /// @param _distributionId The distribution id
    function setDistributionId(bytes32 _distributionName, uint256 _distributionId) external onlyOwner {
        distributionNameToId[_distributionName] = _distributionId;
    
        emit DistributionIdSet(_distributionName, _distributionId);
    }

    /// @notice Gets the distribution id for a given name
    /// @param _distributionName The name of the distribution
    /// @return distributionId The distribution id
    function getDistributionIdByName(bytes32 _distributionName) external view returns(uint256) {
        return distributionNameToId[_distributionName];
    }

    /// @notice Gets the distribution for a given name
    /// @param _distributionName The name of the distribution
    /// @return actions The actions of the distribution
    function getDistributionByName(bytes32 _distributionName) external view returns(Action[] memory) {
        uint256 distributionId = distributionNameToId[_distributionName];
        if (distributionId == 0) revert DistributionNotFound(distributionId);

        return _getDistributionById(distributionId);
    }

    /// @notice Gets the swaps for a given distri
    /// @dev This is a utility function to help with constructing the minAmountsOut array
    /// @param _distributionName The name of the distribution
    /// @param _paymentToken The address of the payment token
    /// @param _estimatedMaxSwaps The estimated maximum number of swaps
    /// @return swaps The swaps for the distribution
    function getSwapsByDistributionName(bytes32 _distributionName, address _paymentToken, uint256 _estimatedMaxSwaps) external view returns (Swap[] memory) {
        return getSwapsByDistributionId(distributionNameToId[_distributionName], _paymentToken, _estimatedMaxSwaps);
    }

    /// @notice Gets the swaps for a given distribution
    /// @dev This is a utility function to help with constructing the minAmountsOut array
    /// @param _distributionId The id of the distribution
    /// @param _paymentToken The address of the payment token
    /// @param _estimatedMaxSwaps The estimated maximum number of swaps
    /// @return swaps The swaps for the distribution
    function getSwapsByDistributionId(uint256 _distributionId, address _paymentToken, uint256 _estimatedMaxSwaps) public view returns (Swap[] memory) {
        Swap[] memory swaps = new Swap[](_estimatedMaxSwaps);
       
        uint256 length = _buildSwapsForDistribution(_distributionId, _paymentToken, swaps, 0, weth);

        Swap[] memory trimmedSwaps = new Swap[](length);
        for (uint256 i = 0; i < length; ++i) {
            trimmedSwaps[i] = swaps[i];
        }

        return trimmedSwaps;
    }

    /// @notice Distributes Ether to multiple beneficiaries according to a single distribution definition
    /// @dev This function aggregates all ETH, performs the necessary swaps on the total amount
    /// and then distributes the final assets proportionally
    /// @param _distributionName The distribution name to execute
    /// @param _requests An array of batch requests, one for each beneficiary
    /// @param _minAmountsOut The minimum amounts out for the aggregated swaps
    /// @param _deadline The deadline for the swaps
    function batchDistributeETH(
        bytes32 _distributionName,
        DistributionRequest[] calldata _requests,
        uint256[] calldata _minAmountsOut,
        uint256 _deadline,
        bytes32 _meta
    ) external payable nonReentrant {
        if (_requests.length == 0) {
            revert BatchIsEmpty();
        }
        if (block.timestamp > _deadline) {
            revert DeadlinePassed();
        }

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < _requests.length; ++i) {
            totalAmount += _requests[i].amount;
        }

        if (totalAmount != msg.value) {
            revert BatchTotalMismatch();
        }

        uint256 distributionId = distributionNameToId[_distributionName];

        BatchContext memory ctx = BatchContext({
            initialTotalAmount: totalAmount,
            minAmountsOutIndex: 0,
            deadline: _deadline,
            meta: _meta
        });

        DistributionContext memory dCtx = DistributionContext({
            distributionId: distributionId,
            amount: totalAmount,
            paymentToken: address(0),
            distributedSoFar: 0
        });

        _execBatchDistribution(dCtx, ctx, _requests, _minAmountsOut);

        // We can emit one event for the whole batch
        emit Distribution(
            _distributionName,
            msg.sender,
            distributionId,
            totalAmount,
            address(0)
        );
    }

    /// @notice Distributes an ERC20 token to multiple beneficiaries according to a single distribution definition
    /// @dev This function aggregates all tokens, performs the necessary swaps on the total amount,
    /// and then distributes the final assets proportionally
    /// @param _distributionName The distribution name to execute
    /// @param _paymentToken The address of the ERC20 token being distributed
    /// @param _requests An array of batch requests, one for each beneficiary
    /// @param _minAmountsOut The minimum amounts out for the aggregated swaps
    /// @param _deadline The deadline for the swaps
    function batchDistributeERC20(
        bytes32 _distributionName,
        address _paymentToken,
        DistributionRequest[] calldata _requests,
        uint256[] calldata _minAmountsOut,
        uint256 _deadline,
        bytes32 _meta
    ) external nonReentrant {
        if (_requests.length == 0) {
            revert BatchIsEmpty();
        }
        if (block.timestamp > _deadline) {
            revert DeadlinePassed();
        }

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < _requests.length; ++i) {
            totalAmount += _requests[i].amount;
        }
        if (totalAmount == 0) {
            revert ZeroAmountNotAllowed();
        }

        IERC20(_paymentToken).safeTransferFrom(msg.sender, address(this), totalAmount);
        
        uint256 distributionId = distributionNameToId[_distributionName];

        BatchContext memory ctx = BatchContext({
            initialTotalAmount: totalAmount,
            minAmountsOutIndex: 0,
            deadline: _deadline,
            meta: _meta
        });

        DistributionContext memory dCtx = DistributionContext({
            distributionId: distributionId,
            amount: totalAmount,
            paymentToken: _paymentToken,
            distributedSoFar: 0
        });

        _execBatchDistribution(dCtx, ctx, _requests, _minAmountsOut);

        emit Distribution(
            _distributionName,
            msg.sender,
            distributionId,
            totalAmount,
            _paymentToken
        );
    }

    /// @notice Fallback function to accept ETH deposits (e.g. from swaps of WETH conversions)
    receive() external payable {
    }

    function _execBatchDistribution(
        DistributionContext memory _dCtx,
        BatchContext memory _ctx,
        DistributionRequest[] calldata _requests,
        uint256[] calldata _minAmountsOut
    ) internal {
        if (_dCtx.distributionId == 0) revert DistributionNotFound(_dCtx.distributionId);

        Action[] memory actions = _getDistributionById(_dCtx.distributionId);

        for (uint256 i = 0; i < actions.length; ++i) {
            uint256 actionTotalAmount = i == actions.length - 1
                ? _dCtx.amount - _dCtx.distributedSoFar
                : (_dCtx.amount * actions[i].basisPoints) / MAX_BASIS_POINTS;

            _execBatchAction(
                actions[i],
                _ctx,
                _requests,
                _minAmountsOut,
                _dCtx,
                actionTotalAmount
            );

            _dCtx.distributedSoFar += actionTotalAmount;
        }
    }

    function _execBatchAction(
        Action memory _action,
        BatchContext memory _ctx,
        DistributionRequest[] calldata _requests,
        uint256[] calldata _minAmountsOut,
        DistributionContext memory _dCtx,
        uint256 _actionTotalAmount
    ) internal {

        if (_action.actionType == ActionType.Burn) {
            if (_dCtx.paymentToken == address(0)) revert BurningETHNotAllowed();
            IBurnable(_dCtx.paymentToken).burn(_actionTotalAmount);

        } else if (_action.actionType == ActionType.Send) {
            _distributeProportionally(
                _action.recipient,
                _requests,
                _ctx.initialTotalAmount,
                _actionTotalAmount,
                _dCtx.paymentToken,
                _ctx.meta
            );

        } else if (_action.actionType == ActionType.Buy) {
            uint256 outAmount = _swap(_actionTotalAmount, _dCtx.paymentToken, _action, _ctx, _minAmountsOut);

            if (_action.distributionId != 0) {
                _execBatchDistribution(
                    DistributionContext({
                        distributionId: _action.distributionId,
                        amount: outAmount,
                        paymentToken: _action.token,
                        distributedSoFar: 0
                    }),
                    _ctx, 
                    _requests,
                    _minAmountsOut
                );
            } else {
                _distributeProportionally(
                    _action.recipient,
                    _requests,
                    _ctx.initialTotalAmount,
                    outAmount,
                    _action.token,
                    _ctx.meta
                );
            }
        } else if (_action.actionType == ActionType.SendAndCall) {
            uint256 distributedSoFar = 0;
            for (uint256 i = 0; i < _requests.length; ++i) {
                uint256 userShare;
                if (i == _requests.length - 1) {
                    userShare = _actionTotalAmount - distributedSoFar;
                } else {
                    userShare = (_actionTotalAmount * _requests[i].amount) / _ctx.initialTotalAmount;
                    distributedSoFar += userShare;
                }

                address target = _action.recipient;
                bytes memory callData = _encodeFunctionCall(
                    _action.selector, _action.callArgsPacked, msg.sender, _requests[i].beneficiary, userShare
                );

                if (_dCtx.paymentToken == address(0)) {
                    (bool ok, ) = target.call{value: userShare}(callData);
                    if (!ok) {
                        if (_requests[i].recipientOnFailure != address(0)) {
                            payable(_requests[i].recipientOnFailure).sendValue(userShare);
                        } else {
                            revert CallFailed(target);
                        }
                    }
                } else {
                    // Use SafeERC20 forceApprove for broad token compatibility.
                    IERC20 token = IERC20(_dCtx.paymentToken);
                    token.forceApprove(target, userShare);
                    (bool ok, ) = target.call(callData);
                    token.forceApprove(target, 0); // Reset approval
                    if (!ok) {
                        if (_requests[i].recipientOnFailure != address(0)) {
                            token.safeTransfer(_requests[i].recipientOnFailure, userShare);
                        } else {
                            revert CallFailed(target);
                        }
                    }
                }
            }
        }
    }
    
    function _swap(
        uint256 _actionTotalAmount,
        address _paymentToken,
        Action memory _action,
        BatchContext memory _ctx,
        uint256[] calldata _minAmountsOut
    ) internal returns (uint256) {
        uint256 outAmount;

        if (_paymentToken == address(0) && _action.token == weth) {
            _swapETHToWETH(_actionTotalAmount, address(this), weth);
            outAmount = _actionTotalAmount;
        } else if (_paymentToken == weth && _action.token == address(0)) {
            _swapWETHToETH(_actionTotalAmount, address(this), weth);
            outAmount = _actionTotalAmount;
        } else {
            PoolConfig memory poolConfig = pools[_getSwapPairKey(_paymentToken, _action.token)];
            if (poolConfig.poolKey.currency0 == Currency.wrap(address(0)) && poolConfig.poolKey.currency1 == Currency.wrap(address(0))) {
                revert PoolConfigNotFound(_paymentToken, _action.token);
            }
            if (_ctx.minAmountsOutIndex >= _minAmountsOut.length || _minAmountsOut[_ctx.minAmountsOutIndex] == 0) {
                revert MinAmountOutNotSet(_ctx.minAmountsOutIndex);
            }

            outAmount = UniSwapper.swapExactIn(
                address(this),
                owner(),
                poolConfig,
                _paymentToken,
                _action.token,
                _actionTotalAmount,
                uint128(_minAmountsOut[_ctx.minAmountsOutIndex]),
                _ctx.deadline,
                uniswapUniversalRouter,
                permit2
            );
            ++_ctx.minAmountsOutIndex; 
        }

        return outAmount;
    }

    /// @notice Helper to distribute a total amount proportionally among beneficiaries.
    /// @dev Handles dust by giving the remainder to the last beneficiary.
    function _distributeProportionally(
        address _fixedRecipient,
        DistributionRequest[] calldata _requests,
        uint256 _initialTotalAmount,
        uint256 _amountToDistribute,
        address _token,
        bytes32 _meta
    ) internal {
        uint256 distributedSoFar = 0;
        for (uint256 i = 0; i < _requests.length; ++i) {
            uint256 userShare;
            if (i == _requests.length - 1) {
                // Last user gets the remainder to prevent dust loss
                userShare = _amountToDistribute - distributedSoFar;
            } else {
                userShare = (_amountToDistribute * _requests[i].amount) / _initialTotalAmount;
                distributedSoFar += userShare;
            }

            if (userShare > 0) {
                 // If a fixed recipient is set, send there. Otherwise, send to the request's beneficiary.
                address finalRecipient = _fixedRecipient == address(0) ? _requests[i].beneficiary : _fixedRecipient;
                _send(finalRecipient, userShare, _token, _requests[i].beneficiary, _meta);
            }
        }
    }

    function _encodeFunctionCall(
        bytes4 _selector,
        bytes12 _callArgsPacked,
        address _sender,
        address _beneficiary,
        uint256 _amount
    ) internal pure returns (bytes memory) {
       CallArgType[] memory callArgs = _decodeCallArgsWithCount(_callArgsPacked);

        bytes memory argsData; 

        for (uint256 i = 0; i < callArgs.length; ++i) {
            if (callArgs[i] == CallArgType.Beneficiary) {
                argsData = bytes.concat(argsData, abi.encode(_beneficiary));
            } else if (callArgs[i] == CallArgType.Sender) {
                argsData = bytes.concat(argsData, abi.encode(_sender));
            } else if (callArgs[i] == CallArgType.Amount) {
                argsData = bytes.concat(argsData, abi.encode(_amount));
            }
        }

        return bytes.concat(abi.encodeWithSelector(_selector), argsData);
    }

    /// @notice Gets a distribution by id
    /// @param _distributionId The id of the distribution
    /// @return actions The actions of the distribution
    function _getDistributionById(uint256 _distributionId) internal view returns (Action[] memory) {
        bytes memory blob = distributions[_distributionId];
        if (blob.length == 0) revert DistributionNotFound(_distributionId);

        return abi.decode(blob, (Action[]));
    }

    function _decodeCallArgsWithCount(bytes12 packed) internal pure returns (CallArgType[] memory args) {
        uint8 count = uint8(packed[0]); // First byte is count
        if (count > 11) {
            revert TooManyCallArgs();
        }

        args = new CallArgType[](count);
        for (uint8 i = 0; i < count; ++i) {
            uint8 val = uint8(packed[i + 1]);
            if (val > uint8(type(CallArgType).max)) {
                revert InvalidCallArgType();
            }
            args[i] = CallArgType(val);
        }
    }

    /// @notice Sends ETH or ERC20 to a recipient
    /// @dev If the _recipient is address(0), the tokens will be sent to the beneficiary
    /// @param _recipient The address of the recipient
    /// @param _amount The amount of tokens to be sent
    /// @param _token The address of the token to be sent
    /// @param _beneficiary The address of the beneficiary
    function _send(
        address _recipient,
        uint256 _amount,
        address _token,
        address _beneficiary,
        bytes32 _meta
    ) internal {
        if (_amount == 0) {
            revert ZeroAmountNotAllowed();
        }

        if (_token == address(0)) {
            if (_recipient != address(0)) {
                payable(_recipient).sendValue(_amount);
            } else {
                payable(_beneficiary).sendValue(_amount);
            }

            emit TokenTransferred(_token, _recipient, _meta, msg.sender, _amount);
        } else {
            if (_recipient != address(0)) {
                IERC20(_token).safeTransfer(_recipient, _amount);
                emit TokenTransferred(_token, _recipient, _meta, msg.sender, _amount);
            } else {
                IERC20(_token).safeTransfer(_beneficiary, _amount);
                emit TokenTransferred(_token, _beneficiary, _meta, msg.sender, _amount);
            }
        }
    }

    /// @notice Swaps ETH to WETH
    /// @param _amount The amount of ETH to be swapped
    /// @param _recipient The address of the recipient
    /// @param _weth The address of the WETH contract
    function _swapETHToWETH(
        uint256 _amount,
        address _recipient,
        address _weth
    ) internal {
        if (_amount == 0) {
            revert ZeroAmountNotAllowed();
        }

        if (_recipient == address(0)) {
            revert ZeroAddressNotAllowed();
        }

        IWETH(_weth).deposit{value: _amount}();

        if (_recipient != address(this)) {
            IERC20(_weth).safeTransfer(_recipient, _amount);
        }
    }

    /// @notice Swaps WETH to ETH
    /// @param _amount The amount of WETH to be swapped
    /// @param _recipient The address of the recipient
    /// @param _weth The address of the WETH contract
    function _swapWETHToETH(
        uint256 _amount,
        address _recipient,
        address _weth
    ) internal {
        if (_amount == 0) {
            revert ZeroAmountNotAllowed();
        }

        if (_recipient == address(0)) {
            revert ZeroAddressNotAllowed();
        }

        IWETH(_weth).withdraw(_amount);

        if (_recipient != address(this)) {
            payable(_recipient).sendValue(_amount);
        }
    }
    

    /// @notice Gets the swap pair key for a given pair of tokens
    /// @param tokenA The address of the one of the tokens
    /// @param tokenB The address of the other token
    function _getSwapPairKey(
        address tokenA,
        address tokenB
    ) internal pure returns (bytes32) {
        if (tokenA < tokenB) {
            return keccak256(abi.encodePacked(tokenA, tokenB));
        } else {
            return keccak256(abi.encodePacked(tokenB, tokenA));
        }
    }

    /// @notice Builds the swaps for a given distribution
    /// @dev This is a recursive function that builds the swaps for the distribution
    /// @param _distributionId The id of the distribution
    /// @param _paymentToken The address of the payment token
    /// @param _swaps The swaps currently being built
    /// @param _swapIndex The index of the current swap
    /// @param _weth The address of the WETH contract
    /// @return swapIndex The new index of the current swap
    function _buildSwapsForDistribution(uint256 _distributionId, address _paymentToken, Swap[] memory _swaps, uint256 _swapIndex, address _weth) internal view returns (uint256){
        Action[] memory actions = _getDistributionById(_distributionId);

        for (uint256 i = 0; i < actions.length; ++i) {
            Action memory action = actions[i];

            if (action.actionType == ActionType.Buy) {
                if (!(_paymentToken == address(0) && action.token == _weth) && !(_paymentToken == _weth && action.token == address(0))) {
                    _swaps[_swapIndex] = Swap({
                        tokenIn: _paymentToken,
                        tokenOut: action.token
                    });

                    _swapIndex++;
                }
                
                if (action.distributionId != 0) {
                    _swapIndex = _buildSwapsForDistribution(action.distributionId, action.token, _swaps, _swapIndex, _weth);
                }
            }
        }
        return _swapIndex;
    }

    /// @notice Validates the burn action
    /// @param _action The action to be validated
    function _validateBurnAction(Action memory _action) internal pure {
        if (_action.token != address(0)) {
            revert InvalidActionDefinition();
        }
        if (_action.distributionId != 0) {
            revert InvalidActionDefinition();
        }
        if (_action.selector != bytes4(0)) {
            revert InvalidActionDefinition();
        }
        if (_action.recipient != address(0)) {
            revert InvalidActionDefinition();
        }
        if (_action.callArgsPacked != bytes12(0)) {
            revert InvalidActionDefinition();
        }
    }

    /// @notice Validates the send action
    /// @param _action The action to be validated
    function _validateSendAction(Action memory _action) internal pure {
        if (_action.token != address(0)) {
            revert InvalidActionDefinition();
        }
        if (_action.distributionId != 0) {
            revert InvalidActionDefinition();
        }
        if (_action.selector != bytes4(0)) {
            revert InvalidActionDefinition();
        }
        if (_action.callArgsPacked != bytes12(0)) {
            revert InvalidActionDefinition();
        }
    }

    /// @notice Validates the buy action
    /// @param _action The action to be validated
    function _validateBuyAction(Action memory _action) internal pure {
        if (_action.distributionId != 0 && _action.recipient != address(0)) {
            revert InvalidActionDefinition();
        }
        if (_action.selector != bytes4(0)) {
            revert InvalidActionDefinition();
        }
        if (_action.callArgsPacked != bytes12(0)) {
            revert InvalidActionDefinition();
        }
    }

    /// @notice Validates the send and call action
    /// @param _action The action to be validated
    function _validateSendAndCallAction(Action memory _action) internal pure {
        if (_action.token != address(0)) {
            revert InvalidActionDefinition();
        }
        if (_action.distributionId != 0) {
            revert InvalidActionDefinition();
        }
        if (_action.selector == bytes4(0)) {
            revert InvalidActionDefinition();
        }
        if (_action.recipient == address(0)) {
            revert InvalidActionDefinition();
        }
    }
}
