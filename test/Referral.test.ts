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
  MAINTAINER_ROLE,
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
import { IDegenPool, OrderBook, MlpToken, DegenFeeDistributor, ReferralTiers, DummyReferralManager, MockERC20 } from "../typechain"

describe("Integrate", () => {
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
  let feeDistributor: DegenFeeDistributor
  let referralManager: DummyReferralManager
  let referralTiers: ReferralTiers
  let timestampOfTest: number
  let referralCode: string

  before(async () => {
    const accounts = await ethers.getSigners()
    admin1 = accounts[0]
    trader1 = accounts[1]
    lp1 = accounts[2]
    broker = accounts[3]

    libs = await deployUnitTestLibraries()
    referralCode = toBytes32("testCode")
  })

  beforeEach(async () => {
    timestampOfTest = await time.latest()
    timestampOfTest = Math.ceil(timestampOfTest / 3600) * 3600 + 3600 // align to next hour

    pool = (await deployUnitTestPool(admin1, libs)) as IDegenPool
    orderBook = (await createContract("OrderBook", [], { "contracts/libraries/LibOrderBook.sol:LibOrderBook": libs.libOrderBook })) as OrderBook
    mlp = (await createContract("MlpToken")) as MlpToken
    feeDistributor = (await createContract("DegenFeeDistributor")) as DegenFeeDistributor
    referralManager = (await createContract("DummyReferralManager")) as DummyReferralManager
    referralTiers = (await createContract("ReferralTiers")) as ReferralTiers

    // referral
    await referralManager.setTierSetting(1, 25000, rate("0.04"), rate("0.06"))
    await referralTiers.initialize()
    await referralTiers.grantRole(MAINTAINER_ROLE, admin1.address)
    await feeDistributor.initialize(pool.address, orderBook.address, referralManager.address, referralTiers.address)

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

  it("no tier (all return to pool)", async () => {
    // +liq usdc
    expect(await mlp.totalSupply()).to.equal(toWei("0"))
    expect(await pool.callStatic.getMlpPrice([toWei("1"), toWei("1000"), toWei("1")])).to.equal(toWei("1")) // init mlp price = 1
    await usdc.connect(lp1).approve(orderBook.address, toUnit("1000000", 6))
    {
      const args = { assetId: 0, rawAmount: toUnit("1000000", 6), isAdding: true }
      const tx1 = await orderBook.connect(lp1).placeLiquidityOrder(args)
      expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(lp1.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("1000000", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("0", 6))
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(true)
    }
    expect(await mlp.totalSupply()).to.equal(toWei("0"))
    expect(await pool.callStatic.getMlpPrice([toWei("1"), toWei("1000"), toWei("1")])).to.equal(toWei("1")) // init mlp price = 1
    {
      await time.increaseTo(timestampOfTest + 86400 * 2 + 330)
      const tx1 = orderBook.connect(broker).fillLiquidityOrder(0, [toWei("1"), toWei("1000"), toWei("1")])
      // fee = 1000000 * 0.01% = 100
      await expect(tx1).to.emit(feeDistributor, "FeeDistributed").withArgs(0, lp1.address, toUnit("100", 6) /* toPool */, toUnit("0", 6) /* toTrader */, toUnit("0", 6) /* toReferral */)
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(false)
      expect(await usdc.balanceOf(lp1.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1000000", 6))
      expect(await mlp.balanceOf(lp1.address)).to.equal(toWei("999900")) // (1000000 - fee) / 1
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("0"))
      const collateralInfo = await pool.getAssetStorageV2(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("1000000")) // 1000000 - fee
    }
    expect(await mlp.totalSupply()).to.equal(toWei("999900"))
    expect(await pool.callStatic.getMlpPrice([toWei("1"), toWei("1000"), toWei("1")])).to.equal(toWei("1.000100010001000100")) // aum = 1000000
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
      await orderBook.connect(trader1).placePositionOrder(args1, refCode)
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("1000", 6))
      expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("0", 6)) // unchanged
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1000000", 6)) // unchanged
      const collateralInfo = await pool.getAssetStorageV2(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("1000000")) // unchanged
    }
    {
      const tx1 = await orderBook.connect(broker).fillPositionOrder(1, toWei("1"), toWei("2000"), [toWei("1"), toWei("2001"), toWei("1")])
      // feeUsd, 2000 * 1 * 0.1% = 2
      await expect(tx1).to.emit(feeDistributor, "FeeDistributed").withArgs(0, trader1.address, toUnit("2", 6) /* toPool */, toUnit("0", 6) /* toTrader */, toUnit("0", 6) /* toReferral */)
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1001000", 6)) // + collateral = 1000000 + 1000
      const subAccount = await pool.getSubAccount(shortAccountId)
      expect(subAccount.collateral).to.equal(toWei("998")) // fee = 2
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("2000"))
      expect(subAccount.entryFunding).to.equal(toWei("0.000054794520547944"))
      const collateralInfo = await pool.getAssetStorageV2(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("1000002")) // +fee
      const assetInfo = await pool.getAssetStorageV2(1)
      expect(assetInfo.totalShortPosition).to.equal(toWei("1"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("2000"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
    }
    expect(await mlp.totalSupply()).to.equal(toWei("999900")) // unchanged
    expect(await pool.callStatic.getMlpPrice([toWei("1"), toWei("2000"), toWei("1")])).to.equal(toWei("1.000102010201020102")) // aum = 1000002 - upnl(0)
  })

  it("tier 1", async () => {
    // referral
    await referralManager.setReferrerCodeFor(lp1.address, referralCode, admin1.address /* recipient */)
    await referralManager.setReferrerCodeFor(trader1.address, referralCode, admin1.address /* recipient */)
    await referralTiers.setTier([referralCode], [1])

    // +liq usdc
    expect(await mlp.totalSupply()).to.equal(toWei("0"))
    expect(await pool.callStatic.getMlpPrice([toWei("1"), toWei("1000"), toWei("1")])).to.equal(toWei("1")) // init mlp price = 1
    await usdc.connect(lp1).approve(orderBook.address, toUnit("1000000", 6))
    {
      const args = { assetId: 0, rawAmount: toUnit("1000000", 6), isAdding: true }
      const tx1 = await orderBook.connect(lp1).placeLiquidityOrder(args)
      expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(admin1.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(lp1.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("1000000", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("0", 6))
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(true)
    }
    expect(await mlp.totalSupply()).to.equal(toWei("0"))
    expect(await pool.callStatic.getMlpPrice([toWei("1"), toWei("1000"), toWei("1")])).to.equal(toWei("1")) // init mlp price = 1
    {
      await time.increaseTo(timestampOfTest + 86400 * 2 + 330)
      const tx1 = orderBook.connect(broker).fillLiquidityOrder(0, [toWei("1"), toWei("1000"), toWei("1")])
      // fee = 1000000 * 0.01% = 100, discount 4% = 4, rebate 6% = 6
      await expect(tx1).to.emit(feeDistributor, "FeeDistributed").withArgs(0, lp1.address, toUnit("90", 6) /* toPool */, toUnit("4", 6) /* toTrader */, toUnit("6", 6) /* toReferral */)
      const result = await orderBook.getOrder(0)
      expect(result[1]).to.equal(false)
      expect(await usdc.balanceOf(lp1.address)).to.equal(toUnit("4", 6)) // + 4
      expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(admin1.address)).to.equal(toUnit("6", 6)) // + 6
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("999990", 6)) // 1000000 - discount 4 - rebate 6
      expect(await mlp.balanceOf(lp1.address)).to.equal(toWei("999900")) // (1000000 - fee) / 1
      expect(await mlp.balanceOf(orderBook.address)).to.equal(toWei("0"))
      const collateralInfo = await pool.getAssetStorageV2(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("999990")) // 1000000 - discount 4 - rebate 6
    }
    expect(await mlp.totalSupply()).to.equal(toWei("999900"))
    expect(await pool.callStatic.getMlpPrice([toWei("1"), toWei("1000"), toWei("1")])).to.equal(toWei("1.000090009000900090")) // aum = 999990
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
      await orderBook.connect(trader1).placePositionOrder(args1, refCode)
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000", 6))
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("1000", 6))
      expect(await usdc.balanceOf(admin1.address)).to.equal(toUnit("6", 6)) // unchanged
      expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("0", 6)) // unchanged
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("999990", 6)) // unchanged
      const collateralInfo = await pool.getAssetStorageV2(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("999990")) // unchanged
    }
    {
      const tx1 = await orderBook.connect(broker).fillPositionOrder(1, toWei("1"), toWei("2000"), [toWei("1"), toWei("2001"), toWei("1")])
      // feeUsd, 2000 * 1 * 0.1% = 2, discount 4% = 0.08, rebate 6% = 0.12
      await expect(tx1).to.emit(feeDistributor, "FeeDistributed").withArgs(0, trader1.address, toUnit("1.8", 6) /* toPool */, toUnit("0.08", 6) /* toTrader */, toUnit("0.12", 6) /* toReferral */)
      expect(await usdc.balanceOf(trader1.address)).to.equal(toUnit("99000.08", 6)) // +0.08
      expect(await usdc.balanceOf(orderBook.address)).to.equal(toUnit("0", 6))
      expect(await usdc.balanceOf(feeDistributor.address)).to.equal(toUnit("0", 6)) // unchanged
      expect(await usdc.balanceOf(admin1.address)).to.equal(toUnit("6.12", 6)) // +0.12
      expect(await usdc.balanceOf(pool.address)).to.equal(toUnit("1000989.8", 6)) // + collateral = 999990 + 1000 - 0.08 - 0.12
      const subAccount = await pool.getSubAccount(shortAccountId)
      expect(subAccount.collateral).to.equal(toWei("998")) // fee = 2
      expect(subAccount.size).to.equal(toWei("1"))
      expect(subAccount.entryPrice).to.equal(toWei("2000"))
      expect(subAccount.entryFunding).to.equal(toWei("0.000054794520547944"))
      const collateralInfo = await pool.getAssetStorageV2(0)
      expect(collateralInfo.spotLiquidity).to.equal(toWei("999991.8")) // +fee
      const assetInfo = await pool.getAssetStorageV2(1)
      expect(assetInfo.totalShortPosition).to.equal(toWei("1"))
      expect(assetInfo.averageShortPrice).to.equal(toWei("2000"))
      expect(assetInfo.totalLongPosition).to.equal(toWei("0"))
      expect(assetInfo.averageLongPrice).to.equal(toWei("0"))
    }
    expect(await mlp.totalSupply()).to.equal(toWei("999900")) // unchanged
    expect(await pool.callStatic.getMlpPrice([toWei("1"), toWei("2000"), toWei("1")])).to.equal(toWei("1.000091809180918091")) // aum = 999991.8 - upnl(0)
  })
})
