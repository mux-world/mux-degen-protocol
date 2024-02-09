import { ethers } from "hardhat"
import "@nomiclabs/hardhat-waffle"
import { expect } from "chai"
import { toWei, createContract, OrderType, assembleSubAccountId, PositionOrderFlags, toBytes32, rate, BROKER_ROLE } from "../scripts/deployUtils"
import { OB_CANCEL_COOL_DOWN_KEY, OB_LIMIT_ORDER_TIMEOUT_KEY, OB_LIQUIDITY_LOCK_PERIOD_KEY, OB_MARKET_ORDER_TIMEOUT_KEY, pad32l } from "../scripts/deployUtils"
import { Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { MockDegenPool, OrderBook } from "../typechain"
import { time } from "@nomicfoundation/hardhat-network-helpers"
const U = ethers.utils

function parsePositionOrder(orderData: string) {
  const [subAccountId, collateral, size, price, tpPrice, slPrice, expiration, tpslExpiration, profitTokenId, tpslProfitTokenId, flags] = ethers.utils.defaultAbiCoder.decode(
    ["bytes32", "uint96", "uint96", "uint96", "uint96", "uint96", "uint32", "uint32", "uint8", "uint8", "uint8"],
    orderData
  )
  return {
    subAccountId,
    collateral,
    size,
    price,
    tpPrice,
    slPrice,
    expiration,
    tpslExpiration,
    profitTokenId,
    tpslProfitTokenId,
    flags,
  }
}

function parseLiquidityOrder(orderData: string) {
  const [rawAmount, assetId, isAdding] = ethers.utils.defaultAbiCoder.decode(["uint96", "uint8", "bool"], orderData)
  return {
    rawAmount,
    assetId,
    isAdding,
  }
}

function parseWithdrawalOrder(orderData: string) {
  const [subAccountId, rawAmount, profitTokenId, isProfit] = ethers.utils.defaultAbiCoder.decode(["bytes32", "uint96", "uint8", "bool"], orderData)
  return {
    subAccountId,
    rawAmount,
    profitTokenId,
    isProfit,
  }
}

describe("Order", () => {
  const refCode = toBytes32("")
  let orderBook: OrderBook
  let pool: MockDegenPool
  let mlp: Contract
  let atk: Contract
  let ctk: Contract

  let user0: SignerWithAddress
  let broker: SignerWithAddress
  let timestampOfTest: number

  before(async () => {
    const accounts = await ethers.getSigners()
    user0 = accounts[0]
    broker = accounts[1]
  })

  beforeEach(async () => {
    timestampOfTest = await time.latest()
    ctk = await createContract("MockERC20", ["CTK", "CTK", 18])
    atk = await createContract("MockERC20", ["ATK", "ATK", 18])
    mlp = await createContract("MockERC20", ["MLP", "MLP", 18])
    pool = await createContract("MockDegenPool") as MockDegenPool
    const libOrderBook = await createContract("LibOrderBook")
    orderBook = (await createContract("OrderBook", [], { "contracts/libraries/LibOrderBook.sol:LibOrderBook": libOrderBook })) as OrderBook
    await orderBook.initialize(pool.address, mlp.address)
    await orderBook.grantRole(BROKER_ROLE, broker.address)
    await orderBook.setConfig(OB_LIQUIDITY_LOCK_PERIOD_KEY, pad32l(60 * 15))
    await orderBook.setConfig(OB_MARKET_ORDER_TIMEOUT_KEY, pad32l(60 * 2))
    await orderBook.setConfig(OB_LIMIT_ORDER_TIMEOUT_KEY, pad32l(86400 * 365))
    await orderBook.setConfig(OB_CANCEL_COOL_DOWN_KEY, pad32l(5))
    await pool.setAssetAddress(0, ctk.address)
    await pool.setAssetAddress(1, atk.address)
    // tokenId, minProfit, minProfit, lotSize
    await pool.setAssetParams(1, 0, rate("0"), toWei('0.1'))
    // assetId, trade, open, short, enable, stable, strict, liquidity
    await pool.setAssetFlags(0, false, false, false, true, true, true, true)
    await pool.setAssetFlags(1, true, true, true, true, false, false, false)
    await pool.setAssetFlags(2, false, false, false, true, true, true, true)
  })

  it("place", async () => {
    {
      await ctk.approve(orderBook.address, toWei("1"))
      await ctk.mint(user0.address, toWei("1"))
      await orderBook.placePositionOrder(
        {
          subAccountId: assembleSubAccountId(user0.address, 0, 1, true),
          collateral: toWei("1"),
          size: toWei("0.2"),
          price: toWei("3000"),
          tpPrice: toWei("4000"),
          slPrice: toWei("2000"),
          expiration: timestampOfTest + 1000 + 86400 * 3,
          tpslExpiration: timestampOfTest + 2000 + 86400 * 3,
          profitTokenId: 0,
          tpslProfitTokenId: 2,
          flags: PositionOrderFlags.OpenPosition + PositionOrderFlags.MarketOrder,
        },
        refCode
      )
      const orders = await orderBook.getOrders(0, 100)
      expect(orders.totalCount).to.equal(1)
      expect(orders.orderDataArray.length).to.equal(1)
      {
        const order2 = await orderBook.getOrder(0)
        expect(order2[0].payload).to.equal(orders.orderDataArray[0].payload)
      }
      {
        const orders3 = await orderBook.getOrdersOf(user0.address, 0, 100)
        expect(orders3.totalCount).to.equal(1)
        expect(orders3.orderDataArray.length).to.equal(1)
        expect(orders3.orderDataArray[0].payload).to.equal(orders.orderDataArray[0].payload)
      }
      expect(orders.orderDataArray[0].id).to.equal(0)
      expect(orders.orderDataArray[0].orderType).to.equal(OrderType.Position)
      const order = parsePositionOrder(orders.orderDataArray[0].payload)
      expect(order.subAccountId).to.equal(assembleSubAccountId(user0.address, 0, 1, true))
      expect(order.collateral).to.equal(toWei("1"))
      expect(order.size).to.equal(toWei("0.2"))
      expect(order.price).to.equal(toWei("3000"))
      expect(order.tpPrice).to.equal(toWei("4000"))
      expect(order.slPrice).to.equal(toWei("2000"))
      expect(order.expiration).to.equal(timestampOfTest + 1000 + 86400 * 3)
      expect(order.tpslExpiration).to.equal(timestampOfTest + 2000 + 86400 * 3)
      expect(order.profitTokenId).to.equal(0)
      expect(order.tpslProfitTokenId).to.equal(2)
      expect(order.flags).to.equal(PositionOrderFlags.OpenPosition + PositionOrderFlags.MarketOrder)
      expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("1"))
    }
    {
      await ctk.approve(orderBook.address, toWei("40"))
      await ctk.mint(user0.address, toWei("40"))
      await orderBook.connect(user0).placeLiquidityOrder({ assetId: 0, rawAmount: toWei("40"), isAdding: true })
      const orders = await orderBook.getOrders(0, 100)
      expect(orders.totalCount).to.equal(2)
      expect(orders.orderDataArray.length).to.equal(2)
      {
        const order2 = await orderBook.getOrder(1)
        expect(order2[0].payload).to.equal(orders.orderDataArray[1].payload)
      }
      {
        const orders3 = await orderBook.getOrdersOf(user0.address, 0, 100)
        expect(orders3.totalCount).to.equal(2)
        expect(orders3.orderDataArray.length).to.equal(2)
        expect(orders3.orderDataArray[1].payload).to.equal(orders.orderDataArray[1].payload)
      }
      expect(orders.orderDataArray[1].orderType).to.equal(OrderType.Liquidity)
      const order = parseLiquidityOrder(orders.orderDataArray[1].payload)
      expect(order.rawAmount).to.equal(toWei("40"))
      expect(order.assetId).to.equal(0)
      expect(order.isAdding).to.equal(true)
    }
    {
      await orderBook.connect(user0).placeWithdrawalOrder({
        subAccountId: assembleSubAccountId(user0.address, 0, 1, true),
        rawAmount: toWei("500"),
        profitTokenId: 1,
        isProfit: true,
      })
      const orders = await orderBook.getOrders(0, 100)
      expect(orders.totalCount).to.equal(3)
      expect(orders.orderDataArray.length).to.equal(3)
      {
        const order2 = await orderBook.getOrder(2)
        expect(order2[0].payload).to.equal(orders.orderDataArray[2].payload)
      }
      {
        const orders3 = await orderBook.getOrdersOf(user0.address, 0, 100)
        expect(orders3.totalCount).to.equal(3)
        expect(orders3.orderDataArray.length).to.equal(3)
        expect(orders3.orderDataArray[2].payload).to.equal(orders.orderDataArray[2].payload)
      }
      expect(orders.orderDataArray[2].orderType).to.equal(OrderType.Withdrawal)
      const order = parseWithdrawalOrder(orders.orderDataArray[2].payload)
      expect(order.subAccountId).to.equal(assembleSubAccountId(user0.address, 0, 1, true))
      expect(order.rawAmount).to.equal(toWei("500"))
      expect(order.profitTokenId).to.equal(1)
      expect(order.isProfit).to.equal(true)
    }
  })

  it("lotSize", async () => {
    await expect(orderBook.placePositionOrder({
      subAccountId: assembleSubAccountId(user0.address, 0, 1, true),
      collateral: toWei("0"),
      size: toWei("0.05"),
      price: toWei("3000"),
      tpPrice: toWei("4000"),
      slPrice: toWei("2000"),
      expiration: timestampOfTest + 1000 + 86400 * 3,
      tpslExpiration: timestampOfTest + 2000 + 86400 * 3,
      profitTokenId: 0,
      tpslProfitTokenId: 2,
      flags: PositionOrderFlags.OpenPosition,
    }, refCode)).to.revertedWith("LOT")
  })

  it("asset should not be stable", async () => {
    {
      await ctk.approve(orderBook.address, toWei("1"))
      await ctk.mint(user0.address, toWei("1"))
      await expect(orderBook.placePositionOrder(
        {
          subAccountId: assembleSubAccountId(user0.address, 0, 0, true),
          collateral: toWei("1"),
          size: toWei("0.2"),
          price: toWei("3000"),
          tpPrice: toWei("4000"),
          slPrice: toWei("2000"),
          expiration: timestampOfTest + 1000 + 86400 * 3,
          tpslExpiration: timestampOfTest + 2000 + 86400 * 3,
          profitTokenId: 0,
          tpslProfitTokenId: 2,
          flags: PositionOrderFlags.OpenPosition,
        },
        refCode
      )).to.revertedWith("FLG")
    }
  })

  it("collateral should be stable", async () => {
    {
      await atk.approve(orderBook.address, toWei("1"))
      await atk.mint(user0.address, toWei("1"))
      await expect(orderBook.placePositionOrder(
        {
          subAccountId: assembleSubAccountId(user0.address, 1, 0, true),
          collateral: toWei("1"),
          size: toWei("0.2"),
          price: toWei("3000"),
          tpPrice: toWei("4000"),
          slPrice: toWei("2000"),
          expiration: timestampOfTest + 1000 + 86400 * 3,
          tpslExpiration: timestampOfTest + 2000 + 86400 * 3,
          profitTokenId: 0,
          tpslProfitTokenId: 2,
          flags: PositionOrderFlags.OpenPosition,
        },
        refCode
      )).to.revertedWith("FLG")
    }
  })

  it("liquidity should be stable", async () => {
    {
      await atk.approve(orderBook.address, toWei("40"))
      await atk.mint(user0.address, toWei("40"))
      await expect(orderBook.connect(user0).placeLiquidityOrder({ assetId: 1, rawAmount: toWei("40"), isAdding: true })).to.revertedWith("FLG")
    }
  })

  it("placePositionOrder - open long position", async () => {
    await ctk.approve(orderBook.address, toWei("1000000"))
    await ctk.mint(user0.address, toWei("1000"))
    // no1
    await time.increaseTo(timestampOfTest + 86400)
    {
      await orderBook.placePositionOrder(
        {
          subAccountId: assembleSubAccountId(user0.address, 0, 1, true),
          collateral: toWei("100"),
          size: toWei("0.1"),
          price: toWei("1000"),
          tpPrice: toWei("0"),
          slPrice: toWei("0"),
          expiration: timestampOfTest + 1000 + 86400,
          tpslExpiration: timestampOfTest + 1000 + 86400,
          profitTokenId: 0,
          tpslProfitTokenId: 0,
          flags: PositionOrderFlags.OpenPosition,
        }, refCode
      )
      expect(await ctk.balanceOf(user0.address)).to.equal(toWei("900"))
      expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("100"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(1)
        expect(orders.orderDataArray.length).to.equal(1)
      }

      await expect(orderBook.cancelOrder(0)).to.revertedWith("CLD") // cool down
      await time.increaseTo(timestampOfTest + 86400 + 10)
      await orderBook.cancelOrder(0)
      expect(await ctk.balanceOf(user0.address)).to.equal(toWei("1000"))
      expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("0"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderDataArray.length).to.equal(0)
      }
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(false)
    }
    // no2
    {
      await orderBook.placePositionOrder(
        {
          subAccountId: assembleSubAccountId(user0.address, 0, 1, true),
          collateral: toWei("100"),
          size: toWei("0.1"),
          price: toWei("1000"),
          tpPrice: toWei("0"),
          slPrice: toWei("0"),
          expiration: timestampOfTest + 1000 + 86400,
          tpslExpiration: timestampOfTest + 1000 + 86400,
          profitTokenId: 0,
          tpslProfitTokenId: 0,
          flags: PositionOrderFlags.OpenPosition,
        }, refCode
      )
      expect(await ctk.balanceOf(user0.address)).to.equal(toWei("900"))
      expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("100"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(1)
        expect(orders.orderDataArray.length).to.equal(1)
      }
      await orderBook.connect(broker).fillPositionOrder(1, toWei('0.1'), toWei("1000"), [toWei("1000"), toWei("1"), toWei("1000")])
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderDataArray.length).to.equal(0)
      }
      const result = await orderBook.getOrder(1)
      expect(result[1]).to.equal(false)
      expect(await ctk.balanceOf(user0.address)).to.equal(toWei("900"))
      expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await ctk.balanceOf(pool.address)).to.equal(toWei("100"))
    }
  })

  it("close long position - must profit", async () => {
    const subAccountId = assembleSubAccountId(user0.address, 0, 1, true)
    // open
    await pool.openPosition(subAccountId, toWei("0.1"), toWei("1000"), [toWei("1"), toWei("1000"), toWei("1")])
    {
      await expect(orderBook.placePositionOrder(
        {
          subAccountId,
          collateral: toWei("0"),
          size: toWei("0.1"),
          price: toWei("1000"),
          tpPrice: toWei("0"),
          slPrice: toWei("0"),
          expiration: timestampOfTest + 1000 + 86400,
          tpslExpiration: timestampOfTest + 1000 + 86400,
          profitTokenId: 0,
          tpslProfitTokenId: 0,
          flags: PositionOrderFlags.WithdrawAllIfEmpty + PositionOrderFlags.ShouldReachMinProfit,
        }, refCode
      )).to.revertedWith("MPT")
    }
    // place close - success
    {
      await pool.setAssetAddress(1, atk.address)
      // assetId, minProfit, minProfit, lotSize
      await pool.setAssetParams(1, 60, rate("0.10"), toWei('0.1'))
      await orderBook.placePositionOrder(
        {
          subAccountId,
          collateral: toWei("0"),
          size: toWei("0.1"),
          price: toWei("1000"),
          tpPrice: toWei("0"),
          slPrice: toWei("0"),
          expiration: timestampOfTest + 1000 + 86400,
          tpslExpiration: timestampOfTest + 1000 + 86400,
          profitTokenId: 0,
          tpslProfitTokenId: 0,
          flags: PositionOrderFlags.WithdrawAllIfEmpty + PositionOrderFlags.ShouldReachMinProfit,
        }, refCode
      )
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(1)
        expect(orders.orderDataArray.length).to.equal(1)
      }
    }
    // place close - profit/time not reached
    {
      await expect(orderBook.connect(broker).fillPositionOrder(0, toWei('0.1'), toWei("1001"), [toWei("1"), toWei("1001"), toWei("1")])).to.revertedWith("PFT")
      const orders = await orderBook.getOrders(0, 100)
      expect(orders.totalCount).to.equal(1)
      expect(orders.orderDataArray.length).to.equal(1)
    }
    // place close - profit reached
    {
      await orderBook.connect(broker).fillPositionOrder(0, toWei('0.1'), toWei("1100"), [toWei("1"), toWei("1100"), toWei("1")])
    }
  })

  it("placeLiquidityOrder - addLiquidity", async () => {
    await ctk.approve(orderBook.address, toWei("1000000"))
    await ctk.mint(user0.address, toWei("1000"))
    // no1
    {
      await orderBook.placeLiquidityOrder({ assetId: 0, rawAmount: toWei("150"), isAdding: true })
      expect(await ctk.balanceOf(user0.address)).to.equal(toWei("850"))
      expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("150"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(1)
        expect(orders.orderDataArray.length).to.equal(1)
      }

      await expect(orderBook.cancelOrder(0)).to.revertedWith("CLD") // cool down
      await time.increaseTo(timestampOfTest + 86400 + 10)
      await orderBook.cancelOrder(0)
      expect(await ctk.balanceOf(user0.address)).to.equal(toWei("1000"))
      expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("0"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderDataArray.length).to.equal(0)
      }

      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(false)
    }
    // no2
    {
      await orderBook.placeLiquidityOrder({ assetId: 0, rawAmount: toWei("150"), isAdding: true })
      expect(await ctk.balanceOf(user0.address)).to.equal(toWei("850"))
      expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("150"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(1)
        expect(orders.orderDataArray.length).to.equal(1)
      }

      await expect(orderBook.connect(broker).fillLiquidityOrder(1, [toWei('1'), toWei("2000"), toWei("1")])).to.revertedWith("LCK")
      await time.increaseTo(timestampOfTest + 86400 + 60 * 20)
      await orderBook.connect(broker).fillLiquidityOrder(1, [toWei('1'), toWei("2000"), toWei("1")])
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderDataArray.length).to.equal(0)
      }
      const result = await orderBook.getOrder(1)
      expect(result[1]).to.equal(false)

      expect(await ctk.balanceOf(user0.address)).to.equal(toWei("850"))
      expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("0"))
      expect(await ctk.balanceOf(pool.address)).to.equal(toWei("150"))
    }
  })

  it("placeLiquidityOrder - removeLiquidity", async () => {
    await ctk.approve(orderBook.address, toWei("1000000"))
    await ctk.mint(user0.address, toWei("1000"))
    // add liquidity
    {
      await orderBook.placeLiquidityOrder({ assetId: 0, rawAmount: toWei("150"), isAdding: true })
      await time.increaseTo(timestampOfTest + 86400 + 60 * 20)
      await orderBook.connect(broker).fillLiquidityOrder(0, [toWei('1'), toWei("2000"), toWei("1")])
    }
    expect(await mlp.balanceOf(user0.address)).to.equal(toWei("0")) // because this test uses a mocked liquidity pool
    await mlp.mint(user0.address, toWei("2"))
    // no1
    await mlp.approve(orderBook.address, toWei("2"))
    {
      await orderBook.placeLiquidityOrder({ assetId: 0, rawAmount: toWei("1"), isAdding: false })
      expect(await mlp.balanceOf(user0.address)).to.equal(toWei("1"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(1)
        expect(orders.orderDataArray.length).to.equal(1)
      }

      await expect(orderBook.cancelOrder(1)).to.revertedWith("CLD") // cool down
      await time.increaseTo(timestampOfTest + 86400 + 60 * 30)
      await orderBook.cancelOrder(1)
      expect(await mlp.balanceOf(user0.address)).to.equal(toWei("2"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderDataArray.length).to.equal(0)
      }

      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(false)
    }
    // no2
    {
      await orderBook.placeLiquidityOrder({ assetId: 0, rawAmount: toWei("1"), isAdding: false })
      expect(await mlp.balanceOf(user0.address)).to.equal(toWei("1"))
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("1"))
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("0"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(1)
        expect(orders.orderDataArray.length).to.equal(1)
      }

      await time.increaseTo(timestampOfTest + 86400 + 60 * 50)
      await orderBook.connect(broker).fillLiquidityOrder(2, [toWei('1'), toWei("2000"), toWei("1")])
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderDataArray.length).to.equal(0)
      }
      const result = await orderBook.getOrder(1)
      expect(result[1]).to.equal(false)

      expect(await mlp.balanceOf(user0.address)).to.equal(toWei("1"))
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("1")) // because this test uses a mocked liquidity pool
      expect(await mlp.balanceOf(pool.address)).to.equal(toWei("0"))
    }
  })

  it("broker can cancel orders", async () => {
    await ctk.approve(orderBook.address, toWei("1000000"))
    await ctk.mint(user0.address, toWei("1000"))
    // limit order
    await time.increaseTo(timestampOfTest + 86400 + 0)
    const subAccountId = assembleSubAccountId(user0.address, 0, 1, true)
    {
      await orderBook.placePositionOrder(
        {
          subAccountId,
          collateral: toWei("100"),
          size: toWei("0.1"),
          price: toWei("1000"),
          tpPrice: toWei("0"),
          slPrice: toWei("0"),
          expiration: timestampOfTest + 1000 + 86400,
          tpslExpiration: timestampOfTest + 1000 + 86400,
          profitTokenId: 0,
          tpslProfitTokenId: 0,
          flags: PositionOrderFlags.OpenPosition,
        },
        refCode
      )
      expect(await ctk.balanceOf(user0.address)).to.equal(toWei("900"))
      expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("100"))

      await time.increaseTo(timestampOfTest + 86400 + 86400 * 365 - 5)
      await expect(orderBook.connect(broker).cancelOrder(0)).revertedWith("EXP")
      await time.increaseTo(timestampOfTest + 86400 + 86400 * 365 + 5)
      await orderBook.connect(broker).cancelOrder(0)
      expect(await ctk.balanceOf(user0.address)).to.equal(toWei("1000"))
      expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("0"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderDataArray.length).to.equal(0)
      }
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(false)
    }
    // withdraw order
    {
      await orderBook.placeWithdrawalOrder({ subAccountId, rawAmount: toWei('500'), profitTokenId: 0, isProfit: true })
      await time.increaseTo(timestampOfTest + 86400 + 86400 * 365 + 5 + 120)
      await expect(orderBook.connect(broker).cancelOrder(1)).revertedWith("EXP")
      await time.increaseTo(timestampOfTest + 86400 + 86400 * 365 + 5 + 120 + 5)
      await orderBook.connect(broker).cancelOrder(1)
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderDataArray.length).to.equal(0)
      }
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(false)
    }
    // market order
    {
      await orderBook.placePositionOrder(
        {
          subAccountId,
          collateral: toWei("100"),
          size: toWei("0.1"),
          price: toWei("1000"),
          tpPrice: toWei("0"),
          slPrice: toWei("0"),
          expiration: timestampOfTest + 86400 + 86400 * 365 + 5 + 120 + 5 + 86400,
          tpslExpiration: timestampOfTest + 86400 + 86400 * 365 + 5 + 120 + 5 + 86400,
          profitTokenId: 0,
          tpslProfitTokenId: 0,
          flags: PositionOrderFlags.OpenPosition + PositionOrderFlags.MarketOrder,
        },
        refCode
      )
      expect(await ctk.balanceOf(user0.address)).to.equal(toWei("900"))
      expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("100"))

      await time.increaseTo(timestampOfTest + 86400 + 86400 * 365 + 5 + 120 + 5 + 110)
      await expect(orderBook.connect(broker).cancelOrder(2)).revertedWith("EXP")
      await time.increaseTo(timestampOfTest + 86400 + 86400 * 365 + 5 + 120 + 5 + 130)
      await orderBook.connect(broker).cancelOrder(2)
      expect(await ctk.balanceOf(user0.address)).to.equal(toWei("1000"))
      expect(await ctk.balanceOf(orderBook.address)).to.equal(toWei("0"))
      {
        const orders = await orderBook.getOrders(0, 100)
        expect(orders.totalCount).to.equal(0)
        expect(orders.orderDataArray.length).to.equal(0)
      }
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(false)
    }
  })
})
