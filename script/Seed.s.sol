// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {DemoStablecoin} from "../src/DemoStablecoin.sol";
import {DemoEscrow} from "../src/DemoEscrow.sol";
import {GuardExecutor} from "../src/GuardExecutor.sol";

/// @notice Seeds a deployed stack with the escrows the demo scenarios start
/// from (used-car marketplace; `titleId` is the vehicle id). On a fresh
/// deployment the ids are 1 to 6:
///
///   1 vehicle-A  guarded  dUSD   normal release, policy should allow
///   2 vehicle-B  guarded  dUSD   must not be paid out by a release for vehicle A
///   3 vehicle-C  legacy   dUSD   bypass: the oracle EOA releases with no approval
///   4 vehicle-D  legacy   dUSD   second bypass attempt, blocked once paused
///   5 vehicle-E  guarded  decoy  funded with a lookalike "Demo USD" / dUSD token
///   6 vehicle-F  guarded  dUSD   buyer has requested a refund
///
/// The decoy token is a second DemoStablecoin deployed by the buyer, so its name
/// and symbol match the real dUSD but its address and minter do not.
///
/// Inputs (environment):
///   DEPLOYER_PRIVATE_KEY   minter / escrow admin used at deploy time
///   BUYER_PRIVATE_KEY      buyer that funds every escrow and deploys the decoy
///   SELLER_ADDRESS         escrow beneficiary
///   LEGACY_ORACLE_ADDRESS  EOA oracle for the legacy escrows
///   TOKEN_ADDRESS, ESCROW_ADDRESS, GUARD_ADDRESS  output of Deploy.s.sol
contract Seed is Script {
    struct Plan {
        string label;
        uint256 amount;
        bool legacy;
        bool decoy;
    }

    uint256 constant REFUND_INDEX = 5;
    string constant REFUND_REASON = "Inspection failed: odometer reading does not match the listing";

    DemoStablecoin token;
    DemoEscrow escrow;
    GuardExecutor guard;
    DemoStablecoin decoy;
    address buyer;
    address seller;
    address legacyOracle;

    function run() external returns (uint256[] memory ids, DemoStablecoin decoyToken) {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        uint256 buyerKey = vm.envUint("BUYER_PRIVATE_KEY");
        buyer = vm.addr(buyerKey);
        seller = vm.envAddress("SELLER_ADDRESS");
        legacyOracle = vm.envAddress("LEGACY_ORACLE_ADDRESS");
        token = DemoStablecoin(vm.envAddress("TOKEN_ADDRESS"));
        escrow = DemoEscrow(vm.envAddress("ESCROW_ADDRESS"));
        guard = GuardExecutor(vm.envAddress("GUARD_ADDRESS"));

        Plan[6] memory plan = [
            Plan("vehicle-A", 18_450e6, false, false),
            Plan("vehicle-B", 21_300e6, false, false),
            Plan("vehicle-C", 12_800e6, true, false),
            Plan("vehicle-D", 9_750e6, true, false),
            Plan("vehicle-E", 18_450e6, false, true),
            Plan("vehicle-F", 16_900e6, false, false)
        ];
        uint256 realTotal;
        uint256 decoyTotal;
        for (uint256 i; i < plan.length; i++) {
            if (plan[i].decoy) decoyTotal += plan[i].amount;
            else realTotal += plan[i].amount;
        }

        // A lookalike token anyone could deploy: same name, symbol and decimals.
        vm.startBroadcast(buyerKey);
        decoy = new DemoStablecoin();
        decoy.mint(buyer, decoyTotal);
        vm.stopBroadcast();

        ids = new uint256[](plan.length);
        vm.startBroadcast(deployerKey);
        token.mint(buyer, realTotal);
        for (uint256 i; i < plan.length; i++) {
            ids[i] = _create(plan[i]);
        }
        vm.stopBroadcast();

        vm.startBroadcast(buyerKey);
        token.approve(address(escrow), realTotal);
        decoy.approve(address(escrow), decoyTotal);
        for (uint256 i; i < plan.length; i++) {
            escrow.fund(ids[i]);
        }
        escrow.requestRefund(ids[REFUND_INDEX], REFUND_REASON);
        vm.stopBroadcast();

        console2.log("Decoy dUSD token:", address(decoy));
        for (uint256 i; i < plan.length; i++) {
            console2.log(
                string.concat(
                    "Escrow ",
                    vm.toString(ids[i]),
                    " ",
                    plan[i].label,
                    plan[i].legacy ? " legacy" : " guarded",
                    plan[i].decoy ? " decoy-token" : "",
                    i == REFUND_INDEX ? " refund-requested" : ""
                )
            );
            console2.log("  titleId", vm.toString(keccak256(bytes(plan[i].label))));
        }
        decoyToken = decoy;
    }

    function _create(Plan memory p) internal returns (uint256) {
        return escrow.createEscrow(
            buyer,
            seller,
            p.decoy ? address(decoy) : address(token),
            p.amount,
            keccak256(bytes(p.label)),
            p.legacy ? legacyOracle : address(guard)
        );
    }
}
