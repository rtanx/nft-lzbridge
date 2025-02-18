import "dotenv/config";
import "@nomicfoundation/hardhat-toolbox";
import { HardhatUserConfig, task } from "hardhat/config";
import "hardhat-contract-sizer";
import "hardhat-deploy";
import "@openzeppelin/hardhat-upgrades";

const { BSCSCAN_API_KEY, ETHERSCAN_API_KEY } = process.env;

task("accounts", "Prints the list of accounts", async (taskArgs, hre) => {
  const accounts = await hre.ethers.getSigners();

  for (const account of accounts) {
    console.log(account.address);
  }

});

function getMnemonic(networkName: string) {
  if (networkName) {
    const mnemonic = process.env['MNEMONIC_' + networkName.toUpperCase()]
    if (mnemonic && mnemonic !== '') {
      return mnemonic
    }
  }

  const mnemonic = process.env.MNEMONIC
  if (!mnemonic || mnemonic === '') {
    return 'test test test test test test test test test test test junk'
  }

  return mnemonic
}

function accounts(chainKey: string = "") {
  return { mnemonic: getMnemonic(chainKey) }
}

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.18",
        settings: {
          viaIR:true,
          optimizer: {
            enabled: true,
            runs: 200,
            details:{
              yulDetails: {
                optimizerSteps:"u",
              },
            },
          },
        },
      },
      {
        version: "0.8.9",
        settings: {
          viaIR:true,
          optimizer: {
            enabled: true,
            runs: 200,
            details:{
              yulDetails: {
                optimizerSteps:"u",
              },
            },
          },
        },
      },
      {
        version: "0.7.6",
        settings: {
          viaIR:true,
          optimizer: {
            enabled: true,
            runs: 200,
            details:{
              yulDetails: {
                optimizerSteps:"u",
              },
            },
          },
        },
      },
      {
        version: "0.8.12",
        settings: {
          viaIR:true,
          optimizer: {
            enabled: true,
            runs: 200,
            details:{
              yulDetails: {
                optimizerSteps:"u",
              },
            },
          },
        },
      }
    ]
  },
  etherscan: {
    apiKey: {
      bsc: `${BSCSCAN_API_KEY}`,
      bscTestnet: `${BSCSCAN_API_KEY}`,
      'bsc-testnet': `${BSCSCAN_API_KEY}`,
      ethereum: `${ETHERSCAN_API_KEY}`,
      // 0x1f49bCd396bC4810FF88f0d1b24703E46115ceC4 0x6Fcb97553D41516Cb228ac03FdC8B9a0a9df04A1
      goerli: `${ETHERSCAN_API_KEY}`,
    }
  },
  contractSizer: {
    alphaSort: false,
    runOnCompile: true,
    disambiguatePaths: false,
  },

  namedAccounts: {
    deployer: {
      default: 1,    // wallet address 1, of the mnemonic in .env
    },
    proxyOwner: {
      default: 1,
    },
  },

  mocha: {
    timeout: 100000000
  },

  defaultNetwork: "ganache",
  networks: {
    ganache: {
      url: "http://127.0.0.1:7545",
      accounts: accounts(),
    },
    ethereum: {
      url: "https://mainnet.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161", // public infura endpoint
      chainId: 1,
      accounts: accounts(),
    },
    bsc: {
      url: "https://bsc-dataseed1.binance.org",
      chainId: 56,
      accounts: accounts(),
    },
    avalanche: {
      url: "https://api.avax.network/ext/bc/C/rpc",
      chainId: 43114,
      accounts: accounts(),
    },
    polygon: {
      url: "https://rpc-mainnet.maticvigil.com",
      chainId: 137,
      accounts: accounts(),
    },
    arbitrum: {
      url: `https://arb1.arbitrum.io/rpc`,
      chainId: 42161,
      accounts: accounts(),
    },
    optimism: {
      url: `https://mainnet.optimism.io`,
      chainId: 10,
      accounts: accounts(),
    },
    fantom: {
      url: `https://rpcapi.fantom.network`,
      chainId: 250,
      accounts: accounts(),
    },
    metis: {
      url: `https://andromeda.metis.io/?owner=1088`,
      chainId: 1088,
      accounts: accounts(),
    },

    goerli: {
      url: "https://goerli.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161", // public infura endpoint
      chainId: 5,
      accounts: accounts(),
    },
    'bsc-testnet': {
      url: 'https://data-seed-prebsc-1-s1.binance.org:8545/',
      chainId: 97,
      accounts: accounts(),
    },
    fuji: {
      url: `https://api.avax-test.network/ext/bc/C/rpc`,
      chainId: 43113,
      accounts: accounts(),
    },
    mumbai: {
      url: "https://rpc-mumbai.maticvigil.com/",
      chainId: 80001,
      accounts: accounts(),
    },
    'arbitrum-goerli': {
      url: `https://goerli-rollup.arbitrum.io/rpc/`,
      chainId: 421613,
      accounts: accounts(),
    },
    'optimism-goerli': {
      url: `https://goerli.optimism.io/`,
      chainId: 420,
      accounts: accounts(),
    },
    'fantom-testnet': {
      url: `https://rpc.ankr.com/fantom_testnet`,
      chainId: 4002,
      accounts: accounts(),
    }
  }

};

export default config;
