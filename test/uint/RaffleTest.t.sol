// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {DeployRaffle} from "script/DeployRaffle.s.sol";
import {Raffle} from "src/Raffle.sol";
import {Test, console} from "lib/forge-std/src/Test.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    Raffle raffle;
    HelperConfig helperConfig;
    address public Player = makeAddr("player");
    uint256 public constant StartUser_Blance = 10 ether;
    uint256 enteranceFee;
    event EnterRaffle(address indexed player);

    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint256 subscriptionId;
    uint32 callbackGasLimit;
    address link;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        (
            enteranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link,

        ) = helperConfig.activeNetworkConfig();
        console.log("msg.sender", msg.sender);
        vm.deal(Player, StartUser_Blance);
    }

    function testgetRaffleStateisOpen() public view {
        assert(raffle.getRaffleState() == Raffle.RaffState.OPEN);
    }

    function testEnterRaffleCanPay() public {
        vm.prank(Player);
        vm.expectRevert(Raffle.Raff_NotEnoughEth.selector);
        raffle.enterRaffle();
    }

    function testRecordPlayerwhenTheyEnter() public {
        vm.prank(Player);
        raffle.enterRaffle{value: enteranceFee}(); // 玩家以一定的以太币进入抽奖
        address playerRecorded = raffle.getplayer(0); // 获取参与者列表中的第一个玩家
        assert(playerRecorded == Player);
    }

    function testEmitEventOnEntrance() public {
        vm.prank(Player);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnterRaffle(Player);
        raffle.enterRaffle{value: enteranceFee}();
    }

    function testcantEnterwhenRaffStateisCalculating() public {
        vm.prank(Player);
        raffle.enterRaffle{value: enteranceFee}(); //玩家第一次成功进入抽奖，支付入场费
        vm.warp(block.timestamp + interval + 1); //将区块时间戳向前推进了 interval + 1 秒
        vm.roll(block.number + 1); //增加区块号，模拟时间的推移。
        raffle.performUpkeep("");
        vm.expectRevert(Raffle.Raff_NotOPEN.selector); //期望下一个交易会被回滚，并返回 Raff_NotOPEN 错误

        vm.prank(Player);
        raffle.enterRaffle{value: enteranceFee}(); //尝试再次进入抽奖，但这次应该会失败
    }

    function testCheckUpkeepReturnsFlaseIfNoBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepRetrunsFlaseIfNoOPEN() public {
        vm.prank(Player);
        raffle.enterRaffle{value: enteranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepRetrunsFalseIfEnoughTimeHasntPassed() public {
        vm.prank(Player);
        raffle.enterRaffle{value: enteranceFee}();
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnTrueWhenParametersAreGood() public {
        vm.prank(Player);
        raffle.enterRaffle{value: enteranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(upkeepNeeded);
    }

    function testperformUpkeepCanOnlyRunIfperfomUpkeepTrue() public {
        vm.prank(Player);
        raffle.enterRaffle{value: enteranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
    }

    function testperformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        uint256 currentBalance = 0;
        uint256 numPlayer = 0;
        uint256 raffleState = 0;
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raff_UpkeepNotNeed.selector,
                currentBalance,
                numPlayer,
                raffleState
            )
        );
        raffle.performUpkeep("");
    }

    modifier raffleEnteredAndTimePassed() {
        vm.prank(Player);
        raffle.enterRaffle{value: enteranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId()
        public
        raffleEnteredAndTimePassed
    {
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        Raffle.RaffState rState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint256(rState) == 1);
    }

    function testfulfillRandomWordsBeCallAfterPerformUpkeep(
        uint256 randomRequestId
    ) public raffleEnteredAndTimePassed {
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testfullfillRandomWordsPickAwinnerAndSendMoney()
        public
        raffleEnteredAndTimePassed
    {
        uint256 addEnters = 5;
        uint256 startEnter = 1;
        for (uint256 i = startEnter; i < addEnters + startEnter; i++) {
            address player = address(uint160(i));
            hoax(player, StartUser_Blance);
            raffle.enterRaffle{value: enteranceFee}();
        }
        uint256 price = enteranceFee * (addEnters + 1);

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        uint256 previousTimestamp = raffle.getS_lastTimeStamp();

        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        // assert(uint256(raffle.getRaffleState()) == 0);
        // assert(raffle.getS_recentWinner() != address(0));
        // assert(raffle.getLengthOfPlayers() == 0);
        // assert(previousTimestamp < raffle.getS_lastTimeStamp());
        console.log(raffle.getS_recentWinner().balance);
        console.log(price);
        console.log(price + StartUser_Blance);
        assert(
            raffle.getS_recentWinner().balance ==
                price + StartUser_Blance - enteranceFee
        );
    }
}
