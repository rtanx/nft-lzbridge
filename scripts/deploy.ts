import { ethers, network, run } from "hardhat";

interface DeploymentConfig {
  networkName: string,
  lz0chainId: number,
  lz0EndpointAddress: string,
}

let deploymentConfigs: DeploymentConfig[] = [];

function initDeploymentConfigs() {
  deploymentConfigs.push({
    networkName: "goerli",
    lz0chainId: 10121,
    lz0EndpointAddress: "0xbfD2135BFfbb0B5378b56643c2Df8a87552Bfa23"
  });

  deploymentConfigs.push({
    networkName: "bscTestnet",
    lz0chainId: 10102,
    lz0EndpointAddress: "0x6Fcb97553D41516Cb228ac03FdC8B9a0a9df04A1"
  })

  deploymentConfigs.push({
    networkName: "polygonMumbai",
    lz0chainId: 10109,
    lz0EndpointAddress:"0xf69186dfBa60DdB133E91E9A4B5673624293d8F8"
  })

  deploymentConfigs.push({
    networkName: "avalancheFujiTestnet",
    lz0chainId: 10106,
    lz0EndpointAddress: "0x93f54D755A063cE7bB9e6Ac47Eccc8e33411d706"
  })

  deploymentConfigs.push({
    networkName:"arbitrumGoerli",
    lz0chainId: 10143,
    lz0EndpointAddress: "0x6aB5Ae6822647046626e83ee6dB8187151E1d5ab"
  })

  deploymentConfigs.push({
    networkName: "moonbaseAlpha",
    lz0chainId: 10126,
    lz0EndpointAddress: "0xb23b28012ee92E8dE39DEb57Af31722223034747"
  })
}

async function main() {
  initDeploymentConfigs();
  const depConf: DeploymentConfig | undefined = deploymentConfigs.find((obj, _) => obj.networkName == network.name);
  if (depConf === undefined) {
    console.log("cannot matching network configuration");
    return
  }

  const [, deployer] = await ethers.getSigners();
  const factory = await ethers.getContractFactory('RankerDaoBridge');

  console.log(`Contract will be deployed with account address ${deployer.address}`);
  console.log("With LayerZero configuration: ");
  console.table(depConf);
  console.log(`Deploying contract to ${network.name}...`);

  const contract = await factory.connect(deployer).deploy(depConf.lz0EndpointAddress)
  const contractAddress = await contract.getAddress();
  console.log(`Contract deployed to address ${contractAddress}`);

  await contract.deploymentTransaction()?.wait();
  console.log("Verifying deployed contract...")
  // await run("verify:verify", {
  //   address: contractAddress,
  //   constructorArguments: [depConf.lz0EndpointAddress]
  // });

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
