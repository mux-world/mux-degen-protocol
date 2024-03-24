// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";

import "../interfaces/ITrade.sol";

import "../libraries/LibAsset.sol";
import "../libraries/LibSubAccount.sol";
import "../libraries/LibMath.sol";
import "../libraries/LibReferenceOracle.sol";
import "../libraries/LibAccount.sol";
import "../libraries/LibTypeCast.sol";

import "../DegenPoolStorage.sol";

contract Trade is DegenPoolStorage, ITrade {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;
    using LibMath for uint256;
    using LibSubAccount for bytes32;
    using LibAsset for Asset;
    using LibAccount for Asset;
    using LibAccount for SubAccount;
    using LibPoolStorage for PoolStorage;
    using LibTypeCast for uint256;
    using LibReferenceOracle for PoolStorage;

    struct OpenPositionContext {
        SubAccountId subAccountId;
        uint96 assetPrice;
        uint96 collateralPrice;
        uint96 fundingFeeUsd;
        uint96 positionFeeUsd;
        uint96 totalFeeUsd;
        uint96 pnlUsd;
    }
    struct ClosePositionContext {
        SubAccountId subAccountId;
        uint96 assetPrice;
        uint96 collateralPrice;
        uint96 profitAssetPrice;
        uint96 fundingFeeUsd;
        uint96 positionFeeUsd;
        uint96 totalFeeUsd;
        uint96 paidFeeUsd;
        uint96 feeInProfitToken;
        uint96 feeInCollateralToken;
        uint96 pnlUsd;
        bool hasProfit;
    }
    struct LiquidateContext {
        SubAccountId subAccountId;
        uint96 assetPrice;
        uint96 collateralPrice;
        uint96 profitAssetPrice;
        uint96 fundingFeeUsd;
        uint96 positionFeeUsd;
        uint96 totalFeeUsd;
        uint96 paidFeeUsd;
        uint96 feeInProfitToken;
        uint96 feeInCollateralToken;
        uint96 oldPositionSize;
        uint96 pnlUsd;
        bool hasProfit;
    }

    /**
     * @notice Open a position.
     *
     * @param  subAccountId     check LibSubAccount.decodeSubAccountId for detail.
     * @param  amount           filled position size. decimals = 18.
     * @param  tradingPrice     price of subAccount.asset. decimals = 18.
     * @param  markPrices       mark prices of all assets. decimals = 18.
     */
    function openPosition(
        bytes32 subAccountId,
        uint96 amount,
        uint96 tradingPrice,
        uint96[] memory markPrices
    ) external onlyOrderBook updateSequence updateBrokerTransactions returns (uint96) {
        require(amount != 0, "A=0"); // Amount Is Zero
        markPrices = _checkAllMarkPrices(markPrices);
        OpenPositionContext memory ctx;
        ctx.subAccountId = subAccountId.decode();
        ctx.assetPrice = markPrices[ctx.subAccountId.assetId];
        ctx.collateralPrice = markPrices[ctx.subAccountId.collateralId];
        _validateSubAccountId(ctx.subAccountId);
        _validateAssets(
            ctx.subAccountId.assetId,
            ASSET_IS_OPENABLE | ASSET_IS_TRADABLE | ASSET_IS_ENABLED,
            ASSET_IS_STABLE
        );
        _validateAssets(ctx.subAccountId.collateralId, ASSET_IS_STABLE | ASSET_IS_ENABLED, 0);
        SubAccount storage subAccount = _storage.accounts[subAccountId];
        Asset storage asset = _storage.assets[ctx.subAccountId.assetId];
        require(ctx.subAccountId.isLong || asset.isShortable(), "SHT"); // can not SHorT this asset
        require(amount % asset.lotSize() == 0, "LOT"); // LOT size mismatch
        tradingPrice = _storage.checkPrice(asset, tradingPrice);

        // fee & funding
        ctx.fundingFeeUsd = asset.fundingFeeUsd(subAccount, ctx.subAccountId.isLong);
        ctx.positionFeeUsd = asset.positionFeeUsd(amount, tradingPrice);
        ctx.totalFeeUsd = ctx.fundingFeeUsd + ctx.positionFeeUsd;
        asset.updateEntryFunding(subAccount, ctx.subAccountId.isLong);
        {
            uint96 feeCollateral = uint256(ctx.totalFeeUsd).wdiv(ctx.collateralPrice).toUint96();
            require(subAccount.collateral >= feeCollateral, "FEE"); // collateral can not pay Fee
            subAccount.collateral -= feeCollateral;
            _collectFee(ctx.subAccountId.collateralId, ctx.subAccountId.account, feeCollateral);
        }
        // position
        (, ctx.pnlUsd) = _traderCappedPnlUsd(
            asset,
            subAccount,
            ctx.subAccountId.isLong,
            subAccount.size,
            tradingPrice,
            _blockTimestamp()
        );
        uint96 newSize = subAccount.size + amount;
        if (ctx.pnlUsd == 0) {
            subAccount.entryPrice = tradingPrice;
        } else {
            subAccount.entryPrice = ((uint256(subAccount.entryPrice) *
                uint256(subAccount.size) +
                uint256(tradingPrice) *
                uint256(amount)) / newSize).toUint96();
        }
        subAccount.size = newSize;
        subAccount.lastIncreasedTime = _blockTimestamp();
        emit OpenPosition(
            ctx.subAccountId.account,
            ctx.subAccountId.assetId,
            OpenPositionArgs({
                subAccountId: subAccountId,
                collateralId: ctx.subAccountId.collateralId,
                isLong: ctx.subAccountId.isLong,
                amount: amount,
                tradingPrice: tradingPrice,
                assetPrice: ctx.assetPrice,
                collateralPrice: ctx.collateralPrice,
                newEntryPrice: subAccount.entryPrice,
                // note: paidFeeUsd = fundingFeeUsd + positionFeeUsd
                fundingFeeUsd: ctx.fundingFeeUsd,
                positionFeeUsd: ctx.positionFeeUsd,
                remainPosition: subAccount.size,
                remainCollateral: subAccount.collateral
            })
        );
        // total
        _increaseTotalSize(asset, ctx.subAccountId.isLong, amount, tradingPrice, markPrices);
        // post check
        require(
            asset.isAccountImSafe(
                subAccount,
                ctx.subAccountId.isLong,
                ctx.collateralPrice,
                ctx.assetPrice,
                _blockTimestamp()
            ),
            "!IM"
        );

        // trace
        _storage.userSubAccountIds[ctx.subAccountId.account].add(subAccountId);
        _storage.subAccountIds.add(subAccountId);
        return tradingPrice;
    }

    /**
     * @notice Close a position.
     *
     * @param  subAccountId     check LibSubAccount.decodeSubAccountId for detail.
     * @param  amount           filled position size. decimals = 18.
     * @param  tradingPrice     price of subAccount.asset. decimals = 18.
     * @param  profitAssetId    for long position (unless asset.useStable is true), ignore this argument;
     *                          for short position, the profit asset should be one of the stable coin.
     * @param  markPrices      mark prices of all assets. decimals = 18.
     */
    function closePosition(
        bytes32 subAccountId,
        uint96 amount,
        uint96 tradingPrice,
        uint8 profitAssetId, // only used when !isLong
        uint96[] memory markPrices
    ) external onlyOrderBook updateSequence updateBrokerTransactions returns (uint96) {
        require(amount != 0, "A=0"); // Amount Is Zero
        markPrices = _checkAllMarkPrices(markPrices);
        ClosePositionContext memory ctx;
        ctx.subAccountId = subAccountId.decode();
        ctx.assetPrice = markPrices[ctx.subAccountId.assetId];
        ctx.collateralPrice = markPrices[ctx.subAccountId.collateralId];
        ctx.profitAssetPrice = markPrices[profitAssetId];
        _validateSubAccountId(ctx.subAccountId);
        _validateAssets(ctx.subAccountId.assetId, ASSET_IS_TRADABLE | ASSET_IS_ENABLED, ASSET_IS_STABLE);
        _validateAssets(ctx.subAccountId.collateralId, ASSET_IS_STABLE | ASSET_IS_ENABLED, 0);
        _validateAssets(profitAssetId, ASSET_IS_STABLE | ASSET_IS_ENABLED, 0);

        Asset storage asset = _storage.assets[ctx.subAccountId.assetId];
        Asset storage collateral = _storage.assets[ctx.subAccountId.collateralId];
        SubAccount storage subAccount = _storage.accounts[subAccountId];
        require(amount <= subAccount.size, "A>S"); // close Amount is Larger than position Size
        tradingPrice = _storage.checkPrice(asset, tradingPrice);

        // total
        _decreaseTotalSize(asset, ctx.subAccountId.isLong, amount, subAccount.entryPrice);
        // fee & funding
        ctx.fundingFeeUsd = asset.fundingFeeUsd(subAccount, ctx.subAccountId.isLong);
        ctx.positionFeeUsd = asset.positionFeeUsd(amount, tradingPrice);
        ctx.totalFeeUsd = ctx.fundingFeeUsd + ctx.positionFeeUsd;
        asset.updateEntryFunding(subAccount, ctx.subAccountId.isLong);
        // realize pnl
        (ctx.hasProfit, ctx.pnlUsd) = _traderCappedPnlUsd(
            asset,
            subAccount,
            subAccountId.isLong(),
            amount,
            tradingPrice,
            _blockTimestamp()
        );
        if (ctx.hasProfit) {
            (ctx.paidFeeUsd, ctx.feeInProfitToken) = _realizeProfit(
                ctx.subAccountId.account,
                ctx.pnlUsd,
                ctx.totalFeeUsd,
                _storage.assets[profitAssetId],
                ctx.profitAssetPrice
            );
        } else {
            _realizeLoss(subAccount, collateral, ctx.collateralPrice, ctx.pnlUsd, true);
        }
        subAccount.size -= amount;
        if (subAccount.size == 0) {
            subAccount.entryPrice = 0;
            subAccount.entryFunding = 0;
            subAccount.lastIncreasedTime = 0;
        }
        // ignore fees if can not afford
        if (ctx.totalFeeUsd > ctx.paidFeeUsd) {
            ctx.feeInCollateralToken = uint256(ctx.totalFeeUsd - ctx.paidFeeUsd).wdiv(ctx.collateralPrice).toUint96();
            ctx.feeInCollateralToken = LibMath.min(ctx.feeInCollateralToken, subAccount.collateral);
            subAccount.collateral -= ctx.feeInCollateralToken;
            ctx.paidFeeUsd += uint256(ctx.feeInCollateralToken).wmul(ctx.collateralPrice).toUint96();
            // remember to call _collectFee
        }
        _mergeAndCollectFee(
            ctx.subAccountId.account,
            profitAssetId,
            ctx.subAccountId.collateralId,
            ctx.feeInProfitToken,
            ctx.feeInCollateralToken
        );
        emit ClosePosition(
            ctx.subAccountId.account,
            ctx.subAccountId.assetId,
            ClosePositionArgs({
                subAccountId: subAccountId,
                collateralId: ctx.subAccountId.collateralId,
                profitAssetId: profitAssetId,
                isLong: ctx.subAccountId.isLong,
                amount: amount,
                tradingPrice: tradingPrice,
                assetPrice: ctx.assetPrice,
                collateralPrice: ctx.collateralPrice,
                profitAssetPrice: ctx.profitAssetPrice,
                fundingFeeUsd: LibMath.min(ctx.fundingFeeUsd, ctx.paidFeeUsd),
                // there is no separate positionFee for compatible reasons
                paidFeeUsd: ctx.paidFeeUsd,
                hasProfit: ctx.hasProfit,
                pnlUsd: ctx.pnlUsd,
                remainPosition: subAccount.size,
                remainCollateral: subAccount.collateral
            })
        );

        // post check
        require(
            asset.isAccountMmSafe(
                subAccount,
                ctx.subAccountId.isLong,
                ctx.collateralPrice,
                ctx.assetPrice,
                _blockTimestamp()
            ),
            "!MM"
        );

        // trace
        if (subAccount.size == 0 && subAccount.collateral == 0) {
            _storage.userSubAccountIds[ctx.subAccountId.account].remove(subAccountId);
            _storage.subAccountIds.remove(subAccountId);
        }
        return tradingPrice;
    }

    function liquidate(
        bytes32 subAccountId,
        uint8 profitAssetId, // only used when !isLong
        uint96 tradingPrice,
        uint96[] memory markPrices
    ) external onlyOrderBook updateSequence updateBrokerTransactions returns (uint96) {
        markPrices = _checkAllMarkPrices(markPrices);
        LiquidateContext memory ctx;
        ctx.subAccountId = subAccountId.decode();
        ctx.assetPrice = markPrices[ctx.subAccountId.assetId];
        ctx.collateralPrice = markPrices[ctx.subAccountId.collateralId];
        ctx.profitAssetPrice = markPrices[profitAssetId];

        _validateSubAccountId(ctx.subAccountId);
        _validateAssets(ctx.subAccountId.assetId, ASSET_IS_TRADABLE | ASSET_IS_ENABLED, ASSET_IS_STABLE);
        _validateAssets(ctx.subAccountId.collateralId, ASSET_IS_STABLE | ASSET_IS_ENABLED, 0);
        _validateAssets(profitAssetId, ASSET_IS_STABLE | ASSET_IS_ENABLED, 0);

        Asset storage asset = _storage.assets[ctx.subAccountId.assetId];
        Asset storage collateral = _storage.assets[ctx.subAccountId.collateralId];
        SubAccount storage subAccount = _storage.accounts[subAccountId];
        require(subAccount.size > 0, "S=0"); // position Size Is Zero
        tradingPrice = _storage.checkPrice(asset, tradingPrice);

        // total
        _decreaseTotalSize(asset, ctx.subAccountId.isLong, subAccount.size, subAccount.entryPrice);
        // fee & funding & borrowing
        ctx.fundingFeeUsd = asset.fundingFeeUsd(subAccount, ctx.subAccountId.isLong);
        ctx.positionFeeUsd = asset.getLiquidationFeeUsd(subAccount.size, tradingPrice);
        ctx.totalFeeUsd = ctx.fundingFeeUsd + ctx.positionFeeUsd;
        // should mm unsafe
        {
            (ctx.hasProfit, ctx.pnlUsd) = _traderCappedPnlUsd(
                asset,
                subAccount,
                ctx.subAccountId.isLong,
                subAccount.size,
                ctx.assetPrice,
                _blockTimestamp()
            );
            require(
                !subAccount.isAccountSafe(
                    ctx.collateralPrice,
                    ctx.assetPrice,
                    asset.maintenanceMarginRate(),
                    ctx.hasProfit,
                    ctx.pnlUsd,
                    ctx.fundingFeeUsd
                ),
                "MMS"
            ); // Maintenance Margin Safe
        }
        // trading pnl
        (ctx.hasProfit, ctx.pnlUsd) = _traderCappedPnlUsd(
            asset,
            subAccount,
            ctx.subAccountId.isLong,
            subAccount.size,
            tradingPrice,
            _blockTimestamp()
        );
        // realize pnl
        ctx.oldPositionSize = subAccount.size;
        if (ctx.hasProfit) {
            // this case is impossible unless MMRate changes
            (ctx.paidFeeUsd, ctx.feeInProfitToken) = _realizeProfit(
                ctx.subAccountId.account,
                ctx.pnlUsd,
                ctx.totalFeeUsd,
                _storage.assets[profitAssetId],
                ctx.profitAssetPrice
            );
        } else {
            ctx.pnlUsd = _realizeLoss(subAccount, collateral, ctx.collateralPrice, ctx.pnlUsd, false);
        }
        subAccount.size = 0;
        subAccount.entryPrice = 0;
        subAccount.entryFunding = 0;
        subAccount.lastIncreasedTime = 0;
        // ignore fees if can not afford
        if (ctx.totalFeeUsd > ctx.paidFeeUsd) {
            ctx.feeInCollateralToken = uint256(ctx.totalFeeUsd - ctx.paidFeeUsd).wdiv(ctx.collateralPrice).toUint96();
            ctx.feeInCollateralToken = LibMath.min(ctx.feeInCollateralToken, subAccount.collateral);
            subAccount.collateral -= ctx.feeInCollateralToken;
            ctx.paidFeeUsd += uint256(ctx.feeInCollateralToken).wmul(ctx.collateralPrice).toUint96();
            // remember to call _collectFee
        }
        _mergeAndCollectFee(
            ctx.subAccountId.account,
            profitAssetId,
            ctx.subAccountId.collateralId,
            ctx.feeInProfitToken,
            ctx.feeInCollateralToken
        );
        {
            LiquidateArgs memory args = LiquidateArgs({
                subAccountId: subAccountId,
                collateralId: ctx.subAccountId.collateralId,
                profitAssetId: profitAssetId,
                isLong: ctx.subAccountId.isLong,
                amount: ctx.oldPositionSize,
                tradingPrice: tradingPrice,
                assetPrice: ctx.assetPrice,
                collateralPrice: ctx.collateralPrice,
                profitAssetPrice: ctx.profitAssetPrice,
                fundingFeeUsd: LibMath.min(ctx.fundingFeeUsd, ctx.paidFeeUsd),
                // there is no separate positionFee for compatible reasons
                paidFeeUsd: ctx.paidFeeUsd,
                hasProfit: ctx.hasProfit,
                pnlUsd: ctx.pnlUsd,
                remainCollateral: subAccount.collateral
            });
            emit Liquidate(ctx.subAccountId.account, ctx.subAccountId.assetId, args);
        }
        // trace
        if (subAccount.size == 0 && subAccount.collateral == 0) {
            _storage.userSubAccountIds[ctx.subAccountId.account].remove(subAccountId);
            _storage.subAccountIds.remove(subAccountId);
        }
        return tradingPrice;
    }

    function _increaseTotalSize(
        Asset storage asset,
        bool isLong,
        uint96 amount,
        uint96 price,
        uint96[] memory markPrices
    ) internal {
        if (isLong) {
            uint96 newPosition = asset.totalLongPosition + amount;
            require(newPosition <= asset.maxLongPositionSize(), "EMP"); // Exceed Max Position
            asset.averageLongPrice = ((uint256(asset.averageLongPrice) *
                uint256(asset.totalLongPosition) +
                uint256(price) *
                uint256(amount)) / uint256(newPosition)).toUint96();
            asset.totalLongPosition = newPosition;
        } else {
            uint96 newPosition = asset.totalShortPosition + amount;
            require(newPosition <= asset.maxShortPositionSize(), "EMP"); // Exceed Max Position
            asset.averageShortPrice = ((uint256(asset.averageShortPrice) *
                uint256(asset.totalShortPosition) +
                uint256(price) *
                uint256(amount)) / uint256(newPosition)).toUint96();
            asset.totalShortPosition = newPosition;
        }
        // reserve
        {
            uint96 reservationUsd = _storage.totalReservationUsd();
            uint96 poolUsd = _storage.poolUsdWithoutPnl(markPrices);
            require(reservationUsd <= poolUsd, "RSV"); // exceed ReSerVation
        }
    }

    function _decreaseTotalSize(Asset storage asset, bool isLong, uint96 amount, uint96 oldEntryPrice) internal {
        if (isLong) {
            uint96 newPosition = asset.totalLongPosition - amount;
            if (newPosition == 0) {
                asset.averageLongPrice = 0;
            } else {
                asset.averageLongPrice = ((uint256(asset.averageLongPrice) *
                    uint256(asset.totalLongPosition) -
                    uint256(oldEntryPrice) *
                    uint256(amount)) / uint256(newPosition)).toUint96();
            }
            asset.totalLongPosition = newPosition;
        } else {
            uint96 newPosition = asset.totalShortPosition - amount;
            if (newPosition == 0) {
                asset.averageShortPrice = 0;
            } else {
                asset.averageShortPrice = ((uint256(asset.averageShortPrice) *
                    uint256(asset.totalShortPosition) -
                    uint256(oldEntryPrice) *
                    uint256(amount)) / uint256(newPosition)).toUint96();
            }
            asset.totalShortPosition = newPosition;
        }
    }

    function _realizeProfit(
        address trader,
        uint96 pnlUsd,
        uint96 totalFeeUsd,
        Asset storage profitAsset,
        uint96 profitAssetPrice
    )
        internal
        returns (
            // spotLiquidity pays the pnl and fee
            uint96 paidFeeUsd,
            uint96 feeInProfitToken
        )
    {
        {
            uint96 pnlCollateral = uint256(pnlUsd).wdiv(profitAssetPrice).toUint96();
            require(pnlCollateral <= profitAsset.spotLiquidity, "IFP"); // Insufficient Funds for Profit
            if (pnlCollateral > 0) {
                profitAsset.spotLiquidity -= pnlCollateral;
            }
        }
        // pnl
        paidFeeUsd = LibMath.min(totalFeeUsd, pnlUsd);
        pnlUsd = pnlUsd - paidFeeUsd;
        if (pnlUsd > 0) {
            uint96 profitCollateral = uint256(pnlUsd).wdiv(profitAssetPrice).toUint96();
            // transfer profit token
            if (profitCollateral > 0) {
                uint256 rawAmount = profitAsset.toRaw(profitCollateral);
                profitAsset.transferOut(trader, rawAmount);
            }
        }
        // fee
        if (paidFeeUsd > 0) {
            feeInProfitToken = uint256(paidFeeUsd).wdiv(profitAssetPrice).toUint96();
            // note: remember to call _collectFee
        }
    }

    function _realizeLoss(
        SubAccount storage subAccount,
        Asset storage collateral,
        uint96 collateralPrice,
        uint96 pnlUsd,
        bool isThrowBankrupt
    ) internal returns (uint96 truncatedPnlUsd) {
        if (pnlUsd == 0) {
            return 0;
        }
        truncatedPnlUsd = pnlUsd;
        uint96 pnlCollateral = uint256(pnlUsd).wdiv(collateralPrice).toUint96();
        if (isThrowBankrupt) {
            require(subAccount.collateral >= pnlCollateral, "M=0"); // Margin balance Is Zero. the account is bankrupt
        } else {
            if (subAccount.collateral < pnlCollateral) {
                pnlCollateral = subAccount.collateral;
                truncatedPnlUsd = uint256(pnlCollateral).wmul(collateralPrice).toUint96();
            }
        }
        subAccount.collateral -= pnlCollateral;
        collateral.spotLiquidity += pnlCollateral;
    }

    function _traderCappedPnlUsd(
        Asset storage asset,
        SubAccount storage subAccount,
        bool isLong,
        uint96 amount,
        uint96 tradingPrice,
        uint32 timestamp
    ) internal view returns (bool hasProfit, uint96 positionPnlUsd) {
        (hasProfit, positionPnlUsd) = asset.positionPnlUsd(subAccount, isLong, amount, tradingPrice, timestamp);
        if (hasProfit) {
            uint96 cappedPnlUsd = ((uint256(amount) * uint256(subAccount.entryPrice) * uint256(asset.adlMaxPnlRate())) /
                1e23).toUint96(); // 18 + 18 + 5 - 23
            positionPnlUsd = LibMath.min(positionPnlUsd, cappedPnlUsd);
        }
    }

    function _isStable(uint8 tokenId) internal view returns (bool) {
        return _storage.assets[tokenId].isStable();
    }

    function _validateSubAccountId(SubAccountId memory subAccountId) internal view {
        require(subAccountId.account != address(0), "T=0"); // Trader address is zero
        require(_storage.isValidAssetId(subAccountId.assetId), "LST"); // the asset is not LiSTed
        require(_storage.isValidAssetId(subAccountId.collateralId), "LST"); // the asset is not LiSTed
        require(subAccountId.isLong || _storage.assets[subAccountId.assetId].isShortable(), "SHT"); // can not SHorT this asset
    }

    function _validateAssets(uint8 assetId, uint56 includes, uint56 excludes) internal view {
        uint56 flags = _storage.assets[assetId].flags;
        require((flags & includes == includes) && (flags & excludes == 0), "FLG");
    }

    function _mergeAndCollectFee(
        address trader,
        uint8 profitAssetId,
        uint8 collateralId,
        uint96 wadInProfit,
        uint96 wadInCollateral
    ) internal {
        if (profitAssetId == collateralId) {
            uint96 wad = wadInProfit + wadInCollateral;
            if (wad > 0) {
                _collectFee(profitAssetId, trader, wad);
            }
        } else {
            if (wadInProfit > 0) {
                _collectFee(profitAssetId, trader, wadInProfit);
            }
            if (wadInCollateral > 0) {
                _collectFee(collateralId, trader, wadInCollateral);
            }
        }
    }
}
