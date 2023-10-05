// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { VelodromeVolatileLPAdaptor } from "contracts/oracles/adaptors/velodrome/VelodromeVolatileLPAdaptor.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { PriceRouter } from "contracts/oracles/PriceRouter.sol";
import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { VelodromeLib } from "contracts/market/zapper/protocols/VelodromeLib.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";
import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";

contract TestVelodromeVolatileLPAdapter is TestBasePriceRouter {
    address private WETH = address(0x4200000000000000000000000000000000000006);
    address private USDC = address(0x7F5c764cBc14f9669B88837ca1490cCa17c31607);

    address private CHAINLINK_PRICE_FEED_ETH =
        0xb7B9A39CC63f856b90B364911CC324dC46aC1770;
    address private CHAINLINK_PRICE_FEED_USDC =
        0x16a9FA2FDa030272Ce99B29CF780dFA30361E0f3;

    address private veloRouter =
        address(0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858);
    address private WETH_USDC =
        address(0x0493Bf8b6DBB159Ce2Db2E0E8403E753Abd1235b);

    VelodromeVolatileLPAdaptor adapter;

    function setUp() public override {
        _fork("ETH_NODE_URI_OPTIMISM", 110333246);

        _deployCentralRegistry();
        priceRouter = new PriceRouter(
            ICentralRegistry(address(centralRegistry)),
            CHAINLINK_PRICE_FEED_ETH
        );
        centralRegistry.setPriceRouter(address(priceRouter));

        adapter = new VelodromeVolatileLPAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        adapter.addAsset(WETH_USDC);

        priceRouter.addApprovedAdaptor(address(adapter));
        priceRouter.addAssetPriceFeed(WETH_USDC, address(adapter));
    }

    function testRevertWhenUnderlyingChainAssetPriceNotSet() public {
        vm.expectRevert(0xe4558fac);
        priceRouter.getPrice(WETH_USDC, true, false);
    }

    function testReturnsCorrectPrice() public {
        chainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        chainlinkAdaptor.addAsset(USDC, CHAINLINK_PRICE_FEED_USDC, true);
        chainlinkAdaptor.addAsset(WETH, CHAINLINK_PRICE_FEED_ETH, true);
        priceRouter.addApprovedAdaptor(address(chainlinkAdaptor));
        priceRouter.addAssetPriceFeed(USDC, address(chainlinkAdaptor));
        priceRouter.addAssetPriceFeed(WETH, address(chainlinkAdaptor));

        (uint256 price, uint256 errorCode) = priceRouter.getPrice(
            WETH_USDC,
            true,
            false
        );
        assertEq(errorCode, 0);
        assertGt(price, 0);
    }

    function testRevertAfterAssetRemove() public {
        testReturnsCorrectPrice();

        adapter.removeAsset(WETH_USDC);
        vm.expectRevert(0xe4558fac);
        priceRouter.getPrice(WETH_USDC, true, false);
    }

    function testPriceDoesNotChangeAfterLargeSwap() public {
        chainlinkAdaptor = new ChainlinkAdaptor(
            ICentralRegistry(address(centralRegistry))
        );
        chainlinkAdaptor.addAsset(USDC, CHAINLINK_PRICE_FEED_USDC, true);
        chainlinkAdaptor.addAsset(WETH, CHAINLINK_PRICE_FEED_ETH, true);
        priceRouter.addApprovedAdaptor(address(chainlinkAdaptor));
        priceRouter.addAssetPriceFeed(USDC, address(chainlinkAdaptor));
        priceRouter.addAssetPriceFeed(WETH, address(chainlinkAdaptor));

        uint256 errorCode;
        uint256 priceBefore;
        (priceBefore, errorCode) = priceRouter.getPrice(
            WETH_USDC,
            true,
            false
        );
        assertEq(errorCode, 0);
        assertGt(priceBefore, 0);

        // try large swap (500K USDC)
        uint256 amount = 500000e6;
        deal(USDC, address(this), amount);
        VelodromeLib._swapExactTokensForTokens(
            veloRouter,
            WETH_USDC,
            USDC,
            WETH,
            amount,
            false
        );

        assertEq(IERC20(USDC).balanceOf(address(this)), 0);
        assertGt(IERC20(WETH).balanceOf(address(this)), 0);

        uint256 priceAfter;
        (priceAfter, errorCode) = priceRouter.getPrice(WETH_USDC, true, false);
        assertEq(errorCode, 0);
        assertApproxEqRel(priceBefore, priceAfter, 100000);
    }
}
