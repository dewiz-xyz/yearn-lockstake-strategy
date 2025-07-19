// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {BaseHealthCheck, ERC20} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter} from "@periphery/interfaces/Uniswap/V3/ISwapRouter.sol";
import {ILockstakeEngine} from "./interfaces/ILockstakeEngine.sol";
import {IStaking} from "./interfaces/IStaking.sol";
import {Auction} from "@periphery/Auctions/Auction.sol";

/// @title LockstakeCumpounder
/// @notice A Yearn V3 TokenizedStrategy that (COIN is defined at deployment):
///         1) Opens URN #0 on LockstakeEngine for itself and selects the COIN farm.
///         2) Locks SKY → COIN farm via LockstakeEngine.lock(...).
///         3) Periodically claims COIN rewards, swaps COIN→SKY, and re-locks SKY to compound.
///         4) Frees SKY on withdrawals.
///
contract LockstakeCumpounder is BaseHealthCheck {
    using SafeERC20 for ERC20;

    /// @notice Which URN index we use for this strategy (we fix to 0).
    uint256 public constant URN_INDEX = 0;

    /// @notice Uniswap V3 router address for swapping REWARD_TOKEN → SKY.
    address private constant UNI_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564; // Uniswap V3 router on Mainnet

    /// @notice The SKY governance token (ERC20) that the Vault holds.
    ERC20 public constant SKY = ERC20(0x56072C95FAA701256059aa122697B133aDEd9279);

    /// @notice The reward token (ERC20) earned by farming SKY.
    ERC20 public immutable REWARD_TOKEN;

    /// @notice MakerDAO’s LockstakeEngine contract address.
    ILockstakeEngine public immutable LOCK_STAKE_ENGINE;

    /// @notice The farm contract address for REWARD_TOKEN rewards (selected via selectFarm).
    IStaking public immutable FARM;

    address public immutable URN;

    ///@notice yearn's referral code
    uint16 public referral = 1007;

    address public voteDelegate;

    uint256 public minAmountToSell = 1000e18;

    address public auction;

    bool public useAuction;

    bool public openDeposits;

    /// @notice Path to be used when swapping REWARD_TOKEN → SKY, as encoded for the Uni V3 router: abi.encodePacked(address from, uint24 pairFee, address 1st hop ... address to)
    bytes public uniV3Path;

    mapping(address => bool) public allowed;

    constructor(address _lockstakeEngine, address _farm, string memory _name) BaseHealthCheck(address(SKY), _name) {
        LOCK_STAKE_ENGINE = ILockstakeEngine(_lockstakeEngine);
        FARM = IStaking(_farm);

        REWARD_TOKEN = ERC20(FARM.rewardsToken());

        // Approve SKY → LockstakeEngine for unlimited locking.
        SKY.forceApprove(_lockstakeEngine, type(uint256).max);

        // Approve REWARD_TOKEN → UniswapV2 Router for unlimited swapping.
        REWARD_TOKEN.forceApprove(UNI_V3_ROUTER, type(uint256).max);

        // 1) Open URN #0 for this strategy address.
        URN = LOCK_STAKE_ENGINE.open(URN_INDEX);

        // 2) Select the REWARD_TOKEN farm for URN #0 (so that lock(...) stakes directly into FARM).
        LOCK_STAKE_ENGINE.selectFarm(address(this), URN_INDEX, _farm, referral);
    }

    /// @dev  Deploys new SKY into LockstakeEngine (automatically staking to REWARD_TOKEN farm).
    /// @param assets  The amount of SKY (in wei) received from the Vault to lock.
    function _deployFunds(uint256 assets) internal override {
        LOCK_STAKE_ENGINE.lock(address(this), URN_INDEX, assets, referral);
    }

    /// @dev  Frees up to `assets` SKY from LockstakeEngine (unstaking from farm → UNLOCK).
    /// @param assets  The amount of SKY (in wei) to free/withdraw back to Vault.
    function _freeFunds(uint256 assets) internal override {
        LOCK_STAKE_ENGINE.free(address(this), URN_INDEX, address(this), assets);
    }

    // NOTE: If useAuction is true, we will use the auction to sell the REWARD_TOKEN rewards.
    //  If useAuction is false, we will swap the REWARD_TOKEN rewards to SKY through UniswapV2 and needs a private relay
    function _harvestAndReport() internal override returns (uint256 _totalAssets) {
        LOCK_STAKE_ENGINE.getReward(address(this), URN_INDEX, address(FARM), address(this));

        uint256 balance = REWARD_TOKEN.balanceOf(address(this));
        if (balance > minAmountToSell) {
            if (useAuction) {
                _kick(balance);
            } else {
                _swapFrom(uniV3Path, balance, 0);
            }
        }

        uint256 newSky = SKY.balanceOf(address(this));
        if (newSky > 0) {
            LOCK_STAKE_ENGINE.lock(address(this), URN_INDEX, newSky, referral);
        }

        _totalAssets = estimatedTotalAssets();
    }

    function availableDepositLimit(address _receiver) public view override returns (uint256) {
        if (openDeposits || allowed[_receiver]) {
            return type(uint256).max;
        }

        return 0;
    }

    /**
     * @dev Used to swap a specific amount of `_from` to `_to`.
     * This will check and handle all allowances as well as not swapping
     * unless `_amountIn` is greater than the set `_minAmountOut`
     *
     * If one of the tokens matches with the `base` token it will do only
     * one jump, otherwise will do two jumps.
     *
     * The corresponding uniFees for each token pair will need to be set
     * other wise this function will revert.
     *
     * @param _path Path for swap execution (encoded for Uni V3 router)
     * @param _amountIn The amount of `_from` we will swap.
     * @param _minAmountOut The min of `_to` to get out.
     * @return _amountOut The actual amount of `_to` that was swapped to
     */
    function _swapFrom(bytes memory _path, uint256 _amountIn, uint256 _minAmountOut)
        internal
        returns (uint256 _amountOut)
    {
        _amountOut = ISwapRouter(UNI_V3_ROUTER).exactInput(
            ISwapRouter.ExactInputParams(_path, address(this), block.timestamp, _amountIn, _minAmountOut)
        );
    }

    /// @dev  Returns an approximate value of total assets (SKY) under management:
    ///       what’s currently staked in URN #0 plus any SKY already sitting in the contract.
    function estimatedTotalAssets() public view returns (uint256) {
        // Locked & staked SKY in URN #0:
        uint256 stakedSky = balanceOfStake();
        // Plus any SKY sitting idle in this contract:
        uint256 idleSky = SKY.balanceOf(address(this));
        return stakedSky + idleSky;
    }

    function balanceOfStake() public view returns (uint256) {
        return FARM.balanceOf(URN);
    }

    function kick() external onlyKeepers {
        require(useAuction, "!useAuction");

        LOCK_STAKE_ENGINE.getReward(address(this), URN_INDEX, address(FARM), address(this));

        uint256 balance = REWARD_TOKEN.balanceOf(address(this));
        if (balance > minAmountToSell) {
            _kick(balance);
        }
    }

    function _kick(uint256 _amount) internal {
        REWARD_TOKEN.transfer(auction, _amount);
        Auction(auction).kick(address(REWARD_TOKEN));
    }

    /**
     * @notice Set the Uniswap V3 path 
     * @param _path Path, encoded for the Uni V3 router
     */
    function setUniV3Path(bytes calldata _path) external onlyManagement {
        uniV3Path = _path;
    }    

    /**
     * @notice Set the minimum amount of rewardsToken to sell
     * @param _minAmountToSell minimum amount to sell in wei
     */
    function setMinAmountToSell(uint256 _minAmountToSell) external onlyManagement {
        minAmountToSell = _minAmountToSell;
    }

    function setOpenDeposits(bool _openDeposits) external onlyManagement {
        openDeposits = _openDeposits;
    }

    function setAllowed(address _depositor, bool _allowed) external onlyManagement {
        allowed[_depositor] = _allowed;
    }

    function setAuction(address _auction) external onlyManagement {
        if (_auction != address(0)) {
            require(Auction(_auction).receiver() == address(this), "receiver");
            require(Auction(_auction).want() == address(asset), "want");
        }
        auction = _auction;
    }

    function setUseAuction(bool _useAuction) external onlyManagement {
        if (_useAuction) require(auction != address(0), "!auction");
        useAuction = _useAuction;
    }

    /**
     * @notice Set the referral code for staking.
     * @param _referral uint16 referral code
     */
    function setReferral(uint16 _referral) external onlyManagement {
        referral = _referral;
    }

    function setVoteDelegate(address _voteDelegate) external onlyManagement {
        voteDelegate = _voteDelegate;

        LOCK_STAKE_ENGINE.selectVoteDelegate(address(this), URN_INDEX, voteDelegate);
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _emergencyWithdraw(uint256 _amount) internal override {
        _amount = _min(_amount, balanceOfStake());
        _freeFunds(_amount);
    }
}
