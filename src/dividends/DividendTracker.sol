// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import './DividendPayingToken.sol';

library IterableMapping {
  // iterable mapping from address to uint;
  struct Map {
    address[] keys;
    mapping(address => uint) values;
    mapping(address => uint) indexOf;
    mapping(address => bool) inserted;
  }

  function get(Map storage map, address key)
    internal
    view
    returns(uint)
  {
    return map.values[key];
  }

  function getIndexOfKey(Map storage map, address key)
    internal
    view
    returns(int)
  {
    if(!map.inserted[key]) {
      return -1;
    }

    return int(map.indexOf[key]);
  }

  function getKeyAtIndex(Map storage map, uint index)
    internal
    view
    returns(address)
  {
    return map.keys[index];
  }

  function size(Map storage map)
    internal
    view
    returns(uint)
  {
    return map.keys.length;
  }

  function set(Map storage map, address key, uint val) internal {
    if(map.inserted[key]) {
      map.values[key] = val;
    } else {
      map.inserted[key] = true;
      map.values[key] = val;
      map.indexOf[key] = map.keys.length;
      map.keys.push(key);
    }
  }

  function remove(Map storage map, address key) internal {
    if(!map.inserted[key]) {
      return;
    }

    delete map.inserted[key];
    delete map.values[key];

    uint index = map.indexOf[key];
    uint lastIndex = map.keys.length - 1;
    address lastKey = map.keys[lastIndex];

    map.indexOf[lastKey] = index;
    delete map.indexOf[key];

    map.keys[index] = lastKey;
    map.keys.pop();
  }
}

