// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {DemoEscrow} from "../../src/DemoEscrow.sol";

/// @notice Manual fallback for the last step of a managed release: after
/// secueji allowed the request (policy ALLOW, or a human approved it in the
/// secueji UI), the operator account sends `release(id)`. Normally secueji
/// sends this transaction itself; use the script only if that step fails.
///
/// The script does not decide anything. It only checks that the operator is
/// the escrow's oracle and prints the facts the policy used. Never run it for a
/// request secueji denied or has not approved yet.
///
/// Inputs (environment):
///   OPERATOR_PRIVATE_KEY  Secueji operator account
///   ESCROW_ADDRESS        DemoEscrow
///   ESCROW_ID             escrow to release (vehicle-A in the demo)
contract OperatorRelease is Script {
    function run() external {
        uint256 key = vm.envUint("OPERATOR_PRIVATE_KEY");
        DemoEscrow escrow = DemoEscrow(vm.envAddress("ESCROW_ADDRESS"));
        uint256 id = vm.envUint("ESCROW_ID");

        DemoEscrow.Escrow memory e = escrow.getEscrow(id);
        address operator = vm.addr(key);
        console2.log("Escrow id:        ", id);
        console2.log("Title id:         ", vm.toString(e.titleId));
        console2.log("Oracle:           ", e.oracle);
        console2.log("Operator:         ", operator);
        console2.log("Token:            ", e.token);
        console2.log("Amount:           ", e.amount);
        console2.log("Seller:           ", e.seller);
        console2.log("State:            ", uint8(e.state));
        console2.log("Refund requested: ", escrow.isRefundRequested(id));
        console2.log("Global pause:     ", escrow.paused());
        console2.log("Escrow paused:    ", escrow.escrowPaused(id));
        require(e.oracle == operator, "operator is not the oracle of this escrow");

        vm.startBroadcast(key);
        escrow.release(id);
        vm.stopBroadcast();

        console2.log("Released", e.amount, "to", e.seller);
    }
}
