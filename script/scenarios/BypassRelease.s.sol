// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {DemoEscrow} from "../../src/DemoEscrow.sol";

/// @notice Demo trigger for the "bypass release" scenario. An account that is
/// not the Secueji operator (an old oracle key the customer never rotated, or a
/// leaked one) calls DemoEscrow.release directly. Nothing went through secueji:
/// no ABI form, no policy decision, no review. Only an escrow whose oracle is
/// this key can be released this way.
///
/// Run it by hand during the demo. The platform is expected to notice an
/// EscrowReleased whose caller is not the operator and, as guardian, pause the
/// escrow. Once paused, running it again on another escrow of the same key
/// reverts with ContractPaused (or EscrowIsPaused) in simulation and nothing is
/// broadcast.
///
/// Inputs (environment):
///   LEGACY_ORACLE_PRIVATE_KEY  key of the old oracle EOA
///   ESCROW_ADDRESS             DemoEscrow
///   ESCROW_ID                  escrow whose oracle is that EOA (vehicle-C / vehicle-D)
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
        console2.log("Guardian:       ", escrow.guardian());
        console2.log("State:          ", uint8(e.state));
        console2.log("Global pause:   ", escrow.paused());
        console2.log("Escrow paused:  ", escrow.escrowPaused(id));
        require(e.oracle == oracle, "escrow oracle is not this key");

        vm.startBroadcast(oracleKey);
        escrow.release(id);
        vm.stopBroadcast();

        console2.log("Released", e.amount, "to", e.seller);
    }
}
