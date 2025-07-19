// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {IStaking} from "../interfaces/IStaking.sol";
import {IStrategyInterface} from "../interfaces/IStrategyInterface.sol";
import {IQuoter} from "../interfaces/IQuoter.sol";

contract StrategyAprOracle {

    address private constant UNI_V3_QUOTER = 0x5e55C9e631FAE526cd4B0526C4818D6e0a9eF0e3; // Uniswap V3 quoter on Mainnet

    /**
     * @notice Will return the expected Apr of a strategy post a debt change.
     * @dev _delta is a signed integer so that it can also represent a debt
     * decrease.
     *
     * This should return the annual expected return at the current timestamp
     * represented as 1e18.
     *
     *      ie. 10% == 1e17
     *
     * _delta will be == 0 to get the current apr.
     *
     * This will potentially be called during non-view functions so gas
     * efficiency should be taken into account.
     *
     * @param _strategy The token to get the apr for.
     * @param _delta The difference in debt.
     * @return . The expected apr for the strategy represented as 1e18.
     */
    function aprAfterDebtChange(address _strategy, int256 _delta)
        external
        view
        returns (uint256)
    {
        IStaking farm = IStaking(IStrategyInterface(_strategy).FARM());

        if (block.timestamp > farm.periodFinish()) {
            return 0;
        }

        uint256 rewardRate = farm.rewardRate();

        // fetch staking token amount
        uint256 stakedAmount = uint256(int256(farm.totalSupply()) + _delta);

        // fetch price
        uint256 stakePrice = price(IStrategyInterface(_strategy).uniV3Path());

        // calculate apr
        uint256 tvl = stakePrice * stakedAmount;

        uint256 rewardsPerYearSky = (rewardRate * 1e18 * 365 days);

        return tvl > 0 ? (rewardsPerYearSky * 1e18) / tvl : 0; // apr in 1e18 (1e18=100%)
    }

    function price(bytes memory _path) public view returns (uint256 output) {
        // get price of 1 Token from UniV3
        (output,,,) = IQuoter(UNI_V3_QUOTER).quoteExactInput(
            _path,
            1e18
        );
    }
}
