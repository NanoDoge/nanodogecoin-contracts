// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

interface IDividendDistributor {
  function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution) external;
  function setShare(address shareholder, uint256 amount) external;
  function deposit() external payable;
  function process(uint256 gas) external;
}