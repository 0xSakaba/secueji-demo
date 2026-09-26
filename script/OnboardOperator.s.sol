// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {console2} from "forge-std/Script.sol";
import {DemoScript} from "./DemoScript.sol";
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
///   OPERATOR_GAS_WEI      target ETH balance; required on mainnet (0 disables
///                         top-up), default 0.01 ether on local / Sepolia
contract OnboardOperator is DemoScript {
    function run() external {
        _checkNetwork();
        uint256 gasTarget = _operatorGasTarget();
        uint256 adminKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        DemoEscrow escrow = DemoEscrow(vm.envAddress("ESCROW_ADDRESS"));
        address operator = vm.envAddress("OPERATOR_ADDRESS");
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
