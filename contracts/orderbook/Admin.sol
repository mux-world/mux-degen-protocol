// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "../libraries/LibTypeCast.sol";
import "../libraries/LibConfigKeys.sol";

import "./Types.sol";
import "./Storage.sol";

/**
 * @title Admin
 * @dev Contract for managing the configuration and pausing of order types in the orderbook.
 */
contract Admin is Storage {
    using LibTypeCast for bytes32;

    /**
     * @dev Emitted when a configuration parameter is set.
     * @param key The configuration parameter key.
     * @param value The configuration parameter value.
     */
    event SetConfig(bytes32 key, bytes32 value);

    /**
     * @dev Emitted when an order type is paused or unpaused.
     * @param orderType The type of order being paused or unpaused.
     * @param isPaused Whether the order type is being paused or unpaused.
     */
    event Pause(OrderType orderType, bool isPaused);

    /**
     * @dev Emitted when a delegator is set.
     * @param delegator The address of the delegator.
     * @param enable Whether the delegator is enabled.
     */
    event SetDelegator(address delegator, bool enable);

    /**
     * @dev Sets a configuration parameter.
     * @param key The configuration parameter key.
     * @param value The configuration parameter value.
     */
    function setConfig(bytes32 key, bytes32 value) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_storage.parameters[key] != value, "CHG"); // setting is not CHanGed
        if (key == LibConfigKeys.OB_LIQUIDITY_LOCK_PERIOD) {
            uint256 lockPeriod = value.toUint256();
            require(lockPeriod <= 86400 * 30, "LCK"); // LoCK time is too large
        } else if (key == LibConfigKeys.OB_MARKET_ORDER_TIMEOUT || key == LibConfigKeys.OB_LIMIT_ORDER_TIMEOUT) {
            uint256 timeout = value.toUint256();
            require(timeout != 0, "T=0"); // Timeout Is Zero
            require(timeout / 10 <= type(uint24).max, "T>M"); // Timeout is Larger than Max
        } else if (key == LibConfigKeys.OB_REFERRAL_MANAGER) {
            require(value.isAddress(), "NAD"); // Not ADdress
        } else if (key == LibConfigKeys.OB_CALLBACK_GAS_LIMIT) {
            // nothing to check
        } else if (key == LibConfigKeys.OB_CANCEL_COOL_DOWN) {
            uint256 coolDown = value.toUint256();
            require(coolDown <= 86400 * 30, "CDL"); // CoolDown time is too Large
        } else {
            revert("URK"); // UnRecognized Key
        }
        _storage.parameters[key] = value;
        emit SetConfig(key, value);
    }

    /**
     * @dev Pauses or unpauses an order type.
     * @param orderType The type of order to pause or unpause.
     * @param isPaused Whether to pause or unpause the order type.
     */
    function pause(OrderType orderType, bool isPaused) external onlyRole(MAINTAINER_ROLE) {
        require(_storage.isPaused[orderType] != isPaused, "CHG"); // setting is not CHanGed
        _storage.isPaused[orderType] = isPaused;
        emit Pause(orderType, isPaused);
    }

    /**
     * @dev Sets a delegator.
     * @param delegator The address of the delegator.
     * @param enable Whether the delegator is enabled.
     */
    function setDelegator(address delegator, bool enable) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _storage.delegators[delegator] = enable;
        emit SetDelegator(delegator, enable);
    }
}
