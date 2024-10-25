// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "test/Mocks/LinkToken.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

contract CreateSubscripts is Script {
    function UsingConfig() public returns (uint256) {
        HelperConfig helperConfig = new HelperConfig();
        (, , address vrfCoordinator, , , , , ) = helperConfig
            .activeNetworkConfig();
        return createSubscript(vrfCoordinator);
    }

    function createSubscript(address vrfCoordinator) public returns (uint256) {
        console.log("creat subscript on ChainId:", block.chainid);
        vm.startBroadcast();
        uint256 subId = VRFCoordinatorV2Mock(vrfCoordinator)
            .createSubscription();
        vm.stopBroadcast();
        console.log("your sub Id is:", subId);
        console.log("please update subscriptionId in Helperconfig.s.sol");
        return subId;
    }

    function run() external returns (uint256) {
        return UsingConfig();
    }
}

contract FundSubscription is Script {
    uint96 public constant FUND_Amount = 3 ether;

    function fundUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        (
            ,
            ,
            address vrfCoordinator,
            ,
            uint256 subId,
            ,
            address link,

        ) = helperConfig.activeNetworkConfig();
        fundSubscriptionS(vrfCoordinator, subId, link);
    }

    function fundSubscriptionS(
        address vrfCoordinator,
        uint256 subId,
        address link
    ) public {
        console.log("Funding subscription:", subId);
        console.log("Using vrfCoordinator:", vrfCoordinator);
        console.log("On ChainId", block.chainid);
        if (block.chainid == 31337) {
            vm.startBroadcast();
            VRFCoordinatorV2Mock(vrfCoordinator).fundSubscription(
                subId,
                FUND_Amount
            );
            vm.stopBroadcast();
        } else {
            vm.startBroadcast();
            LinkToken(link).transferAndCall(
                vrfCoordinator,
                FUND_Amount,
                abi.encode(subId)
            );
            vm.stopBroadcast();
        }
    }

    function run() external {
        fundUsingConfig();
    }
}

contract AddConsumer is Script {
    function addConsumer(
        address raffle,
        address vrfCoordinator,
        uint256 subId,
        uint256 deployerKey
    ) public {
        deployerKey = 0xac8e1e8399980e4932366858e2816ee179841662f8db4cd52f2840e5bc61fb33;
        console.log("adding consumer contract:", raffle);
        console.log("Using vrfCoordinator:", vrfCoordinator);
        console.log("On chainid", block.chainid);
        vm.startBroadcast(deployerKey);

        VRFCoordinatorV2Mock(vrfCoordinator).addConsumer(subId, raffle);
        vm.stopBroadcast();
    }

    function addConsumerUsingConfig(address raffle) public {
        HelperConfig helperConfig = new HelperConfig();
        (
            ,
            ,
            address vrfCoordinator,
            ,
            uint256 subId,
            ,
            ,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();
        addConsumer(raffle, vrfCoordinator, subId, deployerKey);
    }

    function run() external {
        address raffle = DevOpsTools.get_most_recent_deployment(
            "Raffle",
            block.chainid
        );
        addConsumerUsingConfig(raffle);
    }
}
