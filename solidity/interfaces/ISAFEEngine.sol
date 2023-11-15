// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface ISAFEEngine {
  function collateralTypes(bytes32 _cType)
    external
    view
    returns (
      uint256 debtAmount,
      uint256 accumulatedRate,
      uint256 safetyPrice,
      uint256 debtCeiling,
      uint256 debtFloor,
      uint256 liquidationPrice
    );

  function safes(bytes32 _cType, address _safe) external view returns (uint256 lockedCollateral, uint256 generatedDebt);

  function confiscateSAFECollateralAndDebt(
    bytes32 collateralType,
    address safe,
    address collateralCounterparty,
    address debtCounterparty,
    int256 deltaCollateral,
    int256 deltaDebt
  ) external;
}