contract DividendTracker is DividendPayingToken {
  using IterableMapping for IterableMapping.Map;

  IterableMapping.Map private tokenHoldersMap;
  uint256 public lastProcessedIndex;

  mapping(address => bool) public excludedFromDividends;
  mapping(address => uint256) public lastClaimTimes;

  uint256 public claimWait;
  uint256 public immutable minimumTokenBalanceForDividends;

  event ExcludeFromDividends(address indexed account);

  event ClaimWaitUpdated(
    uint256 indexed newValue,
    uint256 indexed oldValue
  );

  event Claim(
    address indexed account,
    uint256 amount,
    bool indexed automatic
  );

  constructor(
    string memory name_,
    string memory symbol_,
    address dividendTokenAddress_,
    uint256 claimWait_
  ) DividendPayingToken(
    string(abi.encodePacked(name_, ': Dividend Tracker')),
    string(abi.encodePacked(symbol_, '_DIVIDEND_TRACKER')),

    dividendTokenAddress_
  ) {
    claimWait = claimWait_;
    minimumTokenBalanceForDividends = 1_000_000_000 * 10**9; // must hold 1 billion tokens which equates to 0.0001% of the total NanoDogeCoin supply
  }

  function _transfer(address, address, uint256)
    internal
    pure
    override
  {
    require(false, 'DividendTracker: No transfers allowed');
  }

  function withdrawDividend()
    public
    pure
    override
  {
    require(false, 'DividendTracker: withdrawDividend disabled. Use the \'claim\' function on the main contract.');
  }

  function excludeFromDividends(address account) external onlyOwner {
    require(!excludedFromDividends[account]);
    excludedFromDividends[account] = true;

    _setBalance(account, 0);
    tokenHoldersMap.remove(account);

    emit ExcludeFromDividends(account);
  }

  function updateClaimWait(uint256 newClaimWait) external onlyOwner {
    require(newClaimWait >= 3600 && newClaimWait <= 86400, 'DividendTracker: claimWait must be updated to between 1 and 24 hours');
    require(newClaimWait != claimWait, 'DividendTracker: Cannot update claimWait to same value');

    emit ClaimWaitUpdated(newClaimWait, claimWait);

    claimWait = newClaimWait;
  }

  function getLastProcessedIndex()
    external
    view
    returns(uint256)
  {
    return lastProcessedIndex;
  }

  function getNumberOfTokenHolders()
    external
    view
    returns(uint256)
  {
    return tokenHoldersMap.keys.length;
  }

  function getAccount(address _account)
    public
    view
    returns(
      address account,
      int256 index,
      int256 iterationsUntilProcessed,
      uint256 withdrawableDividends,
      uint256 totalDividends,
      uint256 lastClaimTime,
      uint256 nextClaimTime,
      uint256 secondsUntilAutoClaimAvailable
    )
  {
    account = _account;
    index = tokenHoldersMap.getIndexOfKey(account);
    iterationsUntilProcessed = -1;

    if(index >= 0) {
      if(uint256(index) > lastProcessedIndex) {
        iterationsUntilProcessed = index - int256(lastProcessedIndex);
      } else {
        uint256 processesUntilEndOfArray = tokenHoldersMap.keys.length > lastProcessedIndex
          ? tokenHoldersMap.keys.length - lastProcessedIndex
          : 0;

        iterationsUntilProcessed = index + int256(processesUntilEndOfArray);
      }
    }

    withdrawableDividends = withdrawableDividendOf(account);
    totalDividends = accumulativeDividendOf(account);

    lastClaimTime = lastClaimTimes[account];

    nextClaimTime = lastClaimTime > 0
      ? lastClaimTime + claimWait
      : 0;

    secondsUntilAutoClaimAvailable = nextClaimTime > block.timestamp
      ? nextClaimTime - block.timestamp
      : 0;
  }

  function getAccountAtIndex(uint256 index)
    public
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
    )
  {
    if(index >= tokenHoldersMap.size()) {
      return (0x0000000000000000000000000000000000000000, -1, -1, 0, 0, 0, 0, 0);
    }

    address account = tokenHoldersMap.getKeyAtIndex(index);

    return getAccount(account);
  }

  function canAutoClaim(uint256 lastClaimTime)
    private
    view
    returns(bool)
  {
    if(lastClaimTime > block.timestamp) {
      return false;
    }

    return (block.timestamp - lastClaimTime) >= claimWait;
  }

  function setBalance(address payable account, uint256 newBalance)
    external
    onlyOwner
  {
    if(excludedFromDividends[account]) {
      return;
    }

    if(newBalance >= minimumTokenBalanceForDividends) {
      _setBalance(account, newBalance);
      tokenHoldersMap.set(account, newBalance);
    } else {
      _setBalance(account, 0);
      tokenHoldersMap.remove(account);
    }

    processAccount(account, true);
  }

  function process(uint256 gas)
    public
    returns(
      uint256,
      uint256,
      uint256
    )
  {
    uint256 numberOfTokenHolders = tokenHoldersMap.keys.length;

    if(numberOfTokenHolders == 0) {
      return (0, 0, lastProcessedIndex);
    }

    uint256 _lastProcessedIndex = lastProcessedIndex;

    uint256 gasUsed = 0;
    uint256 gasLeft = gasleft();

    uint256 iterations = 0;
    uint256 claims = 0;

    while(gasUsed < gas && iterations < numberOfTokenHolders) {
      _lastProcessedIndex += 1;

      if(_lastProcessedIndex >= tokenHoldersMap.keys.length) {
        _lastProcessedIndex = 0;
      }

      address account = tokenHoldersMap.keys[_lastProcessedIndex];

      if(canAutoClaim(lastClaimTimes[account])) {
        if(processAccount(payable(account), true)) {
          claims += 1;
        }
      }

      iterations += 1;

      uint256 newGasLeft = gasleft();

      if(gasLeft > newGasLeft) {
        gasUsed += (gasLeft - newGasLeft);
      }

      gasLeft = newGasLeft;
    }

    lastProcessedIndex = _lastProcessedIndex;

    return (iterations, claims, lastProcessedIndex);
  }

  function processAccount(address payable account, bool automatic)
    public
    onlyOwner
    returns(bool)
  {
    uint256 amount = _withdrawDividendOfUser(account);

    if(amount > 0) {
      lastClaimTimes[account] = block.timestamp;
      emit Claim(account, amount, automatic);
      return true;
    }

    return false;
  }
}