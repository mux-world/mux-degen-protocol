// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "../interfaces/IAdmin.sol";

import "../libraries/LibAsset.sol";
import "../libraries/LibMath.sol";
import "../libraries/LibReferenceOracle.sol";
import "../libraries/LibTypeCast.sol";

import "../DegenPoolStorage.sol";

contract Admin is DegenPoolStorage, IAdmin {
    using LibAsset for Asset;
    using LibMath for uint256;
    using LibPoolStorage for PoolStorage;
    using LibTypeCast for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;

    function setMaintainer(address newMaintainer, bool enable) external onlyDiamondOwner {
        require(_storage.maintainers[newMaintainer] != enable, "CHG"); // not CHanGed
        _storage.maintainers[newMaintainer] = enable;
        emit SetMaintainer(newMaintainer, enable);
    }

    function setMaintenanceParameters(bytes32[] memory keys, bool enable) external onlyDiamondOwner {
        for (uint256 i = 0; i < keys.length; i++) {
            bytes32 key = keys[i];
            if (enable) {
                require(_storage.isMaintenanceParameters.add(key), "CHG");
            } else {
                require(_storage.isMaintenanceParameters.remove(key), "CHG");
            }
            emit SetMaintenanceParameters(_msgSender(), key, enable);
        }
    }

    /**
     * @dev Diamond owner can add assets.
     *
     *      see LibConfigKeys.sol
     */
    function addAsset(
        uint8 assetId,
        bytes32[] calldata keys,
        bytes32[] calldata values
    ) external onlyDiamondOwner updateSequence {
        require(assetId < 0xFF, "FLL"); // assets list is FuLL
        require(assetId == _storage.assetsCount, "NID"); // Not a Valid ID

        Asset storage asset = _storage.assets[assetId];
        asset.id = assetId;
        _storage.assetsCount++;

        for (uint256 i = 0; i < keys.length; i++) {
            require(_authenticationCheck(keys[i]), "NAU"); // Not AUthorized
            asset.parameters[keys[i]] = values[i];
        }
        emit AddAsset(assetId);
        emit SetAssetParameters(_msgSender(), asset.id, keys, values);
    }

    /**
     * @dev Diamond owner or maintainers can set pool.
     *
     *      see LibConfigKeys.sol
     */
    function setPoolParameters(
        bytes32[] calldata keys,
        bytes32[] calldata values,
        bytes32[] calldata currentValues // [] means skip validation
    ) external updateSequence {
        require(keys.length == values.length, "LEN"); // length of KEYS and VALUES are not equal
        bool hasValidation = currentValues.length != 0;
        require(!hasValidation || keys.length == currentValues.length, "LEN"); // length of KEYS and CURRENT_VALUES are not equal
        for (uint256 i = 0; i < keys.length; i++) {
            require(!hasValidation || _storage.parameters[keys[i]] == currentValues[i], "VAL"); // invalid VALue
            require(_authenticationCheck(keys[i]), "NAU"); // Not AUthorized
            _storage.parameters[keys[i]] = values[i];
        }
        emit SetPoolParameters(_msgSender(), keys, values);
    }

    /**
     * @dev Diamond owner or maintainers can set asset.
     *
     *      see LibConfigKeys.sol
     */
    function setAssetParameters(
        uint8 assetId,
        bytes32[] calldata keys,
        bytes32[] calldata values,
        bytes32[] calldata currentValues // [] means skip validation
    ) external updateSequence {
        require(_storage.isValidAssetId(assetId), "LST"); // the asset is not LiSTed
        require(keys.length == values.length, "LEN"); // length of KEYS and VALUES are not equal
        bool hasValidation = currentValues.length != 0;
        require(!hasValidation || keys.length == currentValues.length, "LEN"); // length of KEYS and CURRENT_VALUES are not equal
        Asset storage asset = _storage.assets[assetId];
        for (uint256 i = 0; i < keys.length; i++) {
            require(!hasValidation || asset.parameters[keys[i]] == currentValues[i], "VAL"); // invalid VALue
            require(_authenticationCheck(keys[i]), "NAU"); // Not AUthorized
            asset.parameters[keys[i]] = values[i];
        }
        emit SetAssetParameters(_msgSender(), assetId, keys, values);
    }

    /**
     * @dev Diamond owner or maintainers can set the asset flags.
     */
    function setAssetFlags(
        uint8 assetId,
        bool isTradable,
        bool isOpenable,
        bool isShortable,
        bool isEnabled,
        bool isStable,
        bool isStrictStable,
        bool canAddRemoveLiquidity
    ) external updateSequence {
        require(_msgSender() == _diamondOwner() || _storage.maintainers[_msgSender()], "NAU"); // Not AUthorized
        require(_storage.isValidAssetId(assetId), "LST"); // the asset is not LiSTed
        Asset storage asset = _storage.assets[assetId];
        if (!isStable) {
            require(!isStrictStable, "STB"); // the asset is impossible to be a strict STaBle coin
        }
        uint56 newFlags = asset.flags;
        newFlags = (newFlags & (~ASSET_IS_TRADABLE)) | (isTradable ? ASSET_IS_TRADABLE : 0);
        newFlags = (newFlags & (~ASSET_IS_OPENABLE)) | (isOpenable ? ASSET_IS_OPENABLE : 0);
        newFlags = (newFlags & (~ASSET_IS_SHORTABLE)) | (isShortable ? ASSET_IS_SHORTABLE : 0);
        newFlags = (newFlags & (~ASSET_IS_ENABLED)) | (isEnabled ? ASSET_IS_ENABLED : 0);
        newFlags = (newFlags & (~ASSET_IS_STABLE)) | (isStable ? ASSET_IS_STABLE : 0);
        newFlags = (newFlags & (~ASSET_IS_STRICT_STABLE)) | (isStrictStable ? ASSET_IS_STRICT_STABLE : 0);
        newFlags =
            (newFlags & (~ASSET_CAN_ADD_REMOVE_LIQUIDITY)) |
            (canAddRemoveLiquidity ? ASSET_CAN_ADD_REMOVE_LIQUIDITY : 0);
        asset.flags = newFlags;
        emit SetAssetFlags(_msgSender(), assetId, newFlags);
    }

    /**
     * @dev Some keys can be set by either the diamond owner or the maintainers.
     *
     * @param key see LibConfigKeys.sol
     */
    function _authenticationCheck(bytes32 key) internal view returns (bool) {
        if (_msgSender() == _diamondOwner()) {
            return true;
        }
        if (_storage.maintainers[_msgSender()] && _storage.isMaintenanceParameters.contains(key)) {
            return true;
        }
        return false;
    }
}
