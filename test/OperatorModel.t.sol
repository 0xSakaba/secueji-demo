// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DemoStablecoin} from "../src/DemoStablecoin.sol";
import {DemoEscrow} from "../src/DemoEscrow.sol";

/// Demo path: the customer (escrow admin) delegates to a Secueji operator
/// account. The operator is the oracle of the escrows secueji manages and the
/// guardian of the contract. Everything else stays with the admin.
contract OperatorModelTest is Test {
    uint256 constant AMOUNT = 18_450e6;
    bytes32 constant TITLE_A = keccak256("vehicle-A");
    bytes32 constant TITLE_C = keccak256("vehicle-C");

    address buyer = makeAddr("buyer");
    address seller = makeAddr("seller");
    address operator = makeAddr("operator");
    address legacyOracle = makeAddr("legacyOracle");

    DemoStablecoin token;
    DemoEscrow escrow;

    event EscrowReleased(
        uint256 indexed escrowId, address indexed seller, address token, uint256 amount, address indexed caller
    );
    event Paused(address indexed account);

    function setUp() public {
        token = new DemoStablecoin();
        escrow = new DemoEscrow();
        escrow.setGuardian(operator);
        token.mint(buyer, AMOUNT * 10);
        vm.prank(buyer);
        token.approve(address(escrow), type(uint256).max);
    }

    function _funded(bytes32 title, address oracle) internal returns (uint256 id) {
        id = escrow.createEscrow(buyer, seller, address(token), AMOUNT, title, oracle);
        vm.prank(buyer);
        escrow.fund(id);
    }

    /// S-001: after secueji allows the request, the operator sends release.
    function test_operatorReleasesItsEscrow() public {
        uint256 id = _funded(TITLE_A, operator);
        vm.expectEmit(address(escrow));
        emit EscrowReleased(id, seller, address(token), AMOUNT, operator);
        vm.prank(operator);
        escrow.release(id);
        assertEq(uint8(escrow.getEscrow(id).state), uint8(DemoEscrow.State.Released));
        assertEq(token.balanceOf(seller), AMOUNT);
    }

    /// The operator has no release authority over escrows it is not the oracle of.
    function test_operatorCannotReleaseLegacyEscrow() public {
        uint256 id = _funded(TITLE_C, legacyOracle);
        vm.prank(operator);
        vm.expectRevert(DemoEscrow.NotOracle.selector);
        escrow.release(id);
    }

    /// The admin keeps its own powers; the operator gets none of them.
    function test_operatorHasNoAdminPowers() public {
        uint256 id = _funded(TITLE_A, operator);
        vm.startPrank(operator);
        vm.expectRevert(DemoEscrow.NotAdmin.selector);
        escrow.createEscrow(buyer, operator, address(token), AMOUNT, TITLE_A, operator);
        vm.expectRevert(DemoEscrow.NotAdmin.selector);
        escrow.refund(id);
        vm.expectRevert(DemoEscrow.NotAdmin.selector);
        escrow.setGuardian(operator);
        vm.expectRevert(DemoEscrow.NotAdmin.selector);
        escrow.unpause();
        vm.expectRevert(DemoEscrow.NotAdmin.selector);
        escrow.unpauseEscrow(id);
        vm.stopPrank();
    }

    /// S-002: an old oracle key releases outside secueji; the caller in the
    /// event is not the operator, which is what the monitor looks for.
    /// The operator then pauses as guardian and the next bypass is blocked.
    function test_bypassThenOperatorPausesAndNextBypassFails() public {
        uint256 c = _funded(TITLE_C, legacyOracle);
        uint256 d = _funded(keccak256("vehicle-D"), legacyOracle);

        vm.expectEmit(address(escrow));
        emit EscrowReleased(c, seller, address(token), AMOUNT, legacyOracle);
        vm.prank(legacyOracle);
        escrow.release(c);

        vm.expectEmit(address(escrow));
        emit Paused(operator);
        vm.prank(operator);
        escrow.pause();

        vm.prank(legacyOracle);
        vm.expectRevert(DemoEscrow.ContractPaused.selector);
        escrow.release(d);
        assertEq(uint8(escrow.getEscrow(d).state), uint8(DemoEscrow.State.Funded));
    }

    /// Per-escrow pause by the operator blocks only that escrow.
    function test_operatorPausesOneEscrow() public {
        uint256 a = _funded(TITLE_A, operator);
        uint256 d = _funded(keccak256("vehicle-D"), legacyOracle);
        vm.prank(operator);
        escrow.pauseEscrow(d);

        vm.prank(legacyOracle);
        vm.expectRevert(abi.encodeWithSelector(DemoEscrow.EscrowIsPaused.selector, d));
        escrow.release(d);

        vm.prank(operator);
        escrow.release(a);
    }

    /// A pause stops the operator too, until the admin lifts it.
    function test_pauseBlocksOperatorUntilAdminUnpauses() public {
        uint256 a = _funded(TITLE_A, operator);
        vm.prank(operator);
        escrow.pause();

        vm.prank(operator);
        vm.expectRevert(DemoEscrow.ContractPaused.selector);
        escrow.release(a);

        escrow.unpause();
        vm.prank(operator);
        escrow.release(a);
    }

    /// Refund conflict: the contract does not stop a release over a refund request; the
    /// secueji policy must hold it before the operator sends anything.
    function test_refundRequestDoesNotBlockOperatorOnChain() public {
        uint256 f = _funded(keccak256("vehicle-F"), operator);
        vm.prank(buyer);
        escrow.requestRefund(f, "Inspection failed: odometer reading does not match the listing");
        assertTrue(escrow.isRefundRequested(f));

        vm.prank(operator);
        escrow.release(f);
        assertEq(uint8(escrow.getEscrow(f).state), uint8(DemoEscrow.State.Released));
    }
}
