const hre = require("hardhat");
const {
  storeContractAddress,
  verifyContract,
  printEtherscanLink,
} = require("./helper-functions");

const { ethers, network } = hre;

async function deploy(contractName, args = []) {
  const { chainId } = network.config;

  const CF = await ethers.getContractFactory(contractName);
  const contract = await CF.deploy(
    //subscription ID of personal vrf subscriber on goerli
    "8344",
    // VRF Coordinator on goerli
    "0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D",
    // keyhash on goerli
    "0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15"
  );

  await contract.deployed();
  await storeContractAddress(contract, contractName);
  await verifyContract(
    contract,
    //subscription ID of personal vrf subscriber on goerli
    "8344",
    // VRF Coordinator on goerli
    "0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D",
    // keyhash on goerli
    "0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15"
  );

  console.log("Deployer:", (await ethers.getSigners())[0].address);
  console.log(`${contractName} deployed to:`, contract.address);

  printEtherscanLink(contract.address, chainId);
}

async function main() {
  await deploy("LotteryV2");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
