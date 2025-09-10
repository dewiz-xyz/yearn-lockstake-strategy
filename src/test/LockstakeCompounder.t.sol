// SPDX-License-Identifier: AGPL3
pragma solidity ^0.8.18;

import {Setup, ERC20, IStrategyInterface} from "./utils/Setup.sol";
import {LockstakeCompounder, Hop, Dex} from "../LockstakeCompounder.sol";
import {Auction} from "@periphery/Auctions/Auction.sol";

contract LockstakeCompounderTest is Setup {
    address public mockAuction;

    function setUp() public virtual override {
        super.setUp();

        mockAuction = address(
            new MockAuction(address(strategy), address(asset))
        );
    }

    function test_setSwapPath() public {
        Hop[] memory path = new Hop[](2);
        path[0] = Hop(Dex.UniV3, tokenAddrs["WETH"], tokenAddrs["DAI"], 3000);
        path[1] = Hop(Dex.UniV2, tokenAddrs["DAI"], tokenAddrs["USDC"], 0);

        vm.expectRevert("!management");
        strategy.setSwapPath(path);

        vm.prank(management);
        strategy.setSwapPath(path);

        Hop[] memory retrievedPath = strategy.getSwapPath();
        assertEq(retrievedPath.length, 2);
        assertEq(uint8(retrievedPath[0].dex), uint8(Dex.UniV3));
        assertEq(retrievedPath[0].from, tokenAddrs["WETH"]);
        assertEq(retrievedPath[0].to, tokenAddrs["DAI"]);
        assertEq(retrievedPath[0].fee, 3000);
    }

    function test_getSwapPath() public {
        Hop[] memory path = strategy.getSwapPath();
        assertEq(path.length, 3);

        Hop[] memory newPath = new Hop[](1);
        newPath[0] = Hop(Dex.Psm, tokenAddrs["USDC"], tokenAddrs["USDS"], 0);

        vm.prank(management);
        strategy.setSwapPath(newPath);

        Hop[] memory retrievedPath = strategy.getSwapPath();
        assertEq(retrievedPath.length, 1);
        assertEq(uint8(retrievedPath[0].dex), uint8(Dex.Psm));
    }

    function test_setMinAmountToSell() public {
        uint256 initialAmount = strategy.minAmountToSell();
        uint256 newAmount = 50_000 * 10 ** 18;

        vm.expectRevert("!management");
        strategy.setMinAmountToSell(newAmount);

        vm.prank(management);
        strategy.setMinAmountToSell(newAmount);

        assertEq(strategy.minAmountToSell(), newAmount);
        assertTrue(strategy.minAmountToSell() != initialAmount);
    }

    function test_setTokenHandler() public {
        vm.expectRevert("!management");
        strategy.setTokenHandler(address(0x0ddaf));

        vm.prank(management);
        strategy.setTokenHandler(address(0x0ddaf));

        assertEq(strategy.tokenHandler(), address(0x0ddaf));
    }

    function test_setOpenDeposits() public {
        vm.prank(management);
        strategy.setOpenDeposits(false);
        assertFalse(strategy.openDeposits());

        vm.expectRevert("!management");
        strategy.setOpenDeposits(true);

        vm.prank(management);
        strategy.setOpenDeposits(true);

        assertTrue(strategy.openDeposits());

        vm.prank(management);
        strategy.setOpenDeposits(false);

        assertFalse(strategy.openDeposits());
    }

    function test_setAllowed() public {
        address testUser = address(0x123);

        assertFalse(strategy.allowed(testUser));

        vm.expectRevert("!management");
        strategy.setAllowed(testUser, true);

        vm.prank(management);
        strategy.setAllowed(testUser, true);

        assertTrue(strategy.allowed(testUser));

        vm.prank(management);
        strategy.setAllowed(testUser, false);

        assertFalse(strategy.allowed(testUser));
    }

    function test_availableDepositLimit() public {
        address testUser = address(0x123);

        vm.prank(management);
        strategy.setOpenDeposits(false);
        assertEq(strategy.availableDepositLimit(testUser), 0);

        vm.prank(management);
        strategy.setAllowed(testUser, true);
        assertEq(strategy.availableDepositLimit(testUser), type(uint256).max);

        vm.prank(management);
        strategy.setOpenDeposits(true);
        assertEq(
            strategy.availableDepositLimit(address(0x456)),
            type(uint256).max
        );

        vm.prank(management);
        strategy.setAllowed(testUser, false);
        assertEq(strategy.availableDepositLimit(testUser), type(uint256).max);
    }

    function test_setAuction() public {
        vm.expectRevert("!management");
        strategy.setAuction(mockAuction);

        vm.prank(management);
        strategy.setAuction(mockAuction);

        assertEq(strategy.auction(), mockAuction);

        vm.prank(management);
        strategy.setAuction(address(0));

        assertEq(strategy.auction(), address(0));
    }

    function test_setAuction_invalidReceiver() public {
        address invalidAuction = address(
            new MockAuction(address(0x123), tokenAddrs["WETH"])
        );

        vm.expectRevert("receiver");
        vm.prank(management);
        strategy.setAuction(invalidAuction);
    }

    function test_setAuction_invalidWant() public {
        address invalidAuction = address(
            new MockAuction(address(strategy), tokenAddrs["WETH"])
        );

        vm.expectRevert(bytes("want"));
        vm.prank(management);
        strategy.setAuction(invalidAuction);
    }

    function test_setUseAuction() public {
        assertFalse(strategy.useAuction());

        vm.expectRevert("!auction");
        vm.prank(management);
        strategy.setUseAuction(true);

        vm.prank(management);
        strategy.setAuction(mockAuction);

        vm.expectRevert("!management");
        strategy.setUseAuction(true);

        vm.prank(management);
        strategy.setUseAuction(true);

        assertTrue(strategy.useAuction());

        vm.prank(management);
        strategy.setUseAuction(false);

        assertFalse(strategy.useAuction());
    }

    function test_setReferral() public {
        uint16 initialReferral = strategy.referral();
        uint16 newReferral = 2000;

        vm.expectRevert("!management");
        strategy.setReferral(newReferral);

        vm.prank(management);
        strategy.setReferral(newReferral);

        assertEq(strategy.referral(), newReferral);
        assertTrue(strategy.referral() != initialReferral);
    }

    function test_kick_notUsingAuction() public {
        vm.expectRevert("!useAuction");
        vm.prank(keeper);
        strategy.kick();
    }

    function test_kick_withAuction() public {
        MockAuction auction = new MockAuction(
            address(strategy),
            address(asset)
        );

        address rewardToken = strategy.REWARD_TOKEN();
        auction.enable(rewardToken);

        vm.prank(management);
        strategy.setAuction(address(auction));

        vm.prank(management);
        strategy.setUseAuction(true);

        deal(rewardToken, address(strategy), 50_000 * 10 ** 18); // Above default minAmountToSell

        uint256 balanceBefore = ERC20(rewardToken).balanceOf(address(auction));

        vm.expectRevert("!keeper");
        strategy.kick();

        vm.prank(keeper);
        strategy.kick();

        uint256 balanceAfter = ERC20(rewardToken).balanceOf(address(auction));
        assertGt(balanceAfter, balanceBefore);
    }

    function test_kick_belowMinAmount() public {
        vm.prank(management);
        strategy.setAuction(mockAuction);

        vm.prank(management);
        strategy.setUseAuction(true);

        address rewardToken = address(strategy.REWARD_TOKEN());
        deal(rewardToken, address(strategy), 1000 * 10 ** 18); // Below default minAmountToSell

        uint256 balanceBefore = ERC20(rewardToken).balanceOf(address(strategy));

        vm.prank(keeper);
        strategy.kick();

        assertEq(
            ERC20(rewardToken).balanceOf(address(strategy)),
            balanceBefore
        );
    }

    function test_emergencyWithdraw() public {
        uint256 amount = 100e18;

        mintAndDepositIntoStrategy(strategy, user, amount);

        uint256 stakedBefore = strategy.balanceOfStake();
        assertGt(stakedBefore, 0);

        vm.prank(management);
        strategy.shutdownStrategy();

        uint256 stakedAfter = strategy.balanceOfStake();
        assertLe(stakedAfter, stakedBefore);
    }

    function test_tokenHandlerIntegration() public {
        address rewardToken = strategy.REWARD_TOKEN();
        address tokenHandlerAddr = strategy.tokenHandler();

        assertNotEq(tokenHandlerAddr, address(0), "TokenHandler should be set");

        uint256 initialAmount = 100_000 * 10 ** 18;
        mintAndDepositIntoStrategy(strategy, user, initialAmount);

        MockAuction auction = new MockAuction(tokenHandlerAddr, address(asset));
        auction.enable(rewardToken);

        vm.prank(management);
        strategy.setAuction(address(auction));

        vm.prank(management);
        strategy.setUseAuction(true);

        uint256 kickAmount = 50_000 * 10 ** 18;
        deal(rewardToken, address(strategy), kickAmount);

        vm.prank(keeper);
        strategy.kick();

        assertEq(ERC20(rewardToken).balanceOf(address(auction)), kickAmount);
        assertEq(ERC20(rewardToken).balanceOf(address(strategy)), 0);

        uint256 skySettlementAmount = 40_000 * 10 ** 18; // Simulate SKY proceeds from auction
        deal(address(asset), tokenHandlerAddr, skySettlementAmount);

        assertEq(
            ERC20(address(asset)).balanceOf(tokenHandlerAddr),
            skySettlementAmount
        );

        vm.prank(keeper);
        strategy.report();

        assertEq(ERC20(address(asset)).balanceOf(tokenHandlerAddr), 0);
        assertEq(ERC20(address(asset)).balanceOf(address(strategy)), 0);
        assertEq(
            strategy.estimatedTotalAssets(),
            initialAmount + skySettlementAmount
        );
    }
}

// Mock auction contract for testing
contract MockAuction is Auction {
    constructor(address _receiver, address _want) {
        // Initialize the auction with required parameters
        initialize(
            _want, // want token
            _receiver, // receiver address
            msg.sender, // governance (use deployer for testing)
            1 days, // auction length (1 day for testing)
            1e18 // starting price (1 token for testing)
        );
    }
}
