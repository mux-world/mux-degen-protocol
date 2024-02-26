// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "../interfaces/ILiquidity.sol";

import "../libraries/LibAsset.sol";
import "../libraries/LibSubAccount.sol";
import "../libraries/LibMath.sol";
import "../libraries/LibReferenceOracle.sol";
import "../libraries/LibTypeCast.sol";

import "../DegenPoolStorage.sol";
import "../peripherals/MlpToken.sol";

contract Liquidity is DegenPoolStorage, ILiquidity {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using LibAsset for Asset;
    using LibMath for uint256;
    using LibTypeCast for uint256;
    using LibSubAccount for bytes32;
    using LibPoolStorage for PoolStorage;
    using LibReferenceOracle for PoolStorage;

    /**
     * @dev   Add liquidity.
     *
     * @param trader            liquidity provider address.
     * @param tokenId           asset.id that added.
     * @param rawAmount         asset token amount. decimals = erc20.decimals.
     * @param markPrices        markPrices prices of all supported assets.
     */
    function addLiquidity(
        address trader,
        uint8 tokenId,
        uint256 rawAmount, // NOTE: OrderBook SHOULD transfer rawAmount collateral to LiquidityPool
        uint96[] memory markPrices
    ) external onlyOrderBook updateSequence updateBrokerTransactions returns (uint96 mlpAmount) {
        require(trader != address(0), "T=0"); // Trader address is zero
        require(_storage.isValidAssetId(tokenId), "LST"); // the asset is not LiSTed
        require(rawAmount != 0, "A=0"); // Amount Is Zero
        markPrices = _checkAllMarkPrices(markPrices);
        uint256 totalLiquidityUsd = _storage.poolUsd(markPrices);
        uint96 mlpPrice = _storage.mlpTokenPrice(totalLiquidityUsd);
        Asset storage token = _storage.assets[tokenId];
        require(token.isEnabled(), "ENA"); // the token is temporarily not ENAbled
        require(token.canAddRemoveLiquidity(), "TUL"); // the Token cannot be Used to add Liquidity
        require(token.isStable(), "FLG");
        uint96 tokenPrice = markPrices[tokenId];

        // token amount
        uint96 wadAmount = token.toWad(rawAmount);
        uint96 feeCollateral = uint256(wadAmount).rmul(_storage.liquidityFeeRate()).toUint96();
        wadAmount -= feeCollateral;
        token.spotLiquidity += wadAmount; // without fee
        _collectFee(tokenId, trader, feeCollateral);
        // mlp
        mlpAmount = ((uint256(wadAmount) * uint256(tokenPrice)) / uint256(mlpPrice)).toUint96();
        MlpToken(_storage.mlpToken()).mint(trader, mlpAmount);
        emit AddLiquidity(trader, tokenId, tokenPrice, mlpPrice, mlpAmount, feeCollateral);
        {
            uint96 liquidityCapUsd = _storage.liquidityCapUsd();
            uint96 tokenUsd = ((uint256(wadAmount) * markPrices[tokenId]) / 1e18).toUint96();
            require(tokenUsd + totalLiquidityUsd <= liquidityCapUsd, "LCP"); // Liquidity Cap is reached
        }
    }

    /**
     * @dev Add liquidity but ignore MLP
     */
    function donateLiquidity(
        address who,
        uint8 tokenId,
        uint256 rawAmount // NOTE: OrderBook SHOULD transfer rawAmount collateral to LiquidityPool
    ) external onlyOrderBook updateSequence {
        require(_storage.isValidAssetId(tokenId), "LST"); // the asset is not LiSTed
        require(rawAmount != 0, "A=0"); // Amount Is Zero
        Asset storage token = _storage.assets[tokenId];
        require(token.isEnabled(), "ENA"); // the token is temporarily not ENAbled
        require(token.canAddRemoveLiquidity(), "TUL"); // the Token cannot be Used to add Liquidity
        require(token.isStable(), "FLG");

        // token amount
        uint96 wadAmount = token.toWad(rawAmount);
        token.spotLiquidity += wadAmount;
        emit DonateLiquidity(who, tokenId, wadAmount);
    }

    /**
     * @dev   Remove liquidity.
     *
     * @param trader            liquidity provider address.
     * @param mlpAmount         mlp amount.
     * @param tokenId           asset.id that removed to.
     * @param markPrices        asset prices of all supported assets.
     */
    function removeLiquidity(
        address trader,
        uint96 mlpAmount, // NOTE: OrderBook SHOULD transfer mlpAmount mlp to LiquidityPool
        uint8 tokenId,
        uint96[] memory markPrices
    ) external onlyOrderBook updateSequence updateBrokerTransactions returns (uint256 rawAmount) {
        require(trader != address(0), "T=0"); // Trader address is zero
        require(_storage.isValidAssetId(tokenId), "LST"); // the asset is not LiSTed
        require(mlpAmount != 0, "A=0"); // Amount Is Zero
        markPrices = _checkAllMarkPrices(markPrices);
        uint256 totalLiquidityUsd = _storage.poolUsd(markPrices);
        uint96 mlpPrice = _storage.mlpTokenPrice(totalLiquidityUsd);
        Asset storage token = _storage.assets[tokenId];
        require(token.isEnabled(), "ENA"); // the token is temporarily not ENAbled
        require(token.canAddRemoveLiquidity(), "TUL"); // the Token cannot be Used to remove Liquidity
        require(token.isStable(), "FLG");
        uint96 tokenPrice = markPrices[tokenId];

        // amount
        uint96 wadAmount = ((uint256(mlpAmount) * mlpPrice) / uint256(tokenPrice)).toUint96();
        require(wadAmount <= token.spotLiquidity, "LIQ"); // insufficient LIQuidity
        token.spotLiquidity -= wadAmount; // include fee
        uint96 feeCollateral = uint256(wadAmount).rmul(_storage.liquidityFeeRate()).toUint96();
        wadAmount -= feeCollateral;
        // send token
        _collectFee(tokenId, trader, feeCollateral);
        rawAmount = token.toRaw(wadAmount);
        MlpToken(_storage.mlpToken()).burn(_storage.orderBook(), mlpAmount);
        token.transferOut(trader, rawAmount);
        // reserve
        {
            uint96 reservationUsd = _storage.totalReservationUsd();
            uint96 poolUsd = _storage.poolUsdWithoutPnl(markPrices);
            require(reservationUsd <= poolUsd, "RSV");
        }
        emit RemoveLiquidity(trader, tokenId, tokenPrice, mlpPrice, mlpAmount, feeCollateral);
    }

    /**
     * @notice Anyone can update funding each [fundingInterval] seconds by specifying utilizations.
     *
     *         Check _updateFundingState in Liquidity.sol and _getBorrowing in Trade.sol
     *         on how to calculate funding and borrowing.
     */
    function updateFundingState() external updateSequence {
        uint32 nextFundingTime = (_blockTimestamp() / _storage.fundingInterval()) * _storage.fundingInterval();
        if (_storage.lastFundingTime == 0) {
            // init state. just update lastFundingTime
            _storage.lastFundingTime = nextFundingTime;
        } else if (_storage.lastFundingTime + _storage.fundingInterval() >= _blockTimestamp()) {
            // do nothing
        } else {
            uint32 timeSpan = nextFundingTime - _storage.lastFundingTime;
            _updateFundingState(timeSpan);
            _storage.lastFundingTime = nextFundingTime;
        }
    }

    /**
     * @dev Broker can withdraw brokerGasRebate.
     */
    function claimBrokerGasRebate(address receiver, uint8 assetId) external onlyOrderBook returns (uint256 rawAmount) {
        require(receiver != address(0), "RCV"); // bad ReCeiVer
        Asset storage asset = _storage.assets[assetId];
        require(asset.isStable(), "STB"); // the asset is not STaBle
        uint96 wad = (uint256(_storage.brokerGasRebateUsd()) * uint256(_storage.brokerTransactions)).toUint96();
        require(asset.spotLiquidity >= wad, "LIQ"); // insufficient LIQuidity
        asset.spotLiquidity -= wad;
        rawAmount = asset.toRaw(wad);
        emit ClaimBrokerGasRebate(receiver, _storage.brokerTransactions, assetId, rawAmount);
        _storage.brokerTransactions = 0;
        asset.transferOut(receiver, rawAmount);
        return rawAmount;
    }

    /**
     * @dev borrowing + funding design:
     *
     * 1. trader always pays borrowRateApy to LP. this is prevent trader from both long and short the same token.
     * 2. funding = min(1, abs($longs - $shorts）/ alpha) * betaApy.
     * 3. if longs > shorts，longs pay to LP. otherwise short pay to LP. trader never pays to trader.
     */
    function _updateFundingState(uint32 timeSpan) internal {
        uint8 tokenLen = uint8(_storage.assetsCount);
        for (uint8 tokenId = 0; tokenId < tokenLen; tokenId++) {
            Asset storage asset = _storage.assets[tokenId];
            if (asset.isStable()) {
                continue;
            }
            // funding
            uint96 longsUsd = uint256(asset.totalLongPosition).wmul(asset.averageLongPrice).toUint96();
            uint96 shortsUsd = uint256(asset.totalShortPosition).wmul(asset.averageShortPrice).toUint96();
            (
                bool isPositiveFundingRate,
                uint32 newFundingRateApy,
                uint128 longCumulativeFunding,
                uint128 shortCumulativeFunding
            ) = _getFundingRate(asset.fundingAlpha(), asset.fundingBetaApy(), longsUsd, shortsUsd, timeSpan);
            // borrowing
            (uint32 newBorrowingRateApy, uint128 cumulativeBorrowing) = _getBorrowingRate(
                _storage.borrowingRateApy(),
                timeSpan
            );
            asset.longCumulativeFunding += longCumulativeFunding + cumulativeBorrowing;
            asset.shortCumulativeFunding += shortCumulativeFunding + cumulativeBorrowing;
            emit UpdateFundingRate(
                tokenId,
                isPositiveFundingRate,
                newFundingRateApy,
                newBorrowingRateApy,
                asset.longCumulativeFunding,
                asset.shortCumulativeFunding
            );
        }
    }

    /**
     * @dev Funding rate formula.
     */
    function _getFundingRate(
        uint96 alpha, // 1e18, tokens
        uint32 betaApy, // 1e5
        uint96 longsUsd, // 1e18, tokens
        uint96 shortsUsd, // 1e18, tokens
        uint32 timeSpan // 1e0
    )
        internal
        pure
        returns (
            bool isPositiveFundingRate,
            uint32 newFundingRateApy, // 1e5
            uint128 longCumulativeFunding, // 1e18
            uint128 shortCumulativeFunding // 1e18
        )
    {
        require(alpha != 0, "A=0"); // Alpha Is Zero
        // min(1, abs(longs - shorts）/ alpha) * beta
        isPositiveFundingRate = longsUsd >= shortsUsd;
        uint256 x = isPositiveFundingRate ? longsUsd - shortsUsd : shortsUsd - longsUsd;
        if (x > alpha) {
            x = alpha;
        }
        newFundingRateApy = ((uint256(x) * uint256(betaApy)) / uint256(alpha)).toUint32(); // 18 + 5 - 18
        if (isPositiveFundingRate) {
            longCumulativeFunding = ((uint256(newFundingRateApy) * uint256(timeSpan) * 1e13) / APY_PERIOD).toUint128(); // 5 + 0 + 13 - 0
        } else {
            shortCumulativeFunding = ((uint256(newFundingRateApy) * uint256(timeSpan) * 1e13) / APY_PERIOD).toUint128(); // 5 + 0 + 13 - 0
        }
    }

    /**
     * @dev Borrowing rate formula.
     */
    function _getBorrowingRate(
        uint32 borrowingRateApy, // 1e5
        uint32 timeSpan // 1e0
    )
        internal
        pure
        returns (
            uint32 newBorrowingRateApy, // 1e5
            uint128 cumulativeBorrowing // 1e18
        )
    {
        newBorrowingRateApy = borrowingRateApy;
        cumulativeBorrowing = ((uint256(newBorrowingRateApy) * uint256(timeSpan) * 1e13) / APY_PERIOD).toUint128(); // 5 + 0 + 13 - 0
    }
}
