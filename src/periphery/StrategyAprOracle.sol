// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IStaking} from "../interfaces/IStaking.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";
import {IUniswapV2Router02} from "@periphery/interfaces/Uniswap/V2/IUniswapV2Router02.sol";
import {ISwapRouter} from "@periphery/interfaces/Uniswap/V3/ISwapRouter.sol";
import {IPsmWrapper} from "../interfaces/IPsmWrapper.sol";
import {IMkrSky} from "../interfaces/IMkrSky.sol";
import {Hop, Dex} from "../periphery/MultiSwapper.sol";
import {UniswapV3SwapSimulator} from "../libraries/UniswapV3SwapSimulator.sol";

contract StrategyAprOracle {
    address private constant UNI_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant UNI_V3_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant PSM_WRAPPER =
        0xA188EEC8F81263234dA3622A406892F3D630f98c;
    address private constant MKR_SKY =
        0xA1Ea1bA18E88C381C724a75F23a130420C403f9a;
    address private constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint256 private constant WAD = 1e18;

    /// @notice Will return the expected APR of a strategy post a debt change.
    /// @dev _delta is a signed integer so that it can also represent a debt
    /// decrease.
    ///
    /// This should return the annual expected return at the current timestamp
    /// represented as 1e18.
    ///
    ///      i.e., 10% == 1e17
    ///
    /// _delta will be == 0 to get the current apr.
    ///
    /// This will potentially be called during non-view functions so gas
    /// efficiency should be taken into account.
    ///
    /// @param _strategy The strategy to get the apr for.
    /// @param _delta The difference in debt.
    /// @return The expected apr for the strategy represented as 1e18.
    function aprAfterDebtChange(
        address _strategy,
        int256 _delta
    ) external view returns (uint256) {
        IStaking farm = IStaking(IStrategyInterface(_strategy).FARM());

        if (block.timestamp > farm.periodFinish()) {
            return 0;
        }

        uint256 rewardRate = farm.rewardRate();

        // fetch staking token amount (always SKY)
        uint256 stakedAmount = uint256(int256(farm.totalSupply()) + _delta);

        // get rewards per year in reward token (e.g., SPK)
        // rewardRate is rewards per second, so multiply by seconds in a year
        uint256 rewardsPerYear = rewardRate * 365 days;

        // convert rewards to SKY using swap path (reward token -> SKY)
        uint256 skyPerRewardToken = price(
            IStrategyInterface(_strategy).getSwapPath()
        );

        // calculate APR: (SKY rewards per year) / (SKY staked)
        // Combine operations to avoid precision loss from intermediate division
        return
            stakedAmount > 0 
                ? (skyPerRewardToken * rewardsPerYear) / stakedAmount 
                : 0; // apr in 1e18 (1e18=100%)
    }

    /// @notice Returns the price of a token using a MultiSwapper path.
    /// @param _path The MultiSwapper path for the token pair.
    /// @return output The price of the token.
    function price(Hop[] memory _path) public view returns (uint256 output) {
        require(_path.length > 0, "empty path");

        output = 1e18; // Start with 1 token (18 decimals)

        for (uint256 i = 0; i < _path.length; i++) {
            Hop memory hop = _path[i];

            if (hop.dex == Dex.UniV2) {
                output = _getUniV2Price(hop.from, hop.to, output);
            } else if (hop.dex == Dex.UniV3) {
                output = _getUniV3Price(hop.from, hop.to, hop.fee, output);
            } else if (hop.dex == Dex.Psm) {
                output = _getPsmPrice(hop.from, hop.to, output);
            } else if (hop.dex == Dex.MkrSky) {
                output = _getMkrSkyPrice(output);
            }
        }
    }

    /// @notice Gets price quote from Uniswap V2
    /// @param _from The token to swap from
    /// @param _to The token to swap to
    /// @param _amountIn The amount to swap
    /// @return amountOut The amount out
    function _getUniV2Price(
        address _from,
        address _to,
        uint256 _amountIn
    ) private view returns (uint256 amountOut) {
        address[] memory path = new address[](2);
        path[0] = _from;
        path[1] = _to;

        uint256[] memory amounts = IUniswapV2Router02(UNI_V2_ROUTER)
            .getAmountsOut(_amountIn, path);
        amountOut = amounts[1];
    }

    /// @notice Gets price quote from Uniswap V3 using production-grade gas-efficient simulation
    /// @param _from The token to swap from
    /// @param _to The token to swap to
    /// @param _fee The pool fee
    /// @param _amountIn The amount to swap
    /// @return amountOut The amount out
    function _getUniV3Price(
        address _from,
        address _to,
        uint24 _fee,
        uint256 _amountIn
    ) private view returns (uint256 amountOut) {
        amountOut = UniswapV3SwapSimulator.simulateExactInputSingle(
            ISwapRouter(UNI_V3_ROUTER),
            ISwapRouter.ExactInputSingleParams({
                tokenIn: _from,
                tokenOut: _to,
                fee: _fee,
                recipient: address(0),
                deadline: block.timestamp,
                amountIn: _amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }

    /// @notice Gets price quote from PSM
    /// @param _from The token to swap from
    /// @param _to The token to swap to
    /// @param _amountIn The amount to swap
    /// @return amountOut The amount out
    function _getPsmPrice(
        address _from,
        address _to,
        uint256 _amountIn
    ) private view returns (uint256 amountOut) {
        IPsmWrapper psm = IPsmWrapper(PSM_WRAPPER);

        if (_from == USDS && _to == USDC) {
            uint256 tout = psm.tout();
            amountOut = ((_amountIn * WAD) / (WAD + tout)) / 1e12;
        } else if (_from == USDC && _to == USDS) {
            // For USDC to USDS, we need to account for tin fee
            uint256 tin = psm.tin();
            amountOut = (_amountIn * 1e12 * WAD) / (WAD + tin);
        } else {
            revert("invalid PSM hop");
        }
    }

    /// @notice Gets price quote from MKR-SKY conversion
    /// @param _amountIn The amount of MKR to convert
    /// @return amountOut The amount of SKY out
    function _getMkrSkyPrice(
        uint256 _amountIn
    ) private view returns (uint256 amountOut) {
        IMkrSky mkrSky = IMkrSky(MKR_SKY);
        uint256 rate = mkrSky.rate();
        uint256 fee = mkrSky.fee();

        amountOut = (_amountIn * rate);
        if (fee > 0) {
            amountOut = amountOut - ((amountOut * fee) / WAD);
        }
    }
}
