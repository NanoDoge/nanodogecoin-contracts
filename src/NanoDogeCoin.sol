// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import '@openzeppelin/contracts/utils/Address.sol';
import '@openzeppelin/contracts/utils/Context.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/access/AccessControlEnumerable.sol';

import './pancakeswap/IPancakeFactory.sol';
import './pancakeswap/IPancakePair.sol';
import './pancakeswap/IPancakeRouter02.sol';

import './dividends/DividendTracker.sol';

import './INanoDogeCoin.sol';

contract NanoDogeCoin is
  INanoDogeCoin,
  Context,
  AccessControlEnumerable,
  ReentrancyGuard
{
  using Address for address;

  mapping(address => uint256) private _balances;
  mapping(address => mapping(address => uint256)) private _allowances;

  mapping(address => bool) public automatedMarketMakerPairs;

  mapping(address => bool) private _isExcludedFromFee;
  mapping(address => bool) private _isExcludedFromMaxTx;
  mapping(address => bool) private _isExcludedFromMaxWallet;
  mapping(address => bool) private _liquidityHolders;
  mapping(address => bool) private _isSniper;

  uint256 private constant MAX = type(uint256).max;

  uint8 private _decimals = 9;
  uint256 private _totalSupply;

  string private _name;
  string private _symbol;

  uint256 public _totalFee;
  uint256 private _previousTotalFee;

  uint256 public _marketingFee;
  uint256 public _liquidityFee;
  uint256 public _dividendRewardsFee;

  uint256 private _withdrawableBalance;

  DividendTracker public dividendTracker;
  address private _dividendRewardToken;
  uint256 public gasForProcessing = 300000;

  IPancakeRouter02 public pancakeswapV2Router;
  address public pancakeswapV2Pair;

  address public burnAddress = 0x000000000000000000000000000000000000dEaD;

  address _marketingWallet;
  address _liquidityWallet;

  bool private swapping;
  bool private setPresaleAddresses = true;
  bool public maxWalletEnabled = true;

  bool inSwapAndLiquify;
  bool public swapAndLiquifyEnabled = true;

  uint256 private _maxTxDivisor = 100;
  uint256 private _maxTxAmount;
  uint256 private _previousMaxTxAmount;

  uint256 private _maxWalletDivisor = 100;
  uint256 private _maxWalletAmount;
  uint256 private _perviousMaxWalletAmount;

  uint256 private _numTokensSellToAddToLiquidity;

  bool private _sniperProtection = true;
  bool private _hasLiqBeenAdded = false;
  bool private _tradingEnabled = false;

  uint256 private _liqAddBlock = 0;
  uint256 private _snipeBlockAmount = 3;
  uint256 private _manualSnipeBlock = 300;
  uint256 public snipersCaught = 0;

  modifier lockTheSwap {
    inSwapAndLiquify = true;
    _;
    inSwapAndLiquify = false;
  }

  constructor(
    string memory name_,
    string memory symbol_,
    uint256 supply_,
    uint256 maxTxPercent_,
    uint256 maxWalletPercent_,
    uint256 liquidityThresholdPercentage_,

    uint256 liquidityFee_,
    uint256 marketingFee_,
    uint256 dividendRewardsFee_,

    address[3] memory addresses_,
    address v2Router_
  ) {
    _name = name_;
    _symbol = symbol_;
    _totalSupply = supply_ * (10**uint256(_decimals));
    _numTokensSellToAddToLiquidity = (_totalSupply * liquidityThresholdPercentage_) / 10000;

    _dividendRewardToken = addresses_[0];
    _marketingWallet = addresses_[1];
    _liquidityWallet = addresses_[2];

    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);

    _setupDividendTracker();

    setMaxTxPercent(maxTxPercent_);
    setMaxWalletPercent(maxWalletPercent_);
    changeFees(liquidityFee_, marketingFee_, dividendRewardsFee_);

    _setupPancakeswap(v2Router_);
    _setupExclusions();

    _balances[_msgSender()] = _totalSupply;
    emit Transfer(address(0), _msgSender(), _totalSupply);
  }

  function _setupPancakeswap(address _routerAddress) private {
    pancakeswapV2Router = IPancakeRouter02(_routerAddress);

    // create a pancakeswap pair for this new token
    pancakeswapV2Pair = IPancakeFactory(pancakeswapV2Router.factory())
      .createPair(address(this), pancakeswapV2Router.WETH());

    _setAutomatedMarketMakerPair(pancakeswapV2Pair, true);
  }

  function _setupExclusions() private {
    _isExcludedFromFee[msg.sender] = true;
    _isExcludedFromFee[address(this)] = true;
    _isExcludedFromFee[_marketingWallet] = true;
    _liquidityHolders[msg.sender] = true;
    _isExcludedFromMaxTx[msg.sender] = true;
    _isExcludedFromMaxTx[address(this)] = true;
    _isExcludedFromMaxTx[_marketingWallet] = true;
    _isExcludedFromMaxWallet[msg.sender] = true;
    _isExcludedFromMaxWallet[address(this)] = true;
    _isExcludedFromMaxWallet[pancakeswapV2Pair] = true;
    _isExcludedFromMaxWallet[_marketingWallet] = true;
  }

  function _setupDividendTracker() private {
    dividendTracker = new DividendTracker(
      _name,
      _symbol,
      _dividendRewardToken,
      3600 // 1h claim
    );

    dividendTracker.excludeFromDividends(address(dividendTracker));
    dividendTracker.excludeFromDividends(address(this));
    dividendTracker.excludeFromDividends(msg.sender);
    dividendTracker.excludeFromDividends(address(pancakeswapV2Router));
  }

  function name()
    public
    view
    override
    returns(string memory)
  {
    return _name;
  }

  function symbol()
    public
    view
    override
    returns(string memory)
  {
    return _symbol;
  }

  function decimals()
    public
    view
    override
    returns(uint8)
  {
    return _decimals;
  }

  function totalSupply()
    public
    view
    override
    returns(uint256)
  {
    return _totalSupply;
  }

  function balanceOf(address account)
    public
    view
    override
    returns(uint256)
  {
    return _balances[account];
  }

  function allowance(
    address owner,
    address spender
  )
    public
    view
    override
    returns(uint256)
  {
    return _allowances[owner][spender];
  }

  function approve(
    address spender,
    uint256 amount
  )
    public
    override
    returns(bool)
  {
    _approve(_msgSender(), spender, amount);
    return true;
  }

  function transfer(
    address recipient,
    uint256 amount
  )
    public
    override
    returns(bool)
  {
    _transfer(_msgSender(), recipient, amount);
    return true;
  }

  function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  )
    public
    override
    returns(bool)
  {
    _transfer(sender, recipient, amount);
    _approve(sender, _msgSender(), _allowances[sender][_msgSender()] - amount);
    return true;
  }

  function increaseAllowance(
    address spender,
    uint256 addedValue
  )
    public
    override
    returns(bool)
  {
    _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
    return true;
  }

  function decreaseAllowance(address spender, uint256 subtractedValue)
    public
    override
    returns(bool)
  {
    _approve(_msgSender(), spender, _allowances[_msgSender()][spender] - subtractedValue);
    return true;
  }

  function isSniper(address account)
    public
    view
    override
    returns(bool)
  {
    return _isSniper[account];
  }

  // There is no way to add to the blacklist except through the initial sniper check.
  // But this can remove from the blacklist if someone human somehow made it onto the list.
  function removeSniper(address account)
    external
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    require(_isSniper[account], 'Account is not a recorded sniper.');
    _isSniper[account] = false;
  }

  function setSniperProtectionEnabled(bool enabled)
    external
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    _sniperProtection = enabled;
  }

  // developers have the option to pinpoint and exclude bots from trading on launch.
  function addBotToList(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
    require(block.number - _liqAddBlock < _manualSnipeBlock);
    _isSniper[account] = true;
  }

  function enableTrading() external onlyRole(DEFAULT_ADMIN_ROLE) {
    _tradingEnabled = true;
  }

  // adjusted to allow for smaller than 1%'s, as low as 0.1%
  function setMaxTxPercent(uint256 maxTxPercent_)
    public
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    require(maxTxPercent_ >= 1); // cannot set to 0.

    // division by 1000, set to 20 for 2%, set to 2 for 0.2%
    _maxTxAmount = (_totalSupply * maxTxPercent_) / 1000;
  }

  function maxTxAmountUI()
    external
    view
    override
    returns(uint256)
  {
    return _maxTxAmount / uint256(_decimals);
  }

  // adjusted to allow for smaller than 1%'s, as low as 0.1%
  function setMaxWalletPercent(uint256 maxWalletPercent_)
    public
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    require(maxWalletPercent_ >= 1); // cannot set to 0.

    // division by 1000, set to 20 for 2%, set to 2 for 0.2%
    _maxWalletAmount = (_totalSupply * maxWalletPercent_) / 1000;
  }

  function maxWalletUI()
    external
    view
    override
    returns(uint256)
  {
    return _maxWalletAmount / uint256(_decimals);
  }

  function setSwapAndLiquifyEnabled(bool _enabled)
    external
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    swapAndLiquifyEnabled = _enabled;
    emit SwapAndLiquifyEnabledUpdated(_enabled);
  }

  function excludeFromDividends(address exclude)
    external
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    dividendTracker.excludeFromDividends(address(exclude));
  }

  function excludeFromMaxWallet(address account)
    external
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    _isExcludedFromMaxWallet[account] = true;
  }

  function includeInMaxWallet(address account)
    external
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    _isExcludedFromMaxWallet[account] = false;
  }

  function excludeFromMaxTx(address account)
    external
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    _isExcludedFromMaxTx[account] = true;
  }

  function includeInMaxTx(address account)
    external
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    _isExcludedFromMaxTx[account] = false;
  }

  function excludeFromFee(address account)
    external
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    _isExcludedFromFee[account] = true;
  }

  function includeInFee(address account)
    external
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    _isExcludedFromFee[account] = false;
  }

  function setDxSaleAddress(address dxRouter, address presaleRouter)
    external
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    require(setPresaleAddresses == true, 'You can only set the presale addresses once!');

    setPresaleAddresses = false;
    _liquidityHolders[dxRouter] = true;
    _isExcludedFromFee[dxRouter] = true;
    _liquidityHolders[presaleRouter] = true;
    _isExcludedFromFee[presaleRouter] = true;
    _isExcludedFromMaxTx[dxRouter] = true;
    _isExcludedFromMaxTx[presaleRouter] = true;
    _isExcludedFromMaxWallet[dxRouter] = true;
    _isExcludedFromMaxWallet[presaleRouter] = true;
  }

  function setAutomatedMarketMakerPair(address pair, bool value)
    external
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    require(
      pair != pancakeswapV2Pair,
      'NanoDoge: The PancakeSwap pair cannot be removed from automatedMarketMakerPairs'
    );

    _setAutomatedMarketMakerPair(pair, value);
  }

  function _setAutomatedMarketMakerPair(address pair, bool value) private {
    require(
      automatedMarketMakerPairs[pair] != value,
      'NanoDoge: Automated market maker pair is already set to that value'
    );

    automatedMarketMakerPairs[pair] = value;

    if(value) {
      dividendTracker.excludeFromDividends(pair);
    }

    emit SetAutomatedMarketMakerPair(pair, value);
  }

  function updateClaimWait(uint256 claimWait)
    external
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    dividendTracker.updateClaimWait(claimWait);
  }

  function getClaimWait()
    external
    view
    override
    returns(uint256)
  {
    return dividendTracker.claimWait();
  }

  function getTotalDividendsDistributed()
    external
    view
    override
    returns(uint256)
  {
    return dividendTracker.totalDividendsDistributed();
  }

  function withdrawableDividendOf(address account)
    external
    view
    override
    returns(uint256)
  {
    return dividendTracker.withdrawableDividendOf(account);
  }

  function dividendRewardTokenBalanceOf(address account)
    external
    view
    override
    returns(uint256)
  {
    return dividendTracker.balanceOf(account);
  }

  function getAccountDividendsInfo(address account)
    external
    view
    override
    returns(
      address,
      int256,
      int256,
      uint256,
      uint256,
      uint256,
      uint256,
      uint256
    )
  {
    return dividendTracker.getAccount(account);
  }

  function getAccountDividendsInfoAtIndex(uint256 index)
    external
    view
    override
    returns(
      address,
      int256,
      int256,
      uint256,
      uint256,
      uint256,
      uint256,
      uint256
    )
  {
    return dividendTracker.getAccountAtIndex(index);
  }

  function processDividendTracker(uint256 gas) external override {
    (
      uint256 iterations,
      uint256 claims,
      uint256 lastProcessedIndex
    ) = dividendTracker.process(gas);

    emit ProcessedDividendTracker(
      iterations,
      claims,
      lastProcessedIndex,
      false,
      gas,
      tx.origin
    );
  }

  function claim() external override {
    dividendTracker.processAccount(payable(msg.sender), false);
  }

  function getLastProcessedIndex()
    external
    view
    override
    returns(uint256)
  {
    return dividendTracker.getLastProcessedIndex();
  }

  function getNumberOfDividendTokenHolders()
    external
    view
    override
    returns(uint256)
  {
    return dividendTracker.getNumberOfTokenHolders();
  }

  function _removeAllFee() private {
    if(_totalFee == 0) {
      return;
    }

    _previousTotalFee = _totalFee;
    _totalFee = 0;
  }

  function _restoreAllFee() private {
    _totalFee = _previousTotalFee;
  }

  function isExcludedFromFee(address account)
    public
    view
    override
    returns(bool)
  {
    return _isExcludedFromFee[account];
  }

  function isExcludedFromMaxTx(address account)
    public
    view
    override
    returns(bool)
  {
    return _isExcludedFromMaxTx[account];
  }

  function isExcludedFromMaxWallet(address account)
    public
    view
    override
    returns(bool)
  {
    return _isExcludedFromMaxWallet[account];
  }

  function checkWalletLimit(address to, uint256 amount)
    internal
    view
  {
    if(maxWalletEnabled) {
      uint256 contractBalanceRecepient = balanceOf(to);

      require(
        contractBalanceRecepient + amount <= _maxWalletAmount || _isExcludedFromMaxWallet[to],
        'Max Wallet Amount Exceeded'
      );
    }
  }

  function checkTxLimit(address from, address to, uint256 amount) internal view {
    if(from == pancakeswapV2Pair) {
      require(amount <= _maxTxAmount || _isExcludedFromMaxTx[to], 'TX Limit Exceeded');
    } else {
      require(amount <= _maxTxAmount || _isExcludedFromMaxTx[from], 'TX Limit Exceeded');
    }
  }

  function _approve(
    address owner,
    address spender,
    uint256 amount
  ) private {
    require(owner != address(0), 'ERC20: approve from the zero address');
    require(spender != address(0), 'ERC20: approve to the zero address');

    _allowances[owner][spender] = amount;
    emit Approval(owner, spender, amount);
  }

  function _transfer(address from, address to, uint256 amount) private {
    require(from != address(0), 'ERC20: transfer from the zero address');
    require(to != address(0), 'ERC20: transfer to the zero address');
    require(amount > 0, 'Transfer amount must be greater than zero');

    if(!_isExcludedFromFee[from] && !_isExcludedFromFee[to]) {
      require(_tradingEnabled, 'Trading is currently disabled');
    }

    checkWalletLimit(to, amount);
    checkTxLimit(from, to, amount);

    // is the token balance of this contract address over the min number of
    // tokens that we need to initiate a swap + liquidity lock?
    // also, don't get caught in a circular liquidity event.
    // also, don't swap & liquify if sender is pancakeswap pair.
    uint256 contractTokenBalance = balanceOf(address(this));

    if(contractTokenBalance >= _maxTxAmount) {
      contractTokenBalance = _maxTxAmount;
    }

    if(
      (contractTokenBalance >= _numTokensSellToAddToLiquidity)
        && !inSwapAndLiquify
        && from != pancakeswapV2Pair
        && swapAndLiquifyEnabled
    ) {
      // set inSwapAndLiquify to true so the contract isnt looping through adding liquididty
      inSwapAndLiquify = true;

      contractTokenBalance = _numTokensSellToAddToLiquidity;
      uint256 swapForLiq = (contractTokenBalance * _liquidityFee) / _totalFee;
      _swapAndLiquify(swapForLiq);

      uint256 swapForDividends = (contractTokenBalance * _dividendRewardsFee) / _totalFee;
      _swapAndSendTokenDividends(swapForDividends);

      uint256 swapForMarketing = contractTokenBalance - swapForDividends - swapForLiq;
      _swapTokensForMarketing(swapForMarketing);

      // dust ETH after executing all swaps
      _withdrawableBalance = address(this).balance;

      inSwapAndLiquify = false;
    }

    // indicates if fee should be deducted from transfer
    bool takeFee = true;

    // if any account belongs to _isExcludedFromFee account then remove the fee
    if(_isExcludedFromFee[from] || _isExcludedFromFee[to]) {
      takeFee = false;
    }

    // transfer amount, it will take tax, burn, liquidity fee
    _tokenTransfer(from, to, amount, takeFee);
  }

  function _swapAndLiquify(uint256 tokens) private {
    // split the contract balance into halves
    uint256 half = (tokens / 2);
    uint256 otherHalf = tokens - half;

    // capture the contract's current ETH balance.
    // this is so that we can capture exactly the amount of ETH that the
    // swap creates, and not make the liquidity event include any ETH that
    // has been manually sent to the contract
    uint256 initialBalance = address(this).balance;

    // swap tokens for ETH
    _swapTokensForETH(half);

    // get the delta balance from the swap
    uint256 deltaBalance = (address(this).balance - initialBalance);

    // add liquidity to pancakeswap
    _addLiquidity(otherHalf, deltaBalance);

    emit SwapAndLiquify(half, deltaBalance, otherHalf);
  }

  function _swapTokensForETH(uint256 tokenAmount) private {
    // generate the pancakeswap pair path of token -> weth
    address[] memory path = new address[](2);
    path[0] = address(this);
    path[1] = pancakeswapV2Router.WETH();

    _approve(address(this), address(pancakeswapV2Router), tokenAmount);

    // make the swap
    pancakeswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
      tokenAmount,
      0, // accept any amount of ETH
      path,
      address(this),
      block.timestamp
    );
  }

  function _swapTokensForMarketing(uint256 tokenAmount) private {
    // generate the pancakeswap pair path of token -> weth
    address[] memory path = new address[](2);
    path[0] = address(this);
    path[1] = pancakeswapV2Router.WETH();

    _approve(address(this), address(pancakeswapV2Router), tokenAmount);

    // make the swap
    pancakeswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
      tokenAmount,
      0, // accept any amount of ETH
      path,
      _marketingWallet,
      block.timestamp
    );
  }

  function withdrawLockedETH(address recipient)
    external
    override
    nonReentrant
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    require(recipient != address(0), 'Cannot withdraw the ETH balance to the zero address');
    require(_withdrawableBalance > 0, 'The ETH balance must be greater than 0');

    uint256 amount = _withdrawableBalance;
    _withdrawableBalance = 0;

    (bool success,) = payable(recipient).call{value: amount}('');

    if(!success) {
      revert();
    }
  }

  function _swapTokensForDividends(uint256 tokenAmount, address recipient) private {
    // generate the pancakeswap pair path of weth -> dividend
    address[] memory path = new address[](3);
    path[0] = address(this);
    path[1] = pancakeswapV2Router.WETH();
    path[2] = _dividendRewardToken;

    _approve(address(this), address(pancakeswapV2Router), tokenAmount);

    // make the swap
    pancakeswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
      tokenAmount,
      0, // accept any amount of tokens
      path,
      recipient,
      block.timestamp
    );
  }

  // withdraw any tokens that are not supposed to be insided this contract.
  function withdrawLockedTokens(address recipient, address _token)
    external
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    require(_token != pancakeswapV2Router.WETH());
    require(_token != address(this));

    uint256 amountToWithdraw = IERC20(_token).balanceOf(address(this));
    IERC20(_token).transfer(payable(recipient), amountToWithdraw);
  }

  function _addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
    // approve token transfer to cover all possible scenarios
    _approve(address(this), address(pancakeswapV2Router), tokenAmount);

    // add the liquidity
    pancakeswapV2Router.addLiquidityETH{value: ethAmount}(
      address(this),
      tokenAmount,
      0, // slippage is unavoidable
      0, // slippage is unavoidable
      _liquidityWallet,
      block.timestamp
    );
  }

  function _checkLiquidityAdd(address from, address to) private {
    // if liquidity is added by the _liquidityholders set trading enables to true and start the anti sniper timer
    require(!_hasLiqBeenAdded, 'Liquidity already added and marked.');

    if(_liquidityHolders[from] && to == pancakeswapV2Pair) {
      _hasLiqBeenAdded = true;
      _tradingEnabled = true;
      _liqAddBlock = block.number;
    }
  }

  // this method is responsible for taking all fee, if takeFee is true
  function _tokenTransfer(
    address sender,
    address recipient,
    uint256 amount,
    bool takeFee
  ) private {
    // failsafe, disable the whole system if needed.
    if(_sniperProtection) {
      // if sender is a sniper address, reject the sell.
      if(isSniper(sender)) {
        revert('Sniper rejected.');
      }

      // check if this is the liquidity adding tx to startup.
      if(!_hasLiqBeenAdded) {
        _checkLiquidityAdd(sender, recipient);
      } else {
        if(
          _liqAddBlock > 0
            && sender == pancakeswapV2Pair
            && !_liquidityHolders[sender]
            && !_liquidityHolders[recipient]
        ) {
          if(block.number - _liqAddBlock < _snipeBlockAmount) {
            _isSniper[recipient] = true;
            snipersCaught++;
            emit SniperCaught(recipient);
          }
        }
      }
    }

    if(!takeFee) {
      _removeAllFee();
    }

    _takeLiquidityAndTransfer(sender, recipient, amount);

    try dividendTracker.setBalance(payable(sender), balanceOf(sender)) {} catch {}
    try dividendTracker.setBalance(payable(recipient), balanceOf(recipient)) {} catch {}

    if(!inSwapAndLiquify) {
      uint256 gas = gasForProcessing;

      try dividendTracker.process(gas) returns(
        uint256 iterations,
        uint256 claims,
        uint256 lastProcessedIndex
      ) {
        emit ProcessedDividendTracker(
          iterations,
          claims,
          lastProcessedIndex,
          true,
          gas,
          tx.origin
        );
      } catch {}
    }

    if(!takeFee) {
      _restoreAllFee();
    }
  }

  function _takeLiquidityAndTransfer(
    address sender,
    address recipient,
    uint256 amount
  ) private {
    _balances[sender] -= amount;

    uint256 liquidityAmount = (amount / 100) * _totalFee;
    uint256 transferAmount = amount - liquidityAmount;

    _balances[recipient] += transferAmount;

    if(_isExcludedFromFee[sender] || _isExcludedFromFee[recipient]) {
      emit Transfer(sender, recipient, transferAmount);
      return;
    }

    _balances[address(this)] += liquidityAmount;

    emit Transfer(sender, address(this), liquidityAmount);
    emit Transfer(sender, recipient, transferAmount);
  }

  function setMarketingWallet(address payable newWallet)
    external
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    require(_marketingWallet != newWallet, 'Wallet already set!');
    _marketingWallet = newWallet;
  }

  function setLiquidityWallet(address payable newWallet)
    external
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    require(_liquidityWallet != newWallet, 'Wallet already set!');
    _liquidityWallet = newWallet;
  }

  function updateDividendTracker(address newAddress)
    external
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    require(
      newAddress != address(dividendTracker),
      'NanoDogeCoin: The dividend tracker already has that address'
    );

    DividendTracker newDividendTracker = DividendTracker(payable(newAddress));

    require(
      newDividendTracker.owner() == address(this),
      'NanoDogeCoin: The new dividend tracker must be owned by the token contract'
    );

    newDividendTracker.excludeFromDividends(address(newDividendTracker));
    newDividendTracker.excludeFromDividends(address(this));
    newDividendTracker.excludeFromDividends(msg.sender);
    newDividendTracker.excludeFromDividends(address(pancakeswapV2Router));

    emit UpdateDividendTracker(newAddress, address(dividendTracker));

    dividendTracker = newDividendTracker;
  }

  function _swapAndSendTokenDividends(uint256 tokens) private {
    _swapTokensForDividends(tokens, address(this));
    uint256 dividends = IERC20(_dividendRewardToken).balanceOf(address(this));
    bool success = IERC20(_dividendRewardToken).transfer(address(dividendTracker), dividends);

    if(success) {
      dividendTracker.distributeRewardDividends(dividends);
      emit SendDividends(tokens, dividends);
    }
  }

  function changeFees(
    uint256 liquidityFee,
    uint256 marketingFee,
    uint256 dividendFee
  )
    public
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    // fees are setup so they can not exceed 30% in total
    // and specific limits for each one.
    require(liquidityFee <= 5);
    require(marketingFee <= 5);
    require(dividendFee <= 20);

    _liquidityFee = liquidityFee;
    _marketingFee = marketingFee;
    _dividendRewardsFee = dividendFee;

    _totalFee = liquidityFee + marketingFee + dividendFee;
  }

  receive() external payable {}
}
