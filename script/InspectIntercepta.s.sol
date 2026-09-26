// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {console2} from "forge-std/Script.sol";
import {DemoScript} from "./DemoScript.sol";
import {DemoEscrow} from "../src/DemoEscrow.sol";

/// @notice 唯讀準備 Intercepta 的 unsigned transaction；不讀私鑰、不簽名、不廣播。
contract InspectIntercepta is DemoScript {
    struct Inspection {
        uint256 chainId;
        address from;
        address to;
        bytes data;
        uint256 value;
        address token;
        bool refundRequested;
        bool paused;
        DemoEscrow.State state;
    }

    function inspect(DemoEscrow escrow, uint256 id) public view returns (Inspection memory result) {
        // from 使用合約內真正的 oracle，不能拿一個任意地址假裝可執行。
        DemoEscrow.Escrow memory item = escrow.getEscrow(id);
        // getEscrow 對不存在的 id 會回傳零值；不可把零值當成可供掃描的交易。
        if (item.state == DemoEscrow.State.None) revert DemoEscrow.UnknownEscrow(id);
        result = Inspection({
            chainId: block.chainid,
            from: item.oracle,
            to: address(escrow),
            data: abi.encodeCall(DemoEscrow.release, (id)),
            value: 0,
            token: item.token,
            refundRequested: escrow.isRefundRequested(id),
            paused: escrow.paused() || escrow.escrowPaused(id),
            state: item.state
        });
    }

    function run() external view returns (Inspection memory result) {
        _checkNetwork();
        result = inspect(DemoEscrow(vm.envAddress("ESCROW_ADDRESS")), vm.envUint("ESCROW_ID"));
        console2.log("Chain ID:", result.chainId);
        console2.log("From (escrow oracle):", result.from);
        console2.log("To (escrow contract):", result.to);
        console2.log("Data:", vm.toString(result.data));
        console2.log("Value (wei):", result.value);
        console2.log("Token:", result.token);
        console2.log("Refund requested:", result.refundRequested);
        console2.log("Paused:", result.paused);
        console2.log("Escrow state:", uint8(result.state));
    }
}
