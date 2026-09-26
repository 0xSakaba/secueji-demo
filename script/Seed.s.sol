// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {console2} from "forge-std/Script.sol";
import {DemoScript} from "./DemoScript.sol";
import {DemoStablecoin} from "../src/DemoStablecoin.sol";
import {DemoEscrow} from "../src/DemoEscrow.sol";

/// @notice Seeds the escrows the demo scenarios start from (used-car
/// marketplace; `titleId = keccak256(label)` is the vehicle id). The customer
/// has onboarded secueji with an operator account (OnboardOperator.s.sol), so
/// escrows released through secueji use `oracle = OPERATOR_ADDRESS`:
///
///   vehicle-A  operator       dUSD   normal release, policy should allow
///   vehicle-B  operator       dUSD   must not be paid out by a release for vehicle A
///   vehicle-C  legacy oracle  dUSD   bypass: an old oracle key releases outside secueji
///   vehicle-D  legacy oracle  dUSD   second bypass attempt, blocked once paused
///   vehicle-E  operator       decoy  funded with a lookalike "Demo USD" / dUSD token
///   vehicle-F  operator       dUSD   buyer has requested a refund
///
/// Each label gets TITLE_SUFFIX appended, so a re-seed on an existing
/// deployment can use fresh titles (escrowIdsByTitle then returns one id).
///
/// The decoy token is a DemoStablecoin deployed by the buyer, so its name and
/// symbol match the real dUSD but its address and minter do not. Pass
/// DECOY_TOKEN_ADDRESS to reuse an existing one. Only missing balances are
/// minted: dUSD by the deployer (minter), decoy dUSD by the buyer.
///
/// Inputs (environment):
///   DEPLOYER_PRIVATE_KEY   minter / escrow admin (the customer)
///   BUYER_PRIVATE_KEY      buyer that funds every escrow
///   SELLER_ADDRESS         escrow beneficiary
///   OPERATOR_ADDRESS       Secueji operator account (oracle of operator escrows)
///   LEGACY_ORACLE_ADDRESS  old oracle EOA (oracle of the bypass escrows)
///   TOKEN_ADDRESS, ESCROW_ADDRESS  output of Deploy.s.sol
///   DECOY_TOKEN_ADDRESS    optional; deploy a new decoy when unset
///   TITLE_SUFFIX           optional; appended to every label, default empty
contract Seed is DemoScript {
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
    DemoStablecoin decoy;
    address buyer;
    address seller;
    address operator;
    address legacyOracle;

    function run() external returns (uint256[] memory ids, DemoStablecoin decoyToken) {
        _checkNetwork();
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        uint256 buyerKey = vm.envUint("BUYER_PRIVATE_KEY");
        buyer = vm.addr(buyerKey);
        seller = vm.envAddress("SELLER_ADDRESS");
        operator = vm.envAddress("OPERATOR_ADDRESS");
        legacyOracle = vm.envAddress("LEGACY_ORACLE_ADDRESS");
        token = DemoStablecoin(vm.envAddress("TOKEN_ADDRESS"));
        escrow = DemoEscrow(vm.envAddress("ESCROW_ADDRESS"));
        decoy = DemoStablecoin(vm.envOr("DECOY_TOKEN_ADDRESS", address(0)));
        string memory suffix = vm.envOr("TITLE_SUFFIX", string(""));

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
            plan[i].label = string.concat(plan[i].label, suffix);
            if (plan[i].decoy) decoyTotal += plan[i].amount;
            else realTotal += plan[i].amount;
        }

        // A lookalike token anyone could deploy: same name, symbol and decimals.
        vm.startBroadcast(buyerKey);
        if (address(decoy) == address(0)) decoy = new DemoStablecoin();
        uint256 decoyBalance = decoy.balanceOf(buyer);
        if (decoyBalance < decoyTotal) decoy.mint(buyer, decoyTotal - decoyBalance);
        vm.stopBroadcast();

        ids = new uint256[](plan.length);
        vm.startBroadcast(deployerKey);
        uint256 realBalance = token.balanceOf(buyer);
        if (realBalance < realTotal) token.mint(buyer, realTotal - realBalance);
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
        console2.log("Operator:        ", operator);
        for (uint256 i; i < plan.length; i++) {
            console2.log(
                string.concat(
                    "Escrow ",
                    vm.toString(ids[i]),
                    " ",
                    plan[i].label,
                    plan[i].legacy ? " legacy-oracle" : " operator",
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
            p.legacy ? legacyOracle : operator
        );
    }
}
