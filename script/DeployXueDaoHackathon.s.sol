// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {XueDaoHackathon} from "../src/XueDaoHackathon.sol";

contract DeployXueDaoHackathon is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOY_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // 使用 BNB Testnet 上的 Chainlink ETH/USD 价格预言机地址
        address priceFeed = 0x143db3CEEfbdfe5631aDD3E50f7614B6ba708BA7;

        address kjTokenAddress = vm.envAddress("KJ_TOKEN_ADDRESS"); // KJ 代幣合約地址
        uint256 kjFee = vm.envUint("KJ_FEE"); // KJ 代幣手續費數量

        XueDaoHackathon contractInstance = new XueDaoHackathon(
            0xE2C2fAe0Fb6085049c5AE383e8C32485de64Df41, // 新的退款地址
            120, // 86400 seconds = 1 day
            priceFeed,
            kjTokenAddress, // KJ 代幣合約地址
            kjFee // KJ 代幣手續費數量
        );
        vm.stopBroadcast();
    }
}
