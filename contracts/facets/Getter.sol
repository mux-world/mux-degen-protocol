// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "../interfaces/IGetter.sol";

import "../libraries/LibTypeCast.sol";
import "../libraries/LibSubAccount.sol";
import "../libraries/LibPoolStorage.sol";
import "../libraries/LibAccount.sol";
import "../libraries/LibAsset.sol";

import "../DegenPoolStorage.sol";

contract Getter is DegenPoolStorage, IGetter {
    using LibTypeCast for uint256;
    using LibAsset for Asset;
    using LibAccount for Asset;
    using LibPoolStorage for PoolStorage;
    using LibSubAccount for bytes32;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;

    function diamondOwner() external view returns (address) {
        return _diamondOwner();
    }

    function getPoolParameter(bytes32 key) external view returns (bytes32) {
        return _storage.parameters[key];
    }

    function isMaintainer(address maintainer) external view returns (bool) {
        return _storage.maintainers[maintainer];
    }

    function getMaintenanceParameter(bytes32 key) external view returns (bool) {
        return _storage.isMaintenanceParameters.contains(key);
    }

    function getPoolStorage()
        external
        view
        returns (uint8 assetsCount, uint32 sequence, uint32 lastFundingTime, uint32 brokerTransactions)
    {
        assetsCount = _storage.assetsCount;
        sequence = _storage.sequence;
        lastFundingTime = _storage.lastFundingTime;
        brokerTransactions = _storage.brokerTransactions;
    }

    function getAssetParameter(uint8 assetId, bytes32 key) external view returns (bytes32) {
        require(_storage.isValidAssetId(assetId), "LST"); // the asset is not LiSTed
        Asset storage asset = _storage.assets[assetId];
        return asset.parameters[key];
    }

    function getAssetFlags(uint8 assetId) external view returns (uint56) {
        require(_storage.isValidAssetId(assetId), "LST"); // the asset is not LiSTed
        Asset storage asset = _storage.assets[assetId];
        return asset.flags;
    }

    function getAssetStorageV2(
        uint8 assetId
    )
        external
        view
        returns (
            uint56 flags,
            uint96 spotLiquidity,
            uint96 totalLongPosition,
            uint96 averageLongPrice,
            uint96 totalShortPosition,
            uint96 averageShortPrice,
            uint128 longCumulativeFunding,
            uint128 shortCumulativeFunding
        )
    {
        require(_storage.isValidAssetId(assetId), "LST"); // the asset is not LiSTed
        Asset storage asset = _storage.assets[assetId];
        flags = asset.flags;
        spotLiquidity = asset.spotLiquidity;
        totalLongPosition = asset.totalLongPosition;
        averageLongPrice = asset.averageLongPrice;
        totalShortPosition = asset.totalShortPosition;
        averageShortPrice = asset.averageShortPrice;
        longCumulativeFunding = asset.longCumulativeFunding;
        shortCumulativeFunding = asset.shortCumulativeFunding;
    }

    function getSubAccount(
        bytes32 subAccountId
    )
        external
        view
        returns (uint96 collateral, uint96 size, uint32 lastIncreasedTime, uint96 entryPrice, uint128 entryFunding)
    {
        SubAccount storage subAccount = _storage.accounts[subAccountId];
        collateral = subAccount.collateral;
        size = subAccount.size;
        lastIncreasedTime = subAccount.lastIncreasedTime;
        entryPrice = subAccount.entryPrice;
        entryFunding = subAccount.entryFunding;
    }

    function traderPnl(
        bytes32 subAccountId,
        uint96 price
    ) external returns (bool hasProfit, uint96 positionPnlUsd, uint96 cappedPnlUsd) {
        SubAccount storage subAccount = _storage.accounts[subAccountId];
        Asset storage asset = _storage.assets[subAccountId.assetId()];
        price = LibReferenceOracle.checkPrice(_storage, asset, price);
        (hasProfit, positionPnlUsd) = asset.positionPnlUsd(
            subAccount,
            subAccountId.isLong(),
            subAccount.size,
            price,
            _blockTimestamp()
        );
        cappedPnlUsd = positionPnlUsd;
        if (hasProfit) {
            uint96 maxProfit = ((uint256(subAccount.size) *
                uint256(subAccount.entryPrice) *
                uint256(asset.adlMaxPnlRate())) / 1e23).toUint96(); // 18 + 18 + 5 - 23
            if (positionPnlUsd > maxProfit) {
                cappedPnlUsd = maxProfit;
            }
        }
    }

    function isDeleverageAllowed(bytes32 subAccountId, uint96 markPrice) external returns (bool) {
        SubAccount storage subAccount = _storage.accounts[subAccountId];
        Asset storage asset = _storage.assets[subAccountId.assetId()];
        markPrice = LibReferenceOracle.checkPrice(_storage, asset, markPrice);
        (bool hasProfit, uint96 positionPnlUsd) = asset.positionPnlUsd(
            subAccount,
            subAccountId.isLong(),
            subAccount.size,
            markPrice,
            _blockTimestamp()
        );
        if (hasProfit) {
            uint96 triggerValueUsd = ((uint256(subAccount.size) *
                uint256(subAccount.entryPrice) *
                uint256(asset.adlTriggerRate())) / 1e23).toUint96(); // 18 + 18 + 5 - 23
            return positionPnlUsd >= triggerValueUsd;
        } else {
            return false;
        }
    }

    function getSubAccountIds(
        uint256 begin,
        uint256 end
    ) external view returns (bytes32[] memory subAccountIds, uint256 totalCount) {
        totalCount = _storage.subAccountIds.length();
        if (begin >= end || begin >= totalCount) {
            return (subAccountIds, totalCount);
        }
        end = end <= totalCount ? end : totalCount;
        uint256 size = end - begin;
        subAccountIds = new bytes32[](size);
        for (uint256 i = 0; i < size; i++) {
            subAccountIds[i] = _storage.subAccountIds.at(i + begin);
        }
    }

    function getSubAccountIdsOf(
        address trader,
        uint256 begin,
        uint256 end
    ) external view returns (bytes32[] memory subAccountIds, uint256 totalCount) {
        EnumerableSetUpgradeable.Bytes32Set storage positions = _storage.userSubAccountIds[trader];
        totalCount = positions.length();
        if (begin >= end || begin >= totalCount) {
            return (subAccountIds, totalCount);
        }
        end = end <= totalCount ? end : totalCount;
        uint256 size = end - begin;
        subAccountIds = new bytes32[](size);
        for (uint256 i = 0; i < size; i++) {
            subAccountIds[i] = positions.at(i + begin);
        }
    }

    function getMlpPrice(uint96[] memory markPrices) external returns (uint96 mlpPrice) {
        markPrices = _checkAllMarkPrices(markPrices);
        uint256 totalLiquidityUsd = _storage.poolUsd(markPrices);
        mlpPrice = _storage.mlpTokenPrice(totalLiquidityUsd);
    }
}
