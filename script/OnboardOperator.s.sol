// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {DemoEscrow} from "../src/DemoEscrow.sol";

/// @notice Onboarding step of the customer (the escrow admin) to secueji: hands
/// the Secueji operator account the permissions it needs on DemoEscrow.
///
///   - guardian: the operator can pause the escrow (never unpause, never move
///     funds), so secueji can respond to an anomaly on its own
///   - gas: tops the operator up to OPERATOR_GAS_WEI so it can send transactions
///
/// Release authority is granted per escrow, by creating it with
/// `oracle = OPERATOR_ADDRESS` (see Seed.s.sol). The admin role stays with the
/// customer. Running the script again only does what is still missing.
///
/// Inputs (environment):
///   DEPLOYER_PRIVATE_KEY  escrow admin (the customer's own key)
///   ESCROW_ADDRESS        DemoEscrow
///   OPERATOR_ADDRESS      Secueji operator account
///   OPERATOR_GAS_WEI      optional; target ETH balance, default 0.01 ether
contract OnboardOperator is Script {
    function run() external {
        uint256 adminKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        DemoEscrow escrow = DemoEscrow(vm.envAddress("ESCROW_ADDRESS"));
        address operator = vm.envAddress("OPERATOR_ADDRESS");
        uint256 gasTarget = vm.envOr("OPERATOR_GAS_WEI", uint256(0.01 ether));
        require(escrow.admin() == vm.addr(adminKey), "DEPLOYER_PRIVATE_KEY is not the escrow admin");

        vm.startBroadcast(adminKey);
        if (escrow.guardian() != operator) escrow.setGuardian(operator);
        if (operator.balance < gasTarget) {
            (bool ok,) = payable(operator).call{value: gasTarget - operator.balance}("");
            require(ok, "gas top-up failed");
        }
        vm.stopBroadcast();

        console2.log("Admin (customer):  ", escrow.admin());
        console2.log("Guardian:          ", escrow.guardian());
        console2.log("Operator:          ", operator);
        console2.log("Operator balance:  ", operator.balance);
    }
}
