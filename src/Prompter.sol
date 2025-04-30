// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IUniversalRouter} from "@uniswap/universal-router/src/interfaces/IUniversalRouter.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IBurnable} from "./interfaces/IBurnable.sol";
import {UniSwapper} from "./libraries/UniSwapper.sol";
import {UniswapVersion} from "./types/UniswapVersion.sol";

enum ActionType {
    Burn,
    Send,
    Buy,
    SendAndCall,
    SendAndCallForBeneficiary
}

struct RawAction {
    uint256 distributionId;
    address token;
    bytes4 selector;
    uint16 basisPoints;
    ActionType actionType;
    address recipient;
    address recipientOnFailure;
}

struct PoolConfig {
    PoolKey poolKey;
    UniswapVersion version;
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
}

/// @title Prompter
contract Prompter is Ownable2StepUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    using Address for address payable;
    
    error ZeroAddressNotAllowed();
    error CurrenciesNotInOrder();
    error DistributionNotFound();
    error ZeroAmountNotAllowed();
    error BurningETHNotAllowed();
    error BasisPointsMustSumTo10000();
    error CallFailed();
    
    event DistributionAdded(uint256 indexed distributionId, address indexed sender);
    event Prompt(
        bytes32 indexed promptType,
        address indexed sender,
        address indexed beneficiary,
        uint256 amount,
        address paymentToken,
        uint256 distributionId
    );

    IPositionManager public uniswapPositionManager;
    IUniversalRouter public uniswapUniversalRouter;
    IPermit2 public permit2;
    address public weth;

    mapping(bytes32 => uint256) internal promptDistributionIds;
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
    function initialize(
        address _owner,
        IPositionManager _uniswapPositionManager,
        IUniversalRouter _uniswapUniversalRouter,
        IPermit2 _permit2,
        address _weth
    ) external initializer {
        if (address(_uniswapPositionManager) == address(0) || address(_uniswapUniversalRouter) == address(0)) {
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

    function addDistribution(RawAction[] calldata actions) external virtual returns (uint256 distributionId) {
        // Sum up all basisPoints they must equal exactly 10,000 (100%)
        uint256 totalBasis;
        for (uint256 i = 0; i < actions.length; ++i) {
            totalBasis += actions[i].basisPoints;
        }
        if (totalBasis != 10_000) {
            revert BasisPointsMustSumTo10000();
        }

        distributionId = ++lastDistributionId;
        distributions[distributionId] = abi.encode(actions);

        emit DistributionAdded(distributionId, msg.sender);
    }

    function setPoolConfig(PoolConfig calldata config) external virtual onlyOwner {
        if (config.poolKey.currency0 >= config.poolKey.currency1) {
            revert CurrenciesNotInOrder();
        }

        bytes32 key = keccak256(abi.encodePacked(config.poolKey.currency0, config.poolKey.currency1));

        pools[key] = config;
    }

    function setPromptDistribution(bytes32 promptType, uint256 distributionId) external virtual onlyOwner returns(uint256) {
        promptDistributionIds[promptType] = distributionId;

        return distributionId;
    }

    function promptWithETH(
        bytes32 _promptType, 
        address _beneficiary,
        address _recipientOnFailure
    ) external payable {
        uint256 amount = msg.value;

        if (amount == 0) {
            revert ZeroAmountNotAllowed();
        }

        uint256 distributionId = promptDistributionIds[_promptType];

        _execDistribution(distributionId, _beneficiary, amount, address(0), _recipientOnFailure, weth);

        emit Prompt(
            _promptType,
            msg.sender,
            _beneficiary,
            amount,
            address(0),
            distributionId
        );
    }

    function promptWithERC20(
        bytes32 _promptType, 
        address _beneficiary, 
        uint256 _amount, 
        address _paymentToken,
        address _recipientOnFailure
    ) external {
        if (_amount == 0) {
            revert ZeroAmountNotAllowed();
        }

        IERC20(_paymentToken).safeTransferFrom(msg.sender, address(this), _amount);

        uint256 distributionId = promptDistributionIds[_promptType];

        _execDistribution(distributionId, _beneficiary, _amount, _paymentToken, _recipientOnFailure, weth);

        emit Prompt(
            _promptType,
            msg.sender,
            _beneficiary,
            _amount,
            _paymentToken,
            distributionId
        );
    }

    function _execDistribution(
        uint256 _distributionId,
        address _beneficiary,
        uint256 _amount,
        address _paymentToken,
        address _recipientOnFailure,
        address _weth
    ) internal virtual {
        if (_distributionId == 0) revert DistributionNotFound();

        bytes memory blob = distributions[_distributionId];
        RawAction[] memory actions = abi.decode(blob, (RawAction[]));

        for (uint256 i = 0; i < actions.length; ++i) {
            _execAction(
                actions[i],
                _beneficiary,
                _amount,
                _paymentToken,
                _recipientOnFailure,
                _weth
            );
        }
    }

    function _execAction(
        RawAction memory action,
        address _beneficiary,
        uint256 _amount,
        address _paymentToken,
        address _recipientOnFailure,
        address _weth
    ) internal virtual {
        uint256 split = (_amount * action.basisPoints) / 10_000;

        if (action.actionType == ActionType.Burn) {
            if (_paymentToken== address(0)) revert BurningETHNotAllowed();
            IBurnable(_paymentToken).burn(split);
        } else if (action.actionType == ActionType.Send) {
            if (_paymentToken == address(0)) {
                payable(action.recipient).sendValue(split);
            } else {
                IERC20(_paymentToken).safeTransfer(action.recipient, split);
            }
        } else if (action.actionType == ActionType.Buy) {
            uint256 out;

            if (_paymentToken == address(0) && action.token == _weth) {
                _swapETHToWETH(split, address(this), _weth);
                out = split;
            } else if (_paymentToken == weth && action.token == address(0)) {
                _swapWETHToETH(split, address(this), _weth);
                out = split;
            } else {
                PoolConfig memory poolConfig = pools[_getSwapPairKey(_paymentToken, action.token)];
                
                out = UniSwapper.swapExactIn(
                    address(this),
                    poolConfig.poolKey,
                    _paymentToken,
                    action.token,
                    split,
                    1,
                    poolConfig.version,
                    uniswapUniversalRouter,
                    permit2
                );
            }

            _execDistribution(action.distributionId, _beneficiary, out, action.token, _recipientOnFailure, _weth);
        } else if (
            action.actionType == ActionType.SendAndCall ||
            action.actionType == ActionType.SendAndCallForBeneficiary
        ) {
            address target = action.recipient;
            bool isEth = (_paymentToken == address(0));

            bytes memory callData;
            if (action.actionType == ActionType.SendAndCall) {
                callData = abi.encodeWithSelector(action.selector);
            } else {
                callData = abi.encodeWithSelector(action.selector,_beneficiary);
            }

            if (isEth) {
                (bool ok, ) = target.call{value: split}(callData);
                if (!ok) {
                    _handleFailureETH(split, _recipientOnFailure);
                }
            } else {
                IERC20(_paymentToken).approve(target, split);
                (bool ok, ) = target.call(callData);
                if (!ok) {
                    _handleFailureERC20(_paymentToken, split, _recipientOnFailure);
                }
            }
        }
    }

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

    function _swapWETHToETH(
        uint256 amount,
        address recipient,
        address _weth
    ) internal virtual {
        if (amount == 0) {
            revert ZeroAmountNotAllowed();
        }

        if (recipient == address(0)) {
            revert ZeroAddressNotAllowed();
        }

        IWETH(_weth).withdraw(amount);

        if (recipient != address(this)) {
            payable(recipient).sendValue(amount);
        }
    }

    function _handleFailureETH(
        uint256 _split,
        address _recipientOnFailure
    ) internal virtual {
        if (_recipientOnFailure != address(0)) {
            payable(_recipientOnFailure).sendValue(_split);
        } else {
            revert CallFailed();
        }
    }

    function _handleFailureERC20(
        address _paymentToken,
        uint256 _split,
        address _recipientOnFailure
    ) internal virtual {
        if (_recipientOnFailure != address(0)) {
            IERC20(_paymentToken).safeTransfer(_recipientOnFailure, _split);
        } else {
            revert CallFailed();
        }
    }
    
    /// @notice Access control to upgrade the contract. Only the owner can upgrade
    /// @param _newImplementation The address of the new implementation
    function _authorizeUpgrade(address _newImplementation) internal virtual override onlyOwner {}

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
}
