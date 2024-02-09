// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

import "../Types.sol";
import "./LibConfigKeys.sol";
import "./LibTypeCast.sol";
import "./LibAsset.sol";
import "./LibMath.sol";

library LibPoolStorage {
    using LibAsset for Asset;
    using LibTypeCast for bytes32;
    using LibTypeCast for uint256;
    using LibMath for uint256;

    function isValidAssetId(PoolStorage storage pool, uint256 assetId) internal view returns (bool) {
        return assetId < pool.assetsCount && pool.assets[assetId].id == assetId;
    }

    function poolUsdWithoutPnl(PoolStorage storage pool, uint96[] memory markPrices) internal view returns (uint96) {
        uint256 assetCount = pool.assetsCount;
        require(markPrices.length == assetCount, "LEN"); // LENgth is different
        uint256 sumUsd = 0;
        for (uint256 i = 0; i < assetCount; i++) {
            uint96 markPrice = markPrices[i];
            require(markPrice > 0, "P=0"); // Price Is Zero
            sumUsd += (uint256(pool.assets[i].spotLiquidity) * uint256(markPrice));
        }
        return (sumUsd / 1e18).toUint96();
    }

    function poolUsd(PoolStorage storage pool, uint96[] memory markPrices) internal view returns (uint96) {
        uint96 aum = poolUsdWithoutPnl(pool, markPrices);
        uint256 assetCount = pool.assetsCount;
        for (uint256 i = 0; i < assetCount; i++) {
            Asset storage asset = pool.assets[i];
            uint96 markPrice = markPrices[i];
            require(markPrice > 0, "P=0"); // Price Is Zero
            // long
            if (asset.totalLongPosition != 0) {
                if (markPrice >= asset.averageLongPrice) {
                    // long profit
                    uint256 pnlUsd = uint256(markPrice - asset.averageLongPrice).wmul(asset.totalLongPosition);
                    uint256 cappedPnlUsd = (uint256(asset.totalLongPosition) *
                        uint256(asset.averageLongPrice) *
                        uint256(asset.adlMaxPnlRate())) / 1e23; // 18 + 18 + 5 - 23
                    if (pnlUsd > cappedPnlUsd) {
                        pnlUsd = cappedPnlUsd;
                    }
                    aum -= pnlUsd.toUint96();
                } else {
                    // long loss
                    uint256 pnlUsd = uint256(asset.averageLongPrice - markPrice).wmul(asset.totalLongPosition);
                    aum += pnlUsd.toUint96();
                }
            }
            // short
            if (asset.totalShortPosition != 0) {
                if (markPrice <= asset.averageShortPrice) {
                    // short profit
                    uint256 pnlUsd = uint256(asset.averageShortPrice - markPrice).wmul(asset.totalShortPosition);
                    uint256 cappedPnlUsd = (uint256(asset.totalShortPosition) *
                        uint256(asset.averageShortPrice) *
                        uint256(asset.adlMaxPnlRate())) / 1e23; // 18 + 18 + 5 - 23
                    if (pnlUsd > cappedPnlUsd) {
                        pnlUsd = cappedPnlUsd;
                    }
                    aum -= pnlUsd.toUint96();
                } else {
                    // short loss
                    uint256 pnlUsd = uint256(markPrice - asset.averageShortPrice).wmul(asset.totalShortPosition);
                    aum += pnlUsd.toUint96();
                }
            }
        } // foreach asset
        return aum;
    }

    function mlpTokenPriceByMarkPrices(
        PoolStorage storage pool,
        uint96[] memory markPrices
    ) internal view returns (uint96) {
        uint256 liquidityUsd = poolUsd(pool, markPrices);
        return mlpTokenPrice(pool, liquidityUsd);
    }

    function mlpTokenPrice(PoolStorage storage pool, uint256 liquidityUsd) internal view returns (uint96) {
        uint256 totalSupply = IERC20Upgradeable(mlpToken(pool)).totalSupply();
        if (totalSupply == 0) {
            return 1e18;
        }
        return ((liquidityUsd * 1e18) / totalSupply).toUint96();
    }

    function totalReservationUsd(PoolStorage storage pool) internal view returns (uint96 reservationUsd) {
        uint256 assetCount = pool.assetsCount;
        uint256 usd = 0;
        for (uint256 i = 0; i < assetCount; i++) {
            Asset storage asset = pool.assets[i];
            uint32 rate = asset.adlReserveRate();
            usd += ((uint256(asset.totalShortPosition) * uint256(asset.averageShortPrice) * uint256(rate)) / 1e23); // 18 + 18 + 5 - 23
            usd += ((uint256(asset.totalLongPosition) * uint256(asset.averageLongPrice) * uint256(rate)) / 1e23); // 18 + 18 + 5 - 23
        }
        return usd.toUint96();
    }

    function mlpToken(PoolStorage storage pool) internal view returns (address) {
        return pool.parameters[LibConfigKeys.MLP_TOKEN].toAddress();
    }

    function orderBook(PoolStorage storage pool) internal view returns (address) {
        return pool.parameters[LibConfigKeys.ORDER_BOOK].toAddress();
    }

    function feeDistributor(PoolStorage storage pool) internal view returns (address) {
        return pool.parameters[LibConfigKeys.FEE_DISTRIBUTOR].toAddress();
    }

    function fundingInterval(PoolStorage storage pool) internal view returns (uint32) {
        return pool.parameters[LibConfigKeys.FUNDING_INTERVAL].toUint32();
    }

    function borrowingRateApy(PoolStorage storage pool) internal view returns (uint32) {
        return pool.parameters[LibConfigKeys.BORROWING_RATE_APY].toUint32();
    }

    function liquidityFeeRate(PoolStorage storage pool) internal view returns (uint32) {
        return pool.parameters[LibConfigKeys.LIQUIDITY_FEE_RATE].toUint32();
    }

    function strictStableDeviation(PoolStorage storage pool) internal view returns (uint32) {
        return pool.parameters[LibConfigKeys.STRICT_STABLE_DEVIATION].toUint32();
    }

    function liquidityCapUsd(PoolStorage storage pool) internal view returns (uint96) {
        return pool.parameters[LibConfigKeys.LIQUIDITY_CAP_USD].toUint96();
    }

    // 1e18
    function brokerGasRebateUsd(PoolStorage storage pool) internal view returns (uint256) {
        return pool.parameters[LibConfigKeys.BROKER_GAS_REBATE_USD].toUint256();
    }
}
