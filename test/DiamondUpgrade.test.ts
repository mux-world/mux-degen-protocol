import { ethers } from "hardhat"
import "@nomiclabs/hardhat-ethers"
import { expect } from "chai"
import { Contract } from "ethers"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import { createContract, getSelectors, FacetCutAction, zeroAddress, zeroBytes32 } from "../scripts/deployUtils"
import { Diamond, DiamondLoupeFacet, DiamondCutFacet, OwnershipFacet } from "../typechain"
import { DegenPool } from "../typechain"
const U = ethers.utils

describe("DiamondUpgrade", () => {
  let admin1: SignerWithAddress
  let trader1: SignerWithAddress
  let lp1: SignerWithAddress
  let broker: SignerWithAddress

  let ownershipFacet: OwnershipFacet
  let diamondCutFacet: DiamondCutFacet
  let diamondLoupeFacet: DiamondLoupeFacet
  let diamond: Diamond
  let pool: DegenPool

  before(async () => {
    const accounts = await ethers.getSigners()
    admin1 = accounts[0]
    trader1 = accounts[1]
    lp1 = accounts[2]
    broker = accounts[3]

    diamondCutFacet = (await createContract("DiamondCutFacet")) as DiamondCutFacet
    diamondLoupeFacet = (await createContract("DiamondLoupeFacet")) as DiamondLoupeFacet
    ownershipFacet = (await createContract("OwnershipFacet")) as OwnershipFacet
  })

  beforeEach(async () => {
    const initialCuts = [
      {
        facetAddress: diamondCutFacet.address,
        action: FacetCutAction.Add,
        functionSelectors: Object.values(getSelectors(diamondCutFacet)),
      },
      {
        facetAddress: diamondLoupeFacet.address,
        action: FacetCutAction.Add,
        functionSelectors: Object.values(getSelectors(diamondLoupeFacet)),
      },
      {
        facetAddress: ownershipFacet.address,
        action: FacetCutAction.Add,
        functionSelectors: Object.values(getSelectors(ownershipFacet)),
      },
    ]
    const initialCutArgs = {
      owner: admin1.address,
      init: zeroAddress,
      initCalldata: "0x",
    }
    diamond = (await createContract("Diamond", [initialCuts, initialCutArgs])) as Diamond
    pool = (await ethers.getContractAt("IDegenPool", diamond.address)) as DegenPool
  })

  it("add admin", async () => {
    await expect(pool.setMaintainer(broker.address, true)).to.be.revertedWith('FunctionNotFound("0xb1a61489")')

    const upgrade = (await ethers.getContractAt("DiamondCutFacet", diamond.address)) as DiamondCutFacet
    const adminFacet = await createContract("contracts/facets/Admin.sol:Admin")
    const cuts = [
      {
        facetAddress: adminFacet.address,
        action: FacetCutAction.Add,
        functionSelectors: Object.values(getSelectors(adminFacet)),
      },
    ]
    const initAddress = zeroAddress
    const initArgs = "0x"
    await expect(upgrade.connect(broker).diamondCut(cuts, initAddress, initArgs)).to.be.revertedWith("NotContractOwner")
    await upgrade.diamondCut(cuts, initAddress, initArgs)

    await pool.setMaintainer(broker.address, true)
  })
})
