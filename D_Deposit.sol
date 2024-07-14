pragma solidity ^0.8.0;

import "./Oracle.sol";
import "./Stronghold.sol";

contract Deposit {
    address payable public owner;
    Oracle public oracle;
    Stronghold public stronghold;
    uint256 public totalFees;
    uint256 public lastSnapshotTime;

    event DepositReceived(address indexed from, uint256 value);
    event Redeemed(address indexed from, uint256 value);
    event SnapshotTaken(uint256 indexed timestamp, uint256 totalSupply);

    mapping(uint256 => uint256) public snapshots;

    constructor(address oracleAddress, address strongholdAddress) {
        owner = payable(msg.sender);
        oracle = Oracle(oracleAddress);
        stronghold = Stronghold(strongholdAddress);
    }

    function deposit() external payable {
        require(msg.value > 0, "Deposit amount must be greater than 0");
        emit DepositReceived(msg.sender, msg.value);

        uint256 tokenPriceInUSDT = oracle.getTokenPrice(address(stronghold));
        uint256 tokenAmount = msg.value * 1e18 / tokenPriceInUSDT;
        uint256 fee = msg.value / 10000; // 0.01% fee
        totalFees += fee;

        require(tokenAmount > 0, "Token amount must be greater than 0");

        stronghold.mint(msg.sender, tokenAmount);
        payable(owner).transfer(fee);
    }


    function redeem() public {
        uint256 currentSnapshot = stronghold.snapshotTotalSupply();
        uint256 previousSnapshot = stronghold.previousSnapshotTotalSupply();
        uint256 thirtyDaysAgoSnapshot = stronghold.thirtyDaysAgoSnapshotTotalSupply();

        int256 growth = int256(currentSnapshot) - int256(previousSnapshot);
        int256 growthPercent = (growth * 10000) / int256(previousSnapshot);

        int256 growthLast30Days = int256(currentSnapshot) - int256(thirtyDaysAgoSnapshot);
        int256 growthLast30DaysPercent = (growthLast30Days * 10000) / int256(thirtyDaysAgoSnapshot);

        uint256 tokenPriceInUSDT = oracle.getTokenPrice(address(stronghold));
        uint256 tokenAmount = tokenPriceInUSDT * stronghold.balanceOf(address(this)) / 1e18;
        uint256 fee;

        if (growthPercent >= 100) {
            fee = tokenAmount / 100; // 1% fee
        } else if (growthPercent >= 300) {
            fee = (tokenAmount * 3) / 100; // 3% fee
        } else if (growthPercent >= 500 || growthLast30DaysPercent >= 500) {
            fee = tokenAmount / 10; // 10% fee
        }

        if (growthPercent <= -100) {
            fee = tokenAmount / 100; // 1% fee
        } else if (growthPercent <= -300) {
            fee = (tokenAmount * 3) / 100; // 3% fee
        } else if (growthPercent <= -500 || growthLast30DaysPercent <= -500) {
            fee = tokenAmount / 10; // 10% fee
        }

        uint256 amountToSend = tokenAmount - fee;

        require(amountToSend > 0, "Amount to send must be greater than 0");

        stronghold.transfer(msg.sender, amountToSend);

        emit Redeemed(msg.sender, amountToSend);
    }


    function getCumulativeFees() public view returns (uint256) {
        return totalFees;
    }

    function takeSnapshot() external {
        if (lastSnapshotTime == 0 || block.timestamp >= lastSnapshotTime + 10 days) {
            uint256 totalSupply = stronghold.totalSupply();
            snapshots[block.timestamp] = totalSupply;
            lastSnapshotTime = block.timestamp;
            emit SnapshotTaken(block.timestamp, totalSupply);
        }
    }

    function daysUntilNextSnapshot() public view returns (uint256) {
        if (lastSnapshotTime == 0) {
            return 0;
        } else {
            uint256 daysSinceLastSnapshot = (block.timestamp - lastSnapshotTime) / 1 days;
            return daysSinceLastSnapshot >= 10 ? 0 : 10 - daysSinceLastSnapshot;
        }
    }
}
