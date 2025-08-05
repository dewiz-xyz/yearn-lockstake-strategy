pragma solidity ^0.8.18;

import "forge-std/console2.sol";
import {Setup} from "./utils/Setup.sol";

import {StrategyAprOracle} from "../periphery/StrategyAprOracle.sol";
import {Hop, Dex} from "../periphery/MultiSwapper.sol";
import {IStaking} from "../interfaces/IStaking.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";

contract OracleTest is Setup {
    StrategyAprOracle public oracle;

    function setUp() public override {
        super.setUp();
        oracle = new StrategyAprOracle();
    }

    function checkOracle(address _strategy, uint256 _delta) public {
        _delta = bound(_delta, 1e16, 1e26); // 0.01 to 100M SKY (18 decimals)

        uint256 currentApr = oracle.aprAfterDebtChange(_strategy, 0);

        // Should be greater than 0 but likely less than 100%
        assertGt(currentApr, 0, "ZERO");
        assertLt(currentApr, 1e18, "+100%");

        uint256 negativeDebtChangeApr = oracle.aprAfterDebtChange(
            _strategy,
            -int256(_delta)
        );

        // The apr should go up if deposits go down
        assertLt(currentApr, negativeDebtChangeApr, "negative change");

        uint256 positiveDebtChangeApr = oracle.aprAfterDebtChange(
            _strategy,
            int256(_delta)
        );
        assertGt(currentApr, positiveDebtChangeApr, "positive change");

        // TODO: Uncomment if there are setter functions to test. /// @dev no setters in this oracle
        /**
         * vm.expectRevert("!governance");
         *     vm.prank(user);
         *     oracle.setterFunction(setterVariable);
         *
         *     vm.prank(management);
         *     oracle.setterFunction(setterVariable);
         *
         *     assertEq(oracle.setterVariable(), setterVariable);
         */
    }

    function test_oracle(uint256 _amount, uint16 _percentChange) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _percentChange = uint16(bound(uint256(_percentChange), 10, MAX_BPS));

        mintAndDepositIntoStrategy(strategy, user, _amount);

        uint256 _delta = (_amount * _percentChange) / MAX_BPS;

        checkOracle(address(strategy), _delta);
    }

    // Test price function with single UniV2 hop
    function test_price_singleUniV2Hop() public {
        Hop[] memory path = new Hop[](1);
        path[0] = Hop({
            dex: Dex.UniV2,
            from: tokenAddrs["WETH"],
            to: tokenAddrs["USDC"],
            fee: 0
        });

        uint256 price = oracle.price(path);
        assertGt(price, 0, "UniV2 price should be greater than 0");
    }

    // Test price function with single UniV3 hop
    function test_price_singleUniV3Hop() public {
        Hop[] memory path = new Hop[](1);
        path[0] = Hop({
            dex: Dex.UniV3,
            from: tokenAddrs["WETH"],
            to: tokenAddrs["USDC"],
            fee: 3000 // 0.3%
        });

        uint256 price = oracle.price(path);
        assertGt(price, 0, "UniV3 price should be greater than 0");
    }

    // Test price function with PSM hop (USDS to USDC)
    function test_price_psmHop_USDStoUSDC() public {
        Hop[] memory path = new Hop[](1);
        path[0] = Hop({
            dex: Dex.Psm,
            from: tokenAddrs["USDS"],
            to: tokenAddrs["USDC"],
            fee: 0
        });

        uint256 price = oracle.price(path);
        assertGt(price, 0, "PSM USDS->USDC price should be greater than 0");
        // PSM should give close to 1:1 ratio (accounting for fees)
        assertLt(price, 1.1e18, "PSM price should be reasonable");
    }

    // Test price function with PSM hop (USDC to USDS)
    function test_price_psmHop_USDCtoUSDS() public {
        Hop[] memory path = new Hop[](1);
        path[0] = Hop({
            dex: Dex.Psm,
            from: tokenAddrs["USDC"],
            to: tokenAddrs["USDS"],
            fee: 0
        });

        uint256 price = oracle.price(path);
        assertGt(price, 0, "PSM USDC->USDS price should be greater than 0");
        // PSM should give close to 1:1 ratio (accounting for fees)
        assertEq(price, 1e18 * 1e12);
    }

    // Test price function with invalid PSM hop
    function test_price_invalidPsmHop() public {
        Hop[] memory path = new Hop[](1);
        path[0] = Hop({
            dex: Dex.Psm,
            from: tokenAddrs["WETH"], // Invalid token for PSM
            to: tokenAddrs["DAI"], // Invalid token for PSM
            fee: 0
        });

        vm.expectRevert("invalid PSM hop");
        oracle.price(path);
    }

    // Test price function with multi-hop path
    function test_price_multiHopPath() public {
        Hop[] memory path = new Hop[](2);

        // First hop: WETH -> USDC via UniV3
        path[0] = Hop({
            dex: Dex.UniV3,
            from: tokenAddrs["WETH"],
            to: tokenAddrs["USDC"],
            fee: 3000
        });

        // Second hop: USDC -> USDS via PSM
        path[1] = Hop({
            dex: Dex.Psm,
            from: tokenAddrs["USDC"],
            to: tokenAddrs["USDS"],
            fee: 0
        });

        uint256 price = oracle.price(path);
        assertGt(price, 0, "Multi-hop price should be greater than 0");
    }

    // Test price function with all DEX types in one path
    function test_price_allDexTypes() public {
        Hop[] memory path = new Hop[](4);

        // UniV2 hop
        path[0] = Hop({
            dex: Dex.UniV2,
            from: tokenAddrs["WETH"],
            to: tokenAddrs["DAI"],
            fee: 0
        });

        // UniV3 hop
        path[1] = Hop({
            dex: Dex.UniV3,
            from: tokenAddrs["DAI"],
            to: tokenAddrs["USDC"],
            fee: 500
        });

        // PSM hop
        path[2] = Hop({
            dex: Dex.Psm,
            from: tokenAddrs["USDC"],
            to: tokenAddrs["USDS"],
            fee: 0
        });

        // MkrSky hop
        path[3] = Hop({
            dex: Dex.MkrSky,
            from: address(0),
            to: address(0),
            fee: 0
        });

        uint256 price = oracle.price(path);
        assertGt(price, 0, "All DEX types price should be greater than 0");
    }

    // Test price function with different UniV3 fee tiers
    function test_price_uniV3_differentFeeTiers() public {
        uint24[4] memory feeTiers = [
            uint24(100),
            uint24(500),
            uint24(3000),
            uint24(10000)
        ];

        for (uint256 i = 0; i < feeTiers.length; i++) {
            Hop[] memory path = new Hop[](1);
            path[0] = Hop({
                dex: Dex.UniV3,
                from: tokenAddrs["WETH"],
                to: tokenAddrs["USDC"],
                fee: feeTiers[i]
            });

            uint256 price = oracle.price(path);
            assertGt(
                price,
                0,
                string(
                    abi.encodePacked(
                        "UniV3 price should be > 0 for fee tier ",
                        vm.toString(feeTiers[i])
                    )
                )
            );
        }
    }

    // Test aprAfterDebtChange when farm period has finished
    function test_aprAfterDebtChange_periodFinished() public {
        // Setup strategy with some deposits
        mintAndDepositIntoStrategy(strategy, user, 1e18);

        // Mock the farm's periodFinish to be in the past
        uint256 currentTime = block.timestamp;

        // Fast forward time beyond period finish
        vm.warp(currentTime + 365 days);

        // APR should be 0 when period is finished
        uint256 apr = oracle.aprAfterDebtChange(address(strategy), 0);
        assertEq(apr, 0, "APR should be 0 when period finished");

        // Test with positive and negative deltas - should still be 0
        apr = oracle.aprAfterDebtChange(address(strategy), 1e18);
        assertEq(
            apr,
            0,
            "APR should be 0 with positive delta when period finished"
        );

        apr = oracle.aprAfterDebtChange(address(strategy), -1e18);
        assertEq(
            apr,
            0,
            "APR should be 0 with negative delta when period finished"
        );
    }

    // Test aprAfterDebtChange with extreme delta values
    function test_aprAfterDebtChange_extremeDeltas() public {
        mintAndDepositIntoStrategy(strategy, user, 1e18);

        // Test with very large positive delta
        uint256 apr = oracle.aprAfterDebtChange(
            address(strategy),
            int256(1e30)
        );
        assertGt(apr, 0, "APR should be positive with large positive delta");

        // Test with very large negative delta (but not exceeding staked amount)
        apr = oracle.aprAfterDebtChange(address(strategy), -int256(5e17)); // -0.5 tokens
        assertGt(apr, 0, "APR should be positive with large negative delta");
    }

    // Test price function with empty path
    function test_price_emptyPath() public {
        Hop[] memory emptyPath = new Hop[](0);

        vm.expectRevert("empty path");
        oracle.price(emptyPath);
    }

    // Test price function with MkrSky hop
    function test_price_mkrSkyHop() public {
        Hop[] memory path = new Hop[](1);
        path[0] = Hop({
            dex: Dex.MkrSky,
            from: address(0), // MkrSky doesn't use from/to addresses
            to: address(0),
            fee: 0
        });

        uint256 price = oracle.price(path);
        assertGt(price, 0, "MkrSky price should be greater than 0");
    }

    // Test aprAfterDebtChange with different swap paths
    function test_aprAfterDebtChange_differentSwapPaths() public {
        mintAndDepositIntoStrategy(strategy, user, 1e18);

        // Test current APR calculation
        uint256 apr = oracle.aprAfterDebtChange(address(strategy), 0);
        assertGt(apr, 0, "APR should be greater than 0");

        // Test with small positive delta
        uint256 aprPositive = oracle.aprAfterDebtChange(
            address(strategy),
            1e17
        ); // 0.1 tokens
        assertLt(aprPositive, apr, "APR should decrease with positive delta");

        // Test with small negative delta
        uint256 aprNegative = oracle.aprAfterDebtChange(
            address(strategy),
            -1e17
        ); // -0.1 tokens
        assertGt(aprNegative, apr, "APR should increase with negative delta");
    }

    // Test edge case where delta equals total supply
    function test_aprAfterDebtChange_deltaEqualsSupply() public {
        uint256 depositAmount = 1e18;
        mintAndDepositIntoStrategy(strategy, user, depositAmount);

        // Get current total supply
        IStaking farm = IStaking(strategy.FARM());
        uint256 totalSupply = farm.totalSupply();

        // Test with negative delta equal to total supply (should result in 0 staked amount)
        uint256 apr = oracle.aprAfterDebtChange(
            address(strategy),
            -int256(totalSupply)
        );
        assertEq(
            apr,
            0,
            "APR should be 0 when delta equals negative total supply"
        );
    }
}
