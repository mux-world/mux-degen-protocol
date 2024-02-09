import { ethers } from "hardhat"
import "@nomiclabs/hardhat-ethers"
import { expect } from "chai"
import { time } from "@nomicfoundation/hardhat-network-helpers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import {
  createContract,
  toWei,
  rate,
  pad32l,
  toBytes32,
  toUnit,
  zeroAddress,
  assembleSubAccountId,
  PositionOrderFlags,
  BORROWING_RATE_APY_KEY,
  FUNDING_ALPHA_KEY,
  FUNDING_BETA_APY_KEY,
  toChainlink,
  ReferenceOracleType,
} from "../scripts/deployUtils"
import { UnitTestLibs, deployUnitTestLibraries, deployUnitTestPool, getPoolConfigs } from "../scripts/deployUtils"
import {
  BROKER_ROLE,

  // POOL
  MLP_TOKEN_KEY,
  ORDER_BOOK_KEY,
  FEE_DISTRIBUTOR_KEY,
  FUNDING_INTERVAL_KEY,
  LIQUIDITY_FEE_RATE_KEY,
  STRICT_STABLE_DEVIATION_KEY,
  BROKER_GAS_REBATE_USD_KEY,

  // POOL - ASSET
  SYMBOL_KEY,
  DECIMALS_KEY,
  TOKEN_ADDRESS_KEY,
  LOT_SIZE_KEY,
  INITIAL_MARGIN_RATE_KEY,
  MAINTENANCE_MARGIN_RATE_KEY,
  MIN_PROFIT_RATE_KEY,
  MIN_PROFIT_TIME_KEY,
  POSITION_FEE_RATE_KEY,
  LIQUIDATION_FEE_RATE_KEY,
  REFERENCE_ORACLE_KEY,
  REFERENCE_DEVIATION_KEY,
  REFERENCE_ORACLE_TYPE_KEY,
  MAX_LONG_POSITION_SIZE_KEY,
  MAX_SHORT_POSITION_SIZE_KEY,
  LIQUIDITY_CAP_USD_KEY,

  // ADL
  ADL_RESERVE_RATE_KEY,
  ADL_MAX_PNL_RATE_KEY,
  ADL_TRIGGER_RATE_KEY,

  // OB
  OB_LIQUIDITY_LOCK_PERIOD_KEY,
  OB_REFERRAL_MANAGER_KEY,
  OB_MARKET_ORDER_TIMEOUT_KEY,
  OB_LIMIT_ORDER_TIMEOUT_KEY,
  OB_CALLBACK_GAS_LIMIT_KEY,
  OB_CANCEL_COOL_DOWN_KEY,
} from "../scripts/deployUtils"
import { IDegenPool, OrderBook, MlpToken, DummyFeeDistributor, DummyReferralManager, MockERC20, MockChainlink } from "../typechain"
const U = ethers.utils

