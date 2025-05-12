// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
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

struct ActionArgs {
    address beneficiary;
    address recipientOnFailure;
    address weth;
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

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
}

/// @title TokenDistributor
/// @notice Contract for complex distributions and conversions of tokens 
contract TokenDistributor is Ownable2StepUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    using Address for address payable;
    
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
    
    event PoolConfigSet(
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
        address indexed beneficiary,
        uint256 amount,
        address paymentToken,
        address recipientOnFailure,
        uint256 distributionId
    );

    IPositionManager public uniswapPositionManager;
    IUniversalRouter public uniswapUniversalRouter;
    IPermit2 public permit2;
    address public weth;

    mapping(bytes32 => uint256) internal distributionNameToId;
    mapping(bytes32 => PoolConfig) internal pools;
    mapping(uint256 => bytes) internal distributions;
    uint256 internal lastDistributionId;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @param _owner The owner of the contract and the one who can upgrade it
    /// @param _uniswapPositionManager The address of the position manager
    /// @param _uniswapUniversalRouter The address of the universal router
    /// @param _permit2 The address of the permit2 contract
    /// @param _weth The address of the WETH contract
    function initialize(
        address _owner,
        IPositionManager _uniswapPositionManager,
        IUniversalRouter _uniswapUniversalRouter,
        IPermit2 _permit2,
        address _weth
    ) external initializer {
        if (address(_uniswapPositionManager) == address(0) || address(_uniswapUniversalRouter) == address(0) || address(_permit2) == address(0) || _weth == address(0)) {
            revert ZeroAddressNotAllowed();
        }

        __Ownable_init(_owner); // Checks for zero address
        __Ownable2Step_init();
        __UUPSUpgradeable_init();

        uniswapPositionManager = _uniswapPositionManager;
        uniswapUniversalRouter = _uniswapUniversalRouter;
        permit2 = _permit2;
        weth = _weth;
    }

    /// @notice Adds a distribution to the contract
    /// @dev The actions must sum to 10,000 basis points (100%)
    /// @param _actions The actions to be executed
    /// @return distributionId The id of the distribution
    function addDistribution(Action[] calldata _actions) external virtual returns (uint256 distributionId) {
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
        if (totalBasis != 10_000) {
            revert BasisPointsMustSumTo10000();
        }

        distributionId = ++lastDistributionId;
        distributions[distributionId] = abi.encode(_actions);

        emit DistributionAdded(distributionId, msg.sender);
    }

    /// @notice Gets a distribution by id
    /// @param _distributionId The id of the distribution
    /// @return actions The actions of the distribution
    function getDistributionById(uint256 _distributionId) external view virtual returns (Action[] memory) {
        bytes memory blob = distributions[_distributionId];
        if (blob.length == 0) revert DistributionNotFound(_distributionId);

        return abi.decode(blob, (Action[]));
    }

    /// @notice Sets the pool config for a given pool
    /// @param _config The pool config to be set
    /// @dev The pool key must have currencies in the correct order (currency0 < currency1)
    function setPoolConfig(PoolConfig calldata _config) external virtual onlyOwner {
        if (_config.poolKey.currency0 >= _config.poolKey.currency1) {
            revert CurrenciesNotInOrder();
        }

        bytes32 key = keccak256(abi.encodePacked(_config.poolKey.currency0, _config.poolKey.currency1));

        pools[key] = _config;

        emit PoolConfigSet(
            Currency.unwrap(_config.poolKey.currency0),
            Currency.unwrap(_config.poolKey.currency1),
            address(_config.poolKey.hooks),
            _config.poolKey.fee,
            _config.poolKey.tickSpacing,
            _config.version
        );
    }

    /// @notice Gets the pool config for a given pool
    /// @param _tokenA The address of the first token
    /// @param _tokenB The address of the second token
    /// @return config The pool config
    function getPoolConfig(address _tokenA, address _tokenB) external view virtual returns (PoolConfig memory) {
        bytes32 key = _getSwapPairKey(_tokenA, _tokenB);
        return pools[key];
    }

    /// @notice Sets the distribution id for a given name
    /// @param _distributionName The name of the distribution
    /// @param _distributionId The distribution id
    function setDistributionId(bytes32 _distributionName, uint256 _distributionId) external virtual onlyOwner {
        distributionNameToId[_distributionName] = _distributionId;
    
        emit DistributionIdSet(_distributionName, _distributionId);
    }

    /// @notice Gets the distribution id for a given name
    /// @param _distributionName The name of the distribution
    /// @return distributionId The distribution id
    function getDistributionIdByName(bytes32 _distributionName) external virtual view returns(uint256) {
        return distributionNameToId[_distributionName];
    }

    /// @notice Gets the distribution for a given name
    /// @param _distributionName The name of the distribution
    /// @return actions The actions of the distribution
    function getDistributionByName(bytes32 _distributionName) external virtual view returns(Action[] memory) {
        uint256 distributionId = distributionNameToId[_distributionName];
        if (distributionId == 0) revert DistributionNotFound(distributionId);

        bytes memory blob = distributions[distributionId];
        return abi.decode(blob, (Action[]));
    }

    /// @notice Gets the swaps for a given distri
    /// @dev This is a utility function to help with constructing the minAmountsOut array
    /// @param _distributionName The name of the distribution
    /// @param _paymentToken The address of the payment token
    /// @param _estimatedMaxSwaps The estimated maximum number of swaps
    /// @return swaps The swaps for the distribution
    function getSwapsByDistributionName(bytes32 _distributionName, address _paymentToken, uint256 _estimatedMaxSwaps) external virtual view returns (Swap[] memory) {
        return getSwapsByDistributionId(distributionNameToId[_distributionName], _paymentToken, _estimatedMaxSwaps);
    }

    /// @notice Gets the swaps for a given distribution
    /// @dev This is a utility function to help with constructing the minAmountsOut array
    /// @param _distributionId The id of the distribution
    /// @param _paymentToken The address of the payment token
    /// @param _estimatedMaxSwaps The estimated maximum number of swaps
    /// @return swaps The swaps for the distribution
    function getSwapsByDistributionId(uint256 _distributionId, address _paymentToken, uint256 _estimatedMaxSwaps) public virtual view returns (Swap[] memory) {
        bytes memory blob = distributions[_distributionId];
        if (blob.length == 0) revert DistributionNotFound(_distributionId);

        Swap[] memory swaps = new Swap[](_estimatedMaxSwaps);
       
        uint256 length = _buildSwapsForDistribution(_distributionId, _paymentToken, swaps, 0, weth);

        Swap[] memory trimmedSwaps = new Swap[](length);
        for (uint256 i = 0; i < length; ++i) {
            trimmedSwaps[i] = swaps[i];
        }

        return trimmedSwaps;
    }

    /// @notice Distribute Ether
    /// @dev If the _recipientOnFailure is address(0), the transaction will revert if a SendAndCall fails
    /// @param _distributionName The distribution name
    /// @param _beneficiary The address of the beneficiary
    /// @param _recipientOnFailure The address of the recipient on failure
    /// @param _minAmountsOut The minimum amounts out for the swaps
    /// @param _deadline The deadline for the swaps
    function distributeETH(
        bytes32 _distributionName, 
        address _beneficiary,
        address _recipientOnFailure,
        uint256[] calldata _minAmountsOut,
        uint256 _deadline
    ) external virtual payable {
        uint256 amount = msg.value;

        if (amount == 0) {
            revert ZeroAmountNotAllowed();
        }

        if (block.timestamp > _deadline) {
            revert DeadlinePassed();
        }

        uint256 distributionId = distributionNameToId[_distributionName];
        
        ActionArgs memory args = ActionArgs({
            beneficiary: _beneficiary,
            recipientOnFailure: _recipientOnFailure,
            weth: weth
        });

        _execDistribution(distributionId, args, amount, address(0), _minAmountsOut, 0, _deadline);

        emit Distribution(
            _distributionName,
            msg.sender,
            _beneficiary,
            amount,
            address(0),
            _recipientOnFailure,
            distributionId
        );
    }

    /// @notice Distribute an ERC20 token
    /// @dev If the _recipientOnFailure is address(0), the transaction will revert if a SendAndCall fails
    /// @param _distributionName The distribution name
    /// @param _beneficiary The address of the beneficiary
    /// @param _amount The amount of tokens to be sent
    /// @param _paymentToken The address of the payment token
    /// @param _recipientOnFailure The address of the recipient on failure
    /// @param _minAmountsOut The minimum amounts out for the swaps
    /// @param _deadline The deadline for the swaps
    function distributeERC20(
        bytes32 _distributionName, 
        address _beneficiary, 
        uint256 _amount, 
        address _paymentToken,
        address _recipientOnFailure,
        uint256[] calldata _minAmountsOut,
        uint256 _deadline
    ) external virtual {
        if (_amount == 0) {
            revert ZeroAmountNotAllowed();
        }

        if (block.timestamp > _deadline) {
            revert DeadlinePassed();
        }

        IERC20(_paymentToken).safeTransferFrom(msg.sender, address(this), _amount);

        uint256 distributionId = distributionNameToId[_distributionName];

        ActionArgs memory args = ActionArgs({
            beneficiary: _beneficiary,
            recipientOnFailure: _recipientOnFailure,
            weth: weth
        });

        _execDistribution(distributionId, args, _amount, _paymentToken, _minAmountsOut, 0, _deadline);

        emit Distribution(
            _distributionName,
            msg.sender,
            _beneficiary,
            _amount,
            _paymentToken,
            _recipientOnFailure,
            distributionId
        );
    }

    /// @notice Fallback function to accept ETH deposits (e.g. from swaps of WETH conversions)
    receive() external virtual payable {
    }

    /// @notice Executes a distribution
    /// @dev If the args.recipientOnFailure is address(0), the transaction will revert if a SendAndCall fails
    /// @param _distributionId The id of the distribution
    /// @param _args The action arguments
    /// @param _amount The amount of tokens to be sent
    /// @param _paymentToken The address of the payment token
    /// @param _minAmountsOut The minimum amounts out for the swaps
    /// @param _minAmountsOutIndex The index of the minimum amounts out
    /// @param _deadline The deadline for the swaps
    /// @return minAmountsOutIndex The new index of the minimum amounts out
    function _execDistribution(
        uint256 _distributionId,
        ActionArgs memory _args,
        uint256 _amount,
        address _paymentToken,
        uint256[] calldata _minAmountsOut,
        uint256 _minAmountsOutIndex,
        uint256 _deadline
    ) internal virtual returns (uint256) {
        if (_distributionId == 0) {
            revert DistributionNotFound(_distributionId);
        }

        bytes memory blob = distributions[_distributionId];
        if (blob.length == 0) {
            revert DistributionNotFound(_distributionId);
        }

        Action[] memory actions = abi.decode(blob, (Action[]));

        for (uint256 i = 0; i < actions.length; ++i) {
            _minAmountsOutIndex = _execAction(
                actions[i],
                _args,
               (_amount * actions[i].basisPoints) / 10_000,
                _paymentToken,
                _minAmountsOut,
                _minAmountsOutIndex,
                _deadline
            );
        }

        return _minAmountsOutIndex;
    }

    /// @notice Executes an action
    /// @dev If the _args.recipientOnFailure is address(0), the transaction will revert if a SendAndCall fails
    /// @param _action The action to be executed
    /// @param _args The action arguments
    /// @param _amount The amount of tokens to be sent
    /// @param _paymentToken The address of the payment token
    /// @param _minAmountsOut The minimum amounts out for the swaps
    /// @param _minAmountsOutIndex The index of the minimum amounts out
    /// @param _deadline The deadline for the swaps
    /// @return minAmountsOutIndex The new index of the minimum amounts out
    function _execAction(
        Action memory _action,
        ActionArgs memory _args,
        uint256 _amount,
        address _paymentToken,
        uint256[] calldata _minAmountsOut,
        uint256 _minAmountsOutIndex,
        uint256 _deadline
    ) internal virtual returns (uint256) {
        if (_action.actionType == ActionType.Burn) {
            if (_paymentToken== address(0)) {
                revert BurningETHNotAllowed();
            }
            IBurnable(_paymentToken).burn(_amount);
        } else if (_action.actionType == ActionType.Send) {
            _send(
                _action.recipient,
                _amount,
                _paymentToken,
                _args.beneficiary
            );
        } else if (_action.actionType == ActionType.Buy) {
            uint256 out;

            if (_paymentToken == address(0) && _action.token == _args.weth) {
                _swapETHToWETH(_amount, address(this), _args.weth);
                out = _amount;
            } else if (_paymentToken == weth && _action.token == address(0)) {
                _swapWETHToETH(_amount, address(this), _args.weth);
                out = _amount;
            } else {
                PoolConfig memory poolConfig = pools[_getSwapPairKey(_paymentToken, _action.token)];

                out = UniSwapper.swapExactIn(
                    address(this),
                    poolConfig,
                    _paymentToken,
                    _action.token,
                    _amount,
                    _minAmountsOutIndex < _minAmountsOut.length
                        ? uint128(_minAmountsOut[_minAmountsOutIndex])
                        : 0,
                    _deadline,
                    uniswapUniversalRouter,
                    permit2
                );
                ++_minAmountsOutIndex;
            }

            if (_action.distributionId != 0) {
                _minAmountsOutIndex = _execDistribution(_action.distributionId, _args, out, _action.token, _minAmountsOut, _minAmountsOutIndex, _deadline);
            } else {
                _send(
                    _action.recipient,
                    out,
                    _action.token,
                    _args.beneficiary
                );
            }
        } else if (
            _action.actionType == ActionType.SendAndCall
        ) {
            address target = _action.recipient;
            bool isEth = (_paymentToken == address(0));

            bytes memory callData = _encodeFunctionCall(
                _action.selector,
                _action.callArgsPacked,
                msg.sender,
                _args.beneficiary,
                _amount
            );

            if (isEth) {
                (bool ok, ) = target.call{value: _amount}(callData);
                if (!ok) {
                    if (_args.recipientOnFailure != address(0)) {
                        payable(_args.recipientOnFailure).sendValue(_amount);
                    } else {
                        revert CallFailed(target);
                    }
                }
            } else {
                IERC20(_paymentToken).approve(target, _amount);
                (bool ok, ) = target.call(callData);
                IERC20(_paymentToken).approve(target, 0); // Reset approval in case some of it was not spent or the call failed

                if (!ok) {
                    if (_args.recipientOnFailure != address(0)) {
                        IERC20(_paymentToken).safeTransfer(_args.recipientOnFailure, _amount);
                    } else {
                        revert CallFailed(target);
                    }
                }
            }
        }

        return _minAmountsOutIndex;
    }

    function _encodeFunctionCall(
        bytes4 _selector,
        bytes12 _callArgsPacked,
        address _sender,
        address _beneficiary,
        uint256 _amount
    ) internal virtual pure returns (bytes memory) {
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

    function _decodeCallArgsWithCount(bytes12 packed) internal virtual pure returns (CallArgType[] memory args) {
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
        address _beneficiary
    ) internal virtual {
        if (_amount == 0) {
            revert ZeroAmountNotAllowed();
        }

        if (_token == address(0)) {
            if (_recipient != address(0)) {
                payable(_recipient).sendValue(_amount);
            } else {
                payable(_beneficiary).sendValue(_amount);
            }
        } else {
            if (_recipient != address(0)) {
                IERC20(_token).safeTransfer(_recipient, _amount);
            } else {
                IERC20(_token).safeTransfer(_beneficiary, _amount);
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
    ) internal virtual {
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
    ) internal virtual {
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
    
    /// @notice Access control to upgrade the contract. Only the owner can upgrade
    /// @param _newImplementation The address of the new implementation
    function _authorizeUpgrade(address _newImplementation) internal virtual override onlyOwner {}

    /// @notice Gets the swap pair key for a given pair of tokens
    /// @param tokenA The address of the one of the tokens
    /// @param tokenB The address of the other token
    function _getSwapPairKey(
        address tokenA,
        address tokenB
    ) internal virtual pure returns (bytes32) {
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
    function _buildSwapsForDistribution(uint256 _distributionId, address _paymentToken, Swap[] memory _swaps, uint256 _swapIndex, address _weth) internal virtual view returns (uint256){
        bytes memory blob = distributions[_distributionId];
        if (blob.length == 0) {
            revert DistributionNotFound(_distributionId);
        }

        Action[] memory actions = abi.decode(blob, (Action[]));

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
    function _validateBurnAction(Action memory _action) internal virtual pure {
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
    function _validateSendAction(Action memory _action) internal virtual pure {
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
    function _validateBuyAction(Action memory _action) internal virtual pure {
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
    function _validateSendAndCallAction(Action memory _action) internal virtual pure {
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
