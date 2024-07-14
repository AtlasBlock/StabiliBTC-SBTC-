
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./Stronghold.sol";
import "./Oracle.sol"; // Import Oracle contract

contract UniswapPriceAverage {
    address private immutable swapRouter;
    address private immutable wbtc;
    address private immutable eth;
    address private immutable stronghold;
    Oracle private oracle; // Add state variable for the Oracle contract
    uint256 public lastSnapshotTime;
    uint256 public snapshotBTC_ETH;
    uint256 public snapshotStronghold;
    mapping(uint256 => uint256) public snapshotsBTC_ETH;
    mapping(uint256 => uint256) public snapshotsStronghold;

    // Update constructor to accept Oracle contract address
    constructor(address _swapRouter, address _wbtc, address _eth, address _stronghold, address _oracle) {
        swapRouter = _swapRouter;
        wbtc = _wbtc;
        eth = _eth;
        stronghold = _stronghold;
        oracle = Oracle(_oracle); // Initialize the Oracle state variable
    }

    function getPriceAverage() public view returns (uint256) {
        uint256 ethPriceCumulative = 0;
        uint256 wbtcPriceCumulative = 0;
        address ethWbtcPair = ISwapRouter(swapRouter).pairFor(eth, wbtc);
        (, , uint32 ethWbtcTimestamp) = ISwapRouter(swapRouter).getPairObservation(ethWbtcPair, block.timestamp);
        for (uint256 i = 0; i < 10; i++) {
            (uint160 ethWbtcPrice, , , uint32 observationTimestamp, , , ) =
                ISwapRouter(swapRouter).getPairObservation(ethWbtcPair, ethWbtcTimestamp - i * 1800);
            wbtcPriceCumulative += uint256(ethWbtcPrice) * 2**64 / 1e18;
            ethPriceCumulative += uint256(1e18) * 2**64 / uint256(ethWbtcPrice);
        }
        uint256 wbtcPriceAverage = wbtcPriceCumulative / 10;
        uint256 ethPriceAverage = ethPriceCumulative / 10;
        return (wbtcPriceAverage + ethPriceAverage) / 10000;
    }

    function takeSnapshotBTC_ETH() external {
        if (lastSnapshotTime == 0 || block.timestamp >= lastSnapshotTime + 10 days) {
            snapshotBTC_ETH = getPriceAverage();
            snapshotsBTC_ETH[block.timestamp] = snapshotBTC_ETH;
            lastSnapshotTime = block.timestamp;
        }
    }

    function takeSnapshotStronghold() external {
        if (lastSnapshotTime == 0 || block.timestamp >= lastSnapshotTime + 10 days) {
            snapshotStronghold = oracle.getTokenPrice(stronghold); // Update this line to use Oracle's getTokenPrice()
            snapshotsStronghold[block.timestamp] = snapshotStronghold;
            lastSnapshotTime = block.timestamp;
        }
    }

    function getSnapshotsBTC_ETH() public view returns (Snapshot[] memory) {
        Snapshot[] memory result = new Snapshot[](5);
        uint256 timestamp = block.timestamp;
        for (uint256 i = 0; i < 5; i++) {
            if (snapshotsBTC_ETH[timestamp] > 0) {
                result[i] = Snapshot(timestamp, snapshotsBTC_ETH[timestamp]);
            }
            timestamp -= 10 days;
        }
        return result;
    }

    function daysUntilNextSnapshot() public view returns (uint256) {
        if (lastSnapshotTime == 0) {
            return 0;
        } else {
            uint256 daysSinceLastSnapshot = (block.timestamp - lastSnapshotTime) / 1 days;
            return daysSinceLastSnapshot >= 10 ? 0 : 10 - daysSinceLastSnapshot;
        }
    }

    function daysUntilNextSnapshotStronghold() public view returns (uint256) {
        if (lastSnapshotTime == 0) {
            return 0;
        } else {
            uint256 daysSinceLastSnapshot = (block.timestamp - lastSnapshotTime) / 1 days;
            return daysSinceLastSnapshot >= 10 ? 0 : 10 - daysSinceLastSnapshot;
        }
    }

}
