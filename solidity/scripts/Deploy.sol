// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.19;

import {Script} from 'forge-std/Script.sol';
import {DustyLiquidator} from 'contracts/DustyLiquidator.sol';

abstract contract Deploy is Script {
  function _deploy() internal {
    vm.startBroadcast();
    new DustyLiquidator();
    vm.stopBroadcast();
  }
}

contract DeployMainnet is Deploy {
  function run() external {
    _deploy();
  }
}
