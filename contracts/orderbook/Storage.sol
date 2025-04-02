// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "../libraries/LibTypeCast.sol";
import "../libraries/LibConfigKeys.sol";
import "./Types.sol";

contract Storage is Initializable, AccessControlEnumerableUpgradeable {
    using LibTypeCast for bytes32;

    OrderBookStorage internal _storage;
    bytes32[49] __gap;

    // seconds 1e0
    function _liquidityLockPeriod() internal view returns (uint32) {
        return _storage.parameters[LibConfigKeys.OB_LIQUIDITY_LOCK_PERIOD].toUint32();
    }

    function _marketOrderTimeout() internal view returns (uint32) {
        return _storage.parameters[LibConfigKeys.OB_MARKET_ORDER_TIMEOUT].toUint32();
    }

    function _maxLimitOrderTimeout() internal view returns (uint32) {
        return _storage.parameters[LibConfigKeys.OB_LIMIT_ORDER_TIMEOUT].toUint32();
    }

    function _referralManager() internal view returns (address) {
        return _storage.parameters[LibConfigKeys.OB_REFERRAL_MANAGER].toAddress();
    }

    function _callbackGasLimit() internal view returns (uint256) {
        return _storage.parameters[LibConfigKeys.OB_CALLBACK_GAS_LIMIT].toUint256();
    }

    function _cancelCoolDown() internal view returns (uint32) {
        return _storage.parameters[LibConfigKeys.OB_CANCEL_COOL_DOWN].toUint32();
    }
}
