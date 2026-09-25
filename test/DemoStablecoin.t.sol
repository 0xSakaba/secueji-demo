// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DemoStablecoin} from "../src/DemoStablecoin.sol";

contract DemoStablecoinTest is Test {
    DemoStablecoin internal token;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        token = new DemoStablecoin();
    }

    function test_metadata() public view {
        assertEq(token.name(), "Demo USD");
        assertEq(token.symbol(), "dUSD");
        assertEq(token.decimals(), 6);
        assertEq(token.minter(), address(this));
    }

    function test_minterMints() public {
        token.mint(alice, 100e6);
        assertEq(token.balanceOf(alice), 100e6);
        assertEq(token.totalSupply(), 100e6);
    }

    function test_nonMinterCannotMint() public {
        vm.prank(alice);
        vm.expectRevert(DemoStablecoin.NotMinter.selector);
        token.mint(alice, 1);
    }

    function test_transfer() public {
        token.mint(alice, 100e6);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 40e6));
        assertEq(token.balanceOf(alice), 60e6);
        assertEq(token.balanceOf(bob), 40e6);
    }

    function test_transferRevertsOnInsufficientBalance() public {
        token.mint(alice, 1e6);
        vm.prank(alice);
        vm.expectRevert(DemoStablecoin.InsufficientBalance.selector);
        token.transfer(bob, 2e6);
    }

    function test_transferFromSpendsAllowance() public {
        token.mint(alice, 100e6);
        vm.prank(alice);
        token.approve(bob, 30e6);
        vm.prank(bob);
        token.transferFrom(alice, bob, 20e6);
        assertEq(token.allowance(alice, bob), 10e6);
        assertEq(token.balanceOf(bob), 20e6);
    }

    function test_transferFromRevertsOnInsufficientAllowance() public {
        token.mint(alice, 100e6);
        vm.prank(alice);
        token.approve(bob, 1e6);
        vm.prank(bob);
        vm.expectRevert(DemoStablecoin.InsufficientAllowance.selector);
        token.transferFrom(alice, bob, 2e6);
    }

    function test_infiniteAllowanceIsNotDecremented() public {
        token.mint(alice, 100e6);
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        vm.prank(bob);
        token.transferFrom(alice, bob, 50e6);
        assertEq(token.allowance(alice, bob), type(uint256).max);
    }
}
