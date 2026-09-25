// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {DemoStablecoin} from "../src/DemoStablecoin.sol";
import {DemoEscrow} from "../src/DemoEscrow.sol";
import {GuardExecutor} from "../src/GuardExecutor.sol";

/// @notice Deploys DemoStablecoin, DemoEscrow and GuardExecutor, then registers
/// the human approver on GuardExecutor.
///
/// The broadcasting key becomes the stablecoin minter, the escrow admin and the
/// GuardExecutor owner. All inputs come from the environment:
///   DEPLOYER_PRIVATE_KEY     key that sends the transactions
///   PLATFORM_SIGNER_ADDRESS  address whose signatures authorize guarded releases
///   APPROVER_ADDRESS         human approver registered on GuardExecutor
contract Deploy is Script {
    function run() external returns (DemoStablecoin token, DemoEscrow escrow, GuardExecutor guard) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address platformSigner = vm.envAddress("PLATFORM_SIGNER_ADDRESS");
        address approver = vm.envAddress("APPROVER_ADDRESS");

        vm.startBroadcast(deployerKey);
        token = new DemoStablecoin();
        escrow = new DemoEscrow();
        guard = new GuardExecutor(escrow, platformSigner);
        guard.setApprover(approver, true);
        vm.stopBroadcast();

        console2.log("DemoStablecoin:", address(token));
        console2.log("DemoEscrow:    ", address(escrow));
        console2.log("GuardExecutor: ", address(guard));
        console2.log("Admin/owner:   ", vm.addr(deployerKey));
        console2.log("PlatformSigner:", platformSigner);
        console2.log("Approver:      ", approver);
    }
}
