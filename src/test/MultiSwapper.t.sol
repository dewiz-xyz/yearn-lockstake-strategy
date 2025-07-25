// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {MultiSwapper, Hop, Dex} from "../periphery/MultiSwapper.sol";

contract MockMultiSwapper is MultiSwapper {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    function setSwapPath(Hop[] memory _path) external {
        _setSwapPath(_path);
    }

    function swapFrom(uint256 _amountIn, uint256 _minAmountOut) external returns (uint256) {
        return _swapFrom(_amountIn, _minAmountOut);
    }
}

contract MultiSwapperTest is Test {
    using SafeERC20 for ERC20;

    MockMultiSwapper public multiSwapper;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address public constant MKR = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    address public constant SKY = 0x56072C95FAA701256059aa122697B133aDEd9279;

    uint256 public constant minFuzzAmount = 1e6;
    uint256 public constant maxFuzzAmount = 1e25;

    function setUp() public {
        multiSwapper = new MockMultiSwapper();
        
        vm.label(address(multiSwapper), "MultiSwapper");
        vm.label(WETH, "WETH");
        vm.label(DAI, "DAI");
        vm.label(USDC, "USDC");
        vm.label(USDS, "USDS");
        vm.label(MKR, "MKR");
        vm.label(SKY, "SKY");
    }

    function test_UniV2Swap(uint256 amount) public {
        vm.assume(amount >= minFuzzAmount && amount <= maxFuzzAmount);
        
        Hop[] memory path = new Hop[](1);
        path[0] = Hop(Dex.UniV2, WETH, DAI, 0);
        
        multiSwapper.setSwapPath(path);
        
        deal(WETH, address(multiSwapper), amount);
        
        assertEq(ERC20(WETH).balanceOf(address(multiSwapper)), amount, "Initial WETH balance incorrect");
        assertEq(ERC20(DAI).balanceOf(address(multiSwapper)), 0, "Initial DAI balance should be 0");
        
        uint256 amountOut = multiSwapper.swapFrom(amount, 0);
        
        assertEq(ERC20(WETH).balanceOf(address(multiSwapper)), 0, "WETH should be fully swapped");
        assertEq(ERC20(DAI).balanceOf(address(multiSwapper)), amountOut, "DAI balance should match amountOut");
        assertGt(amountOut, 0, "Should have received DAI");
    }

    function test_UniV3Swap(uint256 amount) public {
        amount = bound(amount, 1e16, 1e20);
        
        Hop[] memory path = new Hop[](1);
        path[0] = Hop(Dex.UniV3, WETH, DAI, 3000);
        
        multiSwapper.setSwapPath(path);
        
        deal(WETH, address(multiSwapper), amount);
        
        assertEq(ERC20(WETH).balanceOf(address(multiSwapper)), amount, "Initial WETH balance incorrect");
        assertEq(ERC20(DAI).balanceOf(address(multiSwapper)), 0, "Initial DAI balance should be 0");
        
        uint256 amountOut = multiSwapper.swapFrom(amount, 0);
        
        assertEq(ERC20(WETH).balanceOf(address(multiSwapper)), 0, "WETH should be fully swapped");
        assertEq(ERC20(DAI).balanceOf(address(multiSwapper)), amountOut, "DAI balance should match amountOut");
        assertGt(amountOut, 0, "Should have received DAI");
    }

    function test_PsmSwap(uint256 amount) public {
        amount = bound(amount, 1e4, 1e12);
        
        Hop[] memory path = new Hop[](1);
        path[0] = Hop(Dex.Psm, USDC, USDS, 0);
        
        multiSwapper.setSwapPath(path);
        
        deal(USDC, address(multiSwapper), amount);
        
        assertEq(ERC20(USDC).balanceOf(address(multiSwapper)), amount, "Initial USDC balance incorrect");
        assertEq(ERC20(USDS).balanceOf(address(multiSwapper)), 0, "Initial USDS balance should be 0");
        
        uint256 amountOut = multiSwapper.swapFrom(amount, 0);
        
        assertEq(ERC20(USDC).balanceOf(address(multiSwapper)), 0, "USDC should be fully swapped");
        assertEq(ERC20(USDS).balanceOf(address(multiSwapper)), amountOut, "USDS balance should match amountOut");
        assertGt(amountOut, 0, "Should have received USDS");
    }

    function test_PsmSwapReverse(uint256 amount) public {
        amount = bound(amount, 1e16, 1e20);
        
        Hop[] memory path = new Hop[](1);
        path[0] = Hop(Dex.Psm, USDS, USDC, 0);
        
        multiSwapper.setSwapPath(path);
        
        deal(USDS, address(multiSwapper), amount);
        
        assertEq(ERC20(USDS).balanceOf(address(multiSwapper)), amount, "Initial USDS balance incorrect");
        assertEq(ERC20(USDC).balanceOf(address(multiSwapper)), 0, "Initial USDC balance should be 0");
        
        uint256 amountOut = multiSwapper.swapFrom(amount, 0);
        
        assertLt(ERC20(USDS).balanceOf(address(multiSwapper)), 1e12, "USDS should be fully swapped"); // values under 1e12 are leftover due to precision loss.
        assertEq(ERC20(USDC).balanceOf(address(multiSwapper)), amountOut, "USDC balance should match amountOut");
        assertGt(amountOut, 0, "Should have received USDC");
    }

    function test_MkrSkySwap(uint256 amount) public {
        amount = bound(amount, 1e16, 1e22);
        
        Hop[] memory path = new Hop[](1);
        path[0] = Hop(Dex.MkrSky, MKR, SKY, 0);
        
        multiSwapper.setSwapPath(path);
        
        deal(MKR, address(multiSwapper), amount);
        
        assertEq(ERC20(MKR).balanceOf(address(multiSwapper)), amount, "Initial MKR balance incorrect");
        assertEq(ERC20(SKY).balanceOf(address(multiSwapper)), 0, "Initial SKY balance should be 0");
        
        uint256 amountOut = multiSwapper.swapFrom(amount, 0);
        
        assertEq(ERC20(MKR).balanceOf(address(multiSwapper)), 0, "MKR should be fully swapped");
        assertGt(ERC20(SKY).balanceOf(address(multiSwapper)), 0, "Should have received SKY");
        assertEq(ERC20(SKY).balanceOf(address(multiSwapper)), amountOut, "SKY balance should match amountOut");
    }

    function test_MultiHopSwap() public {
        uint256 amount = 50 * 10**18;
        
        Hop[] memory path = new Hop[](2);
        path[0] = Hop(Dex.UniV3, WETH, USDC, 500);
        path[1] = Hop(Dex.Psm, USDC, USDS, 0);
        
        multiSwapper.setSwapPath(path);
        
        deal(WETH, address(multiSwapper), amount);
        
        assertEq(ERC20(WETH).balanceOf(address(multiSwapper)), amount, "Initial WETH balance incorrect");
        assertEq(ERC20(USDC).balanceOf(address(multiSwapper)), 0, "Initial USDC balance should be 0");
        assertEq(ERC20(USDS).balanceOf(address(multiSwapper)), 0, "Initial USDS balance should be 0");
        
        uint256 amountOut = multiSwapper.swapFrom(amount, 0);
        
        assertEq(ERC20(WETH).balanceOf(address(multiSwapper)), 0, "WETH should be fully swapped");
        assertEq(ERC20(USDC).balanceOf(address(multiSwapper)), 0, "USDC should be fully swapped");
        assertEq(ERC20(USDS).balanceOf(address(multiSwapper)), amountOut, "USDS balance should match amountOut");
        assertGt(amountOut, 0, "Should have received USDS");
    }

    function test_MinimumOutputRequirement() public {
        Hop[] memory path = new Hop[](1);
        path[0] = Hop(Dex.UniV3, DAI, WETH, 3000);
        
        multiSwapper.setSwapPath(path);

        uint256 amount = 1000 * 10**18;
        
        deal(DAI, address(multiSwapper), amount);
        
        vm.expectRevert("minAmountOut not reached");
        multiSwapper.swapFrom(amount, amount);
    }

    function test_InvalidPsmPath(uint256 amount) public {
        vm.assume(amount >= minFuzzAmount && amount <= maxFuzzAmount);
        
        Hop[] memory path = new Hop[](1);
        path[0] = Hop(Dex.Psm, WETH, DAI, 0);
        
        multiSwapper.setSwapPath(path);
        
        deal(WETH, address(multiSwapper), amount);
        
        vm.expectRevert("invalid PSM hop");
        multiSwapper.swapFrom(amount, 0);
    }
}