// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

import './pancakeswap/IPancakeFactory.sol';
import './pancakeswap/IPancakePair.sol';
import './pancakeswap/IPancakeRouter02.sol';

interface INanoDogeCoin is IERC20, IERC20Metadata {
  event UpdateDividendTracker(
    address indexed newAddress,
    address indexed oldAddress
  );

  event UpdateUniswapV2Router(
    address indexed newAddress,
    address indexed oldAddress
  );

  event ExcludeFromFees(
    address indexed account,
    bool isExcluded
  );

  event ExcludeMultipleAccountsFromFees(
    address[] accounts,
    bool isExcluded
  );

  event SetAutomatedMarketMakerPair(
    address indexed pair,
    bool indexed value
  );

  event LiquidityWalletUpdated(
    address indexed newLiquidityWallet,
    address indexed oldLiquidityWallet
  );

  event GasForProcessingUpdated(
    uint256 indexed newValue,
    uint256 indexed oldValue
  );

  event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);
  event SwapAndLiquifyEnabledUpdated(bool enabled);

  event SwapAndLiquify(
    uint256 half,
    uint256 newBalance,
    uint256 otherHalf
  );

  event ProcessedDividendTracker(
    uint256 iterations,
    uint256 claims,
    uint256 lastProcessedIndex,
    bool indexed automatic,
    uint256 gas,
    address indexed processor
  );

  event SniperCaught(address sniperAddress);

  event SendDividends(
    uint256 tokensSwapped,
    uint256 amount
  );

  function increaseAllowance(address spender, uint256 addedValue)
    external
    returns(bool);

  function decreaseAllowance(address spender, uint256 subtractedValue)
    external
    returns(bool);

  function isSniper(address account) external view returns(bool);

  // There is no way to add to the blacklist except through the initial sniper check.
  // But this can remove from the blacklist if someone human somehow made it onto the list.
  function removeSniper(address account) external;
  function setSniperProtectionEnabled(bool enabled) external;

  // Adjusted to allow for smaller than 1%'s, as low as 0.1%
  function setMaxTxPercent(uint256 _maxTxPercent) external;
  function maxTxAmountUI() external view returns(uint256);
  function setMaxWalletPercent(uint256 maxWalletPercent_) external;
  function maxWalletUI() external view returns(uint256);
  function setSwapAndLiquifyEnabled(bool _enabled) external;
  function excludeFromDividends(address exclude) external;
  function excludeFromFee(address account) external;
  function includeInFee(address account) external;
  function excludeFromMaxWallet(address account) external;
  function includeInMaxWallet(address account) external;
  function excludeFromMaxTx(address account) external;
  function includeInMaxTx(address account) external;

  function setDxSaleAddress(address dxRouter, address presaleRouter) external;
  function setAutomatedMarketMakerPair(address pair, bool value) external;

  function updateClaimWait(uint256 claimWait) external;

  function getClaimWait() external view returns(uint256);

  function getTotalDividendsDistributed() external view returns(uint256);
  function withdrawableDividendOf(address account) external view returns(uint256);
  function dividendRewardTokenBalanceOf(address account) external view returns(uint256);

  function getAccountDividendsInfo(address account)
    external
    view
    returns(
      address,
      int256,
      int256,
      uint256,
      uint256,
      uint256,
      uint256,
      uint256
    );

  function getAccountDividendsInfoAtIndex(uint256 index)
    external
    view
    returns(
      address,
      int256,
      int256,
      uint256,
      uint256,
      uint256,
      uint256,
      uint256
    );

  function processDividendTracker(uint256 gas) external;
  function claim() external;
  function getLastProcessedIndex() external view returns(uint256);
  function getNumberOfDividendTokenHolders() external view returns(uint256);

  function isExcludedFromFee(address account) external view returns(bool);
  function isExcludedFromMaxTx(address account) external view returns(bool);
  function isExcludedFromMaxWallet(address account) external view returns(bool);
  function withdrawLockedETH(address recipient) external;

  // withdraw any tokens that are not supposed to be insided this contract.
  function withdrawLockedTokens(address recipient, address _token) external;
  function setMarketingWallet(address payable newWallet) external;
  function setLiquidityWallet(address payable newWallet) external;
  function updateDividendTracker(address newAddress) external;
  function changeFees(uint256 liquidityFee, uint256 marketingFee, uint256 usdtFee)  external;
}