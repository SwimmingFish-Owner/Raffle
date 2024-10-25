// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Script} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {CreateSubscripts, FundSubscription, AddConsumer} from "./Interactions.s.sol";
import {Test, console} from "lib/forge-std/src/Test.sol";

contract DeployRaffle is Script {
    FundSubscription FUNDSubscription = new FundSubscription();

    function run() external returns (Raffle, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (
            uint256 enteranceFee,
            uint256 interval,
            address vrfCoordinator,
            bytes32 gasLane,
            uint256 subscriptionId,
            uint32 callbackGasLimit,
            address link,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();
        console.log("Current msg.sender:", msg.sender);

        if (subscriptionId == 0) {
            CreateSubscripts createSubscripts = new CreateSubscripts();
            subscriptionId = createSubscripts.createSubscript(vrfCoordinator);
            //Fund it!

            FUNDSubscription.fundSubscriptionS(
                vrfCoordinator,
                subscriptionId,
                link
            );
        }
        vm.startBroadcast();
        Raffle raffle = new Raffle(
            enteranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit
        );
        console.log("Deployer address:", msg.sender);
        vm.stopBroadcast();
        AddConsumer addconsumer = new AddConsumer();
        console.log("Starting to add consumer");

        addconsumer.addConsumer(
            address(raffle),
            vrfCoordinator,
            subscriptionId,
            deployerKey
        );
        console.log("Finished adding consumer");
        return (raffle, helperConfig);
    }
}
