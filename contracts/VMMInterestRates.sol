pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: MIT


import "@openzeppelin/contracts/utils/math/SafeMath.sol";



/**
Explanation:
We dont know what's going to happen during the next period of a loan.
We average rate up to a change, before each change, then record the average, and the new current rate
Similarly after a loan finishes, we calculate the new average and compare with the average at the time the loaned was opened
From the average up to loan open and average up to loan closes, we derive average rate during the loan
*/
abstract contract VMMInterestRates {
	using SafeMath for uint256;
	
	// Min borrowing rate in % APR
	uint public minBorrowingInterestRate = 2 * 10**16; 
	
	// Max borrowing interest rate in APR 10**18
	uint public maxBorrowingInterestRate = 10**18;

	// Start date
	uint public startDate = block.timestamp - 1;
	
	// Last rate update
	uint public lastUpdateDate = block.timestamp;

	// Loast interest rate update
	uint public lastInterestRate = 2 * 10**16;
	
	// Instant interest rate in percent times 10**6 e.g, 2.45% is 2450000
	uint public averageInterestRate = 2* 10 ** 16; //on startup, interest rate is base interest rate
	
	

	
	/// @notice Calculates the instant supply and borrow rates based on pool usage
	/// @param usageRatio the usage ratio scaled by 1e4
	// In percent times 10**6, 3.69% is 3690000
	function getInterestRates( uint usageRatio ) public view returns (uint supplyInterestRate, uint borrowInterestRate )
	{
		// Interest rate is linear usage ratio between 0 and maxBorrowingInterestRate + 2 
		
		uint borrowInterestRate_ = maxBorrowingInterestRate.mul( usageRatio ).div(1e4).add( minBorrowingInterestRate );
		
		// Supply rate is what LP actually get
		uint supplyInterestRate_ = borrowInterestRate_.mul( usageRatio );
		
		return (supplyInterestRate_, borrowInterestRate_);
	}
	
	
	
	/// @notice calculates the new interest rate based on current supply/oustanding LP amounts.
	/// @param usageRatio the usage ratio scaled by 1e4
	function calculateNewInterestRate( uint usageRatio ) public view returns (uint newAverageRate, uint newInstantRate)
	{
		(, uint newBorrowInterestRate) = getInterestRates( usageRatio );
		
		if (lastUpdateDate <= startDate || lastUpdateDate >= block.timestamp ) return (0, 0);
		// calculate the past interest rate period
		// average of rates * durations
		uint newAverageRate_ = ( 
							averageInterestRate * (lastUpdateDate - startDate)
							+ lastInterestRate * ( block.timestamp - lastUpdateDate )
						) / (block.timestamp - startDate);
						
		return (newAverageRate_, newBorrowInterestRate);
	}
	
	
	
	/// @notice Updates the current interest rate. Call after any rate change (ie supply/borrow change)
	/// @param usageRatio the usage ratio scaled by 1e4
	function setInterestRates( uint usageRatio ) public 
	{
		(uint newAverageRate, uint newInstantRate ) = calculateNewInterestRate(usageRatio);
		if ( newAverageRate > 0 && newInstantRate > 0){
			averageInterestRate = newAverageRate;
			lastUpdateDate = block.timestamp;
			lastInterestRate = newInstantRate;
		}
	}
	
	
	
	/// @notice Get rate for a past period based on average before and after
	function calculateAverageInterestRate (
		uint usageRatio ,
		uint startLoanDate,
		uint startLoanRate
	)
		public view
		returns (uint averageLoanRate)
	{
		if ( block.timestamp <= startLoanDate || startLoanDate <= startDate ) return 0;
		//we recalculate the averate rate as time has passed at a new rate, but we dont update anything since it's a view
		(uint newAverageRate,) = calculateNewInterestRate( usageRatio );
		// timeline: startDate -> startLoanDate -> endDate
		// ratexTimeBeforeLoan + ratexTimeDuringLoan = ratexTimeAfterLoan
		// startLoanRate * (startLoanDate - startDate ) + averageLoanRate * (endDate - startLoanDate) = newAverageRate * ( now - startDate )
		
		uint averageLoanRate_ = ( newAverageRate * (block.timestamp - startDate ) - startLoanRate * ( startLoanDate - startDate ) ) / ( block.timestamp - startDate );
		
		return averageLoanRate_;
	}
	
	
}