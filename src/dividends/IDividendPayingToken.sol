// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

interface IDividendPayingToken {
  function dividendOf(address _owner) external view returns(uint256);
  function distributeRewardDividends(uint256 amount) external;
  function withdrawDividend() external;

  event DividendsDistributed(address indexed from, uint256 weiAmount);
  event DividendWithdrawn(address indexed to, uint256 weiAmount);
}