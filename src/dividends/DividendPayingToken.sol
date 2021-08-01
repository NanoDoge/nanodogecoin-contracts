// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import '@openzeppelin/contracts/access/Ownable.sol';

import './IDividendPayingToken.sol';
import './IDividendPayingTokenOptional.sol';

import './../pancakeswap/ERC20.sol';

contract DividendPayingToken is
  Ownable,
  IDividendPayingToken,
  IDividendPayingTokenOptional,
  ERC20
{
  // With `magnitude`, we can properly distribute dividends even if the amount of received ether is small.
  // For more discussion about choosing the value of `magnitude`,
  //  see https://github.com/ethereum/EIPs/issues/1726#issuecomment-472352728
  uint256 constant internal magnitude = 2**128;

  uint256 internal magnifiedDividendPerShare;
  uint256 internal lastAmount;

  address public immutable _dividendToken;

  // About dividendCorrection:
  // If the token balance of a `_user` is never changed, the dividend of `_user` can be computed with:
  //   `dividendOf(_user) = dividendPerShare * balanceOf(_user)`.
  // When `balanceOf(_user)` is changed (via transferring tokens),
  //   `dividendOf(_user)` should not be changed,
  //   but the computed value of `dividendPerShare * balanceOf(_user)` is changed.
  // To keep the `dividendOf(_user)` unchanged, we add a correction term:
  //   `dividendOf(_user) = dividendPerShare * balanceOf(_user) + dividendCorrectionOf(_user)`,
  //   where `dividendCorrectionOf(_user)` is updated whenever `balanceOf(_user)` is changed:
  //   `dividendCorrectionOf(_user) = dividendPerShare * (old balanceOf(_user)) - (new balanceOf(_user))`.
  // So now `dividendOf(_user)` returns the same value before and after `balanceOf(_user)` is changed.
  mapping(address => int256) internal magnifiedDividendCorrections;
  mapping(address => uint256) internal withdrawnDividends;

  uint256 public totalDividendsDistributed;

  constructor(
    string memory _name,
    string memory _symbol,
    address dividendToken_
  ) ERC20(_name, _symbol) {
    _dividendToken = dividendToken_;
  }

  function decimals() public pure override returns(uint8) {
    return 9;
  }

  function distributeRewardDividends(uint256 amount)
    external
    override
    onlyOwner
  {
    require(totalSupply() > 0);

    if(amount > 0) {
      magnifiedDividendPerShare += (amount * magnitude) / totalSupply();
      totalDividendsDistributed += amount;

      emit DividendsDistributed(msg.sender, amount);
    }
  }

  /// @notice Withdraws the ether distributed to the sender.
  /// @dev It emits a `DividendWithdrawn` event if the amount of withdrawn ether is greater than 0.
  function withdrawDividend()
    public
    virtual
    override
  {
    _withdrawDividendOfUser(payable(msg.sender));
  }

  /// @notice Withdraws the ether distributed to the sender.
  /// @dev It emits a `DividendWithdrawn` event if the amount of withdrawn ether is greater than 0.
  function _withdrawDividendOfUser(address payable user)
    internal
    returns(uint256)
  {
    uint256 _withdrawableDividend = withdrawableDividendOf(user);

    if(_withdrawableDividend > 0) {
      withdrawnDividends[user] += _withdrawableDividend;

      bool success = IERC20(_dividendToken).transfer(user, _withdrawableDividend);

      if(!success) {
        withdrawnDividends[user] -= _withdrawableDividend;
        return 0;
      }

      emit DividendWithdrawn(user, _withdrawableDividend);
      return _withdrawableDividend;
    }

    return 0;
  }

  /// @notice View the amount of dividend in wei that an address can withdraw.
  /// @param _owner The address of a token holder.
  /// @return The amount of dividend in wei that `_owner` can withdraw.
  function dividendOf(address _owner)
    public
    view
    override
    returns(uint256)
  {
    return withdrawableDividendOf(_owner);
  }

  /// @notice View the amount of dividend in wei that an address can withdraw.
  /// @param _owner The address of a token holder.
  /// @return The amount of dividend in wei that `_owner` can withdraw.
  function withdrawableDividendOf(address _owner)
    public
    view
    override
    returns(uint256)
  {
    return accumulativeDividendOf(_owner) - withdrawnDividends[_owner];
  }

  /// @notice View the amount of dividend in wei that an address has withdrawn.
  /// @param _owner The address of a token holder.
  /// @return The amount of dividend in wei that `_owner` has withdrawn.
  function withdrawnDividendOf(address _owner)
    public
    view
    override
    returns(uint256)
  {
    return withdrawnDividends[_owner];
  }

  /// @notice View the amount of dividend in wei that an address has earned in total.
  /// @dev accumulativeDividendOf(_owner) = withdrawableDividendOf(_owner) + withdrawnDividendOf(_owner)
  /// = (magnifiedDividendPerShare * balanceOf(_owner) + magnifiedDividendCorrections[_owner]) / magnitude
  /// @param _owner The address of a token holder.
  /// @return The amount of dividend in wei that `_owner` has earned in total.
  function accumulativeDividendOf(address _owner)
    public
    view
    override
    returns(uint256)
  {
    int256 accumulativeDividends = int256(magnifiedDividendPerShare * balanceOf(_owner));
    accumulativeDividends += magnifiedDividendCorrections[_owner];

    return uint256(accumulativeDividends) / magnitude;
  }

  /// @dev Internal function that transfer tokens from one address to another.
  /// Update magnifiedDividendCorrections to keep dividends unchanged.
  /// @param from The address to transfer from.
  /// @param to The address to transfer to.
  /// @param value The amount to be transferred.
  function _transfer(address from, address to, uint256 value)
    internal
    virtual
    override
  {
    int256 _magCorrection = int256(magnifiedDividendPerShare * value);

    magnifiedDividendCorrections[from] += _magCorrection;
    magnifiedDividendCorrections[to] -= _magCorrection;
  }

  function _distributeDividendTokens(address account, uint256 value) internal {
    require(account != address(0), 'ZERO_ADDRESS');

    _beforeTokenTransfer(address(0), account, value);

    _totalSupply += value;
    _balances[account] += value;
    emit Transfer(address(0), account, value);

    _afterTokenTransfer(address(0), account, value);

    magnifiedDividendCorrections[account] -= int256(magnifiedDividendPerShare * value);
  }

  function _destroyDividendTokens(address account, uint256 value) internal {
    require(account != address(0), 'ZERO_ADDRESS');

    _beforeTokenTransfer(account, address(0), value);

    uint256 accountBalance = _balances[account];

    require(accountBalance >= value, 'Destroy amount exceeds balance');

    unchecked {
      _balances[account] = accountBalance - value;
    }

    _totalSupply -= value;

    emit Transfer(account, address(0), value);

    _afterTokenTransfer(account, address(0), value);

    magnifiedDividendCorrections[account] += int256(magnifiedDividendPerShare * value);
  }

  function _setBalance(address account, uint256 newBalance) internal {
    uint256 currentBalance = balanceOf(account);

    if(newBalance > currentBalance) {
      uint256 rewardAmount = newBalance - currentBalance;
      _distributeDividendTokens(account, rewardAmount);
    } else if(newBalance < currentBalance) {
      uint256 burnAmount = currentBalance - newBalance;
      _destroyDividendTokens(account, burnAmount);
    }
  }

  receive() external payable {}
}
