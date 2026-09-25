// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {DemoEscrow} from "../../src/DemoEscrow.sol";

/// @notice Manual fallback for the automated response: the Secueji operator,
/// acting as the escrow guardian, pauses DemoEscrow (all releases and refunds)
/// or a single escrow. The operator can never lift the pause; only the admin
/// (the customer) can (AdminUnpause.s.sol).
///
/// Inputs (environment):
///   OPERATOR_PRIVATE_KEY  Secueji operator account; must be the escrow guardian
///                         (see OnboardOperator.s.sol)
///   ESCROW_ADDRESS        DemoEscrow
///   ESCROW_ID             optional; pause only this escrow. Unset or 0 pauses everything.
contract GuardianPause is Script {
    function run() external {
        uint256 key = vm.envUint("OPERATOR_PRIVATE_KEY");
        DemoEscrow escrow = DemoEscrow(vm.envAddress("ESCROW_ADDRESS"));
        uint256 id = vm.envOr("ESCROW_ID", uint256(0));
        address operator = vm.addr(key);
        require(escrow.guardian() == operator, "operator is not the guardian; run OnboardOperator.s.sol");

        vm.startBroadcast(key);
        if (id == 0) escrow.pause();
        else escrow.pauseEscrow(id);
        vm.stopBroadcast();

        console2.log("Paused by:    ", operator);
        console2.log("Global pause: ", escrow.paused());
        if (id != 0) console2.log("Escrow paused:", id);
    }
}
