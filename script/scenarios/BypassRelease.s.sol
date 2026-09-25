// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {DemoEscrow} from "../../src/DemoEscrow.sol";

/// @notice Demo trigger for the "bypass release" scenario. The legacy oracle EOA
/// calls DemoEscrow.release directly: no GuardExecutor, no human approval, no
/// platform authorization. Only a legacy escrow (oracle == this EOA) can be
/// released this way.
///
/// Run it by hand during the demo; the platform is expected to notice the
/// EscrowReleased event without a matching GuardedRelease and pause the escrow.
/// Once paused, running it again on another legacy escrow reverts with
/// ContractPaused (or EscrowIsPaused) in simulation and nothing is broadcast.
///
/// Inputs (environment):
///   LEGACY_ORACLE_PRIVATE_KEY  key of the legacy oracle EOA
///   ESCROW_ADDRESS             DemoEscrow
///   ESCROW_ID                  legacy escrow to release (3 or 4 on a fresh seed)
contract BypassRelease is Script {
    function run() external {
        uint256 oracleKey = vm.envUint("LEGACY_ORACLE_PRIVATE_KEY");
        DemoEscrow escrow = DemoEscrow(vm.envAddress("ESCROW_ADDRESS"));
        uint256 id = vm.envUint("ESCROW_ID");

        DemoEscrow.Escrow memory e = escrow.getEscrow(id);
        address oracle = vm.addr(oracleKey);
        console2.log("Escrow id:      ", id);
        console2.log("Escrow oracle:  ", e.oracle);
        console2.log("Caller (oracle):", oracle);
        console2.log("State:          ", uint8(e.state));
        console2.log("Global pause:   ", escrow.paused());
        console2.log("Escrow paused:  ", escrow.escrowPaused(id));
        require(e.oracle == oracle, "not a legacy escrow of this oracle");

        vm.startBroadcast(oracleKey);
        escrow.release(id);
        vm.stopBroadcast();

        console2.log("Released", e.amount, "to", e.seller);
    }
}
