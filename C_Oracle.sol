// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract Oracle {
    ISwapRouter private immutable swapRouter;
    IUniswapV3Factory private immutable factory;
    address private immutable weth;
    address private immutable usdt;

    constructor(address _swapRouter, address _factory, address _weth, address _usdt) {
        swapRouter = ISwapRouter(_swapRouter);
        factory = IUniswapV3Factory(_factory);
        weth = _weth;
        usdt = _usdt;
    }

    function getEthPrice() public view returns (uint256) {
        uint160 sqrtPriceX96;
        address poolAddress = factory.getPool(weth, usdt, 3000);
        (sqrtPriceX96, , , , ) = IUniswapV3Pool(poolAddress).snapshotCumulativesInside(0, type(uint128).max);
        uint256 price = uint256(sqrtPriceX96)**2 / 2**64;
        return price;
    }

    function getTokenPrice(address token) public view returns (uint256) {
        uint160 sqrtPriceX96;
        address poolAddress = factory.getPool(token, weth, 3000);
        (sqrtPriceX96, , , , ) = IUniswapV3Pool(poolAddress).snapshotCumulativesInside(0, type(uint128).max);
        uint256 price = uint256(sqrtPriceX96)**2 / 2**64;
        return price;
    }
}
