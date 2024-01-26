// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";

import { OracleRouter } from "contracts/oracles/OracleRouter.sol";
import { ChainlinkAdaptor } from "contracts/oracles/adaptors/chainlink/ChainlinkAdaptor.sol";
import { Curve2PoolLPAdaptor } from "contracts/oracles/adaptors/curve/Curve2PoolLPAdaptor.sol";
import { Convex2PoolCToken } from "contracts/market/collateral/Convex2PoolCToken.sol";
import { Convex3PoolCToken } from "contracts/market/collateral/Convex3PoolCToken.sol";
import { Convex4PoolCToken } from "contracts/market/collateral/Convex4PoolCToken.sol";

import { ICentralRegistry } from "contracts/interfaces/ICentralRegistry.sol";
import { IERC20 } from "contracts/interfaces/IERC20.sol";

import { DeployConfiguration } from "../../utils/DeployConfiguration.sol";

contract ConvexMarketDeployer is DeployConfiguration {
    struct ConvexUnderlyingParam {
        address asset;
        address chainlinkEth;
        address chainlinkUsd;
    }
    struct PriceBound {
        bool divideRate0;
        bool divideRate1;
        bool isCorrelated;
        uint256 lowerBound;
        uint256 upperBound;
    }
    struct ConvexMarketParam {
        address asset;
        address booster;
        uint256 pid;
        address pool;
        PriceBound priceBound;
        address rewarder;
        ConvexUnderlyingParam[] underlyings;
    }

    function _deployConvexMarket(
        string memory name,
        ConvexMarketParam memory param
    ) internal {
        address centralRegistry = _getDeployedContract("centralRegistry");
        console.log("centralRegistry =", centralRegistry);
        require(centralRegistry != address(0), "Set the centralRegistry!");
        address marketManager = _getDeployedContract("marketManager");
        console.log("marketManager =", marketManager);
        require(marketManager != address(0), "Set the marketManager!");
        address oracleRouter = _getDeployedContract("oracleRouter");
        console.log("oracleRouter =", oracleRouter);
        require(oracleRouter != address(0), "Set the oracleRouter!");

        address chainlinkAdaptor = _getDeployedContract("chainlinkAdaptor");
        if (chainlinkAdaptor == address(0)) {
            chainlinkAdaptor = address(
                new ChainlinkAdaptor(ICentralRegistry(centralRegistry))
            );
            console.log("chainlinkAdaptor: ", chainlinkAdaptor);
            _saveDeployedContracts("chainlinkAdaptor", chainlinkAdaptor);
        }
        address curveAdaptor = _getDeployedContract("curveAdaptor");
        if (curveAdaptor == address(0)) {
            curveAdaptor = address(
                new Curve2PoolLPAdaptor(ICentralRegistry(centralRegistry))
            );
            console.log("curveAdaptor: ", curveAdaptor);
            _saveDeployedContracts("curveAdaptor", curveAdaptor);
            Curve2PoolLPAdaptor(curveAdaptor).setReentrancyConfig(2, 50_000);
            Curve2PoolLPAdaptor(curveAdaptor).setReentrancyConfig(3, 50_000);
            Curve2PoolLPAdaptor(curveAdaptor).setReentrancyConfig(4, 50_000);
        }

        // Setup underlying chainlink adapters
        for (uint256 i = 0; i < param.underlyings.length; i++) {
            ConvexUnderlyingParam memory underlyingParam = param.underlyings[
                i
            ];

            if (
                !ChainlinkAdaptor(chainlinkAdaptor).isSupportedAsset(
                    underlyingParam.asset
                )
            ) {
                if (underlyingParam.chainlinkEth != address(0)) {
                    ChainlinkAdaptor(chainlinkAdaptor).addAsset(
                        underlyingParam.asset,
                        underlyingParam.chainlinkEth,
                        0,
                        false
                    );
                }
                if (underlyingParam.chainlinkUsd != address(0)) {
                    ChainlinkAdaptor(chainlinkAdaptor).addAsset(
                        underlyingParam.asset,
                        underlyingParam.chainlinkUsd,
                        0,
                        true
                    );
                }
                console.log("chainlinkAdaptor.addAsset");
            }

            if (
                !OracleRouter(oracleRouter).isApprovedAdaptor(chainlinkAdaptor)
            ) {
                OracleRouter(oracleRouter).addApprovedAdaptor(
                    chainlinkAdaptor
                );
                console.log(
                    "oracleRouter.addApprovedAdaptor: ",
                    chainlinkAdaptor
                );
            }

            try
                OracleRouter(oracleRouter).assetPriceFeeds(
                    underlyingParam.asset,
                    0
                )
            returns (address feed) {} catch {
                OracleRouter(oracleRouter).addAssetPriceFeed(
                    underlyingParam.asset,
                    chainlinkAdaptor
                );
                console.log(
                    "oracleRouter.addAssetPriceFeed: ",
                    underlyingParam.asset
                );
            }
        }

        // Deploy Curve adapter
        if (!OracleRouter(oracleRouter).isApprovedAdaptor(curveAdaptor)) {
            OracleRouter(oracleRouter).addApprovedAdaptor(curveAdaptor);
            console.log("oracleRouter.addApprovedAdaptor: ", curveAdaptor);
        }
        if (!Curve2PoolLPAdaptor(curveAdaptor).isSupportedAsset(param.asset)) {
            Curve2PoolLPAdaptor.AdaptorData memory data;
            data.pool = param.pool;
            data.underlyingOrConstituent0 = param.underlyings[0].asset;
            data.underlyingOrConstituent1 = param.underlyings[1].asset;
            data.divideRate0 = param.priceBound.divideRate0;
            data.divideRate1 = param.priceBound.divideRate1;
            data.isCorrelated = param.priceBound.isCorrelated;
            data.upperBound = param.priceBound.upperBound;
            data.lowerBound = param.priceBound.lowerBound;

            Curve2PoolLPAdaptor(curveAdaptor).addAsset(param.asset, data);
            console.log("curveAdaptor.addAsset");
        }
        try
            OracleRouter(oracleRouter).assetPriceFeeds(param.asset, 0)
        returns (address feed) {} catch {
            OracleRouter(oracleRouter).addAssetPriceFeed(
                param.asset,
                curveAdaptor
            );
            console.log("oracleRouter.addAssetPriceFeed: ", param.asset);
        }

        // Deploy CToken
        address cToken = _getDeployedContract(name);
        if (cToken == address(0)) {
            if (param.underlyings.length == 2) {
                cToken = address(
                    new Convex2PoolCToken(
                        ICentralRegistry(centralRegistry),
                        IERC20(param.asset),
                        marketManager,
                        param.pid,
                        param.rewarder,
                        param.booster
                    )
                );
            } else if (param.underlyings.length == 3) {
                cToken = address(
                    new Convex2PoolCToken(
                        ICentralRegistry(centralRegistry),
                        IERC20(param.asset),
                        marketManager,
                        param.pid,
                        param.rewarder,
                        param.booster
                    )
                );
            } else if (param.underlyings.length == 4) {
                cToken = address(
                    new Convex2PoolCToken(
                        ICentralRegistry(centralRegistry),
                        IERC20(param.asset),
                        marketManager,
                        param.pid,
                        param.rewarder,
                        param.booster
                    )
                );
            }
            console.log("cToken: ", cToken);
            _saveDeployedContracts(name, cToken);
        }

        // followings should be done separate because it requires dust amount deposits
        // marketManager.listToken;
        // marketManager.updateCollateralToken
        // marketManager.setCTokenCollateralCaps
    }
}
