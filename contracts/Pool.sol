//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;



// Scuba Finance: https://github.com

// Primary Author(s)
// NicoDeva


import "hardhat/console.sol";
import "./InterestRates.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";


/// @notice Pool is a LP tokens money market where borrowed LP are directly swapped to create long-short exposure to underlying tokens
contract Pool is ERC20, InterestRates, Ownable {

	/* ========== STATE VARIABLES ========== */

	event NewLoan(address poolAddress, uint amount, address addressCollateral);
	event ClosedLoan(address poolAddress, uint amount, address addressCollateral);

	address public swapRouter; // = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
	address public swapPair; // = 0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5; //temp put it here, should be added on contract creation
	address public tokenA;// = 0x6B175474E89094C44Da98b954EedeAC495271d0F; //DAI in uniswap tokens are sorted by address
	address public tokenB;// = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; //in uniswap tokens are sorted by address
	string public amm;
	string public pairName;

	// Is this money market enabled?
	bool public isPoolEnabled;

	// Current LP suppl
	uint public lpSupply;
	
	// Current LP outstanding LP amount
	uint public lpOutstanding;
	
	// Array of loans created
	Loan[] public loans;
	
	// Loan structure
	struct Loan {
		address owner;
		uint256 amountLpBorrowed;
		address addressCollateral;
		uint256 amountCollateral;
		uint256 amountReturned; //will be > amountCollateral if successsful short, else lower
		uint256 totalLoanTokens; // after withdrawing LP liquidity and selling token0 // totalLoanTokens + amountCollateral = total locked in loan to back LPs
		bool isOpen;
		uint startDate; // timestamp
		uint startRate;
	}
	
	// Liquidation threshold in percent
	uint public liquidationThresholdInPercent = 150;
	
	// Liquidation fee given to the liquidator, in percent
	uint public liquidationFeeInPercent = 10;
	
	
  
	constructor(address _swapPair, address _swapRouter, string memory poolName, string memory _amm, string memory _pairName)
		ERC20(poolName, poolName)
	{
		console.log("build vpmool0");
		swapPair = _swapPair;
		swapRouter = _swapRouter;
		tokenA = IUniswapV2Pair(swapPair).token0();
		tokenB = IUniswapV2Pair(swapPair).token1();
		isPoolEnabled = true;
		pairName = _pairName;
		amm = _amm;
	
		// push dummy loan to avoid the loanId == 0 case
		console.log("Dummy loan");
		loans.push( Loan(address(this), 0, tokenA, 0, 0, 0, false, block.timestamp, averageInterestRate ) );
		// allow uniswap router to spend our LP and tokens
		console.log("Approve uniswap: swapRouter spends LP and tokens");
		IUniswapV2Pair(swapPair).approve(swapRouter, uint(2**250));
		ERC20(tokenA).approve(swapRouter, uint(10**32));
		ERC20(tokenB).approve(swapRouter, uint(10**32));
		console.log("Approve tokens: allow owner to drain this contract tokens and LP");
		ERC20(tokenA).approve(owner(), uint(10**32)); //in case of problem can drain contract through governance decision
		ERC20(tokenB).approve(owner(), uint(10**32));
		IUniswapV2Pair(swapPair).approve(owner(), uint(2**250));
	}

	
	
	/// VARIOUS HELPFUL STUFF
	
	/// @notice Returns the number of loans 
	function loansCount () public view returns (uint256)
	{
		return loans.length;
	}
	
	
	function getPoolInfo () 
		public 
		view
		returns (string memory name, string memory ammName, string memory pair, uint256 poolValue, uint256 myPoolValue, uint usageRatio, bool isEnabled) 
	{
		uint _poolValue = valueOfTokensInLp(totalSupply());
		uint _myPoolValue = valueOfTokensInLp(balanceOf(msg.sender));
		
		return (name, amm, pairName, _poolValue, _myPoolValue, getUsageRatio(), isPoolEnabled );
	}
	

	
	/// LIQUIDITY MANAGEMENT FUNCTIONS
	
	
	/// @notice Gets the current LP balance of this pool
	function poolLpBalance() public view returns (uint256)
	{
		return IUniswapV2Pair(swapPair).balanceOf(address(this));
	}
	
	
	/// @notice Calculates the amount of underlying LP equivalent to the amount of VMM tokens provided
	function valueOfTokensInLp(uint256 amountVMTokens) public view returns (uint256 tokenValueInLp)
	{
		// valueOfTokensInLp / totalLP = amountVMTokens / totalSupply
		if ( totalSupply() == 0 ) return 0;
		return amountVMTokens * poolLpBalance() / totalSupply() ;
	}


	/// @notice Add LP tokens liquidity to this lending contract
	/// @param amountLpTokens Amount of LP tokens provided
	function addLPLiquidity(uint256 amountLpTokens) public returns (uint256 addedLiquidity)
	{
		require ( isPoolEnabled == true, "POOL_DISABLED");
		
		// calculate share of pool added by user: addedLP / totalLP = addedSupply / totalSupply
		uint256 addedSupply = amountLpTokens;
		lpSupply += amountLpTokens;
		uint256 totalLPBalance = IUniswapV2Pair(swapPair).balanceOf(address(this));
		
		if ( poolLpBalance() > 0 )
			addedSupply = amountLpTokens * totalSupply() / totalLPBalance ;
			
		_mint(msg.sender, addedSupply);
		IUniswapV2Pair(swapPair).transferFrom(msg.sender, address(this), amountLpTokens);
		setInterestRates(getUsageRatio());
		return addedSupply;
	}
	
	
	/// @notice Withdraws LP tokens
	function withdrawLPLiquidity(uint256 amountVMTokens) public returns (uint256 removedSupply)
	{
		// calculate share of pool removed by user: removedLP / totalLP = removedSupply / totalSupply
		uint256 removedLPs = valueOfTokensInLp(amountVMTokens);
		_burn(msg.sender, amountVMTokens);
		
		lpSupply -= removedLPs;
		IUniswapV2Pair(swapPair).transfer(msg.sender, removedLPs);
		setInterestRates(getUsageRatio());
		return removedLPs;
	}
	
	
	
	
	/// @notice Usage ratio of the lending pool scaled by 1e4 (or would always be < 1 so 0)
	function getUsageRatio() public view returns (uint)
	{
		if ( lpSupply == 0 ) return 0;
		else return lpOutstanding * 1e4 / lpSupply;
	}
	
	
	/// @notice Get lp interest rates based on usage ratio
	function getLendingInterestRates () public view returns (uint supplyInterestRate, uint borrowInterestRate )
	{
		return getInterestRates( getUsageRatio() );
	}
	
	
	
	

	/// VALUE AND RISK CALCULATIONS FUNCTIONS
	
	
	/**
	 * We want at any time the loan to be solvent with a security margin
	 * Since LP tokens are sold we want to make sure that the value of those LP (+fees) to return remain below the amountCollateral + totalLoanTokens
	 *
	 * ValueLoanInCTokens = amountCollateral + totalLoanTokens //CToken = Collateral Token
	 *
	 * LPValueInCTokens * risk_margin < amountCollateral + totalLoanTokens
	 *
	 * RiskRatio:  (amountCollateral + totalLoanTokens) / LPValueInCTokens
	 * Health/Risk Ratio should stay above liquidationThresholdInPercent 
	 * liquidationThresholdInPercentshould be above liquidationFeeInPercent
	 **/
	
	
	/// @notice Calculates the calue of some LP tokens in terms of one of the pair tokens
	function calculateValueLpInToken(uint256 amountLpToken, address targetToken) public view returns (uint256 valueLpTokens)
	{
		// amountLpToken / totalSupplyLp = amountTokenA / reserveTokenA //then multiply by 2 because eq. value of token B
		(uint reserve0, uint reserve1,) = IUniswapV2Pair(swapPair).getReserves();
		uint totalSupplyLp = IUniswapV2Pair(swapPair).totalSupply();
		
		if ( targetToken == tokenA ) return reserve0 * 2 * amountLpToken / totalSupplyLp;
		else return reserve1 * 2 * amountLpToken / totalSupplyLp;
	}
	
	
	/// @notice Returns the collateral ratio in % for a given amount of tokens
	function calculateRatio(uint256 amountLpBorrowed, address addressToken, uint256 amountToken) public view returns (uint256 riskRatio)
	{
		uint256 lpValueInCToken = calculateValueLpInToken(amountLpBorrowed, addressToken);
		require(amountLpBorrowed > 0 && lpValueInCToken > 0, "VPMOOL_BORROW_BELOW_LIMIT");
		return (lpValueInCToken + amountToken) * 100 / lpValueInCToken; // Want
	}
	

	/// @notice Calculate the risk ratio based on collateral locked
	function calculateLoanRiskRatio (uint256 loanId) public view returns (uint256 riskInPercent)
	{
		require ( loanId < loans.length, "No such loan");
		Loan memory loan = loans[loanId];
		console.log('will calculate loanriskraio');
		uint256 borrowedValueInCToken = calculateValueLpInToken(loan.amountLpBorrowed + calculateFeeInLp(loanId), loan.addressCollateral);
		console.log("got borrowed value %s", borrowedValueInCToken);
		//ratio is (outstanding LP loan value + collateral) / totalLoanTokens
		//at the beginning, borrowedValueInCToken = totalLoanTokens, but as borrowedValueInCToken increases (if only just because of interest rates), ratio goes lower
		uint tToken = loan.totalLoanTokens;
		
		console.log("will make calc ttoken %s amountC %c borrowedValueInCToken %s", tToken, loan.amountCollateral, borrowedValueInCToken);
		return ( tToken + loan.amountCollateral) * 100 / borrowedValueInCToken;
	}
	


	/// @notice Calculates the total outstanding fee for a loan, in LP tokens to be repaid on top of borrowed amount
	function calculateFeeInLp(uint256 loanId ) 
		public view
		returns (uint256 feeInLp)
	{
		uint averageLoanRate = calculateAverageInterestRate(getUsageRatio(), loans[loanId].startDate, loans[loanId].startRate );
		//1y == 31536000 seconds 
		console.log("Loan duration %s", block.timestamp - loans[loanId].startDate);
		console.log("Loan fee rate", averageLoanRate);
		
		console.log("Numderateur %s", (block.timestamp - loans[loanId].startDate)* loans[loanId].amountLpBorrowed );
		uint owed = (block.timestamp - loans[loanId].startDate) * loans[loanId].amountLpBorrowed * averageLoanRate / 10**18 / 31536000;
		return owed; //currently fixed 1%, easy to calculate
	}

	

	/// LENDING FUNCTIONS


	/// @notice Borrow LP tokens with token A or B as collateral
	function borrowLpTokens (uint256 loanId, uint256 amountLpBorrowed, address addressCollateral, uint256 amountCollateral ) public returns (uint256 newLoanId)
	{
		// create new loan or TODO: borrow more in an existing loan
		// we dont transfer LP directly, we execute a strategy: sell LP, keep collateral tokens and swap the other one
		require ( isPoolEnabled == true, "POOL_DISABLED");
		require ( ERC20(addressCollateral).balanceOf(msg.sender) >= amountCollateral, "INSUFFICIENT_COLLATERAL_AVAILABLE");
		
		// if loanId === 0 we open a new loan
		require (loanId == 0, "Borrow more from loan: not implemented");
		
		// step 0: cant borrow more than whatever limit is set later, certainly not more than aailble in pool
		require ( amountLpBorrowed < totalSupply(), "INSUFFICIENT_LP_LIQUIDITY");

		// step 1: require that collateral at least liquidationThresholdInPercent+liquidationFees
		require ( calculateRatio(amountLpBorrowed, addressCollateral, amountCollateral ) >= liquidationThresholdInPercent, "COLLATERAL_RATIO_TOO_LOW" );
		
		console.log("Borrow: collateral ok, ratio: %s", calculateRatio(amountLpBorrowed, addressCollateral, amountCollateral ));
		
		// step 2: tokens are borrowed, we remove the underlying liquidity
		(uint amountA, uint amountB) = IUniswapV2Router02(swapRouter).removeLiquidity(
			tokenA,
			tokenB,
			amountLpBorrowed,
			1,
			1,
			address(this),
			2641641186768 //in a long time
		);
		
		console.log("Borrow: removed liquidity, received token A amount: %s", amountA);
		console.log("Borrow: removed liquidity, received token B amount: %s", amountB);
		
		console.log("Amount A received by removeLiqc%s", amountA);
		console.log("Balance token A %s", IUniswapV2Pair(tokenA).balanceOf(address(this)) );
		console.log("Amount B received by removeLiq %s", amountB);
		console.log("Balance token B %s", IUniswapV2Pair(tokenB).balanceOf(address(this)) );

		// step 3: keep all collateral tokens and swap the other one for more
		uint[] memory amounts;
		address[] memory path = new address[](2);
		if ( addressCollateral == tokenA ) {
			path[0] = tokenB;
			path[1] = tokenA;
			amounts = IUniswapV2Router02(swapRouter).swapExactTokensForTokens(
				amountB,
				1,
				path,
				address(this),
				block.timestamp + 100000
			);
		}
		else {
			path[0] = tokenA;
			path[1] = tokenB;
			amounts = IUniswapV2Router02(swapRouter).swapExactTokensForTokens(
				amountA,
				1,
				path,
				address(this),
				block.timestamp + 100000
			);
		}
		console.log("Borrow: Swapped amounts[0] and received amounts[1]: %s", amounts[1]);
		require ( amounts[0] == amountA || amounts[0] == amountB, "Error while swapping borrowed tokens" );
		
		
		// step 4: record loan total token balance
		uint totalLoanTokens = amounts[1] + (addressCollateral == tokenA ? amountA : amountB);
		lpOutstanding += amountLpBorrowed;
		setInterestRates(getUsageRatio());

		// step 5: transfer the collateral here
		ERC20(addressCollateral).transferFrom(msg.sender, address(this), amountCollateral );
		
		// step 6: save loan
		loans.push( Loan({ 
			owner: msg.sender,
			amountLpBorrowed: amountLpBorrowed, 
			addressCollateral: addressCollateral, 
			amountCollateral: amountCollateral,
			amountReturned: 0,
			totalLoanTokens: totalLoanTokens,
			isOpen: true,
			startDate: block.timestamp,
			startRate: averageInterestRate
			
		}));
		
		return loans.length - 1;
	}
	
	



	
	
	/// @notice Repays a loan by buying back the missing token, adding liquidity then returning the LP tokens to the pool
	// TODO: partially repay
	function liquidateLoan (uint256 loanId) public returns (uint256 returnedToBorrower)
	{
		Loan memory loan = loans[loanId];
		
		require ( loan.isOpen == true, "LOAN_ALREADY_CLOSED" );
		uint healthRatio = calculateLoanRiskRatio(loanId);
		require ( msg.sender == loan.owner || healthRatio < liquidationThresholdInPercent, "CANNOT_LIQUIDATE_ABOVE_THRESHOLD" );
		
		// Step 1: how much LP tokens we owe, and the value of underlying tokens
		uint amountLpToReturn = loans[loanId].amountLpBorrowed + calculateFeeInLp(loanId);
		uint amountA = calculateValueLpInToken(amountLpToReturn, tokenA) / 2;
		uint amountB = calculateValueLpInToken(amountLpToReturn, tokenB) / 2;
		
		// Step 2: swap the collateral for the exact missing token
		uint[] memory amounts;
		address[] memory path = new address[](2);
		if ( loan.addressCollateral == tokenA ) {
			path[0] = tokenA;
			path[1] = tokenB;
			amounts = IUniswapV2Router02(swapRouter).swapTokensForExactTokens(
				amountB,
				loan.amountCollateral + loan.totalLoanTokens, // cant swap more than what's in the loan or losses would be taken by whole pool, leak pb
				path,
				address(this),
				block.timestamp + 100000
			);
		}
		else {
			path[0] = tokenB;
			path[1] = tokenA;
			amounts = IUniswapV2Router02(swapRouter).swapTokensForExactTokens(
				amountA,
				loan.amountCollateral + loan.totalLoanTokens,
				path,
				address(this),
				block.timestamp + 100000
			);
		}
		console.log("We should have swapped, we ahve swapped %s for %s", amounts[0], amounts[1] );

		// Step 3: addLiquidity 
		(uint amountAReturned, uint amountBReturned, uint liquidity) = IUniswapV2Router02(swapRouter).addLiquidity(
			tokenA,
			tokenB,
			amountA,
			amountB,
			1,
			1,
			address(this),
			block.timestamp + 100000
		);
		lpOutstanding -= liquidity;
		setInterestRates(getUsageRatio());
		
		console.log("Liquidate: Returning LP tokens to the pool: %s", liquidity);
		uint remainingTokens = loan.totalLoanTokens + loan.amountCollateral;
		remainingTokens = remainingTokens - amounts[0] - (
										loans[loanId].addressCollateral == tokenA ? amountAReturned : amountBReturned
									);
		
		// Step 4: if owner closes the loan he gets all back, else liquidation fee is sent to msg.sender
		uint returnedTokensToBorrower = remainingTokens;
		console.log("Return to borrower %s, balance here %s",returnedTokensToBorrower, ERC20(loan.addressCollateral).balanceOf(address(this)));
		
		if ( msg.sender == loan.owner ){
			ERC20(loans[loanId].addressCollateral).transfer(loan.owner, returnedTokensToBorrower );
		}
		else {
			// Liquidation by a 3rd party, who gets a % of loan value
			
			uint liqFeeInTokens = liquidationFeeInPercent * loan.totalLoanTokens / 100;
			if ( liqFeeInTokens < remainingTokens ){
				returnedTokensToBorrower = returnedTokensToBorrower - liqFeeInTokens;
				ERC20(loan.addressCollateral).transfer(loan.owner, returnedTokensToBorrower );
				
			}
			else {
				returnedTokensToBorrower = 0;
			}
			
			ERC20(loan.addressCollateral).transfer(msg.sender, liqFeeInTokens );
		}
		
		loans[loanId].isOpen = false;
		loans[loanId].amountReturned = returnedTokensToBorrower;
		return returnedTokensToBorrower;
	}
	
	

}
