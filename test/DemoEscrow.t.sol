// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DemoStablecoin} from "../src/DemoStablecoin.sol";
import {DemoEscrow} from "../src/DemoEscrow.sol";

/// Escrow behaviour on its own, in legacy mode (an EOA oracle). Guarded mode is
/// covered in GuardExecutor.t.sol.
contract DemoEscrowTest is Test {
    uint256 constant AMOUNT = 18_450e6;
    bytes32 constant TITLE = keccak256("title-001");

    address buyer = makeAddr("buyer");
    address seller = makeAddr("seller");
    address legacyOracle = makeAddr("legacyOracle");
    address stranger = makeAddr("stranger");

    DemoStablecoin token;
    DemoEscrow escrow;

    function setUp() public {
        token = new DemoStablecoin();
        escrow = new DemoEscrow();
        token.mint(buyer, AMOUNT * 10);
    }

    function test_createAndFundStoresTerms() public {
        uint256 id = _createFunded(legacyOracle);
        DemoEscrow.Escrow memory e = escrow.getEscrow(id);
        assertEq(e.buyer, buyer);
        assertEq(e.seller, seller);
        assertEq(e.token, address(token));
        assertEq(e.amount, AMOUNT);
        assertEq(e.titleId, TITLE);
        assertEq(e.oracle, legacyOracle);
        assertEq(uint8(e.state), uint8(DemoEscrow.State.Funded));
        assertEq(token.balanceOf(address(escrow)), AMOUNT);
    }

    function test_createEmitsIndexedTitle() public {
        vm.expectEmit(true, true, true, true, address(escrow));
        emit DemoEscrow.EscrowCreated(1, TITLE, buyer, seller, address(token), AMOUNT, legacyOracle);
        escrow.createEscrow(buyer, seller, address(token), AMOUNT, TITLE, legacyOracle);
    }

    function test_escrowIdsByTitle() public {
        bytes32 other = keccak256("title-002");
        uint256 a = escrow.createEscrow(buyer, seller, address(token), AMOUNT, TITLE, legacyOracle);
        uint256 b = escrow.createEscrow(buyer, seller, address(token), AMOUNT, other, legacyOracle);
        uint256 c = escrow.createEscrow(buyer, seller, address(token), AMOUNT, TITLE, legacyOracle);

        uint256[] memory ids = escrow.escrowIdsByTitle(TITLE);
        assertEq(ids.length, 2);
        assertEq(ids[0], a);
        assertEq(ids[1], c);
        ids = escrow.escrowIdsByTitle(other);
        assertEq(ids.length, 1);
        assertEq(ids[0], b);
        assertEq(escrow.escrowIdsByTitle(keccak256("unknown")).length, 0);
    }

    function test_onlyAdminCreates() public {
        vm.prank(stranger);
        vm.expectRevert(DemoEscrow.NotAdmin.selector);
        escrow.createEscrow(buyer, seller, address(token), AMOUNT, TITLE, legacyOracle);
    }

    function test_rejectsInvalidTerms() public {
        vm.expectRevert(DemoEscrow.InvalidTerms.selector);
        escrow.createEscrow(buyer, seller, address(token), 0, TITLE, legacyOracle);
    }

    function test_onlyBuyerFunds() public {
        uint256 id = escrow.createEscrow(buyer, seller, address(token), AMOUNT, TITLE, legacyOracle);
        vm.prank(stranger);
        vm.expectRevert(DemoEscrow.NotBuyer.selector);
        escrow.fund(id);
    }

    /// S-002 legacy: with an EOA oracle, release succeeds with no application approval.
    function test_S002_legacyOracleReleasesWithoutApproval() public {
        uint256 id = _createFunded(legacyOracle);
        vm.prank(legacyOracle);
        escrow.release(id);
        assertEq(token.balanceOf(seller), AMOUNT, "seller not paid");
        assertEq(uint8(escrow.getEscrow(id).state), uint8(DemoEscrow.State.Released), "not released");
    }

    /// S-006 basis: release is one-shot, so a retried release reverts instead of paying twice.
    function test_S006_escrowReleasesOnlyOnce() public {
        uint256 id = _createFunded(legacyOracle);
        vm.prank(legacyOracle);
        escrow.release(id);

        vm.prank(legacyOracle);
        vm.expectRevert(
            abi.encodeWithSelector(DemoEscrow.InvalidState.selector, DemoEscrow.State.Funded, DemoEscrow.State.Released)
        );
        escrow.release(id);
        assertEq(token.balanceOf(seller), AMOUNT, "paid twice");
    }

    function testFuzz_onlyOracleCanRelease(address caller) public {
        uint256 id = _createFunded(legacyOracle);
        vm.assume(caller != legacyOracle);
        vm.prank(caller);
        vm.expectRevert(DemoEscrow.NotOracle.selector);
        escrow.release(id);
    }

    function test_adminRefundsBuyer() public {
        uint256 id = _createFunded(legacyOracle);
        uint256 before = token.balanceOf(buyer);
        escrow.refund(id);
        assertEq(token.balanceOf(buyer), before + AMOUNT);
        assertEq(uint8(escrow.getEscrow(id).state), uint8(DemoEscrow.State.Refunded));
    }

    function test_adminCancelsUnfundedEscrow() public {
        uint256 id = escrow.createEscrow(buyer, seller, address(token), AMOUNT, TITLE, legacyOracle);
        escrow.cancel(id);
        assertEq(uint8(escrow.getEscrow(id).state), uint8(DemoEscrow.State.Cancelled));
    }

    function _createFunded(address oracle) internal returns (uint256 id) {
        id = escrow.createEscrow(buyer, seller, address(token), AMOUNT, TITLE, oracle);
        vm.prank(buyer);
        token.approve(address(escrow), AMOUNT);
        vm.prank(buyer);
        escrow.fund(id);
    }
}
