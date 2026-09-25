// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {DemoStablecoin} from "../src/DemoStablecoin.sol";
import {DemoEscrow} from "../src/DemoEscrow.sol";
import {GuardExecutor} from "../src/GuardExecutor.sol";

/// @notice Deploys DemoStablecoin and DemoEscrow and, if given, a separate
/// escrow guardian. GuardExecutor (the earlier "contract enforces platform
/// signatures" design, not used by the demo scenarios) is only deployed when
/// PLATFORM_SIGNER_ADDRESS is set.
///
/// The broadcasting key becomes the stablecoin minter, the escrow admin, the
/// default escrow guardian and the GuardExecutor owner. To hand the Secueji
/// operator account its permissions afterwards, run OnboardOperator.s.sol.
///
/// Inputs (environment):
///   DEPLOYER_PRIVATE_KEY     key that sends the transactions
///   GUARDIAN_ADDRESS         optional; account allowed to pause the escrow
///                            (defaults to the deployer)
///   PLATFORM_SIGNER_ADDRESS  optional; deploys GuardExecutor with this signer
///   APPROVER_ADDRESS         optional; approver registered on GuardExecutor
contract Deploy is Script {
    function run() external returns (DemoStablecoin token, DemoEscrow escrow, GuardExecutor guard) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address guardian = vm.envOr("GUARDIAN_ADDRESS", deployer);
        address platformSigner = vm.envOr("PLATFORM_SIGNER_ADDRESS", address(0));
        address approver = vm.envOr("APPROVER_ADDRESS", address(0));

        vm.startBroadcast(deployerKey);
        token = new DemoStablecoin();
        escrow = new DemoEscrow();
        if (platformSigner != address(0)) {
            guard = new GuardExecutor(escrow, platformSigner);
            if (approver != address(0)) guard.setApprover(approver, true);
        }
        if (guardian != deployer) escrow.setGuardian(guardian);
        vm.stopBroadcast();

        console2.log("DemoStablecoin:", address(token));
        console2.log("DemoEscrow:    ", address(escrow));
        console2.log("Admin/minter:  ", deployer);
        console2.log("Guardian:      ", escrow.guardian());
        if (address(guard) != address(0)) {
            console2.log("GuardExecutor: ", address(guard));
            console2.log("PlatformSigner:", platformSigner);
            console2.log("Approver:      ", approver);
        }
    }
}
