// SPDX-License-Identifier: MIT
pragma solidity =0.8.19;

import {ISAFEEngine} from 'interfaces/ISAFEEngine.sol';
import {ILiquidationEngine} from 'interfaces/ILiquidationEngine.sol';
import {ILiquidationEngineOverlay} from 'interfaces/ILiquidationEngineOverlay.sol';

import {DustyLiquidator} from 'contracts/DustyLiquidator.sol';

import {Test, stdStorage, StdStorage} from 'forge-std/Test.sol';

contract ForkedTest is Test {
  using stdStorage for StdStorage;

  uint256 public constant FORK_BLOCK = 18_587_893;

  address public constant SAFE_ENGINE = 0xCC88a9d330da1133Df3A7bD823B95e52511A6962;
  address public constant LIQUIDATION_ENGINE = 0x4fFbAA89d648079Faafc7852dE49EA1dc92f9976;
  address public constant LIQUIDATION_ENGINE_OVERLAY = 0xa10C1e933C21315DfcaA8C8eDeDD032BD9b0Bccf;
  bytes32 public constant ETH_A = 0x4554482d41000000000000000000000000000000000000000000000000000000;

  uint256 public constant SAFE_COLLATERAL = 1e18;

  address public dustySafe = address(420);

  uint256 public accumulatedRate;
  uint256 public liquidationQuantity;
  uint256 public liquidationPenalty;

  DustyLiquidator public dustyLiquidator;

  struct Scenario {
    uint256 safeDebt;
    uint256 debtFloor;
  }

  function setUp() public {
    vm.createSelectFork(vm.rpcUrl('mainnet'), FORK_BLOCK);

    dustyLiquidator = DustyLiquidator(0x87dA6E890F061919738F7AF38fFE7BeE746e2FC1);
    (, accumulatedRate,,,,) = ISAFEEngine(SAFE_ENGINE).collateralTypes(ETH_A);
    (, liquidationPenalty, liquidationQuantity) = ILiquidationEngine(LIQUIDATION_ENGINE).collateralTypes(ETH_A);
  }

  event DustySafeLiquidation(address _safe, uint256 _penalty);

  modifier happyPath(Scenario memory _fuzz) {
    uint256 _limitAdjustedDebt = liquidationQuantity * 1e18 / accumulatedRate / liquidationPenalty;

    _fuzz.debtFloor = bound(_fuzz.debtFloor, accumulatedRate + 1, 4307e45);
    _fuzz.safeDebt =
      bound(_fuzz.safeDebt, _limitAdjustedDebt + 1, _limitAdjustedDebt + _fuzz.debtFloor / accumulatedRate);

    _storeScenario(_fuzz);

    _;
  }

  function _storeScenario(Scenario memory _fuzz) internal {
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
  }

  function test_should_revert_when_direct_call(Scenario memory _fuzz) public happyPath(_fuzz) {
    vm.expectRevert('LiquidationEngine/dusty-safe');

    ILiquidationEngine(LIQUIDATION_ENGINE).liquidateSAFE(ETH_A, dustySafe);
  }

  function test_should_not_revert_when_dusty_liquidator_call(Scenario memory _fuzz) public happyPath(_fuzz) {
    dustyLiquidator.liquidateDustySafe(dustySafe);
  }

  function testFail_should_revert_when_floor_is_out_of_range(Scenario memory _fuzz) public {
    uint256 _limitAdjustedDebt = liquidationQuantity * 1e18 / accumulatedRate / liquidationPenalty;

    _fuzz.debtFloor = bound(_fuzz.debtFloor, 4309e45, 1_000_000e45);

    // not partially liquidatable
    vm.assume(_fuzz.debtFloor > _fuzz.safeDebt * accumulatedRate - liquidationQuantity * 1e18 / liquidationPenalty);

    // most dangerous position
    _fuzz.safeDebt = _limitAdjustedDebt + _fuzz.debtFloor / accumulatedRate - 1e18;

    _storeScenario(_fuzz);
    dustyLiquidator.liquidateDustySafe(dustySafe);
  }
}
