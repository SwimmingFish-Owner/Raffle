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

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/interfaces/AutomationCompatibleInterface.sol";
import {console} from "forge-std/console.sol";

contract Raffle is VRFConsumerBaseV2Plus, AutomationCompatibleInterface {
    error Raffle__UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 numPlayers,
        uint256 raffleState
    );
    error Raffle__TransferFailed();
    error Raffle__SendMoreToEnterRaffle();
    error Raffle__RaffleNotOpen();

    enum RaffState {
        OPEN,
        Calculating
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
    bytes32 private immutable i_gasLane; //用于支付请求的gas价格上限
    uint256 private immutable i_subscriptionId; //chainlinkVRF订阅ID
    uint32 private immutable i_callbackGasLimit; //完成VRF回调的最大gas限制

    constructor(
        uint256 subscriptionId,
        bytes32 gasLane, // keyHash
        uint256 interval,
        uint256 entranceFee,
        uint32 callbackGasLimit,
        address vrfCoordinatorV2
    ) VRFConsumerBaseV2Plus(vrfCoordinatorV2) {
        i_gasLane = gasLane;
        i_interval = interval;
        i_subscriptionId = subscriptionId;
        i_enteranceFee = entranceFee;
        s_raffState = RaffState.OPEN;
        s_lastTimeStamp = block.timestamp;
        i_callbackGasLimit = callbackGasLimit;
        // uint256 balance = address(this).balance;
        // if (balance > 0) {
        //     payable(msg.sender).transfer(balance);
        // }
    }

    function enterRaffle() public payable {
        if (msg.value < i_enteranceFee) {
            revert Raffle__SendMoreToEnterRaffle();
        }
        if (s_raffState != RaffState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        console.log("Hi");
        s_player.push(payable(msg.sender));
        emit EnterRaffle(msg.sender);
    }

    function checkUpkeep(
        bytes memory /*checkdata */
    )
        public
        view
        override
        returns (bool upkeepNeeded, bytes memory /* performData */)
    {
        bool TimehasPassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        bool HasBalance = address(this).balance > 0;
        bool isOpen = RaffState.OPEN == s_raffState;
        bool hasPlayer = s_player.length > 0;
        upkeepNeeded = (TimehasPassed && HasBalance && isOpen && hasPlayer);
        return (upkeepNeeded, "0x00");
    }

    // 选择获胜者的函数
    function performUpkeep(bytes calldata /* performData */) external override {
        (bool upkeepNeed, ) = checkUpkeep("");
        if (!upkeepNeed) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_player.length,
                uint256(s_raffState)
            );
        }
        //抽奖正在计算触发者，通常意味着不再接受新的参与者，正在等待随机数生成或其他计算完成。
        s_raffState = RaffState.Calculating;
        uint256 requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_gasLane,
                subId: i_subscriptionId,
                requestConfirmations: Request_confirmation,
                callbackGasLimit: i_callbackGasLimit,
                numWords: Num_words,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            })
        );
        emit RequestedRaffleWinner(requestId);
    }

    // 实现VRF回调函数，用于处理随机数,CEI:Checks,Effects,Interactions
    function fulfillRandomWords(
        uint256,
        uint256[] calldata randomWords
    ) internal override {
        //checks
        //Effects(our own contract)
        uint256 indexOfWinner = randomWords[0] % s_player.length;
        address payable winner = s_player[indexOfWinner];
        s_recentWinner = winner;

        //重置参与者列表,清空了之前存储的所有参与者地址
        s_player = new address payable[](0);
        s_raffState = RaffState.OPEN;

        //更新了最后一次抽奖的时间,返回当前区块的计时器,将这个值赋给s_lastTimeStamp，记录本次抽奖完成的时间
        s_lastTimeStamp = block.timestamp;

        emit WinnerPicked(winner);
        //Interactions(other contracts)
        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
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

    function getNumWords() public pure returns (uint256) {
        return Num_words;
    }

    function getRequestConfirmations() public pure returns (uint256) {
        return Request_confirmation;
    }

    function getLastTimeStamp() public view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getInterval() public view returns (uint256) {
        return i_interval;
    }
}
