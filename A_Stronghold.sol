// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Standard ERC20 dependencies
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// GSN dependencies
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/metatx/MinimalForwarder.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

// Import Contract B and Contract C
import "./UniswapPriceAverage.sol";
import "./Oracle.sol";

import "./UniswapPriceAverage.sol"; // Import the UniswapPriceAverage contract

contract Stronghold is ERC20, Ownable {
    using Address for address;
    using ECDSA for bytes32;

    // Add state variables for Contract B, Contract C, and Uniswap V3 pool
    UniswapPriceAverage public priceAverage;
    Oracle public oracle;
    address public uniswapV3Pool;
    address public usdt;

    address public wethAddress;
    MinimalForwarder public forwarder;
    address public depositContract;
    address public uniswapPriceAverageContract; // Add an address variable to store Contract B's address


    address public owner;
    UniswapPriceAverage public priceAverage;
    uint256 public constant INITIAL_SUPPLY = 5_010_000_000 * 10**18; // 5 billion and ten million tokens
    uint256 public constant LOCKED_SUPPLY = 5_000_000_000 * 10**18; // 5 billion tokens
    uint256 public constant ANNUAL_RELEASE = 1_000_000_000 * 10**18; // 1 billion tokens
    uint256 public lastReleaseTime;
    uint256 public releasedSupply;

    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address _wethAddress,
        address _usdt,
        address _priceAverage,
        address _oracle,
        MinimalForwarder _forwarder
    ) ERC20("Stronghold", "STR") {
        wethAddress = _wethAddress;
        forwarder = _forwarder;
        usdt = _usdt;
        priceAverage = UniswapPriceAverage(_priceAverage);
        oracle = Oracle(_oracle);

        owner = msg.sender;
        priceAverage = UniswapPriceAverage(_priceAverage);
        _mint(owner, INITIAL_SUPPLY - LOCKED_SUPPLY); // 10 million tokens to the owner
        _mint(address(this), LOCKED_SUPPLY); // 5 billion tokens locked
        releasedSupply = 0;
        lastReleaseTime = block.timestamp;
    }

    // Release function
    function releaseTokens() external {
        require(msg.sender == owner, "Only the owner can release tokens");
        require(block.timestamp >= lastReleaseTime + 365 days, "Tokens can only be released once a year");

        uint256 tokensToRelease = ANNUAL_RELEASE;
        if (releasedSupply + tokensToRelease > INITIAL_SUPPLY) {
            tokensToRelease = INITIAL_SUPPLY - releasedSupply;
        }

        require(tokensToRelease > 0, "No more tokens to release");
        _transfer(address(this), owner, tokensToRelease);

        releasedSupply += tokensToRelease;
        lastReleaseTime = block.timestamp;
    }

    // Set depositContract address, can only be called by the contract owner
    function setDepositContract(address _depositContract) external onlyOwner {
        depositContract = _depositContract;
    }

    // Function to set Contract B's address, can only be called by the contract owner
    function setUniswapPriceAverageContract(address _uniswapPriceAverageContract) external onlyOwner {
        uniswapPriceAverageContract = _uniswapPriceAverageContract;
    }

    // Set the Uniswap V3 pool address, can only be called by the contract owner
    function setUniswapV3Pool(address _uniswapV3Pool) external onlyOwner {
        uniswapV3Pool = _uniswapV3Pool;
    }

    // Mint function, can only be called by the depositContract
    function mint(address to, uint256 amount) external {
        require(msg.sender == depositContract, "Caller is not the depositContract");
        _mint(to, amount);
    }

    // Burn function, can only be called by the depositContract
    function burn(address from, uint256 amount) external {
        require(msg.sender == depositContract, "Caller is not the depositContract");
        _burn(from, amount);
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return super.balanceOf(account);
    }

    // Gasless transfer function
    function transferGasless(
        address from,
        address to,
        uint256 amount,
        bytes calldata signature
    ) external {
        // Recreate the signed message
        bytes32 message = keccak256(abi.encodePacked(from, to, amount)).toEthSignedMessageHash();

        // Recover signer from the signature
        address signer = message.recover(signature);

        // Verify that the signer is the `from` address
        require(signer == from, "Invalid signature");

        // Perform the transfer
        _transfer(from, to, amount);
    }


    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        uint256 uniswapPrice = oracle.getTokenPrice(address(this));
        uint256 strongholdPrice = stronghold.getTokenPrice();

        (bool allowed, string memory errorMsg) = checkTransferAllowed(
            _msgSender(),
            recipient,
            amount,
            uniswapPrice,
            strongholdPrice
        );

        require(allowed, errorMsg);
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        uint256 uniswapPrice = oracle.getTokenPrice(address(this));
        uint256 strongholdPrice = stronghold.getTokenPrice();

        (bool allowed, string memory errorMsg) = checkTransferAllowed(
            sender,
            recipient,
            amount,
            uniswapPrice,
            strongholdPrice
        );

        require(allowed, errorMsg);
        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), currentAllowance - amount);
        return true;
    }



    function checkTransferAllowed(
        address from,
        address to,
        uint256 amount,
        uint256 uniswapPrice,
        uint256 strongholdPrice
    ) internal view returns (bool, string memory) {
        bool isBuy = from == uniswapV3Pool && to != uniswapV3Pool;
        bool isSell = to == uniswapV3Pool && from != uniswapV3Pool;

        int256 priceDifference = int256(strongholdPrice) - int256(uniswapPrice);
        int256 priceDifferencePercent = (priceDifference * 10000) / int256(uniswapPrice);

        if (isBuy && priceDifferencePercent > 100) {
            return (false, "Buying not allowed: token price on Uniswap is more than 1% higher");
        }

        if (isSell && priceDifferencePercent < -100) {
            return (false, "Selling not allowed: token price on Uniswap is more than 1% lower");
        }

        uint256 avgPrice = priceAverage.getPriceAverage();
        uint256 currentPrice = oracle.getTokenPrice(address(this));

        int256 priceDifferenceTenDays = int256(currentPrice) - int256(avgPrice);
        int256 priceDifferencePercentTenDays = (priceDifferenceTenDays * 10000) / int256(avgPrice);

        if (priceDifferencePercentTenDays > 100 || priceDifferencePercentTenDays < -100) {
            if (isBuy && currentPrice > avgPrice) {
                return (false, "Buying not allowed: price difference over 10 days is more than 1%");
            }

            if (isSell && currentPrice < avgPrice) {
                return (false, "Selling not allowed: price difference over 10 days is more than 1%");
            }
        }

        if (isBuy && !buyAllowed) {
            return (false, "Buying not allowed");
        }

        if (isSell && !sellAllowed) {
            return (false, "Selling not allowed");
        }

        return (true, "");
    }



}
