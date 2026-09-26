// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";

/// @notice 共用腳本防呆；不改變合約權限，也不能替代 Secueji 的政策檢查。
abstract contract DemoScript is Script {
    function _checkNetwork() internal view {
        // 沒有指定時只允許本機；不從 RPC 自動推測使用者想操作哪個網路。
        uint256 expected = vm.envOr("EXPECTED_CHAIN_ID", uint256(31337));
        require(block.chainid == expected, "demo: unexpected chain id");
        require(expected == 31337 || expected == 84532 || expected == 8453, "demo: unsupported network");
        if (expected == 8453) {
            require(vm.envOr("ALLOW_BASE_MAINNET", false), "demo: Base mainnet requires explicit opt-in");
        }
    }

    function _operatorGasTarget() internal view returns (uint256) {
        // 主網絕不沿用測試網的 0.01 ETH 預設補款；0 表示不補款。
        if (block.chainid == 8453) {
            require(
                bytes(vm.envOr("OPERATOR_GAS_WEI", string(""))).length != 0,
                "demo: set OPERATOR_GAS_WEI explicitly on mainnet"
            );
            return vm.envUint("OPERATOR_GAS_WEI");
        }
        return vm.envOr("OPERATOR_GAS_WEI", uint256(0.01 ether));
    }
}
