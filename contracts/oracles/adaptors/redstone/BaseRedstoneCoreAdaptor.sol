// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import { BaseOracleAdaptor } from "contracts/oracles/adaptors/BaseOracleAdaptor.sol";
import { Bytes32Helper } from "contracts/libraries/Bytes32Helper.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IPriceRouter } from "contracts/interfaces/IPriceRouter.sol";
import { PriceReturnData } from "contracts/interfaces/IOracleAdaptor.sol";

abstract contract BaseRedstoneCoreAdaptor is BaseOracleAdaptor {
    /// TYPES ///

    /// @notice Stores configuration data for Redstone price sources.
    struct AdaptorData {
        /// @notice Whether the asset is configured or not.
        /// @dev    false = unconfigured; true = configured.
        bool isConfigured;
        /// @notice The bytes32 encoded hash of the price feed.
        bytes32 symbolHash;
        /// @param max the max valid price of the asset.
        uint256 max;
    }

    /// CONSTANTS ///
    
    /// @notice If zero is specified for a Redstone Core asset heartbeat,
    ///         this value is used instead.
    uint256 public constant DEFAULT_HEART_BEAT = 1 days;

    /// STORAGE ///

    /// @notice Redstone Adaptor Data for pricing in ETH
    mapping(address => AdaptorData) public adaptorDataNonUSD;

    /// @notice Redstone Adaptor Data for pricing in USD
    mapping(address => AdaptorData) public adaptorDataUSD;

    /// EVENTS ///

    event RedstoneCoreAssetAdded(address asset, AdaptorData assetConfig);
    event RedstoneCoreAssetRemoved(address asset);

    /// ERRORS ///

    error BaseRedstoneCoreAdaptor__AssetIsNotSupported();
    error BaseRedstoneCoreAdaptor__SymbolHashError();
    /// CONSTRUCTOR ///

    constructor(
        ICentralRegistry centralRegistry_
    ) BaseOracleAdaptor(centralRegistry_) {}

    /// EXTERNAL FUNCTIONS ///

    /// @notice Retrieves the price of a given asset.
    /// @dev Uses Redstone Core oracles to fetch the price data.
    ///      Price is returned in USD or ETH depending on 'inUSD' parameter.
    /// @param asset The address of the asset for which the price is needed.
    /// @param inUSD A boolean to determine if the price should be returned in
    ///              USD or not.
    /// @return PriceReturnData A structure containing the price, error status,
    ///                         and the quote format of the price.
    function getPrice(
        address asset,
        bool inUSD,
        bool
    ) external view override returns (PriceReturnData memory) {
        if (!isSupportedAsset[asset]) {
            revert BaseRedstoneCoreAdaptor__AssetIsNotSupported();
        }

        if (inUSD) {
            return _getPriceinUSD(asset);
        }

        return _getPriceinETH(asset);
    }

    /// @notice Add a Redstone Core Price Feed as an asset.
    /// @dev Should be called before `PriceRouter:addAssetPriceFeed` is called.
    /// @param asset The address of the token to add pricing for.
    /// @param inUSD Whether the price feed is in USD (inUSD = true)
    ///              or ETH (inUSD = false).
    function addAsset(
        address asset, 
        bool inUSD
    ) external {
        _checkElevatedPermissions();

        bytes32 symbolHash;
        if (inUSD) {
            // Redstone Core does not append anything at the end of USD denominated feeds,
            // so we use toBytes32 here.
            symbolHash = Bytes32Helper._toBytes32(asset);
        } else {
            // Redstone Core appends "/ETH" at the end of ETH denominated feeds,
            // so we use toBytes32WithETH here.
            symbolHash = Bytes32Helper._toBytes32WithETH(asset);
        }

        AdaptorData storage adaptorData;

        if (inUSD) {
            adaptorData = adaptorDataUSD[asset];
        } else {
            adaptorData = adaptorDataNonUSD[asset];
        }

        // Add a ~10% buffer to maximum price allowed from redstone can stop 
        // updating its price before/above the min/max price.
        // We use a maximum buffered price of 2^192 - 1 since redstone core
        // reports pricing in 8 decimal format, requiring multiplication by
        // 10e10 to standardize to 18 decimal format, which could overflow 
        // when trying to save the final value into an uint240.
        adaptorData.max = (type(uint192).max * 9) / 10;
        adaptorData.symbolHash = symbolHash;
        adaptorData.isConfigured = true;
        isSupportedAsset[asset] = true;

        emit RedstoneCoreAssetAdded(asset, adaptorData);
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into price router to notify it of its removal.
    function removeAsset(address asset) external override {
        _checkElevatedPermissions();

        if (!isSupportedAsset[asset]) {
            revert BaseRedstoneCoreAdaptor__AssetIsNotSupported();
        }

        // Notify the adaptor to stop supporting the asset.
        delete isSupportedAsset[asset];

        // Wipe config mapping entries for a gas refund.
        delete adaptorDataUSD[asset];
        delete adaptorDataNonUSD[asset];

        // Notify the price router that we are going to stop supporting the asset.
        IPriceRouter(centralRegistry.priceRouter()).notifyFeedRemoval(asset);
        
        emit RedstoneCoreAssetRemoved(asset);
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Retrieves the price of a given asset in USD.
    /// @param asset The address of the asset for which the price is needed.
    /// @return A structure containing the price, error status,
    ///         and the quote format of the price (USD).
    function _getPriceinUSD(
        address asset
    ) internal view returns (PriceReturnData memory) {
        if (adaptorDataUSD[asset].isConfigured) {
            return _parseData(adaptorDataUSD[asset], true);
        }

        return _parseData(adaptorDataNonUSD[asset], false);
    }

    /// @notice Retrieves the price of a given asset in ETH.
    /// @param asset The address of the asset for which the price is needed.
    /// @return A structure containing the price, error status,
    ///         and the quote format of the price (ETH).
    function _getPriceinETH(
        address asset
    ) internal view returns (PriceReturnData memory) {
        if (adaptorDataNonUSD[asset].isConfigured) {
            return _parseData(adaptorDataNonUSD[asset], false);
        }

        return _parseData(adaptorDataUSD[asset], true);
    }

    /// @notice Extracts the redstone core feed data for pricing of an asset.
    /// @dev Calls read() from Redstone Core to get the latest data
    ///      for pricing and staleness.
    /// @param data Redstone Core feed details.
    /// @param inUSD A boolean to denote if the price is in USD.
    /// @return A structure containing the price, error status,
    ///         and the currency of the price.
    function _parseData(
        AdaptorData memory data,
        bool inUSD
    ) internal view returns (PriceReturnData memory) {
        uint256 price = _extractPrice(data.symbolHash);

        // Redstone Core always has decimals = 8 so we need to
        // adjust back to decimals = 18.
        uint256 newPrice = uint256(price) * (10 ** 10);

        return (
            PriceReturnData({
                price: uint240(newPrice),
                hadError: _verifyData(
                    uint256(price),
                    data.max
                ),
                inUSD: inUSD
            })
        );
    }

    /// @notice Validates the feed data based on various constraints.
    /// @dev Checks if the value is within a specific range
    ///      and if the data is not outdated.
    /// @param value The value that is retrieved from the feed data.
    /// @param max The maximum limit of the value.
    /// @return A boolean indicating whether the feed data had an error
    ///         (true = error, false = no error).
    function _verifyData(
        uint256 value,
        uint256 max
    ) internal pure returns (bool) {
        // We expect to never get a negative price here, 
        // and a value of 0 would generally indicate no data. 
        // So, we set the minimum intentionally here to 1, 
        // which is denominated in `WAD` form, 
        // meaning a minimum price of 1 / 1e18 in real terms.
        if (value < 1) {
            return true;
        }

        if (value > max) {
            return true;
        }

        // We typically check for feed data staleness through a heartbeat check, 
        // but redstone naturally checks timestamp through its msg.data read, 
        // so we do not need to check again here.

        return false;
    }

    /// INTERNAL FUNCTIONS TO OVERRIDE ///
    function  _extractPrice(bytes32 symbolHash) internal virtual view returns (uint256);

}
