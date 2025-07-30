// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter} from "@periphery/interfaces/Uniswap/V3/ISwapRouter.sol";
import {IUniswapV2Router02} from "@periphery/interfaces/Uniswap/V2/IUniswapV2Router02.sol";
import {IPsmWrapper} from "../interfaces/IPsmWrapper.sol";
import {IMkrSky} from "../interfaces/IMkrSky.sol";

enum Dex {
    UniV2,
    UniV3,
    Psm,
    MkrSky
}

/// @dev 2 storage slots
struct Hop {
    Dex dex;
    address from;
    address to;
    uint24 fee;
}

/**
 *   @title MultiSwapper
 *   @dev This is a simple contract that can be inherited by any tokenized
 *   strategy that needs to use multiple dexes to swap.
 *
 *   The global address variables default to the ETH mainnet addresses.
 *
 *   The only variable that is required is `path`.
 */
contract MultiSwapper {
    using SafeERC20 for ERC20;

    /// @dev Mainnet addresses
    address public constant UNI_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant UNI_V3_ROUTER =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant PSM_WRAPPER =
        0xA188EEC8F81263234dA3622A406892F3D630f98c;
    address public constant MKR_SKY =
        0xA1Ea1bA18E88C381C724a75F23a130420C403f9a;
    address public constant MKR = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint256 public constant WAD = 1e18;

    Hop[] public path;

    constructor() {
        ERC20(MKR).forceApprove(MKR_SKY, type(uint256).max);
    }

    /**
     * @dev Used to swap a specific amount using the storage path. Uses the path array to define tokenFrom and tokenTo.
     *
     * @param _amountIn The amount of `_from` we will swap.
     * @param _minAmountOut The min of `_to` to get out.
     * @return _amountOut The actual amount of `_to` that was swapped to
     */
    function _swapFrom(
        uint256 _amountIn,
        uint256 _minAmountOut
    ) internal virtual returns (uint256 _amountOut) {
        uint256 len = path.length;
        require(len > 0, "no path");

        _amountOut = _amountIn;
        for (uint256 i; i < len; i++) {
            Hop memory hop = path[i];

            if (hop.dex == Dex.UniV2) {
                _amountOut = _uniV2SwapFrom(hop.from, hop.to, _amountOut);
            } else if (hop.dex == Dex.UniV3) {
                _amountOut = _uniV3SwapFrom(
                    hop.from,
                    hop.to,
                    hop.fee,
                    _amountOut
                );
            } else if (hop.dex == Dex.Psm) {
                _amountOut = _psmSwapFrom(hop.from, hop.to, _amountOut);
            } else if (hop.dex == Dex.MkrSky) {
                _amountOut = _mkrSkySwapFrom(_amountOut);
            }
        }

        require(_amountOut >= _minAmountOut, "minAmountOut not reached");
    }

    /**
     * @dev Used to swap a specific amount of `_from` to `_to` on Uni V2.
     *
     * @param _from The token we are swapping from.
     * @param _to The token we are swapping to.
     * @param _amountIn The amount of `_from` we will swap.
     * @return _amountOut The actual amount of `_to` that was swapped to
     */
    function _uniV2SwapFrom(
        address _from,
        address _to,
        uint256 _amountIn
    ) private returns (uint256 _amountOut) {
        address[] memory _path = new address[](2);
        _path[0] = _from;
        _path[1] = _to;

        uint256[] memory amounts = IUniswapV2Router02(UNI_V2_ROUTER)
            .swapExactTokensForTokens(
                _amountIn,
                0,
                _path,
                address(this),
                block.timestamp
            );
        _amountOut = amounts[1];
    }

    /**
     * @dev Used to swap a specific amount of `_from` to `_to` on Uni V3.
     *
     * @param _from The token we are swapping from.
     * @param _to The token we are swapping to.
     * @param _fee The fee amount of the pair.
     * @param _amountIn The amount of `_from` we will swap.
     * @return _amountOut The actual amount of `_to` that was swapped to
     */
    function _uniV3SwapFrom(
        address _from,
        address _to,
        uint24 _fee,
        uint256 _amountIn
    ) private returns (uint256 _amountOut) {
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams(
                _from,
                _to,
                _fee,
                address(this),
                block.timestamp,
                _amountIn,
                0,
                0
            );

        _amountOut = ISwapRouter(UNI_V3_ROUTER).exactInputSingle(params);
    }

    /**
     * @dev Used to swap a specific amount of `_from` to `_to` on the MKR-SKY contract.
     *
     * @param _amountIn The amount of `_from` we will swap.
     * @return _amountOut The actual amount of `_to` that was swapped to
     */
    function _mkrSkySwapFrom(
        uint256 _amountIn
    ) private returns (uint256 _amountOut) {
        IMkrSky(MKR_SKY).mkrToSky(address(this), _amountIn);

        uint256 rate = IMkrSky(MKR_SKY).rate();
        uint256 fee = IMkrSky(MKR_SKY).fee();

        _amountOut = (_amountIn * rate);
        if (fee > 0) {
            _amountOut = _amountOut - ((_amountOut * fee) / WAD);
        }
    }

    /**
     * @dev Used to swap a specific amount of `_from` to `_to` on the USDS-USDC SKY PSM.
     *
     * @param _from The token we are swapping from.
     * @param _to The token we are swapping to.
     * @param _amountIn The amount of `_from` we will swap.
     * @return _amountOut The actual amount of `_to` that was swapped to
     */
    function _psmSwapFrom(
        address _from,
        address _to,
        uint256 _amountIn
    ) private returns (uint256 _amountOut) {
        IPsmWrapper psm = IPsmWrapper(PSM_WRAPPER);

        if (_from == USDS && _to == USDC) {
            uint256 tout = psm.tout();
            _amountOut = ((_amountIn * WAD) / (WAD + tout)) / 1e12;
            psm.buyGem(address(this), _amountOut);
        } else if (_from == USDC && _to == USDS) {
            _amountOut = psm.sellGem(address(this), _amountIn);
        } else {
            revert("invalid PSM hop");
        }
    }

    /**
     * @dev Sets the MultiSwapper path.
     *
     * @param _path Path
     */
    function _setSwapPath(Hop[] memory _path) internal {
        delete path;

        // Effects: Only update storage, no external calls
        for (uint256 i = 0; i < _path.length; i++) {
            path.push(_path[i]);
        }

        // Update approvals after state changes
        updateApprovals();
    }

    /**
     * @dev Updates token approvals for all hops in the current path.
     * This function can be called publicly to refresh approvals if needed.
     */
    function updateApprovals() public {
        for (uint256 i = 0; i < path.length; i++) {
            Hop memory hop = path[i];
            if (hop.dex == Dex.UniV2) {
                ERC20(hop.from).forceApprove(UNI_V2_ROUTER, type(uint256).max);
            } else if (hop.dex == Dex.UniV3) {
                ERC20(hop.from).forceApprove(UNI_V3_ROUTER, type(uint256).max);
            } else if (hop.dex == Dex.Psm) {
                ERC20(hop.from).forceApprove(PSM_WRAPPER, type(uint256).max);
            }
        }
    }
}
