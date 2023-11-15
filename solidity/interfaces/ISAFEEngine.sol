// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface ISAFEEngine {
  function collateralTypes(bytes32 _cType)
    external
    view
    returns (
      uint256 _debtAmount,
      uint256 _accumulatedRate,
      uint256 _safetyPrice,
      uint256 _debtCeiling,
      uint256 _debtFloor,
      uint256 _liquidationPrice
    );

  function safes(
    bytes32 _cType,
    address _safe
  ) external view returns (uint256 _lockedCollateral, uint256 _generatedDebt);

  function confiscateSAFECollateralAndDebt(
    bytes32 _collateralType,
    address _safe,
    address _collateralCounterparty,
    address _debtCounterparty,
    int256 _deltaCollateral,
    int256 _deltaDebt
  ) external;
}
