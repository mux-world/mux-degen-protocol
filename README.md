# MUX Degen Protocol

The MUX Degen Protocol is a margin-trading protocol that specifically tailored to enhance the trading experience for assets with smaller liquidity. This protocol maintains the  capabilities that users have come to expect from the [MUX Protocol](https://github.com/mux-world/mux-protocol) family, while introducing a novel mechanism designed to safeguard the degen trades.

The MUX Degen Protocol employs a dynamic price impact feature, which adjusts trading prices based on the size of the positions. This innovation is pivotal for mitigating the risks associated with price manipulation, ensuring a fairer and more stable trading environment for all participants.

## Protocol Structure

The contract architecture of the MUX Degen Protocol primarily consists of the `DegenPool` and the `OrderBook`. When an `Order` is placed on the `OrderBook`, off-chain `Broker` query the dark `Oracle` to get `markPrice` and `tradingPrice` (with price impact) and fill these orders by calling `OrderBook`. Upon the filling of an order, the `OrderBook` contract communicates with the `DegenPool` to execute the trade.

* `DegenPool`: The `DegenPool` serves as the foundational asset repository and provide traders with the ability to open and close positions. The [DegenPool interface](contracts/interfaces/IDegenPool.sol) is a [Diamond](contracts/third-party/Diamond.sol) contract with multiple facets, which provides functions for collateral management, liquidity management and trading execution, located in [facets](contracts/facets) directory.
* `OrderBook`: The `OrderBook` component is where `Trader` interact with the protocol to place their orders. 

## Settings and Mechanisms

1. `Collateral` and `Underlying` whitelist

    The DegenPool establishes a whitelist of stable coins that are accepted as collateral for trades. Profits and losses from trades are calculated and paid out in stable coins. Additionally, the protocol specifies a set of assets that can be traded, allowing traders to open long or short positions on these `Underlying`.

2. Liquidity reservation
   
    Upon the opening of a position, the `DegenPool` reserves a portion of its liquidity to cover potential profits payable to the trader. This reserved liquidity is locked and cannot be removed from the pool, ensuring that there are always sufficient funds available to meet the obligations arising from winning trades.

3. Margin balance

    The protocol closely monitors each trader's margin balance.
    
    `Margin Balance = Collateral + PnL - Funding Payment`

4. Liquidation

    If a trader's losses lead their margin balance to fall below the `Maintenance Margin Rate`, a keeper function is triggered to call the liquidation interface, which closes the position to prevent further losses.

5. Automatic Deleveraging (ADL)

    When a `Trader`'s profit rate exceeds the ADL trigger rate, another keeper function is activated to call the ADL interface, initiating the closure of the position.  To further mitigate the risk of delayed execution by the ADL keeper and ensure that profits do not exceed the reserved liquidity, the protocol enforces a maximum profit ratio. This ratio caps the profit that can be realized from a single position.
