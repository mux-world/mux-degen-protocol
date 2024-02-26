// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "../orderbook/Types.sol";

interface IOrderBook {
    /**
     * @notice Open/close position. called by Trader.
     *
     *         Market order will expire after marketOrderTimeout seconds.
     *         Limit/Trigger order will expire after deadline.
     * @param  orderParams        order details includes:
     *         subAccountId       sub account id. see LibSubAccount.decodeSubAccountId.
     *         collateralAmount   deposit collateral before open; or withdraw collateral after close. decimals = erc20.decimals.
     *         size               position size. decimals = 18.
     *         price              limit price. decimals = 18.
     *         profitTokenId      specify the profitable asset.id when closing a position and making a profit.
     *                            take no effect when opening a position or loss.
     *         flags              a bitset of LibOrder.POSITION_*.
     *                            POSITION_OPEN                     this flag means openPosition; otherwise closePosition
     *                            POSITION_MARKET_ORDER             this flag means ignore limitPrice
     *                            POSITION_WITHDRAW_ALL_IF_EMPTY    this flag means auto withdraw all collateral if position.size == 0
     *                            POSITION_TRIGGER_ORDER            this flag means this is a trigger order (ex: stop-loss order). otherwise this is a limit order (ex: take-profit order)
     *         deadline           a unix timestamp after which the limit/trigger order MUST NOT be filled. fill 0 for market order.
     * @param  referralCode       set referral code of the trading account.
     */
    function placePositionOrder(PositionOrderParams memory orderParams, bytes32 referralCode) external;

    /**
     * @notice Add/remove liquidity. called by Liquidity Provider.
     *
     *         Can be filled after liquidityLockPeriod seconds.
     * @param  orderParams   order details includes:
     *         assetId       asset.id that added/removed to.
     *         rawAmount     asset token amount. decimals = erc20.decimals.
     *         isAdding      true for add liquidity, false for remove liquidity.
     */
    function placeLiquidityOrder(LiquidityOrderParams memory orderParams) external;

    /**
     * @notice Withdraw collateral/profit. called by Trader.
     *
     *         This order will expire after marketOrderTimeout seconds.
     * @param  orderParams        order details includes:
     *         subAccountId       sub account id. see LibSubAccount.decodeSubAccountId.
     *         rawAmount          collateral or profit asset amount. decimals = erc20.decimals.
     *         profitTokenId      always 0. not supported in DegenPool. only for compatibility
     *         isProfit           always false. not supported in DegenPool. only for compatibility
     */
    function placeWithdrawalOrder(WithdrawalOrderParams memory orderParams) external;

    /**
     * @dev   Open/close a position. called by Broker.
     *
     * @param orderId           order id.
     * @param filledAmount      fill amount. decimals = 18.
     * @param tradingPrice      trading price. decimals = 18.
     * @param markPrices        mark prices of all assets. decimals = 18.
     */
    function fillPositionOrder(
        uint64 orderId,
        uint96 filledAmount,
        uint96 tradingPrice,
        uint96[] memory markPrices
    ) external;

    /**
     * @dev   Add/remove liquidity. called by Broker.
     *
     *        Check _getLiquidityFeeRate in Liquidity.sol on how to calculate liquidity fee.
     * @param orderId           order id.
     * @param markPrices        mark prices of all assets. decimals = 18.
     */
    function fillLiquidityOrder(uint64 orderId, uint96[] calldata markPrices) external;

    function fillAdlOrder(AdlOrderParams memory orderParams, uint96 tradingPrice, uint96[] memory markPrices) external;

    function donateLiquidity(
        uint8 assetId,
        uint96 rawAmount // erc20.decimals
    ) external;

    /**
     * @dev   Withdraw collateral/profit. called by Broker.
     *
     * @param orderId           order id.
     * @param markPrices        mark prices of all assets. decimals = 18.
     */
    function fillWithdrawalOrder(uint64 orderId, uint96[] memory markPrices) external;

    /**
     * @notice Cancel an Order by orderId.
     */
    function cancelOrder(uint64 orderId) external;

    /**
     * @notice Trader can withdraw all collateral only when position = 0.
     */
    function withdrawAllCollateral(bytes32 subAccountId) external;

    /**
     * @notice Anyone can update funding each [fundingInterval] seconds by specifying utilizations.
     *
     *         Check _updateFundingState in Liquidity.sol and _getBorrowing in Trade.sol
     *         on how to calculate funding and borrowing.
     */
    function updateFundingState() external;

    /**
     * @notice Deposit collateral into a subAccount.
     *
     * @param  subAccountId       sub account id. see LibSubAccount.decodeSubAccountId.
     * @param  collateralAmount   collateral amount. decimals = erc20.decimals.
     */
    function depositCollateral(bytes32 subAccountId, uint256 collateralAmount) external;

    function liquidate(
        bytes32 subAccountId,
        uint8 profitAssetId, // only used when !isLong
        uint96 tradingPrice,
        uint96[] memory assetPrices
    ) external;

    /**
     * @dev Broker can withdraw brokerGasRebate.
     */
    function claimBrokerGasRebate(uint8 assetId) external returns (uint256 rawAmount);
}
