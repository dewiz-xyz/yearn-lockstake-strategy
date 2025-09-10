// SPDX-License-Identifier: AGPL3
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {TokenHandler} from "../periphery/TokenHandler.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract TokenHandlerTest is Test {
    TokenHandler public tokenHandler;
    MockERC20 public token;
    address public receiver;
    address public unauthorized;

    function setUp() public {
        receiver = makeAddr("receiver");
        unauthorized = makeAddr("unauthorized");
        token = new MockERC20("Test Token", "TEST");
        tokenHandler = new TokenHandler(receiver, address(token));
    }

    function test_constructor() public {
        assertEq(tokenHandler.receiver(), receiver);
        assertEq(address(tokenHandler.token()), address(token));
    }

    function test_wipe_success() public {
        uint256 amount = 1000e18;
        token.mint(address(tokenHandler), amount);

        assertEq(token.balanceOf(address(tokenHandler)), amount);
        assertEq(token.balanceOf(receiver), 0);

        vm.prank(receiver);
        tokenHandler.wipe();

        assertEq(token.balanceOf(address(tokenHandler)), 0);
        assertEq(token.balanceOf(receiver), amount);
    }

    function test_wipe_unauthorized() public {
        uint256 amount = 1000e18;
        token.mint(address(tokenHandler), amount);

        vm.prank(unauthorized);
        vm.expectRevert("unauthorized");
        tokenHandler.wipe();

        assertEq(token.balanceOf(address(tokenHandler)), amount);
        assertEq(token.balanceOf(receiver), 0);
    }

    function test_wipe_zeroBalance() public {
        assertEq(token.balanceOf(address(tokenHandler)), 0);

        vm.prank(receiver);
        tokenHandler.wipe();

        assertEq(token.balanceOf(address(tokenHandler)), 0);
        assertEq(token.balanceOf(receiver), 0);
    }
}
