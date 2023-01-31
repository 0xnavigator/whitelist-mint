// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Test.sol';
import '../src/Minter.sol';
import '../src/interfaces/IMinter.sol';
import '../src/mock/USDC.sol';

contract MinterTest is Test {
  Minter public minter;
  address public depositToken;
  uint constant SUPPLY = 100_000_000000;

  IMinter.DeployParams params;

  function setUp() public {
    depositToken = address(new USDC(SUPPLY));
    params = IMinter.DeployParams({
      name: 'Share Tokens',
      symbol: 'STO',
      depositToken: depositToken,
      minInvestmentAmount: _tokenAmount(1_000, depositToken)
    });
    minter = new Minter(params);
    ERC20(depositToken).approve(address(minter), type(uint256).max);
  }

  function testDeployment() public {
    assertTrue(keccak256(abi.encodePacked(minter.name())) == keccak256(abi.encodePacked('Share Tokens')), 'Name Check');
    assertTrue(keccak256(abi.encodePacked(minter.symbol())) == keccak256(abi.encodePacked('STO')), 'Symbol Check');
    assertTrue(ERC20(depositToken).totalSupply() == SUPPLY, 'Supply check');
    assertTrue(ERC20(minter).balanceOf(address(this)) == 150_000 ether, 'Team balance check');
  }

  function testWhitelist() public {
    address user = address(0x01);
    uint cap = _tokenAmount(10_000, depositToken);
    minter.whitelistOrEditCap(user, cap);
    _checkInvestor(user, cap, 0);
  }

  function testAddInvestorRevert() public {
    address user = address(0x01);
    uint cap = _tokenAmount(10_000, depositToken);
    minter.whitelistOrEditCap(user, cap);
    vm.expectRevert(bytes('Minter: Cap already set'));
    minter.whitelistOrEditCap(user, cap);
  }

  function testChangeCapAfterDepositRevert() public {
    address user = address(this);
    uint amount = _tokenAmount(2_000, depositToken);
    uint cap = _tokenAmount(10_000, depositToken);
    minter.whitelistOrEditCap(user, cap);
    minter.deposit(amount);
    vm.expectRevert(bytes('Minter: Cap must be higher than deposited amount'));
    minter.whitelistOrEditCap(user, 1_000_000000);
  }

  function testChangeCap() public {
    address user = address(0x01);
    uint cap = _tokenAmount(10_000, depositToken);
    minter.whitelistOrEditCap(user, cap);
    minter.whitelistOrEditCap(user, cap / 2);
    _checkInvestor(user, cap / 2, 0);
  }

  function testCloseRaise() public {
    minter.closeRaise();
    assertTrue(ERC20(minter).balanceOf(address(this)) == 300_000 ether, 'Team balance check');
  }

  function testDepositAfterCloseRaiseRevert() public {
    uint amount = _tokenAmount(10_000, depositToken);
    minter.closeRaise();
    vm.expectRevert(bytes('Minter: Raise is no longer active'));
    minter.deposit(amount);
  }

  function testDepositNonWhitelistRevert() public {
    uint amount = _tokenAmount(10_000, depositToken);
    vm.expectRevert(bytes('Minter: User not whitelisted'));
    minter.deposit(amount);
  }

  function testDepositMinInvestmentAmountRevert() public {
    uint cap = _tokenAmount(1_000, depositToken);
    uint amount = _tokenAmount(100, depositToken);
    minter.whitelistOrEditCap(address(this), cap);
    vm.expectRevert(bytes('Minter: Amount must be higher than minimum investment amount'));
    minter.deposit(amount);
  }

  function testInvestorCapReachedRevert() public {
    uint cap = _tokenAmount(1_000, depositToken);
    uint amount = _tokenAmount(1_000, depositToken);
    minter.whitelistOrEditCap(address(this), cap);
    minter.deposit(amount);
    vm.expectRevert(bytes('Minter: Investor cap already reached'));
    minter.deposit(amount);
  }

  function testMintedAmount() public {
    address user = address(0x01);
    uint cap = _tokenAmount(1_000, depositToken);
    uint amount = _tokenAmount(1_000, depositToken);
    _depositFlow(user, cap, amount);
    assertTrue(minter.balanceOf(address(user)) == 1_000 ether, 'STO balance check');
  }

  function testPartialMint() public {
    address user = address(0x01);
    uint initialBalance = type(uint).max;
    uint cap = _tokenAmount(10_000, depositToken);
    uint amount = _tokenAmount(1_000, depositToken);
    _depositFlow(user, cap, amount);
    _checkInvestor(user, cap, amount);
    vm.startPrank(user);
    minter.deposit(amount);
    _checkInvestor(user, cap, amount * 2);
    minter.deposit(cap);
    _checkInvestor(user, cap, cap);
    assertTrue(minter.balanceOf(address(user)) == 10_000 ether, 'STO balance check');
    assertTrue(ERC20(depositToken).balanceOf(address(user)) == initialBalance - cap);
  }

  function testPullFunds() public {
    address recipient = address(0x01);
    uint cap = _tokenAmount(10_000, depositToken);
    uint amount = _tokenAmount(10_000, depositToken);
    minter.whitelistOrEditCap(address(this), cap);
    minter.deposit(amount);
    minter.pullFunds(recipient);
    assertTrue(
      ERC20(depositToken).balanceOf(recipient) == _tokenAmount(10_000, depositToken),
      'Deposit token balance check'
    );
  }

  function testDepositAboveCap() public {
    address user = address(this);
    uint initialBalance = ERC20(depositToken).balanceOf(user);
    uint cap = _tokenAmount(10_000, depositToken);
    uint amount = initialBalance;
    minter.whitelistOrEditCap(user, cap);
    minter.deposit(amount);
    _checkInvestor(user, cap, cap);
    assertTrue(ERC20(depositToken).balanceOf(user) == amount - cap, 'Deposit token balance check');
    assertTrue(minter.balanceOf(user) == 10_000 ether + minter.TEAM_SUPPLY(), 'STO balance check');
  }

  function _checkInvestor(address _user, uint _cap, uint _deposited) internal {
    (uint cp, uint dp) = minter.investor(_user);
    assertTrue(_cap == cp, 'Cap check');
    assertTrue(_deposited == dp, 'Deposit check');
  }

  function _tokenAmount(uint _amountWithNoDecimals, address _token) internal view returns (uint) {
    return _amountWithNoDecimals * 10 ** ERC20(_token).decimals();
  }

  function _depositFlow(address _user, uint _cap, uint _amount) internal {
    minter.whitelistOrEditCap(_user, _cap);
    deal(depositToken, _user, type(uint).max);
    vm.startPrank(_user);
    ERC20(depositToken).approve(address(minter), type(uint).max);
    minter.deposit(_amount);
    vm.stopPrank();
  }
}
