// 合约布局：
// version: Solidity版本声明
// imports: 导入其他合约或库
// errors: 自定义错误声明
// interfaces, libraries, contracts: 接口、库和合约的声明
// Type declarations: 类型声明（如使用struct或enum）
// State variables: 状态变量声明
// Events: 事件声明
// Modifiers: 修饰器声明
// Functions: 函数声明

// 函数布局：
// constructor: 构造函数
// receive function: 接收以太币的函数（如果存在）
// fallback function: 回退函数（如果存在）
// external: 外部函数
// public: 公共函数
// internal: 内部函数
// private: 私有函数
// view & pure functions: 只读函数和纯函数

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {Script, console} from "forge-std/Script.sol";

contract Raffle is VRFConsumerBaseV2 {
    error Raff_NotEnoughEth();
    error Raff_transferFailed();
    error Raff_NotOPEN();
    error Raff_UpkeepNotNeed(
        uint256 currentBalance,
        uint256 numPlayer,
        uint256 raffState
    );

    enum RaffState {
        OPEN, //表示抽奖一个开放状态，参与者可以参与抽奖。
        Calculating //表示抽奖正在计算触发者，通常意味着不再接受新的参与者，正在等待随机数生成或其他计算完成。
    }

    RaffState private s_raffState; //跟踪当前抽奖的状态
    uint32 private constant Num_words = 1; //需要的随机数数量
    uint16 private constant Request_confirmation = 3; //确认请求所需要的区块数
    uint256 private s_lastTimeStamp; //上一次抽奖的时间
    uint256 private immutable i_interval; //@dev duration of lottery in seconds

    address payable[] private s_player; //参与抽奖的玩家地址列表
    address private s_recentWinner; //中奖的参与者

    event EnterRaffle(address indexed player); //当玩家进入抽奖时触发的事件
    event WinnerPicked(address indexed winner); //中奖者领奖时触发的事件
    event RequestedRaffleWinner(uint256 indexed requestId);

    uint256 private immutable i_enteranceFee; //进入抽奖的费用
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator; //ChainlinkVRF协调器
    bytes32 private immutable i_gasLane; //用于支付请求的gas价格上限
    uint256 private immutable i_subscriptionId; //chainlinkVRF订阅ID
    uint32 private immutable i_callbackGasLimit; //完成VRF回调的最大gas限制

    constructor(
        uint256 enteranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_enteranceFee = enteranceFee;
        i_interval = interval;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        s_lastTimeStamp = block.timestamp;

        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffState = RaffState.OPEN;
    }

    // 允许用户进入抽奖的函数
    function enterRaffle() public payable {
        if (msg.value < i_enteranceFee) {
            revert Raff_NotEnoughEth();
        }
        if (s_raffState != RaffState.OPEN) {
            revert Raff_NotOPEN(); //抽奖一个开放状态，参与者可以参与抽奖。
        }
        s_player.push(payable(msg.sender)); // 将玩家添加到玩家列表中
        emit EnterRaffle(msg.sender); // 触发进入抽奖事件
    }

    //when is the winner supposed to be picked
    function checkUpkeep(
        bytes memory /*checkdata */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        //检查从上次时间戳 s_lastTimeStamp 到当前区块时间 block.timestamp 是否已超过设定的间隔 i_interval。
        bool TimehasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval;
        bool HasBalance = address(this).balance > 0;
        bool isOpen = RaffState.OPEN == s_raffState;
        bool hasPlayer = s_player.length > 0;
        upkeepNeeded = (TimehasPassed && HasBalance && isOpen && hasPlayer);
        return (upkeepNeeded, "0x00");
    }

    // 选择获胜者的函数
    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeed, ) = checkUpkeep(""); //调用 checkUpkeep 函数以检查是否需要执行维护工作，并获取返回的 upkeepNeed 状态
        if (!upkeepNeed) {
            revert Raff_UpkeepNotNeed(
                address(this).balance,
                s_player.length,
                uint256(s_raffState)
            );
        }
        s_raffState = RaffState.Calculating; //抽奖正在计算触发者，通常意味着不再接受新的参与者，正在等待随机数生成或其他计算完成。
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            Request_confirmation,
            i_callbackGasLimit,
            Num_words
        ); // 请求随机数
        require(requestId != 0, "Invalid requestId");
        emit RequestedRaffleWinner(requestId);
    }

    // 实现VRF回调函数，用于处理随机数,CEI:Checks,Effects,Interactions
    function fulfillRandomWords(
        uint256,
        /*requestId*/ uint256[] memory randomWords
    ) internal override {
        //checks
        console.log("fulfillRandomWords called"); // 调试信息
        console.log("Random words received:", randomWords[0]); // 打印随机数
        //Effects(our own contract)
        uint256 indexOfWinner = randomWords[0] % s_player.length;
        address payable winner = s_player[indexOfWinner];
        s_recentWinner = winner;
        s_raffState = RaffState.OPEN;
        s_lastTimeStamp = block.timestamp; //更新了最后一次抽奖的时间,返回当前区块的计时器,将这个值赋给s_lastTimeStamp，记录本次抽奖完成的时间
        s_player = new address payable[](0); //重置参与者列表,清空了之前存储的所有参与者地址

        emit WinnerPicked(winner);
        //Interactions(other contracts)
        (bool success, ) = s_recentWinner.call{value: address(this).balance}(
            ""
        );
        if (!success) {
            revert Raff_transferFailed();
        }
    }

    // 获取进入抽奖费用的函数
    function getEnteranceFee() external view returns (uint256) {
        return i_enteranceFee;
    }

    function getRaffleState() external view returns (RaffState) {
        return s_raffState;
    }

    function getplayer(
        uint256 indexedOfPlayer
    ) external view returns (address) {
        return s_player[indexedOfPlayer];
    }

    function getS_recentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getLengthOfPlayers() external view returns (uint256) {
        return s_player.length;
    }

    function getS_lastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }
}
