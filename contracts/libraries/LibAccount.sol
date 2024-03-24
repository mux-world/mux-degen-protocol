// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "../libraries/LibPoolStorage.sol";
import "../libraries/LibAsset.sol";
import "./LibTypeCast.sol";
import "./LibMath.sol";
import "./LibReferenceOracle.sol";

import "../libraries/LibSubAccount.sol";
import "../Types.sol";

library LibAccount {
    using LibAsset for Asset;
    using LibAccount for SubAccount;
    using LibPoolStorage for PoolStorage;
    using LibTypeCast for uint256;
    using LibMath for uint256;

    function assetPnlUsd(Asset storage asset, uint96 assetPrice) internal view returns (int256 assetPnl) {
        require(assetPrice > 0, "P=0"); // Price Is Zero
        int256 totalProfitUsd;
        if (asset.totalLongPosition != 0) {
            int256 longPriceDelta = int256(uint256(assetPrice)) - int256(uint256(asset.averageLongPrice));
            totalProfitUsd = (longPriceDelta * int256(uint256(asset.totalLongPosition))) / 1e18;
        }
        if (asset.totalShortPosition != 0) {
            int256 shortPriceDelta = int256(uint256(asset.averageShortPrice)) - int256(uint256(assetPrice));
            totalProfitUsd = (shortPriceDelta * int256(uint256(asset.totalLongPosition))) / 1e18;
        }
        return totalProfitUsd;
    }

    function positionPnlUsd(
        Asset storage asset,
        SubAccount storage subAccount,
        bool isLong,
        uint96 amount,
        uint96 assetPrice,
        uint32 timestamp
    ) internal view returns (bool hasProfit, uint96 pnlUsd) {
        if (amount == 0) {
            return (false, 0);
        }
        require(assetPrice > 0, "P=0"); // Price Is Zero
        hasProfit = isLong ? assetPrice > subAccount.entryPrice : assetPrice < subAccount.entryPrice;
        uint96 priceDelta = assetPrice >= subAccount.entryPrice
            ? assetPrice - subAccount.entryPrice
            : subAccount.entryPrice - assetPrice;
        if (
            hasProfit &&
            timestamp < subAccount.lastIncreasedTime + asset.minProfitTime() &&
            priceDelta < uint256(subAccount.entryPrice).rmul(asset.minProfitRate()).toUint96()
        ) {
            hasProfit = false;
            return (false, 0);
        }
        pnlUsd = uint256(priceDelta).wmul(amount).toUint96();
    }

    // NOTE: settle funding by modify subAccount.collateral before this function
    function isAccountImSafe(
        Asset storage asset,
        SubAccount storage subAccount,
        bool isLong,
        uint96 collateralPrice,
        uint96 assetPrice,
        uint32 timestamp
    ) internal view returns (bool) {
        (bool hasProfit, uint96 pnlUsd) = positionPnlUsd(
            asset,
            subAccount,
            isLong,
            subAccount.size,
            assetPrice,
            timestamp
        );
        return isAccountSafe(subAccount, collateralPrice, assetPrice, asset.initialMarginRate(), hasProfit, pnlUsd, 0);
    }

    // NOTE: settle funding by modify subAccount.collateral before this function
    function isAccountMmSafe(
        Asset storage asset,
        SubAccount storage subAccount,
        bool isLong,
        uint96 collateralPrice,
        uint96 assetPrice,
        uint32 timestamp
    ) internal view returns (bool) {
        (bool hasProfit, uint96 pnlUsd) = positionPnlUsd(
            asset,
            subAccount,
            isLong,
            subAccount.size,
            assetPrice,
            timestamp
        );
        return
            isAccountSafe(subAccount, collateralPrice, assetPrice, asset.maintenanceMarginRate(), hasProfit, pnlUsd, 0);
    }

    function isAccountSafe(
        SubAccount storage subAccount,
        uint96 collateralPrice,
        uint96 assetPrice,
        uint32 marginRate,
        bool hasProfit,
        uint96 pnlUsd,
        uint96 fundingFee // fundingFee = 0 if subAccount.collateral was modified
    ) internal view returns (bool) {
        uint256 thresholdUsd = (uint256(subAccount.size) * uint256(assetPrice) * uint256(marginRate)) / 1e18 / 1e5;
        thresholdUsd += fundingFee;
        uint256 collateralUsd = uint256(subAccount.collateral).wmul(collateralPrice);
        // break down "collateralUsd +/- pnlUsd >= thresholdUsd >= 0"
        if (hasProfit) {
            return collateralUsd + pnlUsd >= thresholdUsd;
        } else {
            return collateralUsd >= thresholdUsd + pnlUsd;
        }
    }

    function fundingFeeUsd(
        Asset storage asset,
        SubAccount storage subAccount,
        bool isLong
    ) internal view returns (uint96) {
        if (subAccount.size == 0) {
            return 0;
        }
        uint256 cumulativeFunding;
        if (isLong) {
            cumulativeFunding = asset.longCumulativeFunding - subAccount.entryFunding;
        } else {
            cumulativeFunding = asset.shortCumulativeFunding - subAccount.entryFunding;
        }
        uint256 sizeUsd = uint256(subAccount.size).wmul(subAccount.entryPrice);
        return cumulativeFunding.wmul(sizeUsd).toUint96();
    }

    function positionFeeUsd(Asset storage asset, uint96 amount, uint96 price) internal view returns (uint96) {
        uint256 feeUsd = ((uint256(price) * uint256(asset.positionFeeRate())) * uint256(amount)) / 1e5 / 1e18;
        return feeUsd.toUint96();
    }

    function getLiquidationFeeUsd(
        Asset storage asset,
        uint96 amount,
        uint96 assetPrice
    ) internal view returns (uint96) {
        uint256 feeUsd = ((uint256(assetPrice) * uint256(asset.liquidationFeeRate())) * uint256(amount)) / 1e5 / 1e18;
        return feeUsd.toUint96();
    }

    // note: you can skip this function if newPositionSize > 0
    function updateEntryFunding(Asset storage asset, SubAccount storage subAccount, bool isLong) internal {
        subAccount.entryFunding = isLong ? asset.longCumulativeFunding : asset.shortCumulativeFunding;
    }
}
