// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import {ISAFEEngine} from 'interfaces/ISAFEEngine.sol';
import {ILiquidationEngine} from 'interfaces/ILiquidationEngine.sol';
import {ILiquidationEngineOverlay} from 'interfaces/ILiquidationEngineOverlay.sol';

import {DustyLiquidator} from 'contracts/DustyLiquidator.sol';

import 'forge-std/Test.sol';

contract CommonE2EBase is Test {
  using stdStorage for StdStorage;

  uint256 internal constant _FORK_BLOCK = 18_569_420;

  address constant SAFE_ENGINE = 0xCC88a9d330da1133Df3A7bD823B95e52511A6962;
  address constant LIQUIDATION_ENGINE = 0x4fFbAA89d648079Faafc7852dE49EA1dc92f9976;
  address constant LIQUIDATION_ENGINE_OVERLAY = 0xa10C1e933C21315DfcaA8C8eDeDD032BD9b0Bccf;
  bytes32 constant ETH_A = 0x4554482d41000000000000000000000000000000000000000000000000000000;

  uint256 constant LIQUIDATION_QUANTITY = 90_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000_000;
  uint256 constant LIQUIDATION_PENALTY = 1_100_000_000_000_000_000;
  uint256 constant MIN_PENALTY = 1_090_000_000_000_000_000;
  uint256 constant MAX_PENALTY = 1_150_000_000_000_000_000;

  uint256 constant SAFE_COLLATERAL = 1e18;

  address dustySafe = address(420);

  DustyLiquidator dustyLiquidator;

  struct Scenario {
    uint256 accumulatedRate;
    uint256 debtFloor;
    uint256 safeDebt;
  }

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl('mainnet'), _FORK_BLOCK);
    dustyLiquidator = new DustyLiquidator();
  }

  Scenario _fuzzed;

  event DustySafeLiquidation(address _safe, uint256 _penalty);

  modifier happyPath(Scenario memory _fuzz) {
    // valid values
    _fuzz.accumulatedRate = bound(_fuzz.accumulatedRate, 0.5e27, 1.5e27); // safe assumption
    _fuzz.debtFloor = bound(_fuzz.debtFloor, _fuzz.accumulatedRate + 1, 1_000_000e45); // safe assumption

    uint256 _limitAdjustedDebt = LIQUIDATION_QUANTITY * 1e18 / _fuzz.accumulatedRate / LIQUIDATION_PENALTY;
    vm.assume(_limitAdjustedDebt < 10_000_000_000e18); // safe assumption

    // max possible value of limitAdjustedDebt
    uint256 _maxLimitAdjustedDebt = LIQUIDATION_QUANTITY * 1e18 / _fuzz.accumulatedRate / MIN_PENALTY;

    // dusty
    _fuzz.safeDebt =
      bound(_fuzz.safeDebt, _limitAdjustedDebt + 1, _limitAdjustedDebt + _fuzz.debtFloor / _fuzz.accumulatedRate);

    // scenario assumptions
    vm.assume(_limitAdjustedDebt < type(uint256).max / SAFE_COLLATERAL); // not overflow
    vm.assume(SAFE_COLLATERAL * _limitAdjustedDebt / _fuzz.safeDebt > 0); // not-null

    // set up
    stdstore.target(SAFE_ENGINE).sig(ISAFEEngine.collateralTypes.selector).with_key(ETH_A).depth(1).checked_write(
      _fuzz.accumulatedRate
    );

    stdstore.target(SAFE_ENGINE).sig(ISAFEEngine.collateralTypes.selector).with_key(ETH_A).depth(4).checked_write(
      _fuzz.debtFloor
    );

    stdstore.target(SAFE_ENGINE).sig(ISAFEEngine.collateralTypes.selector).with_key(ETH_A).depth(5).checked_write(1);

    stdstore.target(SAFE_ENGINE).sig(ISAFEEngine.safes.selector).with_key(ETH_A).with_key(dustySafe).depth(0)
      .checked_write(SAFE_COLLATERAL);

    stdstore.target(SAFE_ENGINE).sig(ISAFEEngine.safes.selector).with_key(ETH_A).with_key(dustySafe).depth(1)
      .checked_write(_fuzz.safeDebt);

    stdstore.target(LIQUIDATION_ENGINE).sig(ILiquidationEngine.onAuctionSystemCoinLimit.selector).checked_write(
      type(uint256).max
    );

    stdstore.target(LIQUIDATION_ENGINE_OVERLAY).sig(ILiquidationEngineOverlay.authorizedAccounts.selector).with_key(
      address(dustyLiquidator)
    ).checked_write(1);

    // store bounded values to storage
    _fuzzed = _fuzz;

    _;
  }

  function test_should_revert_when_direct_call(Scenario memory _fuzz) public happyPath(_fuzz) {
    vm.expectRevert('LiquidationEngine/dusty-safe');

    ILiquidationEngine(LIQUIDATION_ENGINE).liquidateSAFE(ETH_A, dustySafe);
  }

  function test_should_not_revert_when_dusty_liquidator_call(Scenario memory _fuzz) public happyPath(_fuzz) {
    vm.assume(
      _whollyLiquidatable(_fuzzed.accumulatedRate, _fuzzed.safeDebt)
        || _partiallyLiquidatable(_fuzzed.accumulatedRate, _fuzzed.debtFloor, _fuzzed.safeDebt)
    );

    dustyLiquidator.liquidateDustySafe(dustySafe);
  }

  function test_emit_when_dusty_liquidator_min_penalty(Scenario memory _fuzz) public happyPath(_fuzz) {
    vm.assume(_whollyLiquidatable(_fuzzed.accumulatedRate, _fuzzed.safeDebt));

    vm.expectEmit();
    emit DustySafeLiquidation(dustySafe, MIN_PENALTY);

    dustyLiquidator.liquidateDustySafe(dustySafe);
  }

  function test_emit_when_dusty_liquidator_max_penalty(Scenario memory _fuzz) public happyPath(_fuzz) {
    vm.assume(!_whollyLiquidatable(_fuzzed.accumulatedRate, _fuzzed.safeDebt));
    vm.assume(_partiallyLiquidatable(_fuzzed.accumulatedRate, _fuzzed.debtFloor, _fuzzed.safeDebt));

    vm.expectEmit();
    emit DustySafeLiquidation(dustySafe, MAX_PENALTY);

    dustyLiquidator.liquidateDustySafe(dustySafe);
  }

  function test_emit_when_dusty_liquidator_max_penalty_simplified(Scenario memory _fuzz) public happyPath(_fuzz) {
    vm.assume(!_whollyLiquidatable(_fuzzed.accumulatedRate, _fuzzed.safeDebt));
    vm.assume(_partiallyLiquidatableSimplified(_fuzzed.debtFloor));

    vm.expectEmit();
    emit DustySafeLiquidation(dustySafe, MAX_PENALTY);

    dustyLiquidator.liquidateDustySafe(dustySafe);
  }

  function _whollyLiquidatable(uint256 _accumulatedRate, uint256 _safeDebt) internal pure returns (bool) {
    return _safeDebt < LIQUIDATION_QUANTITY * 1e18 / _accumulatedRate / MIN_PENALTY;
  }

  function _partiallyLiquidatable(
    uint256 _accumulatedRate,
    uint256 _debtFloor,
    uint256 _safeDebt
  ) internal pure returns (bool) {
    return _debtFloor < _safeDebt * _accumulatedRate - LIQUIDATION_QUANTITY * 1e18 / MAX_PENALTY;
  }

  function _partiallyLiquidatableSimplified(uint256 _debtFloor) internal pure returns (bool) {
    return _debtFloor < LIQUIDATION_QUANTITY * 1e18 / MIN_PENALTY - LIQUIDATION_QUANTITY * 1e18 / MAX_PENALTY;
  }
}
