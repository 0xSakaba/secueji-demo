// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DemoEscrow} from "../src/DemoEscrow.sol";
import {DemoStablecoin} from "../src/DemoStablecoin.sol";
import {InspectIntercepta} from "../script/InspectIntercepta.s.sol";

contract InterceptaInspectionTest is Test {
    DemoEscrow escrow;
    DemoStablecoin token;
    InspectIntercepta inspector;
    address buyer = makeAddr("buyer");
    address seller = makeAddr("seller");
    address operator = makeAddr("operator");
    uint256 id;

    function setUp() public {
        escrow = new DemoEscrow();
        token = new DemoStablecoin();
        inspector = new InspectIntercepta();
        id = escrow.createEscrow(buyer, seller, address(token), 123e6, keccak256("inspection-case"), operator);
        token.mint(buyer, 123e6);
        vm.startPrank(buyer);
        token.approve(address(escrow), 123e6);
        escrow.fund(id);
        vm.stopPrank();
    }

    function test_buildsUnsignedRequestWithoutReleasingFunds() public {
        vm.chainId(8453); // 本機 EVM，不連主網。
        InspectIntercepta.Inspection memory result = inspector.inspect(escrow, id);
        assertEq(result.chainId, 8453);
        assertEq(result.from, operator);
        assertEq(result.to, address(escrow));
        assertEq(result.data, abi.encodeWithSignature("release(uint256)", id));
        assertEq(result.value, 0);
        assertEq(result.token, address(token));
        assertEq(uint8(result.state), uint8(DemoEscrow.State.Funded));
        assertFalse(result.refundRequested);
        assertFalse(result.paused);
        assertEq(token.balanceOf(address(escrow)), 123e6);
        assertEq(token.balanceOf(seller), 0);
    }

    function test_keepsBusinessConflictSeparateFromProviderResult() public {
        vm.prank(buyer);
        escrow.requestRefund(id, "demo dispute");
        escrow.pauseEscrow(id);
        InspectIntercepta.Inspection memory result = inspector.inspect(escrow, id);
        assertTrue(result.refundRequested);
        assertTrue(result.paused);
        assertEq(uint8(escrow.getEscrow(id).state), uint8(DemoEscrow.State.Funded));
    }

    function test_rejectsMissingEscrowInsteadOfGeneratingZeroAddressRequest() public {
        vm.expectRevert(abi.encodeWithSelector(DemoEscrow.UnknownEscrow.selector, 999));
        inspector.inspect(escrow, 999);
    }
}
