// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {DemoStablecoin} from "../src/DemoStablecoin.sol";
import {PrepareRiskyApproval} from "../script/PrepareRiskyApproval.s.sol";

contract RiskyApprovalTest is Test {
    DemoStablecoin token;
    PrepareRiskyApproval preview;
    address owner = makeAddr("demo-owner");
    address spender = makeAddr("candidate-not-a-real-risk-result");

    function setUp() public {
        token = new DemoStablecoin();
        preview = new PrepareRiskyApproval();
        token.mint(owner, 10e6);
    }

    function test_preparesUnlimitedApprovalWithoutGrantingAnyAllowance() public {
        vm.chainId(8453); // 僅本機 EVM 模擬網路識別。
        PrepareRiskyApproval.Request memory result = preview.prepare(owner, address(token), spender);
        assertEq(result.chainId, 8453);
        assertEq(result.from, owner);
        assertEq(result.to, address(token));
        assertEq(result.data, abi.encodeWithSignature("approve(address,uint256)", spender, type(uint256).max));
        assertEq(result.value, 0);
        assertEq(token.allowance(owner, spender), 0);
        assertEq(token.balanceOf(owner), 10e6);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_rejectsZeroOwner() public {
        vm.expectRevert(bytes("demo: zero approval party"));
        preview.prepare(address(0), address(token), spender);
    }

    function test_rejectsZeroSpender() public {
        vm.expectRevert(bytes("demo: zero approval party"));
        preview.prepare(owner, address(token), address(0));
    }

    function test_rejectsTokenWithoutCode() public {
        vm.expectRevert(bytes("demo: token has no code on this chain"));
        preview.prepare(owner, makeAddr("not-deployed"), spender);
    }
}
