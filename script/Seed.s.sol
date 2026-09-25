// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {DemoStablecoin} from "../src/DemoStablecoin.sol";
import {DemoEscrow} from "../src/DemoEscrow.sol";
import {GuardExecutor} from "../src/GuardExecutor.sol";

/// @notice Seeds a deployed stack with one funded escrow per mode so the demo
/// can show both paths:
///   - legacy:  oracle is an EOA, which can release with no approval;
///   - guarded: oracle is GuardExecutor, which needs approver + platform signatures.
///
/// Inputs (environment):
///   DEPLOYER_PRIVATE_KEY   minter / escrow admin used at deploy time
///   BUYER_PRIVATE_KEY      buyer that funds both escrows
///   SELLER_ADDRESS         escrow beneficiary
///   LEGACY_ORACLE_ADDRESS  EOA oracle for the legacy escrow
///   TOKEN_ADDRESS, ESCROW_ADDRESS, GUARD_ADDRESS  output of Deploy.s.sol
contract Seed is Script {
    uint256 constant AMOUNT = 18_450e6;

    function run() external returns (uint256 legacyId, uint256 guardedId) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        uint256 buyerKey = vm.envUint("BUYER_PRIVATE_KEY");
        address buyer = vm.addr(buyerKey);
        address seller = vm.envAddress("SELLER_ADDRESS");
        address legacyOracle = vm.envAddress("LEGACY_ORACLE_ADDRESS");
        DemoStablecoin token = DemoStablecoin(vm.envAddress("TOKEN_ADDRESS"));
        DemoEscrow escrow = DemoEscrow(vm.envAddress("ESCROW_ADDRESS"));
        GuardExecutor guard = GuardExecutor(vm.envAddress("GUARD_ADDRESS"));

        vm.startBroadcast(deployerKey);
        token.mint(buyer, AMOUNT * 2);
        legacyId = escrow.createEscrow(buyer, seller, address(token), AMOUNT, keccak256("title-legacy"), legacyOracle);
        guardedId = escrow.createEscrow(buyer, seller, address(token), AMOUNT, keccak256("title-guarded"), address(guard));
        vm.stopBroadcast();

        vm.startBroadcast(buyerKey);
        token.approve(address(escrow), AMOUNT * 2);
        escrow.fund(legacyId);
        escrow.fund(guardedId);
        vm.stopBroadcast();

        console2.log("Legacy escrow id: ", legacyId);
        console2.log("Guarded escrow id:", guardedId);
    }
}
