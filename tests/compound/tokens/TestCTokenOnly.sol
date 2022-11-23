// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "contracts/compound/Comptroller/Comptroller.sol";
import "contracts/compound/Comptroller/ComptrollerInterface.sol";
import "contracts/compound/Token/CErc20Immutable.sol";
import "contracts/compound/SimplePriceOracle.sol";
import "contracts/compound/InterestRateModel/InterestRateModel.sol";

import "tests/compound/deploy.sol";
import "tests/lib/DSTestPlus.sol";
import "hardhat/console.sol";

contract User {}

contract TestCToken is DSTestPlus {
    address public dai = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    address public admin;
    address public user;
    address public liquidator;
    DeployCompound public deployments;
    address public unitroller;
    CErc20Immutable public cDAI;
    SimplePriceOracle public priceOracle;

    function setUp() public {
        deployments = new DeployCompound();
        deployments.makeCompound();
        unitroller = address(deployments.unitroller());
        priceOracle = SimplePriceOracle(deployments.priceOracle());
        priceOracle.setDirectPrice(dai, 1e18);

        admin = deployments.admin();
        user = address(this);
        liquidator = address(new User());

        // prepare 200K DAI
        hevm.store(dai, keccak256(abi.encodePacked(uint256(uint160(user)), uint256(2))), bytes32(uint256(200000e18)));
        hevm.store(
            dai,
            keccak256(abi.encodePacked(uint256(uint160(liquidator)), uint256(2))),
            bytes32(uint256(200000e18))
        );
    }

    function testInitialize() public {
        cDAI = new CErc20Immutable(
            dai,
            ComptrollerInterface(unitroller),
            InterestRateModel(address(deployments.jumpRateModel())),
            1e18,
            "cDAI",
            "cDAI",
            18,
            payable(admin)
        );
    }

    function testMint() public {
        cDAI = new CErc20Immutable(
            dai,
            ComptrollerInterface(unitroller),
            InterestRateModel(address(deployments.jumpRateModel())),
            1e18,
            "cDAI",
            "cDAI",
            18,
            payable(admin)
        );
        // support market
        hevm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cDAI)));

        // enter markets
        hevm.prank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cDAI);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // approve
        IERC20(dai).approve(address(cDAI), 100e18);

        // mint
        assertTrue(cDAI.mint(100e18));
        assertGt(cDAI.balanceOf(user), 0);
    }

    function testRedeem() public {
        cDAI = new CErc20Immutable(
            dai,
            ComptrollerInterface(unitroller),
            InterestRateModel(address(deployments.jumpRateModel())),
            1e18,
            "cDAI",
            "cDAI",
            18,
            payable(admin)
        );
        // support market
        hevm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cDAI)));

        // enter markets
        hevm.prank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cDAI);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // approve
        IERC20(dai).approve(address(cDAI), 100e18);

        uint256 balanceBeforeMint = IERC20(dai).balanceOf(user);
        // mint
        assertTrue(cDAI.mint(100e18));
        assertEq(cDAI.balanceOf(user), 100e18);
        assertGt(balanceBeforeMint, IERC20(dai).balanceOf(user));

        // redeem
        cDAI.redeem(cDAI.balanceOf(user));
        assertEq(cDAI.balanceOf(user), 0);
        assertEq(balanceBeforeMint, IERC20(dai).balanceOf(user));
    }

    function testRedeemUnderlying() public {
        cDAI = new CErc20Immutable(
            dai,
            ComptrollerInterface(unitroller),
            InterestRateModel(address(deployments.jumpRateModel())),
            1e18,
            "cDAI",
            "cDAI",
            18,
            payable(admin)
        );
        // support market
        hevm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cDAI)));

        // enter markets
        hevm.prank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cDAI);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // approve
        IERC20(dai).approve(address(cDAI), 100e18);

        uint256 balanceBeforeMint = IERC20(dai).balanceOf(user);
        // mint
        assertTrue(cDAI.mint(100e18));
        assertEq(cDAI.balanceOf(user), 100e18);
        assertGt(balanceBeforeMint, IERC20(dai).balanceOf(user));

        // redeem
        cDAI.redeemUnderlying(100e18);
        assertEq(cDAI.balanceOf(user), 0);
        assertEq(balanceBeforeMint, IERC20(dai).balanceOf(user));
    }

    function testBorrow() public {
        cDAI = new CErc20Immutable(
            dai,
            ComptrollerInterface(unitroller),
            InterestRateModel(address(deployments.jumpRateModel())),
            1e18,
            "cDAI",
            "cDAI",
            18,
            payable(admin)
        );
        // support market
        hevm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cDAI)));

        // enter markets
        hevm.prank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cDAI);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // approve
        IERC20(dai).approve(address(cDAI), 100e18);

        // mint
        assertTrue(cDAI.mint(100e18));
        assertEq(cDAI.balanceOf(user), 100e18);

        uint256 balanceBeforeBorrow = IERC20(dai).balanceOf(user);
        // borrow
        cDAI.borrow(50e18);
        assertEq(cDAI.balanceOf(user), 100e18);
        assertEq(balanceBeforeBorrow + 50e18, IERC20(dai).balanceOf(user));
    }

    function testRepayBorrow() public {
        cDAI = new CErc20Immutable(
            dai,
            ComptrollerInterface(unitroller),
            InterestRateModel(address(deployments.jumpRateModel())),
            1e18,
            "cDAI",
            "cDAI",
            18,
            payable(admin)
        );
        // support market
        hevm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cDAI)));

        // enter markets
        hevm.prank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cDAI);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // approve
        IERC20(dai).approve(address(cDAI), 100e18);

        // mint
        assertTrue(cDAI.mint(100e18));
        assertEq(cDAI.balanceOf(user), 100e18);

        uint256 balanceBeforeBorrow = IERC20(dai).balanceOf(user);
        // borrow
        cDAI.borrow(50e18);
        assertEq(cDAI.balanceOf(user), 100e18);
        assertEq(balanceBeforeBorrow + 50e18, IERC20(dai).balanceOf(user));

        // approve
        IERC20(dai).approve(address(cDAI), 50e18);

        // repay
        cDAI.repayBorrow(50e18);
        assertEq(balanceBeforeBorrow, IERC20(dai).balanceOf(user));
    }

    function testRepayBorrowBehalf() public {
        cDAI = new CErc20Immutable(
            dai,
            ComptrollerInterface(unitroller),
            InterestRateModel(address(deployments.jumpRateModel())),
            1e18,
            "cDAI",
            "cDAI",
            18,
            payable(admin)
        );
        // support market
        hevm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cDAI)));

        // enter markets
        hevm.prank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cDAI);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // approve
        IERC20(dai).approve(address(cDAI), 100e18);

        // mint
        assertTrue(cDAI.mint(100e18));
        assertEq(cDAI.balanceOf(user), 100e18);

        uint256 balanceBeforeBorrow = IERC20(dai).balanceOf(user);
        // borrow
        cDAI.borrow(50e18);
        assertEq(cDAI.balanceOf(user), 100e18);
        assertEq(balanceBeforeBorrow + 50e18, IERC20(dai).balanceOf(user));

        // approve
        IERC20(dai).approve(address(cDAI), 50e18);

        // repay
        cDAI.repayBorrowBehalf(user, 50e18);
        assertEq(balanceBeforeBorrow, IERC20(dai).balanceOf(user));
    }

    function testLiquidateBorrow() public {
        cDAI = new CErc20Immutable(
            dai,
            ComptrollerInterface(unitroller),
            InterestRateModel(address(deployments.jumpRateModel())),
            1e18,
            "cDAI",
            "cDAI",
            18,
            payable(admin)
        );
        // support market
        hevm.prank(admin);
        Comptroller(unitroller)._supportMarket(CToken(address(cDAI)));

        // enter markets
        hevm.prank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(cDAI);
        ComptrollerInterface(unitroller).enterMarkets(markets);

        // approve
        IERC20(dai).approve(address(cDAI), 100e18);

        // mint
        assertTrue(cDAI.mint(100e18));
        assertEq(cDAI.balanceOf(user), 100e18);

        // borrow
        cDAI.borrow(50e18);
        assertEq(cDAI.balanceOf(user), 100e18);

        // price dump
        priceOracle.setDirectPrice(dai, 6e17);

        // approve
        hevm.prank(liquidator);
        IERC20(dai).approve(address(cDAI), 100e18);

        // liquidateBorrow
        hevm.prank(liquidator);
        cDAI.liquidateBorrow(user, 12e18, CTokenInterface(cDAI));

        assertEq(cDAI.balanceOf(liquidator), 5832000000000000000);
    }
}
