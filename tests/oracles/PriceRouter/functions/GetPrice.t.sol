// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";

contract GetPriceTest is TestBasePriceRouter {
    function test_getPrice_fail_whenNoFeedsAvailable() public {
        vm.expectRevert(0xe4558fac);
        priceRouter.getPrice(_USDC_ADDRESS, true, true);
    }

    function test_getPrice_success() public {
        _addSinglePriceFeed();

        (, int256 usdcPrice, , , ) = AggregatorV3Interface(_CHAINLINK_USDC_USD)
            .latestRoundData();

        (uint256 price, uint256 errorCode) = priceRouter.getPrice(
            _USDC_ADDRESS,
            true,
            true
        );

        assertEq(price, uint256(usdcPrice) * 1e10);
        assertEq(errorCode, 0);

        (, int256 ethPrice, , , ) = AggregatorV3Interface(_CHAINLINK_USDC_ETH)
            .latestRoundData();

        (price, errorCode) = priceRouter.getPrice(_USDC_ADDRESS, false, true);

        assertEq(price, uint256(ethPrice));
        assertEq(errorCode, 0);
    }
}
