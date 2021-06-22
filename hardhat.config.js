/**
 * @type import('hardhat/config').HardhatUserConfig
 */


 require('@nomiclabs/hardhat-ethers');

 const { alchemyApiKey, mnemonic } = require('./secrets.json');



module.exports = {
  solidity: {
    version: "0.6.12",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
    // compilers: [
    //   {
    //     version: "0.5.0",
    //     settings: {
    //       optimizer: {
    //         enabled: true,
    //         runs: 200
    //       }
    //     }
    //   },
    //   {
    //     version: "0.5.16",
    //     settings: {
    //       optimizer: {
    //         enabled: true,
    //         runs: 200
    //       }
    //     }
    //   },
    //   {
    //     version: "0.6.0",
    //     settings: {
    //       optimizer: {
    //         enabled: true,
    //         runs: 200
    //       }
    //     }
    //   }
    // ]
  },
  networks: {
      rinkeby: {
        url: `https://eth-rinkeby.alchemyapi.io/v2/${alchemyApiKey}`,
        accounts: {mnemonic: mnemonic}
      },
      mainnet: {
        url: `https://eth-mainnet.alchemyapi.io/v2/LOTq6i-unlZrg-yS_ZUqOcTU6LOVUraS`,
        accounts: {mnemonic: mnemonic}
      }
   },
   gas: 50000000
};
