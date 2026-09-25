// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DemoStablecoin} from "../src/DemoStablecoin.sol";
import {DemoEscrow} from "../src/DemoEscrow.sol";
import {GuardExecutor} from "../src/GuardExecutor.sol";

/// Guardian role and emergency pause. The response to a bypass release is to
/// pause: the guardian can stop funds from moving but can never move them or
/// lift the pause.
contract DemoEscrowPauseTest is Test {
    uint256 constant APPROVER_PK = 0xA11CE;
    uint256 constant PLATFORM_PK = 0xB0B;
    uint256 constant AMOUNT = 18_450e6;
    bytes32 constant TITLE = keccak256("vehicle-A");

    address buyer = makeAddr("buyer");
    address seller = makeAddr("seller");
    address legacyOracle = makeAddr("legacyOracle");
    address guardian = makeAddr("guardian");
    address stranger = makeAddr("stranger");

    DemoStablecoin token;
    DemoEscrow escrow;
    GuardExecutor guard;

    event GuardianSet(address indexed previousGuardian, address indexed newGuardian);
    event Paused(address indexed account);
    event Unpaused(address indexed account);
    event EscrowPaused(uint256 indexed escrowId, address indexed account);
    event EscrowUnpaused(uint256 indexed escrowId, address indexed account);

    function setUp() public {
        token = new DemoStablecoin();
        escrow = new DemoEscrow();
        guard = new GuardExecutor(escrow, vm.addr(PLATFORM_PK));
        guard.setApprover(vm.addr(APPROVER_PK), true);
        token.mint(buyer, AMOUNT * 10);
        escrow.setGuardian(guardian);
    }

    /* ---------------------------------------------------------------- */
    /* Guardian role                                                     */
    /* ---------------------------------------------------------------- */

    function test_deployerIsDefaultGuardian() public {
        DemoEscrow fresh = new DemoEscrow();
        assertEq(fresh.guardian(), address(this));
        assertFalse(fresh.paused());
    }

    function test_adminSetsGuardian() public {
        address next = makeAddr("nextGuardian");
        vm.expectEmit(address(escrow));
        emit GuardianSet(guardian, next);
        escrow.setGuardian(next);
        assertEq(escrow.guardian(), next);
    }

    function test_onlyAdminSetsGuardian() public {
        vm.prank(guardian);
        vm.expectRevert(DemoEscrow.NotAdmin.selector);
        escrow.setGuardian(stranger);
    }

    function test_guardianCannotBeZero() public {
        vm.expectRevert(DemoEscrow.ZeroAddress.selector);
        escrow.setGuardian(address(0));
    }

    /* ---------------------------------------------------------------- */
    /* Global pause                                                      */
    /* ---------------------------------------------------------------- */

    function test_guardianPausesAndEmits() public {
        vm.expectEmit(address(escrow));
        emit Paused(guardian);
        vm.prank(guardian);
        escrow.pause();
        assertTrue(escrow.paused());
    }

    function test_adminCanPause() public {
        escrow.pause();
        assertTrue(escrow.paused());
    }

    function testFuzz_strangerCannotPause(address caller) public {
        vm.assume(caller != guardian && caller != address(this));
        vm.prank(caller);
        vm.expectRevert(DemoEscrow.NotGuardian.selector);
        escrow.pause();
    }

    /// Bypass response: after a pause the legacy oracle EOA can no longer release.
    function test_pauseBlocksLegacyRelease() public {
        uint256 first = _createFunded(legacyOracle);
        uint256 second = _createFunded(legacyOracle);
        vm.prank(legacyOracle);
        escrow.release(first);

        vm.prank(guardian);
        escrow.pause();

        vm.prank(legacyOracle);
        vm.expectRevert(DemoEscrow.ContractPaused.selector);
        escrow.release(second);
        assertEq(uint8(escrow.getEscrow(second).state), uint8(DemoEscrow.State.Funded));
        assertEq(token.balanceOf(seller), AMOUNT, "second release went through");
    }

    function test_pauseBlocksGuardedRelease() public {
        uint256 id = _createFunded(address(guard));
        (
            GuardExecutor.ReleaseIntent memory intent,
            bytes memory approvalSig,
            GuardExecutor.Authorization memory auth,
            bytes memory authSig
        ) = _signedBundle(id, 1);

        vm.prank(guardian);
        escrow.pause();

        vm.expectRevert(DemoEscrow.ContractPaused.selector);
        guard.execute(intent, approvalSig, auth, authSig);
        assertFalse(guard.nonceUsed(1), "nonce consumed by a reverted release");
    }

    function test_pauseBlocksRefund() public {
        uint256 id = _createFunded(legacyOracle);
        vm.prank(guardian);
        escrow.pause();
        vm.expectRevert(DemoEscrow.ContractPaused.selector);
        escrow.refund(id);
    }

    function test_onlyAdminUnpauses() public {
        vm.prank(guardian);
        escrow.pause();

        vm.prank(guardian);
        vm.expectRevert(DemoEscrow.NotAdmin.selector);
        escrow.unpause();

        vm.expectEmit(address(escrow));
        emit Unpaused(address(this));
        escrow.unpause();
        assertFalse(escrow.paused());
    }

    function test_releaseWorksAgainAfterUnpause() public {
        uint256 id = _createFunded(legacyOracle);
        escrow.pause();
        escrow.unpause();
        vm.prank(legacyOracle);
        escrow.release(id);
        assertEq(token.balanceOf(seller), AMOUNT);
    }

    /* ---------------------------------------------------------------- */
    /* Per-escrow pause                                                  */
    /* ---------------------------------------------------------------- */

    function test_guardianPausesSingleEscrow() public {
        uint256 paused = _createFunded(legacyOracle);
        uint256 other = _createFunded(legacyOracle);

        vm.expectEmit(address(escrow));
        emit EscrowPaused(paused, guardian);
        vm.prank(guardian);
        escrow.pauseEscrow(paused);
        assertTrue(escrow.escrowPaused(paused));

        vm.prank(legacyOracle);
        vm.expectRevert(abi.encodeWithSelector(DemoEscrow.EscrowIsPaused.selector, paused));
        escrow.release(paused);

        vm.expectRevert(abi.encodeWithSelector(DemoEscrow.EscrowIsPaused.selector, paused));
        escrow.refund(paused);

        vm.prank(legacyOracle);
        escrow.release(other);
        assertEq(token.balanceOf(seller), AMOUNT, "other escrow blocked");
    }

    function test_pauseEscrowRejectsUnknownId() public {
        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(DemoEscrow.UnknownEscrow.selector, 42));
        escrow.pauseEscrow(42);
    }

    function test_strangerCannotPauseEscrow() public {
        uint256 id = _createFunded(legacyOracle);
        vm.prank(stranger);
        vm.expectRevert(DemoEscrow.NotGuardian.selector);
        escrow.pauseEscrow(id);
    }

    function test_onlyAdminUnpausesEscrow() public {
        uint256 id = _createFunded(legacyOracle);
        vm.prank(guardian);
        escrow.pauseEscrow(id);

        vm.prank(guardian);
        vm.expectRevert(DemoEscrow.NotAdmin.selector);
        escrow.unpauseEscrow(id);

        vm.expectEmit(address(escrow));
        emit EscrowUnpaused(id, address(this));
        escrow.unpauseEscrow(id);
        assertFalse(escrow.escrowPaused(id));

        vm.prank(legacyOracle);
        escrow.release(id);
        assertEq(token.balanceOf(seller), AMOUNT);
    }

    /* ---------------------------------------------------------------- */
    /* Helpers                                                           */
    /* ---------------------------------------------------------------- */

    function _createFunded(address oracle) internal returns (uint256 id) {
        id = escrow.createEscrow(buyer, seller, address(token), AMOUNT, TITLE, oracle);
        vm.prank(buyer);
        token.approve(address(escrow), AMOUNT);
        vm.prank(buyer);
        escrow.fund(id);
    }

    function _signedBundle(uint256 id, uint256 nonce)
        internal
        view
        returns (
            GuardExecutor.ReleaseIntent memory intent,
            bytes memory approvalSig,
            GuardExecutor.Authorization memory auth,
            bytes memory authSig
        )
    {
        intent = GuardExecutor.ReleaseIntent({
            escrow: address(escrow),
            escrowId: id,
            titleId: TITLE,
            token: address(token),
            beneficiary: seller,
            amount: AMOUNT,
            businessRef: keccak256("order-A"),
            policyVersion: keccak256("policy-v1"),
            nonce: nonce,
            expiry: block.timestamp + 1 hours
        });
        approvalSig = _sign(APPROVER_PK, guard.intentDigest(intent));
        auth = GuardExecutor.Authorization({
            intentHash: guard.intentDigest(intent),
            policyVersion: intent.policyVersion,
            evidenceHash: keccak256("evidence"),
            nonce: nonce,
            expiry: block.timestamp + 10 minutes
        });
        authSig = _sign(PLATFORM_PK, guard.authorizationDigest(auth));
    }

    function _sign(uint256 pk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }
}
