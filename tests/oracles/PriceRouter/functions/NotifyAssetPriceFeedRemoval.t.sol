// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TestBasePriceRouter } from "../TestBasePriceRouter.sol";

contract NotifyAssetPriceFeedRemovalTest is TestBasePriceRouter {
    function test_notifyAssetPriceFeedRemoval_fail_whenCallerIsNotApprovedAdaptor()
        public
    {
        vm.expectRevert("PriceRouter: UNAUTHORIZED");
        priceRouter.notifyAssetPriceFeedRemoval(_USDC_ADDRESS);
    }

    function test_notifyAssetPriceFeedRemoval_fail_whenNoFeedsAvailable()
        public
    {
        priceRouter.addApprovedAdaptor(address(chainlinkAdaptor));

        vm.prank(address(chainlinkAdaptor));

        vm.expectRevert(0xe4558fac);
        priceRouter.notifyAssetPriceFeedRemoval(_USDC_ADDRESS);
    }

    function test_notifyAssetPriceFeedRemoval_fail_whenSingleFeedDoesNotExist()
        public
    {
        _addSinglePriceFeed();

        priceRouter.addApprovedAdaptor(address(dualChainlinkAdaptor));

        vm.prank(address(dualChainlinkAdaptor));

        vm.expectRevert(0xe4558fac);
        priceRouter.notifyAssetPriceFeedRemoval(_USDC_ADDRESS);
    }

    function test_notifyAssetPriceFeedRemoval_fail_whenDualFeedDoesNotExist()
        public
    {
        _addDualPriceFeed();

        priceRouter.addApprovedAdaptor(address(1));

        vm.prank(address(1));

        vm.expectRevert(0xe4558fac);
        priceRouter.notifyAssetPriceFeedRemoval(_USDC_ADDRESS);
    }

    function test_notifyAssetPriceFeedRemoval_success_whenRemoveSingleFeed()
        public
    {
        _addSinglePriceFeed();

        assertEq(
            priceRouter.assetPriceFeeds(_USDC_ADDRESS, 0),
            address(chainlinkAdaptor)
        );

        vm.prank(address(chainlinkAdaptor));
        priceRouter.notifyAssetPriceFeedRemoval(_USDC_ADDRESS);

        vm.expectRevert();
        priceRouter.assetPriceFeeds(_USDC_ADDRESS, 0);
    }

    function test_notifyAssetPriceFeedRemoval_success_whenRemoveDualFeed()
        public
    {
        _addDualPriceFeed();

        assertEq(
            priceRouter.assetPriceFeeds(_USDC_ADDRESS, 0),
            address(chainlinkAdaptor)
        );
        assertEq(
            priceRouter.assetPriceFeeds(_USDC_ADDRESS, 1),
            address(dualChainlinkAdaptor)
        );

        vm.prank(address(chainlinkAdaptor));
        priceRouter.notifyAssetPriceFeedRemoval(_USDC_ADDRESS);

        assertEq(
            priceRouter.assetPriceFeeds(_USDC_ADDRESS, 0),
            address(dualChainlinkAdaptor)
        );

        vm.expectRevert();
        priceRouter.assetPriceFeeds(_USDC_ADDRESS, 1);
    }
}