describe("Trade", () => {
  const refCode = toBytes32("")

  let admin1: SignerWithAddress
  let trader1: SignerWithAddress
  let lp1: SignerWithAddress
  let broker: SignerWithAddress
  let usdc: MockERC20
  let usdt: MockERC20
  let xxx: MockERC20

  let libs: UnitTestLibs
  let pool: IDegenPool
  let orderBook: OrderBook
  let mlp: MlpToken
  let feeDistributor: DummyFeeDistributor
  let referralManager: DummyReferralManager
  let timestampOfTest: number

  before(async () => {
    const accounts = await ethers.getSigners()
    admin1 = accounts[0]
    trader1 = accounts[1]
    lp1 = accounts[2]
    broker = accounts[3]

    libs = await deployUnitTestLibraries()
    feeDistributor = (await createContract("DummyFeeDistributor")) as DummyFeeDistributor
    referralManager = (await createContract("DummyReferralManager")) as DummyReferralManager
  })

  beforeEach(async () => {
    timestampOfTest = await time.latest()
    timestampOfTest = Math.ceil(timestampOfTest / 3600) * 3600 + 3600 // align to next hour

    pool = (await deployUnitTestPool(admin1, libs)) as IDegenPool
    orderBook = (await createContract("OrderBook", [], { "contracts/libraries/LibOrderBook.sol:LibOrderBook": libs.libOrderBook })) as OrderBook
    mlp = (await createContract("MlpToken")) as MlpToken

    // mlp
    await mlp.initialize("MLP", "MLP", pool.address)

    // pool
    {
      const { keys, values, currentValues } = getPoolConfigs([
        // POOL
        { k: MLP_TOKEN_KEY, v: mlp.address, old: "0" },
        { k: ORDER_BOOK_KEY, v: orderBook.address, old: "0" },
        { k: FEE_DISTRIBUTOR_KEY, v: feeDistributor.address, old: "0" },

        { k: FUNDING_INTERVAL_KEY, v: "3600", old: "0" },
        { k: BORROWING_RATE_APY_KEY, v: rate("0.01"), old: "0" },

        { k: LIQUIDITY_FEE_RATE_KEY, v: rate("0.0001"), old: rate("0") },

        { k: STRICT_STABLE_DEVIATION_KEY, v: rate("0.005"), old: rate("0") },
        { k: BROKER_GAS_REBATE_USD_KEY, v: toWei("0.5"), old: toWei("0") },

        { k: LIQUIDITY_CAP_USD_KEY, v: toWei("1000000"), old: toWei("0") },
      ])
      await pool.setPoolParameters(keys, values, currentValues)
    }

    // order book
    await orderBook.initialize(pool.address, mlp.address)
    await orderBook.setConfig(OB_LIQUIDITY_LOCK_PERIOD_KEY, pad32l(300))
    await orderBook.setConfig(OB_REFERRAL_MANAGER_KEY, pad32l(referralManager.address))
    await orderBook.setConfig(OB_MARKET_ORDER_TIMEOUT_KEY, pad32l(120))
    await orderBook.setConfig(OB_LIMIT_ORDER_TIMEOUT_KEY, pad32l(86400 * 30))
    await orderBook.setConfig(OB_CALLBACK_GAS_LIMIT_KEY, pad32l("2000000"))
    await orderBook.setConfig(OB_CANCEL_COOL_DOWN_KEY, pad32l(5))
    await orderBook.grantRole(BROKER_ROLE, broker.address)

    // dummy tokens
    usdc = (await createContract("MockERC20", ["USDC", "USDC", 6])) as MockERC20
    await usdc.mint(lp1.address, toUnit("1000000", 6))
    await usdc.mint(trader1.address, toUnit("100000", 6))
    usdt = (await createContract("MockERC20", ["USDT", "USDT", 6])) as MockERC20
    await usdt.mint(lp1.address, toUnit("1000000", 6))
    await usdt.mint(trader1.address, toUnit("100000", 6))
    xxx = (await createContract("MockERC20", ["XXX", "XXX", 18])) as MockERC20
    await xxx.mint(lp1.address, toUnit("1000000", 18))
    await xxx.mint(trader1.address, toUnit("100000", 18))

    // assets
    {
      const { keys, values } = getPoolConfigs([
        { k: SYMBOL_KEY, v: toBytes32("USDC") },
        { k: DECIMALS_KEY, v: "6" },
        { k: TOKEN_ADDRESS_KEY, v: usdc.address },
      ])
      await pool.addAsset(0, keys, values)
      // id, tradable, openable, shortable, enabled, stable, strict, liquidity
      await pool.setAssetFlags(0, false, false, false, true, true, true, true)
    }
    {
      const { keys, values } = getPoolConfigs([
        { k: SYMBOL_KEY, v: toBytes32("XXX") },
        { k: DECIMALS_KEY, v: "18" },
        { k: TOKEN_ADDRESS_KEY, v: xxx.address }, // test only! actual system does not allow to add unstable coins as collateral
        { k: LOT_SIZE_KEY, v: toWei("1.0") },

        { k: INITIAL_MARGIN_RATE_KEY, v: rate("0.10") },
        { k: MAINTENANCE_MARGIN_RATE_KEY, v: rate("0.05") },
        { k: MIN_PROFIT_RATE_KEY, v: rate("0.01") },
        { k: MIN_PROFIT_TIME_KEY, v: 10 },
        { k: POSITION_FEE_RATE_KEY, v: rate("0.001") },
        { k: LIQUIDATION_FEE_RATE_KEY, v: rate("0.002") },

        { k: REFERENCE_ORACLE_KEY, v: zeroAddress },
        { k: REFERENCE_DEVIATION_KEY, v: rate("0.05") },
        { k: REFERENCE_ORACLE_TYPE_KEY, v: 0 },

        { k: MAX_LONG_POSITION_SIZE_KEY, v: toWei("10000000") },
        { k: MAX_SHORT_POSITION_SIZE_KEY, v: toWei("10000000") },
        { k: FUNDING_ALPHA_KEY, v: toWei("20000") },
        { k: FUNDING_BETA_APY_KEY, v: rate("0.20") },

        { k: ADL_RESERVE_RATE_KEY, v: rate("0.80") },
        { k: ADL_MAX_PNL_RATE_KEY, v: rate("0.50") },
        { k: ADL_TRIGGER_RATE_KEY, v: rate("0.90") },
      ])
      await pool.addAsset(1, keys, values)
      // id, tradable, openable, shortable, enabled, stable, strict, liquidity
      await pool.setAssetFlags(1, true, true, true, true, false, false, false)
    }
    {
      const { keys, values } = getPoolConfigs([
        { k: SYMBOL_KEY, v: toBytes32("USDT") },
        { k: DECIMALS_KEY, v: "6" },
        { k: TOKEN_ADDRESS_KEY, v: usdt.address },
      ])
      await pool.addAsset(2, keys, values)
      // id, tradable, openable, shortable, enabled, stable, strict, liquidity
      await pool.setAssetFlags(2, false, false, false, true, true, true, true)
    }

    await time.increaseTo(timestampOfTest + 86400 * 1)
    await orderBook.connect(broker).updateFundingState()
    await time.increaseTo(timestampOfTest + 86400 * 2)
    await orderBook.connect(broker).updateFundingState()
    {
      const assetInfo = await pool.getAssetStorageV2(1)
      expect(assetInfo.longCumulativeFunding).to.equal(toWei("0.000027397260273972")) // funding = 0 (no skew), borrowing = 0.01 / 365
      expect(assetInfo.shortCumulativeFunding).to.equal(toWei("0.000027397260273972")) // funding = 0 (no skew), borrowing = 0.01 / 365
    }
  })

  it("mini test: +liq, +trade", async () => {
    // +liq usdc
    await usdc.connect(lp1).approve(orderBook.address, toUnit("1000000", 6))
    {
      const args = { assetId: 0, rawAmount: toUnit("1000000", 6), isAdding: true }
      const tx1 = await orderBook.connect(lp1).placeLiquidityOrder(args)
      await expect(tx1).to.emit(orderBook, "NewLiquidityOrder").withArgs(lp1.address, 0, [args.rawAmount, args.assetId, args.isAdding])
      expect(await usdc.balanceOf(lp1.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("1000000", 6))
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(true)
    }
    {
      await time.increaseTo(timestampOfTest + 86400 * 2 + 330)
      const tx1 = orderBook.connect(broker).fillLiquidityOrder(0, [toWei("1"), toWei("1000"), toWei("1")])
      await expect(tx1)
        .to.emit(pool, "AddLiquidity")
        .withArgs(lp1.address, 0, toWei("1") /* tokenPrice */, toWei("1") /* mlpPrice */, toWei("999900") /* mlpAmount */, toWei("100") /* feeCollateral */)
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(false)
      expect(await usdc.balanceOf(lp1.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("100", 6)) // fee = 100
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("999900", 6))
      expect(await mlp.balanceOf(lp1.address)).to.equal(toWei("999900")) // (1000000 - fee) / 1
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("0"))
      const collateralInfo = await pool.getAssetStorageV2(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("999900"))
    }
    // open short, using usdc
    const shortAccountId = assembleSubAccountId(trader1.address, 0, 1, false)
    await usdc.connect(trader1).approve(orderBook.address, toUnit("1000", 6))
    {
      const args = {
        subAccountId: shortAccountId,
        collateral: toUnit("1000", 6),
        size: toWei("1"),
        price: toWei("1000"),
        tpPrice: "0",
        slPrice: "0",
        expiration: timestampOfTest + 86400 * 2 + 340,
        tpslExpiration: timestampOfTest + 86400 * 2 + 340,
        profitTokenId: 0,
        tpslProfitTokenId: 0,
        flags: PositionOrderFlags.OpenPosition,
      }
      const tx1 = await orderBook.connect(trader1).placePositionOrder(args, refCode)
      await expect(tx1)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(trader1.address, 1, [
          args.subAccountId,
          args.collateral,
          args.size,
          args.price,
          args.tpPrice,
          args.slPrice,
          args.expiration,
          args.tpslExpiration,
          args.profitTokenId,
          args.tpslProfitTokenId,
          args.flags,
        ])
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("1000", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("999900", 6))
      const collateralInfo = await pool.getAssetStorageV2(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("999900"))
      // fill
      const tx2 = orderBook.connect(broker).fillPositionOrder(1, toWei("1"), toWei("2000"), [toWei("1"), toWei("2001"), toWei("1")])
      await expect(tx2)
        .to.emit(pool, "OpenPosition")
        .withArgs(
          trader1.address,
          1, // asset id
          [
            args.subAccountId,
            0, // collateral id
            false, // isLong
            args.size,
            toWei("2000"), // trading price
            toWei("2001"), // asset price
            toWei("1"), // collateral price
            toWei("2000"), // entry
            toWei("2"), // feeUsd
            args.size, // remainPosition
            toWei("998"), // remainCollateral
          ]
        )
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("102", 6)) // fee = 2000 * 1 * 0.1% = 2
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1000898", 6)) // 999900 + collateral - fee
      const subAccount = await pool.getSubAccount(shortAccountId)
      expect(subAccount.collateral).to.equal(toWei("998")) // fee = 2
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("2000"))
      expect(subAccount.entryFunding).to.equal(toWei("0.000027397260273972"))
      const collateralInfo2 = await pool.getAssetStorageV2(0)
      expect(collateralInfo2.spotLiquidity).to.equal(toWei("999900")) // unchanged
      const assetInfo2 = await pool.getAssetStorageV2(1)
      expect(assetInfo2.totalShortPosition).to.equal(toWei("1"))
      expect(assetInfo2.averageShortPrice).to.equal(toWei("2000"))
      expect(assetInfo2.totalLongPosition).to.equal(toWei("0"))
      expect(assetInfo2.averageLongPrice).to.equal(toWei("0"))
    }
  })

  it("deposit, withdraw collateral when position = 0", async () => {
    const shortAccountId = assembleSubAccountId(trader1.address, 0, 1, false)
    await usdc.connect(trader1).approve(orderBook.address, toUnit("1000", 6))
    {
      await expect(pool.depositCollateral(shortAccountId, toUnit("1000", 6))).to.revertedWith("BOK")
      await expect(orderBook.connect(lp1).depositCollateral(shortAccountId, toUnit("1000", 6))).to.revertedWith("SND")
      await expect(orderBook.connect(trader1).depositCollateral(shortAccountId, toUnit("0", 6))).to.revertedWith("C=0")
      const tx1 = await orderBook.connect(trader1).depositCollateral(shortAccountId, toUnit("1000", 6))
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1000", 6))
      const subAccount = await pool.getSubAccount(shortAccountId)
      expect(subAccount.collateral).to.equal(toWei("1000"))
      expect(subAccount.size).to.equal(toWei("0"))
      expect(subAccount.entryPrice).to.equal(toWei("0"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
    }
    {
      await expect(pool.connect(trader1).withdrawAllCollateral(shortAccountId)).to.revertedWith("BOK")
      await expect(orderBook.connect(lp1).withdrawAllCollateral(shortAccountId)).to.revertedWith("SND")
      await orderBook.connect(trader1).withdrawAllCollateral(shortAccountId)
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("100000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("0", 6))
      const subAccount = await pool.getSubAccount(shortAccountId)
      expect(subAccount.collateral).to.equal(toWei("0"))
      expect(subAccount.size).to.equal(toWei("0"))
      expect(subAccount.entryPrice).to.equal(toWei("0"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
    }
  })

  it("+/-liquidity, +/-trade", async () => {
    // +liq usdc
    expect(await mlp.totalSupply()).to.equal(toWei("0"))
    expect(await pool.callStatic.getMlpPrice([toWei("1"), toWei("1000"), toWei("1")])).to.equal(toWei("1")) // init mlp price = 1
    await usdc.connect(lp1).approve(orderBook.address, toUnit("1000000", 6))
    {
      const args = { assetId: 0, rawAmount: toUnit("1000000", 6), isAdding: true }
      await expect(pool.connect(lp1).addLiquidity(lp1.address, 0, toUnit("1000000", 6), [toWei("1"), toWei("1000"), toWei("1")])).to.revertedWith("BOK")
      await expect(orderBook.connect(lp1).placeLiquidityOrder({ ...args, rawAmount: toUnit("0", 6) })).to.revertedWith("A=0")
      const tx1 = await orderBook.connect(lp1).placeLiquidityOrder(args)
      await expect(tx1).to.emit(orderBook, "NewLiquidityOrder").withArgs(lp1.address, 0, [args.rawAmount, args.assetId, args.isAdding])
      expect(await usdc.balanceOf(lp1.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("1000000", 6))
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(true)
    }
    expect(await mlp.totalSupply()).to.equal(toWei("0"))
    expect(await pool.callStatic.getMlpPrice([toWei("1"), toWei("1000"), toWei("1")])).to.equal(toWei("1")) // init mlp price = 1
    {
      await expect(orderBook.connect(broker).fillLiquidityOrder(0, [toWei("1"), toWei("1000"), toWei("1")])).to.revertedWith("LCK")
      await expect(orderBook.connect(lp1).fillLiquidityOrder(0, [toWei("1"), toWei("1000"), toWei("1")])).to.revertedWith("AccessControl")
      await time.increaseTo(timestampOfTest + 86400 * 2 + 330)
      const tx1 = orderBook.connect(broker).fillLiquidityOrder(0, [toWei("1"), toWei("1000"), toWei("1")])
      await expect(tx1)
        .to.emit(pool, "AddLiquidity")
        .withArgs(lp1.address, 0, toWei("1") /* tokenPrice */, toWei("1") /* mlpPrice */, toWei("999900") /* mlpAmount */, toWei("100") /* feeCollateral */)
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(false)
      expect(await usdc.balanceOf(lp1.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("100", 6)) // fee = 1000000 * 0.01% = 100
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("999900", 6))
      expect(await mlp.balanceOf(lp1.address)).to.equal(toWei("999900")) // (1000000 - fee) / 1
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("0"))
      const collateralInfo = await pool.getAssetStorageV2(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("999900")) // 1000000 - fee
    }
    expect(await mlp.totalSupply()).to.equal(toWei("999900"))
    expect(await pool.callStatic.getMlpPrice([toWei("1"), toWei("1000"), toWei("1")])).to.equal(toWei("1")) // aum = 999900 (fee was 100)
    // -liq usdc
    {
      const args = { assetId: 0, rawAmount: toWei("1"), isAdding: false }
      await expect(pool.connect(lp1).removeLiquidity(lp1.address, toWei("1"), 0, [toWei("1"), toWei("1000"), toWei("1")])).to.revertedWith("BOK")
      await expect(orderBook.connect(lp1).placeLiquidityOrder({ ...args, rawAmount: toUnit("0", 6) })).to.revertedWith("A=0")
      await mlp.connect(lp1).approve(orderBook.address, toWei("1"))
      const tx1 = await orderBook.connect(lp1).placeLiquidityOrder(args)
      await expect(tx1).to.emit(orderBook, "NewLiquidityOrder").withArgs(lp1.address, 1, [args.rawAmount, args.assetId, args.isAdding])
      expect(await mlp.balanceOf(lp1.address)).to.equal(toWei("999899"))
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("1"))
    }
    expect(await mlp.totalSupply()).to.equal(toWei("999900"))
    expect(await pool.callStatic.getMlpPrice([toWei("1"), toWei("1000"), toWei("1")])).to.equal(toWei("1")) // aum = 999900 (unchanged)
    {
      await expect(orderBook.connect(broker).fillLiquidityOrder(1, [toWei("1"), toWei("2000"), toWei("1")])).to.revertedWith("LCK")
      await time.increaseTo(timestampOfTest + 86400 * 2 + 660)
      const tx1 = await orderBook.connect(broker).fillLiquidityOrder(1, [toWei("1"), toWei("2000"), toWei("1")])
      expect(await usdc.balanceOf(lp1.address)).to.equal(toUnit("0.9999", 6)) // fee = 1 * 0.01% = 0.0001, 1 - fee
      expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("100.0001", 6)) // +fee
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("999899", 6)) // -1
      expect(await mlp.balanceOf(lp1.address)).to.equal(toWei("999899"))
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("0"))
      const collateralInfo = await pool.getAssetStorageV2(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("999899")) // - 1
    }
    expect(await mlp.totalSupply()).to.equal(toWei("999899"))
    expect(await pool.callStatic.getMlpPrice([toWei("1"), toWei("1000"), toWei("1")])).to.equal(toWei("1")) // aum = 999899
    // update funding, 1 day later
    await time.increaseTo(timestampOfTest + 86400 * 3 + 700)
    await orderBook.connect(broker).updateFundingState()
    {
      const assetInfo = await pool.getAssetStorageV2(1)
      expect(assetInfo.longCumulativeFunding).to.equal(toWei("0.000054794520547944")) // funding = 0 (no skew), borrowing += 0.01 / 365 * 1
      expect(assetInfo.shortCumulativeFunding).to.equal(toWei("0.000054794520547944")) // funding = 0 (no skew), borrowing += 0.01 / 365 * 1
    }
    // open short xxx, using usdc
    const shortAccountId = assembleSubAccountId(trader1.address, 0, 1, false)
    await usdc.connect(trader1).approve(orderBook.address, toUnit("1000", 6))
    const args1 = {
      subAccountId: shortAccountId,
      collateral: toUnit("1000", 6),
      size: toWei("1"),
      price: toWei("2000"),
      tpPrice: "0",
      slPrice: "0",
      expiration: timestampOfTest + 86400 * 3 + 800,
      tpslExpiration: timestampOfTest + 86400 * 3 + 800,
      profitTokenId: 0,
      tpslProfitTokenId: 0,
      flags: PositionOrderFlags.OpenPosition,
    }
    {
      await expect(pool.connect(trader1).openPosition(shortAccountId, toWei("1"), toWei("1000"), [toWei("1"), toWei("1000"), toWei("1")])).to.revertedWith("BOK")
      await expect(orderBook.connect(lp1).placePositionOrder(args1, refCode)).to.revertedWith("SND")
      await expect(orderBook.connect(trader1).placePositionOrder({ ...args1, size: 0 }, refCode)).to.revertedWith("S=0")
      const tx1 = await orderBook.connect(trader1).placePositionOrder(args1, refCode)
      await expect(tx1)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(trader1.address, 2, [
          args1.subAccountId,
          args1.collateral,
          args1.size,
          args1.price,
          args1.tpPrice,
          args1.slPrice,
          args1.expiration,
          args1.tpslExpiration,
          args1.profitTokenId,
          args1.tpslProfitTokenId,
          args1.flags,
        ])
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("1000", 6))
      expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("100.0001", 6)) // unchanged
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("999899", 6)) // unchanged
      const collateralInfo = await pool.getAssetStorageV2(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("999899")) // unchanged
    }
    {
      await expect(orderBook.connect(trader1).fillPositionOrder(2, toWei("1"), toWei("2000"), [toWei("1"), toWei("2001"), toWei("1")])).to.revertedWith("AccessControl")
      await expect(orderBook.connect(broker).fillPositionOrder(2, toWei("1"), toWei("1999"), [toWei("1"), toWei("2001"), toWei("1")])).to.revertedWith("LMT")
      await expect(orderBook.connect(broker).fillPositionOrder(2, toWei("2"), toWei("2000"), [toWei("1"), toWei("2001"), toWei("1")])).to.revertedWith("FAM")
      const tx1 = await orderBook.connect(broker).fillPositionOrder(2, toWei("1"), toWei("2000"), [toWei("1"), toWei("2001"), toWei("1")])
      await expect(tx1)
        .to.emit(pool, "OpenPosition")
        .withArgs(
          trader1.address,
          1, // asset id
          [
            args1.subAccountId,
            0, // collateral id
            false, // isLong
            args1.size,
            toWei("2000"), // trading price
            toWei("2001"), // asset price
            toWei("1"), // collateral price
            toWei("2000"), // entry
            toWei("2"), // feeUsd, 2000 * 1 * 0.1% = 2
            args1.size, // remainPosition
            toWei("998"), // remainCollateral, collateral - fee
          ]
        )
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("102.0001", 6)) // + fee
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1000897", 6)) // + collateral - fee = 999899 + 1000 - 2
      const subAccount = await pool.getSubAccount(shortAccountId)
      expect(subAccount.collateral).to.equal(toWei("998")) // fee = 2
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("2000"))
      expect(subAccount.entryFunding).to.equal(toWei("0.000054794520547944"))
      const collateralInfo = await pool.getAssetStorageV2(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("999899")) // unchanged
      const assetInfo = await pool.getAssetStorageV2(1)
      expect(assetInfo.totalShortPosition).to.equal(toWei("1"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("2000"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
    }
    expect(await mlp.totalSupply()).to.equal(toWei("999899"))
    expect(await pool.callStatic.getMlpPrice([toWei("1"), toWei("2000"), toWei("1")])).to.equal(toWei("1")) // aum = 999899 - upnl(0)
    await expect(orderBook.connect(lp1).withdrawAllCollateral(shortAccountId)).to.revertedWith("SND")
    await expect(orderBook.connect(trader1).withdrawAllCollateral(shortAccountId)).to.revertedWith("S>0")
    // open long xxx, using usdc
    const longAccountId = assembleSubAccountId(trader1.address, 0, 1, true)
    await usdc.connect(trader1).approve(orderBook.address, toUnit("10000", 6))
    const args2 = {
      subAccountId: longAccountId,
      collateral: toUnit("10000", 6),
      size: toWei("10"),
      price: toWei("3000"),
      tpPrice: "0",
      slPrice: "0",
      expiration: timestampOfTest + 86400 * 3 + 800,
      tpslExpiration: timestampOfTest + 86400 * 3 + 800,
      profitTokenId: 0,
      tpslProfitTokenId: 0,
      flags: PositionOrderFlags.OpenPosition,
    }
    {
      const tx1 = await orderBook.connect(trader1).placePositionOrder(args2, refCode)
      await expect(tx1)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(trader1.address, 3, [
          args2.subAccountId,
          args2.collateral,
          args2.size,
          args2.price,
          args2.tpPrice,
          args2.slPrice,
          args2.expiration,
          args2.tpslExpiration,
          args2.profitTokenId,
          args2.tpslProfitTokenId,
          args2.flags,
        ])
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("89000", 6)) // - 10000
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("10000", 6))
      expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("102.0001", 6)) // unchanged
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1000897", 6)) // unchanged
      const collateralInfo = await pool.getAssetStorageV2(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("999899")) // unchanged
    }
    {
      await expect(orderBook.connect(broker).fillPositionOrder(3, toWei("10"), toWei("3001"), [toWei("1"), toWei("3001"), toWei("1")])).to.revertedWith("LMT")
      await expect(orderBook.connect(broker).fillPositionOrder(3, toWei("11"), toWei("2000"), [toWei("1"), toWei("2001"), toWei("1")])).to.revertedWith("FAM")
      const tx1 = await orderBook.connect(broker).fillPositionOrder(3, toWei("10"), toWei("2000"), [toWei("1"), toWei("2001"), toWei("1")])
      await expect(tx1)
        .to.emit(pool, "OpenPosition")
        .withArgs(
          trader1.address,
          1, // asset id
          [
            args2.subAccountId,
            0, // collateral id
            true, // isLong
            args2.size,
            toWei("2000"), // trading price
            toWei("2001"), // asset price
            toWei("1"), // collateral price
            toWei("2000"), // entry
            toWei("20"), // feeUsd, 2000 * 10 * 0.1% = 20
            args2.size, // remainPosition
            toWei("9980"), // remainCollateral, collateral - fee
          ]
        )
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("89000", 6)) // unchanged
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("122.0001", 6)) // + 20
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1010877", 6)) // + collateral - fee = 1000897 + 10000 - 20
      const subAccount = await pool.getSubAccount(longAccountId)
      expect(subAccount.collateral).to.equal(toWei("9980")) // fee = 20
      expect(subAccount.size).to.equal(toWei("10"))
      expect(subAccount.entryPrice).to.equal(toWei("2000"))
      expect(subAccount.entryFunding).to.equal(toWei("0.000054794520547944"))
      const collateralInfo = await pool.getAssetStorageV2(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("999899")) // unchanged
      const assetInfo = await pool.getAssetStorageV2(1)
      expect(assetInfo.totalShortPosition).to.equal(toWei("1"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("2000"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("10"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("2000"))
    }
    expect(await mlp.totalSupply()).to.equal(toWei("999899"))
    expect(await pool.callStatic.getMlpPrice([toWei("1"), toWei("2000"), toWei("1")])).to.equal(toWei("1")) // aum = 999899 - upnl(0)
    // update funding, 1 day later
    {
      // skew = (10 - 1) * 2000 = $18000
      // funding = skew / alpha * beta = $18000 / 20000 * apy 20% = apy 18%
      await time.increaseTo(timestampOfTest + 86400 * 4 + 0)
      const tx1 = await orderBook.connect(broker).updateFundingState()
      await expect(tx1).to.emit(pool, "UpdateFundingRate").withArgs(
        1, // tokenId
        true, // isPositiveFundingRate
        rate("0.18"), // newFundingRateApy
        rate("0.01"), // newBorrowingRateApy
        toWei("0.000575342465753422"), // longCumulativeFunding, += 0.18 / 365 + 0.01 / 365
        toWei("0.000082191780821916") // shortCumulativeFunding, += 0 + 0.01 / 365
      )
      const assetInfo = await pool.getAssetStorageV2(1)
      expect(assetInfo.longCumulativeFunding).to.equal(toWei("0.000575342465753422"))
      expect(assetInfo.shortCumulativeFunding).to.equal(toWei("0.000082191780821916"))
      expect(assetInfo.totalShortPosition).to.equal(toWei("1"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("2000"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("10"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("2000"))
    }
    expect(await mlp.totalSupply()).to.equal(toWei("999899"))
    expect(await pool.callStatic.getMlpPrice([toWei("1"), toWei("1960"), toWei("1")])).to.equal(toWei("1.000360036363672730")) // aum = 999899 - (1960 - 2000) * 9 = 1000259
    // close short, profit in usdc, auto withdraw all
    const args3 = {
      subAccountId: shortAccountId,
      collateral: toUnit("0", 6),
      size: toWei("1"),
      price: toWei("1950"),
      tpPrice: "0",
      slPrice: "0",
      expiration: timestampOfTest + 86400 * 4 + 800,
      tpslExpiration: timestampOfTest + 86400 * 4 + 800,
      profitTokenId: 0,
      tpslProfitTokenId: 0,
      flags: PositionOrderFlags.WithdrawAllIfEmpty,
    }
    {
      const tx1 = await orderBook.connect(trader1).placePositionOrder(args3, refCode)
      await expect(tx1)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(trader1.address, 4, [
          args3.subAccountId,
          args3.collateral,
          args3.size,
          args3.price,
          args3.tpPrice,
          args3.slPrice,
          args3.expiration,
          args3.tpslExpiration,
          args3.profitTokenId,
          args3.tpslProfitTokenId,
          args3.flags,
        ])
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("89000", 6)) // unchanged
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("122.0001", 6)) // unchanged
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1010877", 6)) // unchanged
    }
    {
      await expect(orderBook.connect(broker).fillPositionOrder(4, toWei("1"), toWei("1960"), [toWei("1"), toWei("1960"), toWei("1")])).to.revertedWith("LMT")
      const tx1 = await orderBook.connect(broker).fillPositionOrder(4, toWei("1"), toWei("1900"), [toWei("1"), toWei("1910"), toWei("1")]) // pnl = 100
      await expect(tx1)
        .to.emit(pool, "ClosePosition")
        .withArgs(
          trader1.address,
          1, // asset id
          [
            args3.subAccountId,
            0, // collateral id
            0, // profit asset id
            false, // isLong
            args3.size,
            toWei("1900"), // trading price
            toWei("1910"), // asset price
            toWei("1"), // collateral price
            toWei("1"), // profit asset price
            toWei("1.954794520547944000"), // pos fee + funding(using entry) + borrowing(using entry) = 1900 * 1 * 0.1% + 0 + 2000 * 1 * 1% / 365
            true, // hasProfit
            toWei("100"), // pnlUsd
            toWei("0"), // remainPosition
            toWei("998"), // remainCollateral = unchanged, because pnl was sent
          ]
        )
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90096.045205", 6)) // + 998 + pnl - fee = 89000 + 998 + 100 - 1.954794520547944000
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("123.954894", 6)) // + fee = 122.0001 + 1.954794520547944000
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1009779.000001", 6)) // - pnl - remainCollateral = 1010877 - 100 - 998
      const subAccount = await pool.getSubAccount(shortAccountId)
      expect(subAccount.collateral).to.equal(toWei("0"))
      expect(subAccount.size).to.equal(toWei("0"))
      expect(subAccount.entryPrice).to.equal(toWei("0"))
      expect(subAccount.entryFunding).to.equal(toWei("0"))
      const collateralInfo = await pool.getAssetStorageV2(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("999799")) // 999899 - pnl
      const assetInfo = await pool.getAssetStorageV2(1)
      expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("10"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("2000"))
    }
    expect(await mlp.totalSupply()).to.equal(toWei("999899"))
    expect(await pool.callStatic.getMlpPrice([toWei("1"), toWei("2110"), toWei("1")])).to.equal(toWei("0.998799878787757563")) // aum = 999799 - (2110 - 2000) * 10 = 998699
    // close long, profit in usdc, partial withdraw
    const args4 = {
      subAccountId: longAccountId,
      collateral: toUnit("1", 6),
      size: toWei("1"),
      price: toWei("2000"),
      tpPrice: "0",
      slPrice: "0",
      expiration: timestampOfTest + 86400 * 4 + 800,
      tpslExpiration: timestampOfTest + 86400 * 4 + 800,
      profitTokenId: 0,
      tpslProfitTokenId: 0,
      flags: 0,
    }
    {
      const tx1 = await orderBook.connect(trader1).placePositionOrder(args4, refCode)
      await expect(tx1)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(trader1.address, 5, [
          args4.subAccountId,
          args4.collateral,
          args4.size,
          args4.price,
          args4.tpPrice,
          args4.slPrice,
          args4.expiration,
          args4.tpslExpiration,
          args4.profitTokenId,
          args4.tpslProfitTokenId,
          args4.flags,
        ])
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90096.045205", 6)) // unchanged
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("123.954894", 6)) // unchanged
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1009779.000001", 6)) // unchanged
    }
    {
      await expect(orderBook.connect(broker).fillPositionOrder(5, toWei("1"), toWei("1999"), [toWei("1"), toWei("1999"), toWei("1")])).to.revertedWith("LMT")
      const tx1 = await orderBook.connect(broker).fillPositionOrder(5, toWei("1"), toWei("2100"), [toWei("1"), toWei("2110"), toWei("1")]) // pnl = 100
      await expect(tx1)
        .to.emit(pool, "ClosePosition")
        .withArgs(
          trader1.address,
          1, // asset id
          [
            args4.subAccountId,
            0, // collateral id
            0, // profit asset id
            true, // isLong
            args4.size,
            toWei("2100"), // trading price
            toWei("2110"), // asset price
            toWei("1"), // collateral price
            toWei("1"), // profit asset price
            toWei("12.510958904109560000"), // pos fee + funding(using entry) + borrowing(using entry) = 1900 * 1 * 0.1% + 0 + 2000 * 10 * 1% / 365
            true, // hasProfit
            toWei("100"), // pnlUsd
            toWei("9"), // remainPosition
            toWei("9980"), // remainCollateral = unchanged, because pnl was sent
          ]
        )
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90184.534246", 6)) // + withdraw + pnl - fee = 90096.045205 + 1 + 100 - 12.510958904109560000
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("136.465852", 6)) // + fee = 123.954894 + 12.510958904109560000
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1009678.000002", 6)) // - pnl - withdraw = 1009779.000001 - 100 - 1
      const subAccount = await pool.getSubAccount(longAccountId)
      expect(subAccount.collateral).to.equal(toWei("9979")) // 9980 - withdraw
      expect(subAccount.size).to.equal(toWei("9"))
      expect(subAccount.entryPrice).to.equal(toWei("2000")) // unchanged
      expect(subAccount.entryFunding).to.equal(toWei("0.000575342465753422")) // updated!
      const collateralInfo = await pool.getAssetStorageV2(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("999699")) // 999799 - pnl
      const assetInfo = await pool.getAssetStorageV2(1)
      expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("9"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("2000"))
    }
    // claim broker gas rebate. 2 liquidity orders, 2 open position orders, 2 close position orders
    {
      expect(await usdc.balanceOf(broker.address)).to.equal(toUnit("0", 6))
      await expect(pool.claimBrokerGasRebate(broker.address, 0)).to.revertedWith("BOK")
      await expect(orderBook.claimBrokerGasRebate(0)).to.revertedWith("AccessControl")
      await expect(orderBook.connect(broker).claimBrokerGasRebate(1)).to.revertedWith("STB")
      await expect(orderBook.connect(broker).claimBrokerGasRebate(0)).to.emit(pool, "ClaimBrokerGasRebate").withArgs(broker.address, 6, 0, toUnit("3.0", 6))
      expect(await usdc.balanceOf(broker.address)).to.equal(toUnit("3.0", 6))
      await expect(orderBook.connect(broker).claimBrokerGasRebate(0)).to.emit(pool, "ClaimBrokerGasRebate").withArgs(broker.address, 0, 0, toUnit("0.0", 6))
      expect(await usdc.balanceOf(broker.address)).to.equal(toUnit("3.0", 6))
    }
  })

  it("trade collateral must be stable", async () => {
    // open short xxx, using xxx
    const shortAccountId = assembleSubAccountId(trader1.address, 1, 1, false)
    const args = {
      subAccountId: shortAccountId,
      collateral: toUnit("1", 18),
      size: toWei("1"),
      price: toWei("1000"),
      tpPrice: "0",
      slPrice: "0",
      expiration: timestampOfTest + 86400 * 2 + 800,
      tpslExpiration: timestampOfTest + 86400 * 2 + 800,
      profitTokenId: 0,
      tpslProfitTokenId: 0,
      flags: PositionOrderFlags.OpenPosition,
    }
    await xxx.connect(trader1).approve(orderBook.address, toUnit("1", 18))
    await expect(orderBook.connect(trader1).placePositionOrder(args, refCode)).to.revertedWith("FLG")
  })

  it("liquidity collateral must be stable", async () => {
    const args = { assetId: 1, rawAmount: toUnit("1", 18), isAdding: true }
    await xxx.connect(lp1).approve(orderBook.address, toUnit("1", 18))
    await expect(orderBook.connect(lp1).placeLiquidityOrder(args)).to.revertedWith("FLG")
  })

  it("open position cause reserved > spotLiquidity", async () => {
    // open long xxx, using usdc
    const longAccountId = assembleSubAccountId(trader1.address, 0, 1, true)
    await usdc.connect(trader1).approve(orderBook.address, toUnit("10000", 6))
    const args2 = {
      subAccountId: longAccountId,
      collateral: toUnit("10000", 6),
      size: toWei("1"),
      price: toWei("1"),
      tpPrice: "0",
      slPrice: "0",
      expiration: timestampOfTest + 86400 * 2 + 800,
      tpslExpiration: timestampOfTest + 86400 * 2 + 800,
      profitTokenId: 0,
      tpslProfitTokenId: 0,
      flags: PositionOrderFlags.OpenPosition,
    }
    await orderBook.connect(trader1).placePositionOrder(args2, refCode)
    await expect(orderBook.connect(broker).fillPositionOrder(0, toWei("1"), toWei("1"), [toWei("1"), toWei("1"), toWei("1")])).to.revertedWith("RSV")
  })

  describe("add some liquidity and test more", () => {
    beforeEach(async () => {
      // +liq usdc
      await usdc.connect(lp1).approve(orderBook.address, toUnit("1000000", 6))
      {
        const args = { assetId: 0, rawAmount: toUnit("1000000", 6), isAdding: true }
        await orderBook.connect(lp1).placeLiquidityOrder(args)
      }
      {
        await time.increaseTo(timestampOfTest + 86400 * 2 + 330)
        await orderBook.connect(broker).fillLiquidityOrder(0, [toWei("1"), toWei("1000"), toWei("1")])
        expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("100", 6)) // fee = 1000000 * 0.01% = 100
        expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("999900", 6))
        const collateralInfo = await pool.getAssetStorageV2(0)
        expect(collateralInfo.spotLiquidity).to.equal(toWei("999900")) // 1000000 - fee
        const assetInfo = await pool.getAssetStorageV2(1)
        expect(assetInfo.longCumulativeFunding).to.equal(toWei("0.000027397260273972"))
        expect(assetInfo.shortCumulativeFunding).to.equal(toWei("0.000027397260273972"))
      }
      expect(await mlp.totalSupply()).to.equal(toWei("999900"))
      expect(await pool.callStatic.getMlpPrice([toWei("1"), toWei("1000"), toWei("1")])).to.equal(toWei("1")) // aum = 999900 (fee was 100)
    })

    describe("open long and test more", () => {
      let longAccountId = ""

      beforeEach(async () => {
        longAccountId = assembleSubAccountId(trader1.address, 0, 1, true)
        // open long xxx, using usdc
        await usdc.connect(trader1).approve(orderBook.address, toUnit("10000", 6))
        const args2 = {
          subAccountId: longAccountId,
          collateral: toUnit("10000", 6),
          size: toWei("2"),
          price: toWei("2000"),
          tpPrice: "0",
          slPrice: "0",
          expiration: timestampOfTest + 86400 * 2 + 800,
          tpslExpiration: timestampOfTest + 86400 * 2 + 800,
          profitTokenId: 0,
          tpslProfitTokenId: 0,
          flags: PositionOrderFlags.OpenPosition,
        }
        {
          await orderBook.connect(trader1).placePositionOrder(args2, refCode)
          expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // - 10000
          expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("100", 6)) // unchanged
          expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("999900", 6)) // unchanged
          const collateralInfo = await pool.getAssetStorageV2(0)
          expect(collateralInfo.spotLiquidity).to.equal(toWei("999900")) // unchanged
        }
        {
          await orderBook.connect(broker).fillPositionOrder(1, toWei("2"), toWei("2000"), [toWei("1"), toWei("2000"), toWei("1")])
          expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
          expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("104", 6)) // + 4
          expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1009896", 6)) // + collateral - fee = 999900 + 10000 - 4
          const subAccount = await pool.getSubAccount(longAccountId)
          expect(subAccount.collateral).to.equal(toWei("9996")) // fee = 4
          expect(subAccount.size).to.equal(toWei("2"))
          expect(subAccount.entryPrice).to.equal(toWei("2000"))
          expect(subAccount.entryFunding).to.equal(toWei("0.000027397260273972"))
          const collateralInfo = await pool.getAssetStorageV2(0)
          expect(collateralInfo.spotLiquidity).to.equal(toWei("999900")) // unchanged
          const assetInfo = await pool.getAssetStorageV2(1)
          expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
          expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
          expect(assetInfo.totalLongPosition).to.equal(toWei("2"))
          expect(assetInfo.averageLongPrice).to.equal(toWei("2000"))
          expect(assetInfo.longCumulativeFunding).to.equal(toWei("0.000027397260273972"))
          expect(assetInfo.shortCumulativeFunding).to.equal(toWei("0.000027397260273972"))
        }
      })

      it("long capped pnl", async () => {
        // mlp price should handle capped pnl
        // entry value = 2000 * 2 = 4000, maxProfit = 50% = 2000
        // assume mark price = 2001
        expect(await mlp.totalSupply()).to.equal(toWei("999900"))
        expect(await pool.callStatic.getMlpPrice([toWei("1"), toWei("3501"), toWei("1")])).to.equal(toWei("0.997999799979997999")) // aum = 999900 - upnl(2000)
        // close long, profit in usdc, partial withdraw
        const args4 = {
          subAccountId: longAccountId,
          collateral: toUnit("0", 6),
          size: toWei("1"),
          price: toWei("3501"),
          tpPrice: "0",
          slPrice: "0",
          expiration: timestampOfTest + 86400 * 4 + 800,
          tpslExpiration: timestampOfTest + 86400 * 4 + 800,
          profitTokenId: 0,
          tpslProfitTokenId: 0,
          flags: 0,
        }
        {
          await orderBook.connect(trader1).placePositionOrder(args4, refCode)
          expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
          expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("104", 6)) // unchanged
          expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1009896", 6)) // unchanged
        }
        {
          // closing entry value = 2000 * 1 = 2000, maxProfit = 50% = 1000
          const tx1 = await orderBook.connect(broker).fillPositionOrder(2, toWei("1"), toWei("3501"), [toWei("1"), toWei("3502"), toWei("1")])
          await expect(tx1)
            .to.emit(pool, "ClosePosition")
            .withArgs(
              trader1.address,
              1, // asset id
              [
                args4.subAccountId,
                0, // collateral id
                0, // profit asset id
                true, // isLong
                args4.size,
                toWei("3501"), // trading price
                toWei("3502"), // asset price
                toWei("1"), // collateral price
                toWei("1"), // profit asset price
                toWei("3.501"), // pos fee = 3501 * 1 * 0.1%
                true, // hasProfit
                toWei("1000"), // pnlUsd
                toWei("1.0"), // remainPosition
                toWei("9996"), // remainCollateral = unchanged, because pnl was sent
              ]
            )
          expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90996.499", 6)) // + withdraw + pnl - fee = 90000 + 0 + 1000 - 3.501
          expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("107.501", 6)) // + fee
          expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1008896", 6)) // - pnl - withdraw = 1009896 - 1000 - 0
          const subAccount = await pool.getSubAccount(longAccountId)
          expect(subAccount.collateral).to.equal(toWei("9996")) // 9996 - withdraw
          expect(subAccount.size).to.equal(toWei("1"))
          expect(subAccount.entryPrice).to.equal(toWei("2000")) // unchanged
          expect(subAccount.entryFunding).to.equal(toWei("0.000027397260273972")) // unchanged
          const collateralInfo = await pool.getAssetStorageV2(0)
          expect(collateralInfo.spotLiquidity).to.equal(toWei("998900")) // 999900 - pnl
          const assetInfo = await pool.getAssetStorageV2(1)
          expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
          expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
          expect(assetInfo.totalLongPosition).to.equal(toWei("1"))
          expect(assetInfo.averageLongPrice).to.equal(toWei("2000"))
        }
      })

      it("ADL a long position", async () => {
        // trigger exit = 3800, trigger roe = (3800 - 2000) / 2000 = 90%
        // closing entry value = 2000 * 2 = 4000, maxProfit = 50% = 2000
        // pnl = (3501 - 2000) * 2 = 3002 > maxProfit
        const args4 = {
          subAccountId: longAccountId,
          size: toWei("2"),
          price: toWei("3500"),
          profitTokenId: 0,
        }
        {
          await expect(orderBook.connect(trader1).fillAdlOrder(args4, toWei("3501"), [toWei("1"), toWei("3799"), toWei("1")])).to.revertedWith("AccessControl")
          await expect(orderBook.connect(broker).fillAdlOrder(args4, toWei("3501"), [toWei("1"), toWei("3799"), toWei("1")])).to.revertedWith("DLA")
          const tx1 = orderBook.connect(broker).fillAdlOrder(args4, toWei("3501"), [toWei("1"), toWei("3800"), toWei("1")])
          await expect(tx1)
            .to.emit(pool, "ClosePosition")
            .withArgs(
              trader1.address,
              1, // asset id
              [
                args4.subAccountId,
                0, // collateral id
                0, // profit asset id
                true, // isLong
                toWei("2"), // amount
                toWei("3501"), // trading price
                toWei("3800"), // asset price
                toWei("1"), // collateral price
                toWei("1"), // profit asset price
                toWei("7.002"), // pos fee = 3501 * 2 * 0.1%
                true, // hasProfit
                toWei("2000"), // pnlUsd
                toWei("0"), // remainPosition
                toWei("9996"), // remainCollateral = unchanged, because pnl was sent
              ]
            )
          expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("101988.998", 6)) // + withdraw + pnl - fee = 90000 + 9996 + 2000 - 7.002
          expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("111.002", 6)) // + fee
          expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("997900", 6)) // - pnl - withdraw = 1009896 - 2000 - 9996
          const subAccount = await pool.getSubAccount(longAccountId)
          expect(subAccount.collateral).to.equal(toWei("0"))
          expect(subAccount.size).to.equal(toWei("0"))
          expect(subAccount.entryPrice).to.equal(toWei("0"))
          expect(subAccount.entryFunding).to.equal(toWei("0"))
          const collateralInfo = await pool.getAssetStorageV2(0)
          expect(collateralInfo.spotLiquidity).to.equal(toWei("997900")) // = pool balance
          const assetInfo = await pool.getAssetStorageV2(1)
          expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
          expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
          expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
          expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
        }
      })

      it("withdraw collateral", async () => {
        // update funding
        // funding = skew / alpha * beta = $4000 / 20000 * apy 20% = apy 4%, borrowing = apy 1%
        await time.increaseTo(timestampOfTest + 86400 * 2 + 86400)
        // withdraw
        {
          await expect(orderBook.connect(trader1).placeWithdrawalOrder({ subAccountId: longAccountId, rawAmount: toUnit("0", 6), profitTokenId: 0, isProfit: false })).to.revertedWith("A=0")
          await expect(orderBook.connect(trader1).placeWithdrawalOrder({ subAccountId: longAccountId, rawAmount: toUnit("1", 6), profitTokenId: 0, isProfit: false }))
            .to.emit(orderBook, "NewWithdrawalOrder")
            .withArgs(trader1.address, 2, [longAccountId, toUnit("1", 6), 0, false])
          expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
          expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6)) // unchanged
          expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1009896", 6)) // unchanged
        }
        {
          // longCumulativeFunding, 0.000027397260273972 + 0.05 * 1 / 365 = 0.000164383561643835013698630136986
          // fundingFee = 2000 * 2 * 0.05 * 1 / 365 = 0.547945205479452054794520547945
          // pnl = (2100 - 2000) * 2 = 200
          await expect(orderBook.connect(trader1).fillWithdrawalOrder(2, [toWei("1"), toWei("2100"), toWei("1")])).to.revertedWith("AccessControl")
          await orderBook.connect(broker).fillWithdrawalOrder(2, [toWei("1"), toWei("2100"), toWei("1")])
          const assetInfo = await pool.getAssetStorageV2(1)
          expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
          expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
          expect(assetInfo.totalLongPosition).to.equal(toWei("2"))
          expect(assetInfo.averageLongPrice).to.equal(toWei("2000"))
          expect(assetInfo.longCumulativeFunding).to.equal(toWei("0.000164383561643834"))
          expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90001", 6)) // +withdraw = +1
          expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
          expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1009894.452055", 6)) // -withdraw - fee = 1009896 - 1 - 0.547945205479452054794520547945
          const subAccount = await pool.getSubAccount(longAccountId)
          expect(subAccount.collateral).to.equal(toWei("9994.452054794520552000")) // 9996 - fundingFee - withdraw
          expect(subAccount.size).to.equal(toWei("2"))
          expect(subAccount.entryPrice).to.equal(toWei("2000")) // unchanged
          expect(subAccount.entryFunding).to.equal(toWei("0.000164383561643834")) // update to new
          const collateralInfo = await pool.getAssetStorageV2(0)
          expect(collateralInfo.spotLiquidity).to.equal(toWei("999900")) // unchanged
        }
      })
    })

    describe("open short and test more", () => {
      let shortAccountId = ""

      beforeEach(async () => {
        shortAccountId = assembleSubAccountId(trader1.address, 0, 1, false)
        // open short xxx, using usdc
        await usdc.connect(trader1).approve(orderBook.address, toUnit("10000", 6))
        const args2 = {
          subAccountId: shortAccountId,
          collateral: toUnit("10000", 6),
          size: toWei("2"),
          price: toWei("2000"),
          tpPrice: "0",
          slPrice: "0",
          expiration: timestampOfTest + 86400 * 2 + 800,
          tpslExpiration: timestampOfTest + 86400 * 2 + 800,
          profitTokenId: 0,
          tpslProfitTokenId: 0,
          flags: PositionOrderFlags.OpenPosition,
        }
        {
          await orderBook.connect(trader1).placePositionOrder(args2, refCode)
          expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // - 10000
          expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("100", 6)) // unchanged
          expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("999900", 6)) // unchanged
          const collateralInfo = await pool.getAssetStorageV2(0)
          expect(collateralInfo.spotLiquidity).to.equal(toWei("999900")) // unchanged
        }
        {
          await orderBook.connect(broker).fillPositionOrder(1, toWei("2"), toWei("2000"), [toWei("1"), toWei("2000"), toWei("1")])
          expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
          expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("104", 6)) // + 4
          expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1009896", 6)) // + collateral - fee = 999900 + 10000 - 4
          const subAccount = await pool.getSubAccount(shortAccountId)
          expect(subAccount.collateral).to.equal(toWei("9996")) // fee = 4
          expect(subAccount.size).to.equal(toWei("2"))
          expect(subAccount.entryPrice).to.equal(toWei("2000"))
          expect(subAccount.entryFunding).to.equal(toWei("0.000027397260273972"))
          const collateralInfo = await pool.getAssetStorageV2(0)
          expect(collateralInfo.spotLiquidity).to.equal(toWei("999900")) // unchanged
          const assetInfo = await pool.getAssetStorageV2(1)
          expect(assetInfo.totalShortPosition).to.equal(toWei("2"))
          expect(assetInfo.averageShortPrice).to.equal(toWei("2000"))
          expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
          expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
        }
      })

      it("short capped pnl", async () => {
        // mlp price should handle capped pnl
        // entry value = 2000 * 2 = 4000, maxProfit = 50% = 2000
        // assume mark price = 999
        expect(await mlp.totalSupply()).to.equal(toWei("999900"))
        expect(await pool.callStatic.getMlpPrice([toWei("1"), toWei("999"), toWei("1")])).to.equal(toWei("0.997999799979997999")) // aum = 999900 - upnl(2000)
        // close long, profit in usdc, partial withdraw
        const args4 = {
          subAccountId: shortAccountId,
          collateral: toUnit("0", 6),
          size: toWei("1"),
          price: toWei("999"),
          tpPrice: "0",
          slPrice: "0",
          expiration: timestampOfTest + 86400 * 4 + 800,
          tpslExpiration: timestampOfTest + 86400 * 4 + 800,
          profitTokenId: 0,
          tpslProfitTokenId: 0,
          flags: 0,
        }
        {
          await orderBook.connect(trader1).placePositionOrder(args4, refCode)
          expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
          expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("104", 6)) // unchanged
          expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1009896", 6)) // unchanged
        }
        {
          // closing entry value = 2000 * 1 = 2000, maxProfit = 50% = 1000
          const tx1 = await orderBook.connect(broker).fillPositionOrder(2, toWei("1"), toWei("999"), [toWei("1"), toWei("998"), toWei("1")])
          await expect(tx1)
            .to.emit(pool, "ClosePosition")
            .withArgs(
              trader1.address,
              1, // asset id
              [
                args4.subAccountId,
                0, // collateral id
                0, // profit asset id
                false, // isLong
                args4.size,
                toWei("999"), // trading price
                toWei("998"), // asset price
                toWei("1"), // collateral price
                toWei("1"), // profit asset price
                toWei("0.999"), // pos fee = 999 * 1 * 0.1%
                true, // hasProfit
                toWei("1000"), // pnlUsd
                toWei("1.0"), // remainPosition
                toWei("9996"), // remainCollateral = unchanged, because pnl was sent
              ]
            )
          expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90999.001", 6)) // + withdraw + pnl - fee = 90000 + 0 + 1000 - 0.999
          expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("104.999", 6)) // + fee
          expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1008896", 6)) // - pnl - withdraw = 1009896 - 1000 - 0
          const subAccount = await pool.getSubAccount(shortAccountId)
          expect(subAccount.collateral).to.equal(toWei("9996")) // 9996 - withdraw
          expect(subAccount.size).to.equal(toWei("1"))
          expect(subAccount.entryPrice).to.equal(toWei("2000")) // unchanged
          expect(subAccount.entryFunding).to.equal(toWei("0.000027397260273972")) // unchanged
          const collateralInfo = await pool.getAssetStorageV2(0)
          expect(collateralInfo.spotLiquidity).to.equal(toWei("998900")) // 999900 - pnl
          const assetInfo = await pool.getAssetStorageV2(1)
          expect(assetInfo.totalShortPosition).to.equal(toWei("1"))
          expect(assetInfo.averageShortPrice).to.equal(toWei("2000"))
          expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
          expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
        }
      })

      it("liquidate because of funding", async () => {
        // skew = (2 - 0) * 2000 = $4000, pnl = 0
        // funding = skew / alpha * beta = $4000 / 20000 * apy 20% = apy 4%, borrowing = apy 1%
        // mm = 2000 * 2 * 0.05 = 200 (MM unsafe)
        // liquidate time = 48 years + 357 days + 17 hours
        // funding/borrowing = 2000 * 2 * 0.05 * (48 + 357/365 + 17/24/365) = 9796.00
        // collateral = 9996 - 0 - 9796.00 = 199.99 < 200
        //
        // update funding to 1 hour before liquidate
        {
          await time.increaseTo(timestampOfTest + 86400 * 2 + 48 * 365 * 86400 + 357 * 86400 + 16 * 3600)
          const tx1 = await orderBook.connect(broker).updateFundingState()
          await expect(tx1).to.emit(pool, "UpdateFundingRate").withArgs(
            1, // tokenId
            false, // isPositiveFundingRate
            rate("0.04"), // newFundingRateApy
            rate("0.01"), // newBorrowingRateApy
            toWei("0.489826484018264839"), // longCumulativeFunding, 0.000027397260273972 + 0.01 * (48 + 357/365 + 16/24/365)
            toWei("2.449022831050228309") // shortCumulativeFunding, 0.000027397260273972 + 0.05 * (48 + 357/365 + 16/24/365)
          )
          const assetInfo = await pool.getAssetStorageV2(1)
          expect(assetInfo.longCumulativeFunding).to.equal(toWei("0.489826484018264839"))
          expect(assetInfo.shortCumulativeFunding).to.equal(toWei("2.449022831050228309"))
          expect(assetInfo.totalShortPosition).to.equal(toWei("2"))
          expect(assetInfo.averageShortPrice).to.equal(toWei("2000"))
          expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
          expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
        }
        await expect(orderBook.connect(broker).liquidate(shortAccountId, 0, toWei("2000"), [toWei("1"), toWei("2000"), toWei("1")])).to.revertedWith("MMS")
        // update funding
        {
          await time.increaseTo(timestampOfTest + 86400 * 2 + 48 * 365 * 86400 + 357 * 86400 + 17 * 3600)
          const tx1 = await orderBook.connect(broker).updateFundingState()
          await expect(tx1).to.emit(pool, "UpdateFundingRate").withArgs(
            1, // tokenId
            false, // isPositiveFundingRate
            rate("0.04"), // newFundingRateApy
            rate("0.01"), // newBorrowingRateApy
            toWei("0.489827625570776254"), // longCumulativeFunding, 0.000027397260273972 + 0.01 * (48 + 357/365 + 17/24/365)
            toWei("2.449028538812785386") // shortCumulativeFunding, 0.000027397260273972 + 0.05 * (48 + 357/365 + 17/24/365)
          )
          const assetInfo = await pool.getAssetStorageV2(1)
          expect(assetInfo.longCumulativeFunding).to.equal(toWei("0.489827625570776254"))
          expect(assetInfo.shortCumulativeFunding).to.equal(toWei("2.449028538812785386"))
          expect(assetInfo.totalShortPosition).to.equal(toWei("2"))
          expect(assetInfo.averageShortPrice).to.equal(toWei("2000"))
          expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
          expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
        }
        {
          await expect(orderBook.connect(broker).liquidate(shortAccountId, 0, toWei("2000"), [toWei("1"), toWei("2000"), toWei("1")]))
            .to.emit(pool, "Liquidate")
            .withArgs(trader1.address, 1, [
              shortAccountId,
              0, // collateralId
              0, // profitAssetId
              false, // isLong
              toWei("2"), // amount
              toWei("2000"), // tradingPrice
              toWei("2000"), // assetPrice
              toWei("1"), // collateralPrice
              toWei("1"), // profitAssetPrice
              toWei("9804.004566210045656000"), // feeUsd = 2000 * 2 * (0.002 + 0.05 * (48 + 357/365 + 17/24/365))
              false, // hasProfit
              toWei("0"), // pnlUsd. (2000 - 2000) * 2
              toWei("191.995433789954344000"), // remainCollateral. 9996 + pnl - fee
            ])
          expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90191.995433", 6)) // 90000 + remainCollateral
          expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
          expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("999900.000001", 6)) // 1009896 - fee - remainCollateral = original liquidity (because collateral can afford)
          const subAccount = await pool.getSubAccount(shortAccountId)
          expect(subAccount.collateral).to.equal(toWei("0"))
          expect(subAccount.size).to.equal(toWei("0"))
          expect(subAccount.entryPrice).to.equal(toWei("0"))
          expect(subAccount.entryFunding).to.equal(toWei("0"))
          const collateralInfo = await pool.getAssetStorageV2(0)
          expect(collateralInfo.spotLiquidity).to.equal(toWei("999900")) // = pool balance
          const assetInfo = await pool.getAssetStorageV2(1)
          expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
          expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
          expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
          expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
        }
      })

      it("0 < fee < margin < MM. liquidate short", async () => {
        // liquidate time = 48 years + 357 days + 17 hours
        // funding/borrowing = 0
        // collateral = 9996 + (2000 - 6664.8) * 2 - 0 = 666.40
        // mm = 6664.8 * 2 * 0.05 = 666.48
        await expect(orderBook.connect(broker).liquidate(shortAccountId, 0, toWei("6665"), [toWei("1"), toWei("6664.7"), toWei("1")])).to.revertedWith("MMS")
        await expect(orderBook.connect(broker).liquidate(shortAccountId, 0, toWei("6665"), [toWei("1"), toWei("6664.8"), toWei("1")]))
          .to.emit(pool, "Liquidate")
          .withArgs(trader1.address, 1, [
            shortAccountId,
            0, // collateralId
            0, // profitAssetId
            false, // isLong
            toWei("2"), // amount
            toWei("6665"), // tradingPrice
            toWei("6664.8"), // assetPrice
            toWei("1"), // collateralPrice
            toWei("1"), // profitAssetPrice
            toWei("26.66"), // feeUsd = 6665 * 2 * 0.002 = 26.66
            false, // hasProfit
            toWei("9330"), // pnlUsd. (2000 - 6665) * 2
            toWei("639.34"), // remainCollateral. 9996 + pnl - fee
          ])
        expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90639.34", 6)) // 90000 + remainCollateral
        expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
        expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1009230", 6)) // 1009896 - fee - remainCollateral
        const subAccount = await pool.getSubAccount(shortAccountId)
        expect(subAccount.collateral).to.equal(toWei("0"))
        expect(subAccount.size).to.equal(toWei("0"))
        expect(subAccount.entryPrice).to.equal(toWei("0"))
        expect(subAccount.entryFunding).to.equal(toWei("0"))
        const collateralInfo = await pool.getAssetStorageV2(0)
        expect(collateralInfo.spotLiquidity).to.equal(toWei("1009230")) // = pool balance
        const assetInfo = await pool.getAssetStorageV2(1)
        expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
        expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
        expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
        expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
      })

      it("0 < margin < fee < MM. liquidate short", async () => {
        // collateral + pnl = 9996 + (2000 - 6993) * 2 = 10 < fee
        await expect(orderBook.connect(broker).liquidate(shortAccountId, 0, toWei("6993"), [toWei("1"), toWei("6664.8"), toWei("1")]))
          .to.emit(pool, "Liquidate")
          .withArgs(trader1.address, 1, [
            shortAccountId,
            0, // collateralId
            0, // profitAssetId
            false, // isLong
            toWei("2"), // amount
            toWei("6993"), // tradingPrice
            toWei("6664.8"), // assetPrice
            toWei("1"), // collateralPrice
            toWei("1"), // profitAssetPrice
            toWei("10"), // feeUsd = 6993 * 2 * 0.002 = 27.972, but capped by remain collateral
            false, // hasProfit
            toWei("9986"), // pnlUsd. (2000 - 6665) * 2
            toWei("0"), // remainCollateral
          ])
        expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
        expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
        expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1009886", 6)) // 1009896 - fee - remainCollateral
        const subAccount = await pool.getSubAccount(shortAccountId)
        expect(subAccount.collateral).to.equal(toWei("0"))
        expect(subAccount.size).to.equal(toWei("0"))
        expect(subAccount.entryPrice).to.equal(toWei("0"))
        expect(subAccount.entryFunding).to.equal(toWei("0"))
        const collateralInfo = await pool.getAssetStorageV2(0)
        expect(collateralInfo.spotLiquidity).to.equal(toWei("1009886")) // = pool balance
        const assetInfo = await pool.getAssetStorageV2(1)
        expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
        expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
        expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
        expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
      })

      it("margin < 0. liquidate short", async () => {
        // collateral + pnl = 9996 + (2000 - 7000) * 2 = -4 < 0
        await expect(orderBook.connect(broker).liquidate(shortAccountId, 0, toWei("7000"), [toWei("1"), toWei("6664.8"), toWei("1")]))
          .to.emit(pool, "Liquidate")
          .withArgs(trader1.address, 1, [
            shortAccountId,
            0, // collateralId
            0, // profitAssetId
            false, // isLong
            toWei("2"), // amount
            toWei("7000"), // tradingPrice
            toWei("6664.8"), // assetPrice
            toWei("1"), // collateralPrice
            toWei("1"), // profitAssetPrice
            toWei("0"), // feeUsd
            false, // hasProfit
            toWei("9996"), // pnlUsd. all of collateral
            toWei("0"), // remainCollateral
          ])
        expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
        expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
        expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1009896", 6)) // unchanged
        const subAccount = await pool.getSubAccount(shortAccountId)
        expect(subAccount.collateral).to.equal(toWei("0"))
        expect(subAccount.size).to.equal(toWei("0"))
        expect(subAccount.entryPrice).to.equal(toWei("0"))
        expect(subAccount.entryFunding).to.equal(toWei("0"))
        const collateralInfo = await pool.getAssetStorageV2(0)
        expect(collateralInfo.spotLiquidity).to.equal(toWei("1009896")) // = pool balance
        const assetInfo = await pool.getAssetStorageV2(1)
        expect(assetInfo.totalShortPosition).to.equal(toWei("0"))
        expect(assetInfo.averageShortPrice).to.equal(toWei("0"))
        expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
        expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
      })

      describe("add chainlink", () => {
        let mockChainlink: MockChainlink

        beforeEach(async () => {
          mockChainlink = (await createContract("MockChainlink")) as MockChainlink
          await mockChainlink.setAnswer(toChainlink("1.0"))
          {
            const { keys, values, currentValues } = getPoolConfigs([
              { k: REFERENCE_ORACLE_KEY, v: mockChainlink.address, old: "0" },
              { k: REFERENCE_DEVIATION_KEY, v: rate("0"), old: "0" },
              { k: REFERENCE_ORACLE_TYPE_KEY, v: ReferenceOracleType.Chainlink, old: "0" },
            ])
            await pool.setAssetParameters(0, keys, values, currentValues)
          }
        })

        it("strict stable price dampener. ignore broker price", async () => {
          await mockChainlink.setAnswer(toChainlink("0.999"))

          // mlp price should handle capped pnl
          // entry value = 2000 * 2 = 4000, maxProfit = 50% = 2000
          // assume mark price = 999
          expect(await mlp.totalSupply()).to.equal(toWei("999900"))
          expect(await pool.callStatic.getMlpPrice([toWei("0.99"), toWei("999"), toWei("0.99")])).to.equal(toWei("0.997999799979997999")) // aum = 999900 - upnl(2000)
          // close long, profit in usdc, partial withdraw
          const args4 = {
            subAccountId: shortAccountId,
            collateral: toUnit("0", 6),
            size: toWei("1"),
            price: toWei("999"),
            tpPrice: "0",
            slPrice: "0",
            expiration: timestampOfTest + 86400 * 4 + 800,
            tpslExpiration: timestampOfTest + 86400 * 4 + 800,
            profitTokenId: 0,
            tpslProfitTokenId: 0,
            flags: 0,
          }
          {
            await orderBook.connect(trader1).placePositionOrder(args4, refCode)
            expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
            expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("104", 6)) // unchanged
            expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1009896", 6)) // unchanged
          }
          {
            // closing entry value = 2000 * 1 = 2000, maxProfit = 50% = 1000
            const tx1 = await orderBook.connect(broker).fillPositionOrder(2, toWei("1"), toWei("999"), [toWei("0.99"), toWei("998"), toWei("0.99")])
            await expect(tx1)
              .to.emit(pool, "ClosePosition")
              .withArgs(
                trader1.address,
                1, // asset id
                [
                  args4.subAccountId,
                  0, // collateral id
                  0, // profit asset id
                  false, // isLong
                  args4.size,
                  toWei("999"), // trading price
                  toWei("998"), // asset price
                  toWei("1"), // collateral price. important!
                  toWei("1"), // profit asset price
                  toWei("0.999"), // pos fee = 999 * 1 * 0.1%
                  true, // hasProfit
                  toWei("1000"), // pnlUsd
                  toWei("1.0"), // remainPosition
                  toWei("9996"), // remainCollateral = unchanged, because pnl was sent
                ]
              )
            expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90999.001", 6)) // + withdraw + pnl - fee = 90000 + 0 + 1000 - 0.999
            expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("104.999", 6)) // + fee
            expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1008896", 6)) // - pnl - withdraw = 1009896 - 1000 - 0
            const subAccount = await pool.getSubAccount(shortAccountId)
            expect(subAccount.collateral).to.equal(toWei("9996")) // 9996 - withdraw
            expect(subAccount.size).to.equal(toWei("1"))
            expect(subAccount.entryPrice).to.equal(toWei("2000")) // unchanged
            expect(subAccount.entryFunding).to.equal(toWei("0.000027397260273972")) // unchanged
            const collateralInfo = await pool.getAssetStorageV2(0)
            expect(collateralInfo.spotLiquidity).to.equal(toWei("998900")) // 999900 - pnl
            const assetInfo = await pool.getAssetStorageV2(1)
            expect(assetInfo.totalShortPosition).to.equal(toWei("1"))
            expect(assetInfo.averageShortPrice).to.equal(toWei("2000"))
            expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
            expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
          }
        })

        it("strict stable price dampener. use broker price", async () => {
          await mockChainlink.setAnswer(toChainlink("0.99"))

          // mlp price should handle capped pnl
          // entry value = 2000 * 2 = 4000, maxProfit = 50% = 2000
          // assume mark price = 999
          expect(await mlp.totalSupply()).to.equal(toWei("999900"))
          expect(await pool.callStatic.getMlpPrice([toWei("0.99"), toWei("999"), toWei("0.99")])).to.equal(toWei("0.987999799979997999")) // aum = 999900 * 0.99 - upnl(2000)
          // close long, profit in usdc, partial withdraw
          const args4 = {
            subAccountId: shortAccountId,
            collateral: toUnit("0", 6),
            size: toWei("1"),
            price: toWei("999"),
            tpPrice: "0",
            slPrice: "0",
            expiration: timestampOfTest + 86400 * 4 + 800,
            tpslExpiration: timestampOfTest + 86400 * 4 + 800,
            profitTokenId: 0,
            tpslProfitTokenId: 0,
            flags: 0,
          }
          {
            await orderBook.connect(trader1).placePositionOrder(args4, refCode)
            expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("90000", 6)) // unchanged
            expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("104", 6)) // unchanged
            expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1009896", 6)) // unchanged
          }
          {
            // closing entry value = 2000 * 1 = 2000, maxProfit = 50% = 1000
            const tx1 = await orderBook.connect(broker).fillPositionOrder(2, toWei("1"), toWei("999"), [toWei("0.999"), toWei("998"), toWei("0.999")])
            await expect(tx1)
              .to.emit(pool, "ClosePosition")
              .withArgs(
                trader1.address,
                1, // asset id
                [
                  args4.subAccountId,
                  0, // collateral id
                  0, // profit asset id
                  false, // isLong
                  args4.size,
                  toWei("999"), // trading price
                  toWei("998"), // asset price
                  toWei("0.99"), // collateral price. important!
                  toWei("0.99"), // profit asset price
                  toWei("0.999"), // pos fee = 999 * 1 * 0.1%
                  true, // hasProfit
                  toWei("1000"), // pnlUsd
                  toWei("1.0"), // remainPosition
                  toWei("9996"), // remainCollateral = unchanged, because pnl was sent
                ]
              )
            expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("91009.091919", 6)) // + withdraw + pnl/collateralPrice - fee/collateralPrice = 90000 + 0 + 1000/0.99 - 0.999/0.99
            expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("105.009090", 6)) // + fee/collateralPrice = 0.999 / 0.99
            expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1008885.898991", 6)) // - pnl - withdraw = 1009896 - 1000/0.99 - 0
            const subAccount = await pool.getSubAccount(shortAccountId)
            expect(subAccount.collateral).to.equal(toWei("9996")) // 9996 - withdraw
            expect(subAccount.size).to.equal(toWei("1"))
            expect(subAccount.entryPrice).to.equal(toWei("2000")) // unchanged
            expect(subAccount.entryFunding).to.equal(toWei("0.000027397260273972")) // unchanged
            const collateralInfo = await pool.getAssetStorageV2(0)
            expect(collateralInfo.spotLiquidity).to.equal(toWei("998889.898989898989898990")) // 999900 - pnl = 999900 - 1000/0.99
            const assetInfo = await pool.getAssetStorageV2(1)
            expect(assetInfo.totalShortPosition).to.equal(toWei("1"))
            expect(assetInfo.averageShortPrice).to.equal(toWei("2000"))
            expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
            expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
          }
        })
      })
    })

    it("remove liquidity cause reserved > spotLiquidity", async () => {
      {
        const collateralInfo = await pool.getAssetStorageV2(0)
        expect(collateralInfo.spotLiquidity).to.equal(toWei("999900")) // 1000000 - fee
      }
      // open long xxx, using usdc
      const longAccountId = assembleSubAccountId(trader1.address, 0, 1, true)
      await usdc.connect(trader1).approve(orderBook.address, toUnit("100000", 6))
      const args2 = {
        subAccountId: longAccountId,
        collateral: toUnit("100000", 6),
        size: toWei("900000"),
        price: toWei("1"),
        tpPrice: "0",
        slPrice: "0",
        expiration: timestampOfTest + 86400 * 2 + 800,
        tpslExpiration: timestampOfTest + 86400 * 2 + 800,
        profitTokenId: 0,
        tpslProfitTokenId: 0,
        flags: PositionOrderFlags.OpenPosition,
      }
      await orderBook.connect(trader1).placePositionOrder(args2, refCode)
      await orderBook.connect(broker).fillPositionOrder(1, toWei("900000"), toWei("1"), [toWei("1"), toWei("1"), toWei("1")])
      expect(await pool.callStatic.getMlpPrice([toWei("1"), toWei("1"), toWei("1")])).to.equal(toWei("1"))
      // reserve 900,000 * 80%, liquidity 999,900, can remove 279,900
      {
        await mlp.connect(lp1).approve(orderBook.address, toWei("279901"))
        const args = { assetId: 0, rawAmount: toWei("279901"), isAdding: false }
        await time.increaseTo(timestampOfTest + 86400 * 2 + 500)
        await orderBook.connect(lp1).placeLiquidityOrder(args)
        await time.increaseTo(timestampOfTest + 86400 * 2 + 500 + 1800)
        await expect(orderBook.connect(broker).fillLiquidityOrder(2, [toWei("1"), toWei("1"), toWei("1")])).to.revertedWith("RSV")
        await orderBook.connect(lp1).cancelOrder(2)
      }
      {
        await mlp.connect(lp1).approve(orderBook.address, toWei("279900"))
        const args = { assetId: 0, rawAmount: toWei("279900"), isAdding: false }
        await orderBook.connect(lp1).placeLiquidityOrder(args)
        await time.increaseTo(timestampOfTest + 86400 * 2 + 500 + 1800 + 1800)
        await orderBook.connect(broker).fillLiquidityOrder(3, [toWei("1"), toWei("1"), toWei("1")])
      }
    })

    it("tp/sl strategy", async () => {
      // open long, tp/sl strategy takes effect when fill
      const longAccountId = assembleSubAccountId(trader1.address, 0, 1, true)
      await usdc.connect(trader1).approve(orderBook.address, toUnit("10000", 6))
      const args2 = {
        subAccountId: longAccountId,
        collateral: toUnit("10000", 6),
        size: toWei("2"),
        price: toWei("2000"),
        tpPrice: toWei("2200"),
        slPrice: toWei("1800"),
        expiration: timestampOfTest + 86400 * 2 + 800,
        tpslExpiration: timestampOfTest + 86400 * 2 + 1000,
        profitTokenId: 0,
        tpslProfitTokenId: 2,
        flags: PositionOrderFlags.OpenPosition + PositionOrderFlags.MarketOrder + PositionOrderFlags.TpSlStrategy,
      }
      await orderBook.connect(trader1).placePositionOrder(args2, refCode)
      const tx2 = await orderBook.connect(broker).fillPositionOrder(1, toWei("2"), toWei("2000"), [toWei("1"), toWei("2000"), toWei("1")])
      await expect(tx2)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(trader1.address, 2, [
          args2.subAccountId,
          toWei("0"), // collateral
          args2.size,
          toWei("2200"), // price
          toWei("0"), // tpPrice
          toWei("0"), // slPrice
          timestampOfTest + 86400 * 2 + 1000, // expiration
          0, // tpslExpiration
          2, // profitTokenId
          0, // tpslProfitTokenId
          PositionOrderFlags.WithdrawAllIfEmpty + PositionOrderFlags.ShouldReachMinProfit,
        ])
      await expect(tx2)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(trader1.address, 3, [
          args2.subAccountId,
          toWei("0"), // collateral
          args2.size,
          toWei("1800"), // price
          toWei("0"), // tpPrice
          toWei("0"), // slPrice
          timestampOfTest + 86400 * 2 + 1000, // expiration
          0, // tpslExpiration
          2, // profitTokenId
          0, // tpslProfitTokenId
          PositionOrderFlags.WithdrawAllIfEmpty + PositionOrderFlags.TriggerOrder,
        ])
      // close tp+sl
      const args3 = {
        subAccountId: longAccountId,
        collateral: toUnit("12345", 6),
        size: toWei("2"),
        price: toWei("2000"),
        tpPrice: toWei("2200"),
        slPrice: toWei("1800"),
        expiration: timestampOfTest + 86400 * 2 + 800,
        tpslExpiration: timestampOfTest + 86400 * 2 + 1000,
        profitTokenId: 0,
        tpslProfitTokenId: 2,
        flags: PositionOrderFlags.TpSlStrategy,
      }
      await expect(orderBook.connect(trader1).placePositionOrder(args3, refCode)).to.revertedWith("C!0")
      args3.collateral = toUnit("0", 6)
      const tx3 = await orderBook.connect(trader1).placePositionOrder(args3, refCode)
      await expect(tx3)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(trader1.address, 4, [
          args2.subAccountId,
          toWei("0"), // collateral
          args2.size,
          toWei("2200"), // price
          toWei("0"), // tpPrice
          toWei("0"), // slPrice
          timestampOfTest + 86400 * 2 + 1000, // expiration
          0, // tpslExpiration
          2, // profitTokenId
          0, // tpslProfitTokenId
          PositionOrderFlags.WithdrawAllIfEmpty + PositionOrderFlags.ShouldReachMinProfit,
        ])
      await expect(tx3)
        .to.emit(orderBook, "NewPositionOrder")
        .withArgs(trader1.address, 5, [
          args2.subAccountId,
          toWei("0"), // collateral
          args2.size,
          toWei("1800"), // price
          toWei("0"), // tpPrice
          toWei("0"), // slPrice
          timestampOfTest + 86400 * 2 + 1000, // expiration
          0, // tpslExpiration
          2, // profitTokenId
          0, // tpslProfitTokenId
          PositionOrderFlags.WithdrawAllIfEmpty + PositionOrderFlags.TriggerOrder,
        ])
    })
  })
})
