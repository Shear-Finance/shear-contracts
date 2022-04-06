pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: MIT

// import "@openzeppelin/contracts/access/Ownable.sol"; 
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol

import "hardhat/console.sol";

import "./Pool.sol";
import "./PoolFactory.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";


/// Router and factory creates and references  pools
contract Router is Ownable {
	
	// Factory address for pools deployment
	address public factoryAddress;
	
	// Initial pool version
	uint public currentPoolVersion = 1;

	// If released, anyone can create new pools 
	bool public isReleased = false;

	address[] public poolList;
	mapping ( address => address ) public pairToPool;
	mapping ( address => uint ) public poolVersion;

	/// Admin functions
	function release() public onlyOwner {
		isReleased = true;
	}
	
	/// @notice Updates factory contract
	function updateFactory ( address newFactoryAddress, uint poolVersion_ ) 
		public 
		onlyOwner
	{
		//require (poolVersion_ > currentPoolVersion, "VERSION_ERROR");
		console.log("factoryAddress = newFactoryAddress");
		factoryAddress = newFactoryAddress;
		currentPoolVersion = poolVersion_;
	}
	
	
	/// @notice Get the number of pools
	function getPoolCount() public view returns (uint256 poolCount) {
		return poolList.length;
	}
	
	
	
	/// @notice Creates a new pool if not existing (with current version)
	function createPool(address swapPair, address swapRouter, string memory amm) 
		public 
		returns (address poolAddress)
	{
		//require ( isReleased || msg.sender == owner(), "ONLY_OWNER_ALLOWED");
		console.log("pairToPool: %s , poolVersion: %s", pairToPool[swapPair], poolVersion[swapPair]);
		require ( pairToPool[swapPair] == address(0) || poolVersion[swapPair] < currentPoolVersion, "MARKET_ALREADY_EXISTS" ); 
		console.log('ok go');
		address newPool = PoolFactory(factoryAddress).createPool(swapPair, swapRouter, amm);
		console.log('created new pool %s', newPool);
		poolList.push(newPool);
		console.log('newPool %s', newPool);
		pairToPool[swapPair] = newPool;
		
		console.log('newPool version %s', currentPoolVersion);
		poolVersion[newPool] = currentPoolVersion;
		
		return newPool;
	}
	

}