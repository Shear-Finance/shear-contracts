pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: MIT

import "./VMMPool.sol";

/**
* VMM Factory contract
* Deploys a VMMPool
* If a new VMMPool version is needed after an upgrade, just deploy a new factory and update router factory address
*/
contract VMMFactory {
	
	/// @notice Creates a new pool
	/// @param swapPair The address of the AMM pair (should be IUniswapV2Pair compatible) 
	/// @param swapRouter The address of the AMM router (should be IUniswapV2Router02 compatible)
	/// @param amm The name/symbol of the AMM (e.g UNI, SUSHI, SPIRIT)
	function createPool(address swapPair, address swapRouter, string memory amm) 
		public 
		returns (address poolAddress) 
	{

		address token0 = IUniswapV2Pair(swapPair).token0();
		address token1 = IUniswapV2Pair(swapPair).token1();
		
		string memory pairName = string(bytes.concat(
				bytes( ERC20(token0).symbol() ),
				bytes("-"),
				bytes( ERC20(token1).symbol() )
			));
		string memory poolName = string(bytes.concat(
				"Scuba-+",
				bytes(amm),
				bytes(pairName)
			));
		VMMPool vmmPool = new VMMPool(swapPair, swapRouter, poolName, amm, pairName);

		return address(vmmPool);
	}
}