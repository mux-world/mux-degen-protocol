import { ethers } from "hardhat"
import { BytesLike } from "ethers"
import { ContractTransaction, Contract, ContractReceipt } from "ethers"
import { TransactionReceipt } from "@ethersproject/providers"
import { hexlify, concat, zeroPad, arrayify } from "@ethersproject/bytes"
import { BigNumber as EthersBigNumber, BigNumberish, parseFixed, formatFixed } from "@ethersproject/bignumber"
import chalk from "chalk"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"

export const zeroBytes32 = ethers.constants.HashZero
export const zeroAddress = ethers.constants.AddressZero

export enum OrderType {
  Invalid,
  Position,
  Liquidity,
  Withdrawal,
  Rebalance,
}

export enum PositionOrderFlags {
  OpenPosition = 0x80, // this flag means openPosition; otherwise closePosition
  MarketOrder = 0x40, // this flag means ignore limitPrice
  WithdrawAllIfEmpty = 0x20, // this flag means auto withdraw all collateral if position.size == 0
  TriggerOrder = 0x10, // this flag means this is a trigger order (ex: stop-loss order). otherwise this is a limit order (ex: take-profit order)
  TpSlStrategy = 0x08, // for open-position-order, this flag auto place take-profit and stop-loss orders when open-position-order fills.
  //                      for close-position-order, this flag means ignore limitPrice and profitTokenId, and use extra.tpPrice, extra.slPrice, extra.tpslProfitTokenId instead.
  ShouldReachMinProfit = 0x04, // this flag is used to ensure that either the minProfitTime is met or the minProfitRate ratio is reached when close a position. only available when minProfitTime > 0.
  AutoDeleverage = 0x02, // denotes that this order is an auto-deleverage order
}

export enum ReferenceOracleType {
  None,
  Chainlink,
}

export const FacetCutAction = {
  Add: 0,
  Replace: 1,
  Remove: 2,
}

export const ASSET_IS_STABLE = 0x00000000000001 // is a usdt, usdc, ...
export const ASSET_CAN_ADD_REMOVE_LIQUIDITY = 0x00000000000002 // can call addLiquidity and removeLiquidity with this token
export const ASSET_IS_TRADABLE = 0x00000000000100 // allowed to be assetId
export const ASSET_IS_OPENABLE = 0x00000000010000 // can open position
export const ASSET_IS_SHORTABLE = 0x00000001000000 // allow shorting this asset
export const ASSET_IS_ENABLED = 0x00010000000000 // allowed to be assetId and collateralId
export const ASSET_IS_STRICT_STABLE = 0x01000000000000 // assetPrice is always 1 unless volatility exceeds strictStableDeviation

// POOL
export const MLP_TOKEN_KEY = hashString("MLP_TOKEN")
export const ORDER_BOOK_KEY = hashString("ORDER_BOOK")
export const FEE_DISTRIBUTOR_KEY = hashString("FEE_DISTRIBUTOR")

export const FUNDING_INTERVAL_KEY = hashString("FUNDING_INTERVAL")
export const BORROWING_RATE_APY_KEY = hashString("BORROWING_RATE_APY")

export const LIQUIDITY_FEE_RATE_KEY = hashString("LIQUIDITY_FEE_RATE")

export const STRICT_STABLE_DEVIATION_KEY = hashString("STRICT_STABLE_DEVIATION")
export const BROKER_GAS_REBATE_USD_KEY = hashString("BROKER_GAS_REBATE_USD")

// POOL - ASSET
export const SYMBOL_KEY = hashString("SYMBOL")
export const DECIMALS_KEY = hashString("DECIMALS")
export const TOKEN_ADDRESS_KEY = hashString("TOKEN_ADDRESS")
export const LOT_SIZE_KEY = hashString("LOT_SIZE")

export const INITIAL_MARGIN_RATE_KEY = hashString("INITIAL_MARGIN_RATE")
export const MAINTENANCE_MARGIN_RATE_KEY = hashString("MAINTENANCE_MARGIN_RATE")
export const MIN_PROFIT_RATE_KEY = hashString("MIN_PROFIT_RATE")
export const MIN_PROFIT_TIME_KEY = hashString("MIN_PROFIT_TIME")
export const POSITION_FEE_RATE_KEY = hashString("POSITION_FEE_RATE")
export const LIQUIDATION_FEE_RATE_KEY = hashString("LIQUIDATION_FEE_RATE")

