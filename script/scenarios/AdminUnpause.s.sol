// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {DemoEscrow} from "../../src/DemoEscrow.sol";

/// @notice Resets the demo after a pause. Only the escrow admin can unpause.
///
/// Inputs (environment):
///   DEPLOYER_PRIVATE_KEY  escrow admin
///   ESCROW_ADDRESS        DemoEscrow
///   ESCROW_ID             optional; unpause only this escrow. Unset or 0 lifts the global pause.
contract AdminUnpause is Script {
    function run() external {
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        DemoEscrow escrow = DemoEscrow(vm.envAddress("ESCROW_ADDRESS"));
        uint256 id = vm.envOr("ESCROW_ID", uint256(0));

        vm.startBroadcast(key);
        if (id == 0) escrow.unpause();
        else escrow.unpauseEscrow(id);
        vm.stopBroadcast();

        console2.log("Global pause: ", escrow.paused());
        if (id != 0) console2.log("Escrow paused:", escrow.escrowPaused(id));
    }
}
