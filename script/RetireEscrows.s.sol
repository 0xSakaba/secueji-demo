// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {DemoEscrow} from "../src/DemoEscrow.sol";

/// @notice Takes old demo escrows out of play so they cannot be confused with
/// the current scenario set. The admin refunds a Funded escrow to the buyer and
/// cancels a Created one; escrows that are already closed are skipped.
///
/// Refund is blocked while the contract or the escrow is paused, so unpause
/// first (AdminUnpause.s.sol) if needed.
///
/// Inputs (environment):
///   DEPLOYER_PRIVATE_KEY  escrow admin
///   ESCROW_ADDRESS        DemoEscrow
///   ESCROW_IDS            comma-separated ids, for example 1,2,3,4,5,6
contract RetireEscrows is Script {
    function run() external {
        uint256 adminKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        DemoEscrow escrow = DemoEscrow(vm.envAddress("ESCROW_ADDRESS"));
        uint256[] memory ids = vm.envUint("ESCROW_IDS", ",");

        vm.startBroadcast(adminKey);
        for (uint256 i; i < ids.length; i++) {
            DemoEscrow.State state = escrow.getEscrow(ids[i]).state;
            if (state == DemoEscrow.State.Funded) {
                escrow.refund(ids[i]);
                console2.log("Refunded ", ids[i]);
            } else if (state == DemoEscrow.State.Created) {
                escrow.cancel(ids[i]);
                console2.log("Cancelled", ids[i]);
            } else {
                console2.log("Skipped  ", ids[i], "state", uint8(state));
            }
        }
        vm.stopBroadcast();
    }
}