export const REFERENCE_ORACLE_KEY = hashString("REFERENCE_ORACLE")
export const REFERENCE_DEVIATION_KEY = hashString("REFERENCE_DEVIATION")
export const REFERENCE_ORACLE_TYPE_KEY = hashString("REFERENCE_ORACLE_TYPE")

export const MAX_LONG_POSITION_SIZE_KEY = hashString("MAX_LONG_POSITION_SIZE")
export const MAX_SHORT_POSITION_SIZE_KEY = hashString("MAX_SHORT_POSITION_SIZE")
export const FUNDING_ALPHA_KEY = hashString("FUNDING_ALPHA")
export const FUNDING_BETA_APY_KEY = hashString("FUNDING_BETA_APY")

export const LIQUIDITY_CAP_USD_KEY = hashString("LIQUIDITY_CAP_USD")

export const ADL_RESERVE_RATE_KEY = hashString("ADL_RESERVE_RATE")
export const ADL_MAX_PNL_RATE_KEY = hashString("ADL_MAX_PNL_RATE")
export const ADL_TRIGGER_RATE_KEY = hashString("ADL_TRIGGER_RATE")

// ORDERBOOK
export const BROKER_ROLE = hashString("BROKER_ROLE")
export const CALLBACKER_ROLE = hashString("CALLBACKER_ROLE")
export const MAINTAINER_ROLE = hashString("MAINTAINER_ROLE")
export const OB_LIQUIDITY_LOCK_PERIOD_KEY = hashString("OB_LIQUIDITY_LOCK_PERIOD")
export const OB_REFERRAL_MANAGER_KEY = hashString("OB_REFERRAL_MANAGER")
export const OB_MARKET_ORDER_TIMEOUT_KEY = hashString("OB_MARKET_ORDER_TIMEOUT")
export const OB_LIMIT_ORDER_TIMEOUT_KEY = hashString("OB_LIMIT_ORDER_TIMEOUT")
export const OB_CALLBACK_GAS_LIMIT_KEY = hashString("OB_CALLBACK_GAS_LIMIT")
export const OB_CANCEL_COOL_DOWN_KEY = hashString("OB_CANCEL_COOL_DOWN")

export function toWei(n: string): EthersBigNumber {
  return ethers.utils.parseEther(n)
}

export function fromWei(n: BigNumberish): string {
  return ethers.utils.formatEther(n)
}

export function toUnit(n: string, decimals: number): EthersBigNumber {
  return parseFixed(n, decimals)
}

export function fromUnit(n: BigNumberish, decimals: number): string {
  return formatFixed(n, decimals)
}

export function toBytes32(s: string): string {
  return ethers.utils.formatBytes32String(s)
}

export function fromBytes32(s: BytesLike): string {
  return ethers.utils.parseBytes32String(s)
}

export function rate(n: string): EthersBigNumber {
  return toUnit(n, 5)
}

export function toChainlink(n: string): EthersBigNumber {
  return toUnit(n, 8)
}

export function printInfo(...message: any[]) {
  console.log(chalk.yellow("INF "), ...message)
}

export function printError(...message: any[]) {
  console.log(chalk.red("ERR "), ...message)
}

export function hashString(x: string): Buffer {
  return hash(ethers.utils.toUtf8Bytes(x))
}

export function hash(x: BytesLike): Buffer {
  return Buffer.from(ethers.utils.keccak256(x).slice(2), "hex")
}

export async function createFactory(path: any, libraries: { [name: string]: { address: string } } = {}): Promise<any> {
  const parsed: { [name: string]: string } = {}
  for (var name in libraries) {
    parsed[name] = libraries[name].address
  }
  return await ethers.getContractFactory(path, { libraries: parsed })
}

export async function createContract(path: any, args: any = [], libraries: { [name: string]: { address: string } } = {}): Promise<Contract> {
  const factory = await createFactory(path, libraries)
  return await factory.deploy(...args)
}

export function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

export async function ensureFinished(transaction: Promise<Contract> | Promise<ContractTransaction>): Promise<TransactionReceipt | ContractReceipt> {
  const result: Contract | ContractTransaction = await transaction
  let receipt: TransactionReceipt | ContractReceipt
  if ((result as Contract).deployTransaction) {
    receipt = await (result as Contract).deployTransaction.wait()
  } else {
    receipt = await result.wait()
  }
  if (receipt.status !== 1) {
    throw new Error(`receipt err: ${receipt.transactionHash}`)
  }
  return receipt
}

