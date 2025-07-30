// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {BaseHealthCheck, ERC20} from "@periphery/Bases/HealthCheck/BaseHealthCheck.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter} from "@periphery/interfaces/Uniswap/V3/ISwapRouter.sol";
import {ILockstakeEngine} from "./interfaces/ILockstakeEngine.sol";
import {IStaking} from "./interfaces/IStaking.sol";
import {Auction} from "@periphery/Auctions/Auction.sol";
import {MultiSwapper, Hop, Dex} from "./periphery/MultiSwapper.sol";

/// @title LockstakeCumpounder
/// @notice A Yearn V3 TokenizedStrategy that (COIN is defined at deployment):
///         1) Opens URN #0 on LockstakeEngine for itself and selects the COIN farm.
///         2) Locks SKY → COIN farm via LockstakeEngine.lock(...).
///         3) Periodically claims COIN rewards, swaps COIN→SKY, and re-locks SKY to compound.
///         4) Frees SKY on withdrawals.
///
contract LockstakeCumpounder is BaseHealthCheck, MultiSwapper {
    using SafeERC20 for ERC20;

    /// @notice Which URN index we use for this strategy (we fix to 0).
    uint256 public constant URN_INDEX = 0;

    /// @notice The SKY governance token (ERC20) that the Vault holds.
    ERC20 public constant SKY =
        ERC20(0x56072C95FAA701256059aa122697B133aDEd9279);

    /// @notice The reward token (ERC20) earned by farming SKY.
    ERC20 public immutable REWARD_TOKEN;

    /// @notice MakerDAO’s LockstakeEngine contract address.
    ILockstakeEngine public immutable LOCK_STAKE_ENGINE;

    /// @notice The farm contract address for REWARD_TOKEN rewards (selected via selectFarm).
    IStaking public immutable FARM;

    address public immutable URN;

    /// @notice Yearn's referral code.
    uint16 public referral = 1007;

    /// @notice Delegate that can use the voting power of the staked SKY.
    address public voteDelegate;

    /// @notice Minimum amount to sell (avoid selling dust)
    uint256 public minAmountToSell = 10_000 * 10 ** 18;

    /// @notice Address of auction contract
    address public auction;

    /// @notice Boolean, strategy will rely on auctions if true, will swap if false
    bool public useAuction;

    /// @notice Indicates whether deposits are open
    bool public openDeposits;

    /// @notice Allowlist if deposits are closed.
    mapping(address => bool) public allowed;

    /// @notice Initializes the contract with the given parameters.
    /// @param _lockstakeEngine The address of the LockstakeEngine contract.
    /// @param _farm The address of the farm contract.
    /// @param _name The name of the strategy.
    constructor(
        address _lockstakeEngine,
        address _farm,
        string memory _name
    ) BaseHealthCheck(address(SKY), _name) {
        LOCK_STAKE_ENGINE = ILockstakeEngine(_lockstakeEngine);
        FARM = IStaking(_farm);

        REWARD_TOKEN = ERC20(FARM.rewardsToken());

        // Approve SKY → LockstakeEngine for unlimited locking.
        SKY.forceApprove(_lockstakeEngine, type(uint256).max);

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

    /// @dev  Harvests rewards and reports the total assets under management.
    ///  If useAuction is true, we will use the auction to sell the REWARD_TOKEN rewards.
    ///  If useAuction is false, we will swap the REWARD_TOKEN rewards to SKY through the MultiSwapper route.
    /// @return _totalAssets The total assets under management.
    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        LOCK_STAKE_ENGINE.getReward(
            address(this),
            URN_INDEX,
            address(FARM),
            address(this)
        );

        uint256 balance = REWARD_TOKEN.balanceOf(address(this));
        if (balance > minAmountToSell) {
            if (useAuction) {
                _kick(balance);
            } else {
                _swapFrom(balance, 0);
            }
        }

        uint256 newSky = SKY.balanceOf(address(this));
        if (newSky > 0) {
            LOCK_STAKE_ENGINE.lock(address(this), URN_INDEX, newSky, referral);
        }

        _totalAssets = estimatedTotalAssets();
    }

    /// @notice Returns the available deposit limit for a given address.
    /// @param _receiver The address to check the deposit limit for.
    /// @return The available deposit limit.
    function availableDepositLimit(
        address _receiver
    ) public view override returns (uint256) {
        if (openDeposits || allowed[_receiver]) {
            return type(uint256).max;
        }

        return 0;
    }

    /// @notice Returns an approximate value of total assets (SKY) under management:
    ///         what’s currently staked in URN #0 plus any SKY already sitting in the contract.
    /// @return The total assets under management.
    function estimatedTotalAssets() public view returns (uint256) {
        // Locked & staked SKY in URN #0:
        uint256 stakedSky = balanceOfStake();
        // Plus any SKY sitting idle in this contract:
        uint256 idleSky = SKY.balanceOf(address(this));
        return stakedSky + idleSky;
    }

    /// @notice Returns the amount of SKY staked in the farm for the URN.
    /// @return The amount of SKY staked.
    function balanceOfStake() public view returns (uint256) {
        return FARM.balanceOf(URN);
    }

    /// @notice Claims rewards and kicks the auction if the balance is sufficient.
    function kick() external onlyKeepers {
        require(useAuction, "!useAuction");

        LOCK_STAKE_ENGINE.getReward(
            address(this),
            URN_INDEX,
            address(FARM),
            address(this)
        );

        uint256 balance = REWARD_TOKEN.balanceOf(address(this));
        if (balance > minAmountToSell) {
            _kick(balance);
        }
    }

    /// @dev Internal function to transfer rewards and kick the auction.
    /// @param _amount The amount of reward tokens to transfer.
    function _kick(uint256 _amount) internal {
        REWARD_TOKEN.safeTransfer(auction, _amount);
        Auction(auction).kick(address(REWARD_TOKEN));
    }

    /// @notice Sets the MultiSwapper path
    /// @param _path Path
    function setSwapPath(Hop[] calldata _path) external onlyManagement {
        _setSwapPath(_path);
    }

    /// @notice Gets the current MultiSwapper path
    /// @return The current swap path
    function getSwapPath() external view returns (Hop[] memory) {
        return path;
    }

    /// @notice Sets the minimum amount of rewardsToken to sell
    /// @param _minAmountToSell minimum amount to sell in wei
    function setMinAmountToSell(
        uint256 _minAmountToSell
    ) external onlyManagement {
        minAmountToSell = _minAmountToSell;
    }

    /// @notice Sets whether deposits are open to everyone.
    /// @param _openDeposits Boolean indicating if deposits are open.
    function setOpenDeposits(bool _openDeposits) external onlyManagement {
        openDeposits = _openDeposits;
    }

    /// @notice Sets whether a specific depositor is allowed to deposit.
    /// @param _depositor The address of the depositor.
    /// @param _allowed Boolean indicating if the depositor is allowed.
    function setAllowed(
        address _depositor,
        bool _allowed
    ) external onlyManagement {
        allowed[_depositor] = _allowed;
    }

    /// @notice Sets the auction contract address.
    /// @param _auction The address of the auction contract.
    function setAuction(address _auction) external onlyManagement {
        if (_auction != address(0)) {
            require(Auction(_auction).receiver() == address(this), "receiver");
            require(Auction(_auction).want() == address(asset), "want");
        }
        auction = _auction;
    }

    /// @notice Sets whether to use the auction for selling rewards.
    /// @param _useAuction Boolean indicating if the auction should be used.
    function setUseAuction(bool _useAuction) external onlyManagement {
        if (_useAuction) require(auction != address(0), "!auction");
        useAuction = _useAuction;
    }

    /// @notice Sets the referral code for staking.
    /// @param _referral uint16 referral code
    function setReferral(uint16 _referral) external onlyManagement {
        referral = _referral;
    }

    /// @notice Sets the vote delegate for the URN.
    /// @param _voteDelegate The address of the vote delegate.
    function setVoteDelegate(address _voteDelegate) external onlyManagement {
        voteDelegate = _voteDelegate;

        LOCK_STAKE_ENGINE.selectVoteDelegate(
            address(this),
            URN_INDEX,
            voteDelegate
        );
    }

    /// @dev Returns the minimum of two unsigned integers.
    /// @param a The first unsigned integer.
    /// @param b The second unsigned integer.
    /// @return The smaller of the two integers.
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @dev Internal function to handle emergency withdrawals.
    /// @param _amount The amount to withdraw.
    function _emergencyWithdraw(uint256 _amount) internal override {
        _amount = _min(_amount, balanceOfStake());
        _freeFunds(_amount);
    }
}
