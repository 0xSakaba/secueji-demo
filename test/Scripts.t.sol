// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {NetworkSafetyChecks} from "./NetworkSafety.t.sol";
import {DemoStablecoin} from "../src/DemoStablecoin.sol";
import {DemoEscrow} from "../src/DemoEscrow.sol";
import {GuardExecutor} from "../src/GuardExecutor.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {OnboardOperator} from "../script/OnboardOperator.s.sol";
import {Seed} from "../script/Seed.s.sol";
import {RetireEscrows} from "../script/RetireEscrows.s.sol";
import {OperatorRelease} from "../script/scenarios/OperatorRelease.s.sol";
import {BypassRelease} from "../script/scenarios/BypassRelease.s.sol";
import {GuardianPause} from "../script/scenarios/GuardianPause.s.sol";
import {AdminUnpause} from "../script/scenarios/AdminUnpause.s.sol";
import {InspectIntercepta} from "../script/InspectIntercepta.s.sol";

/// Runs the deployment, onboarding, seed and scenario scripts end to end, the
/// same order as the Base Sepolia re-seed: seed, retire the old set, seed again
/// with fresh titles, then play the scenarios.
///
/// Every variable a script reads is set here, because forge also loads the
/// project's `.env` and its values must not leak into the test. One test
/// function only, since the environment is shared by the whole process.
contract ScriptsTest is NetworkSafetyChecks {
    uint256 constant DEPLOYER_PK = 0xD3910;
    uint256 constant BUYER_PK = 0xB0E3;
    uint256 constant OPERATOR_PK = 0x0E3A;
    uint256 constant LEGACY_PK = 0x1E6AC;
    address constant ZERO = address(0);

    address deployer = vm.addr(DEPLOYER_PK);
    address buyer = vm.addr(BUYER_PK);
    address operator = vm.addr(OPERATOR_PK);
    address legacyOracle = vm.addr(LEGACY_PK);
    address seller = makeAddr("seller");
    address platformSigner = makeAddr("platformSigner");

    function _key(string memory name, uint256 pk) internal {
        vm.setEnv(name, vm.toString(bytes32(pk)));
    }

    function _state(DemoEscrow escrow, uint256 id) internal view returns (DemoEscrow.State) {
        return escrow.getEscrow(id).state;
    }

    function test_fullDemoFlow() public {
        // 環境變數是整個 Forge 程序共用；所有腳本情境集中在此依序執行。
        _checkNetworkSafety();
        _fullDemoFlow(31337, 0.01 ether);
        _fullDemoFlow(84532, 0.01 ether);
        _fullDemoFlow(8453, 0);
    }

    function _fullDemoFlow(uint256 chainId, uint256 gasTarget) internal {
        // 僅在本機 EVM 模擬不同 chain id，沒有 RPC、主網交易或真實資金。
        vm.chainId(chainId);
        vm.setEnv("EXPECTED_CHAIN_ID", vm.toString(chainId));
        vm.setEnv("ALLOW_BASE_MAINNET", chainId == 8453 ? "true" : "false");
        vm.deal(operator, 0);
        vm.deal(deployer, 1 ether);
        _key("DEPLOYER_PRIVATE_KEY", DEPLOYER_PK);
        _key("BUYER_PRIVATE_KEY", BUYER_PK);
        _key("OPERATOR_PRIVATE_KEY", OPERATOR_PK);
        _key("LEGACY_ORACLE_PRIVATE_KEY", LEGACY_PK);
        vm.setEnv("GUARDIAN_ADDRESS", chainId == 8453 ? "" : vm.toString(deployer));
        vm.setEnv("PLATFORM_SIGNER_ADDRESS", chainId == 8453 ? "" : vm.toString(platformSigner));
        vm.setEnv("APPROVER_ADDRESS", chainId == 8453 ? "" : vm.toString(ZERO));
        vm.setEnv("SELLER_ADDRESS", vm.toString(seller));
        vm.setEnv("OPERATOR_ADDRESS", vm.toString(operator));
        vm.setEnv("LEGACY_ORACLE_ADDRESS", vm.toString(legacyOracle));
        vm.setEnv("OPERATOR_GAS_WEI", vm.toString(gasTarget));

        // 主網樣板的 optional 欄位留白；不能因 source 後變成空字串而壞掉。
        (DemoStablecoin token, DemoEscrow escrow, GuardExecutor guard) = new Deploy().run();
        assertEq(escrow.admin(), deployer);
        assertEq(escrow.guardian(), deployer);
        assertEq(address(guard) == ZERO, chainId == 8453);
        vm.setEnv("TOKEN_ADDRESS", vm.toString(address(token)));
        vm.setEnv("ESCROW_ADDRESS", vm.toString(address(escrow)));

        // Onboarding: guardian and gas; running it twice changes nothing.
        OnboardOperator onboard = new OnboardOperator();
        onboard.run();
        onboard.run();
        assertEq(escrow.guardian(), operator);
        assertEq(operator.balance, gasTarget);
        assertEq(escrow.admin(), deployer);

        // First seed: plain labels, new decoy token.
        vm.setEnv("TITLE_SUFFIX", "");
        vm.setEnv("DECOY_TOKEN_ADDRESS", chainId == 8453 ? "" : vm.toString(ZERO));
        (uint256[] memory first, DemoStablecoin decoy) = new Seed().run();
        assertEq(first[0], 1);
        assertEq(decoy.minter(), buyer);
        assertEq(escrow.getEscrow(1).oracle, operator);
        assertEq(escrow.getEscrow(3).oracle, legacyOracle);
        uint256 supply = token.totalSupply();

        // Retire the first set: every escrow is refunded to the buyer.
        vm.setEnv("ESCROW_IDS", "1,2,3,4,5,6");
        new RetireEscrows().run();
        for (uint256 id = 1; id <= 6; id++) {
            assertEq(uint8(_state(escrow, id)), uint8(DemoEscrow.State.Refunded));
        }
        assertEq(token.balanceOf(buyer), supply);
        new RetireEscrows().run(); // already closed: skipped, no revert

        // Second seed: fresh titles, reused decoy, no new mint needed.
        vm.setEnv("TITLE_SUFFIX", "-2");
        vm.setEnv("DECOY_TOKEN_ADDRESS", vm.toString(address(decoy)));
        (uint256[] memory ids, DemoStablecoin decoy2) = new Seed().run();
        assertEq(address(decoy2), address(decoy));
        assertEq(token.totalSupply(), supply);
        assertEq(ids[0], 7);
        assertEq(ids[5], 12);
        uint256[] memory byTitle = escrow.escrowIdsByTitle(keccak256("vehicle-A-2"));
        assertEq(byTitle.length, 1);
        assertEq(byTitle[0], 7);
        assertEq(escrow.getEscrow(11).token, address(decoy));
        assertTrue(escrow.isRefundRequested(12));
        assertFalse(escrow.isRefundRequested(7));

        // 真正執行唯讀入口：即使所有私鑰為空，也能準備 unsigned 參數。
        vm.setEnv("ESCROW_ID", "12");
        vm.setEnv("DEPLOYER_PRIVATE_KEY", "");
        vm.setEnv("BUYER_PRIVATE_KEY", "");
        vm.setEnv("OPERATOR_PRIVATE_KEY", "");
        vm.setEnv("LEGACY_ORACLE_PRIVATE_KEY", "");
        InspectIntercepta.Inspection memory inspection = new InspectIntercepta().run();
        assertEq(inspection.chainId, chainId);
        assertEq(inspection.from, operator);
        assertTrue(inspection.refundRequested);
        assertEq(uint8(_state(escrow, 12)), uint8(DemoEscrow.State.Funded));
        _key("DEPLOYER_PRIVATE_KEY", DEPLOYER_PK);
        _key("BUYER_PRIVATE_KEY", BUYER_PK);
        _key("OPERATOR_PRIVATE_KEY", OPERATOR_PK);
        _key("LEGACY_ORACLE_PRIVATE_KEY", LEGACY_PK);

        // vehicle-A: operator release after secueji allowed it.
        vm.setEnv("ESCROW_ID", "7");
        new OperatorRelease().run();
        assertEq(uint8(_state(escrow, 7)), uint8(DemoEscrow.State.Released));
        assertEq(token.balanceOf(seller), 18_450e6);

        // The operator is not the oracle of the legacy escrows.
        vm.setEnv("ESCROW_ID", "9");
        OperatorRelease wrong = new OperatorRelease();
        vm.expectRevert(bytes("operator is not the oracle of this escrow"));
        wrong.run();

        // vehicle-C: bypass release by the old oracle key.
        new BypassRelease().run();
        assertEq(uint8(_state(escrow, 9)), uint8(DemoEscrow.State.Released));

        // Response: the operator pauses as guardian.
        vm.setEnv("ESCROW_ID", "0");
        new GuardianPause().run();
        assertTrue(escrow.paused());

        // vehicle-D: the next bypass is blocked.
        vm.setEnv("ESCROW_ID", "10");
        BypassRelease second = new BypassRelease();
        vm.expectRevert(DemoEscrow.ContractPaused.selector);
        second.run();
        vm.stopBroadcast(); // the reverted script never reached its own stopBroadcast
        assertEq(uint8(_state(escrow, 10)), uint8(DemoEscrow.State.Funded));

        // Reset by the customer.
        vm.setEnv("ESCROW_ID", "0");
        new AdminUnpause().run();
        assertFalse(escrow.paused());
    }
}