export function assembleSubAccountId(account: string, collateral: number, asset: number, isLong: boolean): string {
  return hexlify(
    concat([arrayify(account), [arrayify(EthersBigNumber.from(collateral))[0]], [arrayify(EthersBigNumber.from(asset))[0]], arrayify(EthersBigNumber.from(isLong ? 1 : 0)), zeroPad([], 9)])
  )
}

export function pad32r(s: EthersBigNumber | number | string): string {
  let num = arrayify(EthersBigNumber.from(s))
  if (num.length > 32) {
    throw new Error(`out of range: ${s}`)
  }
  const result = new Uint8Array(32)
  result.set(num, 0)
  return hexlify(result)
}

export function pad32l(s: EthersBigNumber | number | string): string {
  let num = arrayify(EthersBigNumber.from(s))
  if (num.length > 32) {
    throw new Error(`out of range: ${s}`)
  }
  const result = new Uint8Array(32)
  result.set(num, 32 - num.length)
  return hexlify(result)
}

export function getSelectors(contract: Contract): { [method: string]: string } {
  const selectors = {}
  for (const name in contract.interface.functions) {
    const signature = contract.interface.getSighash(contract.interface.functions[name])
    selectors[name] = signature
  }
  return selectors
}

export async function deployDiamond(admin1: SignerWithAddress, facets: Contract[]): Promise<Contract> {
  const initialCuts = facets.map((facet: Contract) => {
    return {
      facetAddress: facet.address,
      action: FacetCutAction.Add,
      functionSelectors: Object.values(getSelectors(facet)),
    }
  })
  const initialCutArgs = {
    owner: admin1.address,
    init: zeroAddress,
    initCalldata: "0x",
  }
  return await createContract("Diamond", [initialCuts, initialCutArgs])
}

// unit-test only!
export interface UnitTestLibs {
  diamondCutFacet: Contract
  diamondLoupeFacet: Contract
  ownershipFacet: Contract
  adminFacet: Contract
  accountFacet: Contract
  getterFacet: Contract
  liquidityFacet: Contract
  tradeFacet: Contract
  libOrderBook: Contract
}

// unit-test only!
export async function deployUnitTestLibraries(): Promise<UnitTestLibs> {
  const diamondCutFacet = await createContract("DiamondCutFacet")
  const diamondLoupeFacet = await createContract("DiamondLoupeFacet")
  const ownershipFacet = await createContract("OwnershipFacet")
  const adminFacet = await createContract("contracts/facets/Admin.sol:Admin")
  const accountFacet = await createContract("contracts/facets/Account.sol:Account")
  const getterFacet = await createContract("contracts/facets/Getter.sol:Getter")
  const liquidityFacet = await createContract("contracts/facets/Liquidity.sol:Liquidity")
  const tradeFacet = await createContract("contracts/facets/Trade.sol:Trade")
  const libOrderBook = await createContract("contracts/libraries/LibOrderBook.sol:LibOrderBook")
  return {
    diamondCutFacet,
    diamondLoupeFacet,
    ownershipFacet,
    adminFacet,
    accountFacet,
    getterFacet,
    liquidityFacet,
    tradeFacet,
    libOrderBook,
  }
}

// unit-test only!
export async function deployUnitTestPool(admin1: SignerWithAddress, libs: UnitTestLibs): Promise<Contract> {
  const facets = [libs.diamondCutFacet, libs.diamondLoupeFacet, libs.ownershipFacet, libs.adminFacet, libs.accountFacet, libs.getterFacet, libs.liquidityFacet, libs.tradeFacet]
  const diamond = await deployDiamond(admin1, facets)
  return await ethers.getContractAt("IDegenPool", diamond.address)
}

export function getPoolConfigs(configs: { k: Buffer; v: EthersBigNumber | number | string; old?: string | EthersBigNumber }[]): {
  keys: Buffer[]
  values: string[]
  currentValues: string[]
} {
  const keys: Buffer[] = [],
    values: string[] = [],
    currentValues: string[] = []
  for (const config of configs) {
    keys.push(config.k)
    values.push(pad32l(config.v))
    if (config.old) {
      currentValues.push(pad32l(config.old))
    }
  }
  return { keys, values, currentValues }
}
