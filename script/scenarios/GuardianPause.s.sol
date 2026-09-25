// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {DemoEscrow} from "../../src/DemoEscrow.sol";

/// @notice Manual fallback for the automated response: the guardian pauses
/// DemoEscrow (all releases and refunds) or a single escrow.
///
/// Inputs (environment):
///   GUARDIAN_PRIVATE_KEY  optional; defaults to DEPLOYER_PRIVATE_KEY (the default guardian)
///   ESCROW_ADDRESS        DemoEscrow
///   ESCROW_ID             optional; pause only this escrow. Unset or 0 pauses everything.
contract GuardianPause is Script {
    function run() external {
        uint256 key = vm.envOr("GUARDIAN_PRIVATE_KEY", uint256(0));
        if (key == 0) key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        DemoEscrow escrow = DemoEscrow(vm.envAddress("ESCROW_ADDRESS"));
        uint256 id = vm.envOr("ESCROW_ID", uint256(0));

        vm.startBroadcast(key);
        if (id == 0) escrow.pause();
        else escrow.pauseEscrow(id);
        vm.stopBroadcast();

        console2.log("Paused by:    ", vm.addr(key));
        console2.log("Global pause: ", escrow.paused());
        if (id != 0) console2.log("Escrow paused:", id);
    }
}
