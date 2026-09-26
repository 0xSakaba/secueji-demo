// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {console2} from "forge-std/Script.sol";
import {DemoScript} from "./DemoScript.sol";
import {DemoStablecoin} from "../src/DemoStablecoin.sol";

/// @notice 僅產生 approve 的未簽名掃描參數，不呼叫 approve、不讀私鑰、不廣播。
/// RISKY_SPENDER_ADDRESS 是測試候選；是否有風險必須以真實 Intercepta 回應為準。
contract PrepareRiskyApproval is DemoScript {
    struct Request {
        uint256 chainId;
        address from;
        address to;
        bytes data;
        uint256 value;
    }

    function prepare(address owner, address token, address spender) public view returns (Request memory result) {
        require(owner != address(0) && spender != address(0), "demo: zero approval party");
        require(token.code.length > 0, "demo: token has no code on this chain");
        // 只編碼，不呼叫 token 或 spender。最大授權量本身不是 provider 已判定惡意的證據。
        result = Request({
            chainId: block.chainid,
            from: owner,
            to: token,
            data: abi.encodeCall(DemoStablecoin.approve, (spender, type(uint256).max)),
            value: 0
        });
    }

    function run() external view returns (Request memory result) {
        _checkNetwork();
        result = prepare(
            vm.envAddress("APPROVAL_OWNER_ADDRESS"),
            vm.envAddress("TOKEN_ADDRESS"),
            vm.envAddress("RISKY_SPENDER_ADDRESS")
        );
        console2.log("UNSIGNED ANALYSIS ONLY - DO NOT SIGN OR BROADCAST");
        console2.log("Chain ID:", result.chainId);
        console2.log("From:", result.from);
        console2.log("To (demo token):", result.to);
        console2.log("Data:", vm.toString(result.data));
        console2.log("Value (wei):", result.value);
    }
}
