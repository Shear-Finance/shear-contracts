// deploy/00_deploy_your_contract.js

const { ethers } = require("hardhat");

const localChainId = "31337";

// const sleep = (ms) =>
//   new Promise((r) =>
//     setTimeout(() => {
//       console.log(`waited for ${(ms / 1000).toFixed(3)} seconds`);
//       r();
//     }, ms)
//   );


module.exports = async ({ getNamedAccounts, deployments, getChainId }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const chainId = await getChainId();
  
  const devAccountAddress = "0x1Fc444e3E4C60e864BfBaA25953B42Fa73695Cf8"
  
  await deploy("GovernanceToken", {
    from: deployer,
    args: [],
    log: true,
    waitConfirmations: 2,
	skipIfAlreadyDeployed: false,
  })
  const GovernanceToken = await ethers.getContract("GovernanceToken", deployer)
    


  await deploy("Staking", {
    from: deployer,
    args: [GovernanceToken.address],
    log: true,
    waitConfirmations: 2,
	skipIfAlreadyDeployed: false,
  })
  const Staking = await ethers.getContract("Staking", deployer)
  
  
	
  await deploy("MasterChef", {
    from: deployer,
    args: [GovernanceToken.address, devAccountAddress, devAccountAddress, Staking.address],
    log: true,
    waitConfirmations: 2,
	skipIfAlreadyDeployed: false,
  })
  const MasterChef = await ethers.getContract("MasterChef", deployer)
  try {
	let tx = await GovernanceToken.changeMasterchef(MasterChef.address);
	await tx.wait()
  }
  catch(e) { } // could fail if already deployed





  await deploy("PoolFactory", {
    from: deployer,
    log: true,
    waitConfirmations: 2,
  })
  const PoolFactory = await ethers.getContract("PoolFactory", deployer)
  
  
  
  await deploy("Router", {
    from: deployer,
    log: true,
    waitConfirmations: 2,
  });
  const Router = await ethers.getContract("Router", deployer);
  try {
	let tx1 = await Router.updateFactory(PoolFactory.address, 1);
	await tx1.wait()
  }
  catch(e){
	  console.log("Router couldnt change factory address")
  }
  
/*
  console.log("Step 1")
  const usdcDaiUniPair = "0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5";
  const uniRouter = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";
  try {
	  
	await Router.createPool(usdcDaiUniPair, uniRouter, "UNI");
	  
  }
  catch(e){console.log('create pool failed', e)}
  try {
	const newPool = await Router.pairToPool(usdcDaiUniPair) ;
	await MasterChef.add(100, newPool, false) //add pool in masterchef, pool number 0 baby
  }
  catch(e) { console.log("Couldnt create new pool maybe didnt redeploy", e)  }
*/

//give masterchef ownership to dev so he can set rewards
  try {
	let tx2 = await MasterChef.transferOwnership(devAccountAddress) //add pool in masterchef, pool number 0 baby
	await tx2.wait()
  }
  catch(e) { console.log("Couldnt transfer masterchef ownership", e)  }
  /*
  console.log("Step 2")
  // Deploy a pool to get ABI updated
  await deploy("Pool", {
    // Learn more about args here: https://www.npmjs.com/package/hardhat-deploy#deploymentsdeploy
    from: deployer,
    args: ["0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5", "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D", "VMM-SA-ASD", "UNI", "PLI-PLOP"],
    log: true,
    waitConfirmations: 5,
  })
  console.log("Step 3")
  const DummyPool = await ethers.getContract("Pool", deployer)
  
  console.log("Step 4")
  // Getting a previously deployed contract
  const usdcDaiPool = await Router.pairToPool(usdcDaiUniPair);
  const Pool = await ethers.getContractAt("Pool", usdcDaiPool);
  
  // Changing ownerships to dev for testing
  //await Router.transferOwnership(devAccountAddress);
*/


  /*
  //If you want to send value to an address from the deployer
  const deployerWallet = ethers.provider.getSigner()
  await deployerWallet.sendTransaction({
    to: "0x34aA3F359A9D614239015126635CE7732c18fDF3",
    value: ethers.utils.parseEther("0.001")
  })
  */

  /*
  //If you want to send some ETH to a contract on deploy (make your constructor payable!)
  const yourContract = await deploy("YourContract", [], {
  value: ethers.utils.parseEther("0.05")
  });
  */

  /*
  //If you want to link a library into your contract:
  // reference: https://github.com/austintgriffith/scaffold-eth/blob/using-libraries-example/packages/hardhat/scripts/deploy.js#L19
  const yourContract = await deploy("YourContract", [], {}, {
   LibraryName: **LibraryAddress**
  });
  */

  // Verify from the command line by running `yarn verify`

  // You can also Verify your contracts with Etherscan here...
  // You don't want to verify on localhost
  // try {
  //   if (chainId !== localChainId) {
  //     await run("verify:verify", {
  //       address: YourContract.address,
  //       contract: "contracts/YourContract.sol:YourContract",
  //       contractArguments: [],
  //     });
  //   }
  // } catch (error) {
  //   console.error(error);
  // }
};
module.exports.tags = ["Router", "Pool", "GovernanceToken", "MasterChef"];
