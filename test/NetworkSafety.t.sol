// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {OnboardOperator} from "../script/OnboardOperator.s.sol";
import {Seed} from "../script/Seed.s.sol";
import {RetireEscrows} from "../script/RetireEscrows.s.sol";
import {OperatorRelease} from "../script/scenarios/OperatorRelease.s.sol";
import {BypassRelease} from "../script/scenarios/BypassRelease.s.sol";
import {GuardianPause} from "../script/scenarios/GuardianPause.s.sol";
import {AdminUnpause} from "../script/scenarios/AdminUnpause.s.sol";

/// 所有測試都在本機 EVM 改 chain id，不連接主網，也不讀取真實私鑰。
abstract contract NetworkSafetyChecks is Test {
    function _resetSafetyEnvironment() internal {
        vm.setEnv("EXPECTED_CHAIN_ID", "84532");
        vm.setEnv("ALLOW_BASE_MAINNET", "false");
        vm.setEnv("DEPLOYER_PRIVATE_KEY", "");
        vm.setEnv("BUYER_PRIVATE_KEY", "");
        vm.setEnv("OPERATOR_PRIVATE_KEY", "");
        vm.setEnv("LEGACY_ORACLE_PRIVATE_KEY", "");
    }

    function _checkNetworkSafety() internal {
        _resetSafetyEnvironment();
        _allEntryPointsRejectWrongNetworkBeforeReadingKeys();
        _resetSafetyEnvironment();
        _baseMainnetRequiresExplicitOptIn();
        _resetSafetyEnvironment();
        _otherMainnetsAreNotAllowedEvenWithOptIn();
        _resetSafetyEnvironment();
        _mainnetOnboardingRequiresExplicitGasTargetBeforeKeys();
    }

    function _allEntryPointsRejectWrongNetworkBeforeReadingKeys() internal {
        address[8] memory scripts = [
            address(new Deploy()),
            address(new OnboardOperator()),
            address(new Seed()),
            address(new RetireEscrows()),
            address(new OperatorRelease()),
            address(new BypassRelease()),
            address(new GuardianPause()),
            address(new AdminUnpause())
        ];
        vm.chainId(8453);
        for (uint256 i; i < scripts.length; i++) {
            (bool ok, bytes memory reason) = scripts[i].call(abi.encodeWithSignature("run()"));
            assertFalse(ok);
            assertEq(reason, abi.encodeWithSignature("Error(string)", "demo: unexpected chain id"));
        }
    }

    function _baseMainnetRequiresExplicitOptIn() internal {
        vm.chainId(8453);
        vm.setEnv("EXPECTED_CHAIN_ID", "8453");
        Deploy deployment = new Deploy();
        vm.expectRevert(bytes("demo: Base mainnet requires explicit opt-in"));
        deployment.run();
    }

    function _otherMainnetsAreNotAllowedEvenWithOptIn() internal {
        vm.chainId(1);
        vm.setEnv("EXPECTED_CHAIN_ID", "1");
        vm.setEnv("ALLOW_BASE_MAINNET", "true");
        Deploy deployment = new Deploy();
        vm.expectRevert(bytes("demo: unsupported network"));
        deployment.run();
    }

    function _mainnetOnboardingRequiresExplicitGasTargetBeforeKeys() internal {
        vm.chainId(8453);
        vm.setEnv("EXPECTED_CHAIN_ID", "8453");
        vm.setEnv("ALLOW_BASE_MAINNET", "true");
        vm.setEnv("OPERATOR_GAS_WEI", "");
        OnboardOperator onboard = new OnboardOperator();
        vm.expectRevert(bytes("demo: set OPERATOR_GAS_WEI explicitly on mainnet"));
        onboard.run();
    }
}
