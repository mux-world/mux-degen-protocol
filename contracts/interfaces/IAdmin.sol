// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

/**
 * @title IAdmin
 * @dev Interface for the Admin contract.
 */
interface IAdmin {
    event SetMaintainer(address indexed newMaintainer, bool enable);
    event SetMaintenanceParameters(address indexed operator, bytes32 keys, bool enable);
    event AddAsset(uint8 indexed id);
    event SetPoolParameters(address indexed operator, bytes32[] keys, bytes32[] values);
    event SetAssetParameters(address indexed operator, uint8 indexed assetId, bytes32[] keys, bytes32[] values);
    event SetAssetFlags(address indexed operator, uint8 indexed assetId, uint56 newFlags);

    function setMaintainer(address newMaintainer, bool enable) external;

    function setMaintenanceParameters(bytes32[] memory keys, bool enable) external;

    function addAsset(uint8 assetId, bytes32[] calldata keys, bytes32[] calldata values) external;

    function setPoolParameters(
        bytes32[] calldata keys,
        bytes32[] calldata values,
        bytes32[] calldata currentValues
    ) external;

    function setAssetParameters(
        uint8 assetId,
        bytes32[] calldata keys,
        bytes32[] calldata values,
        bytes32[] calldata currentValues
    ) external;

    function setAssetFlags(
        uint8 assetId,
        bool isTradable,
        bool isOpenable,
        bool isShortable,
        bool isEnabled,
        bool isStable,
        bool isStrictStable,
        bool canAddRemoveLiquidity
    ) external;
}
