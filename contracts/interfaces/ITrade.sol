// SPDX-License-Identifier: GPL-2.0-or-later

/**
 * @title ITrade
 * @dev Interface for the Trade contract, which handles opening, closing, and liquidating positions, as well as withdrawing profits.
 */
pragma solidity 0.8.19;

interface ITrade {
    struct OpenPositionArgs {
        bytes32 subAccountId;
        uint8 collateralId;
        bool isLong;
        uint96 amount;
        uint96 tradingPrice;
        uint96 assetPrice;
        uint96 collateralPrice;
        uint96 newEntryPrice;
        uint96 feeUsd;
        uint96 remainPosition;
        uint96 remainCollateral;
    }
    struct ClosePositionArgs {
        bytes32 subAccountId;
        uint8 collateralId;
        uint8 profitAssetId;
        bool isLong;
        uint96 amount;
        uint96 tradingPrice;
        uint96 assetPrice;
        uint96 collateralPrice;
        uint96 profitAssetPrice;
        uint96 feeUsd;
        bool hasProfit;
        uint96 pnlUsd;
        uint96 remainPosition;
        uint96 remainCollateral;
    }
    struct LiquidateArgs {
        bytes32 subAccountId;
        uint8 collateralId;
        uint8 profitAssetId;
        bool isLong;
        uint96 amount;
        uint96 tradingPrice;
        uint96 assetPrice;
        uint96 collateralPrice;
        uint96 profitAssetPrice;
        uint96 feeUsd;
        bool hasProfit;
        uint96 pnlUsd;
        uint96 remainCollateral;
    }

    event OpenPosition(address indexed trader, uint8 indexed assetId, OpenPositionArgs args);
    event ClosePosition(address indexed trader, uint8 indexed assetId, ClosePositionArgs args);
    event Liquidate(address indexed trader, uint8 indexed assetId, LiquidateArgs args);

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
    ) external returns (uint96);

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
        uint8 profitAssetId,
        uint96[] memory markPrices
    ) external returns (uint96);

    function liquidate(
        bytes32 subAccountId,
        uint8 profitAssetId,
        uint96 tradingPrice,
        uint96[] memory markPrices
    ) external returns (uint96);
}
