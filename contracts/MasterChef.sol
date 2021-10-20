// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "./QEntry.sol";

contract MasterChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    //Info for each user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
    }
//        How reward is calculated:
//            For any point in time, a user is entitled to a certain amount of qent.
//            Definition:
//                -lp amount: The amount of lp the user deposited.
//                -awarded: The amount that has already been awarded.
//                          Since we are calculating the amount the user is entitled to on the flight,
//                          we need a way to subtracted already awarded amount.
//                -pool percent: lpAmount / totalLpAmount in pool
//                -total qent distribute to pool: the amount of qent distributed to pool since last reward block.
//            This amount is calculated using the following formula:
//                pending reward = ( user pool percent * total qent distribute to pool) - reward debt

// todo: add aave smart contract interaction
//    when deposit to a pool, amount is send to the corresponding aave pool
//    interest will be use to buy back qentry
    QEntry public qentry;

    struct PoolInfo{
        IERC20 lpToken; //address of LP token, could be an erc20 token, or an lp erc20 pair
        uint256 allocPoint; // how many point ( allocated point/ total allocated point = percentage of the award every block toward the pool)
        uint256 lastRewardBlock;
        uint256 accQentryPerShare;
        uint16 depositFeeBP;
    }

    IERC20 public usdc;
    address public usdcQentryLP = address(0x0); // this is needed to keep the price of qent stable
    address public burnaddr;
    address public nftaddr = address(0x0);// nft system if there is a need in the future
    uint256 public QentryPerBlock = 5 ether;
    uint256 public maxEmissionRate = 10 ether;
    uint256 public constant BONUS_MULTIPLIER= 1;
    address public feeAddress; // this is the address of prize controller
    PoolInfo[] public poolInfo;
    mapping(uint256=> mapping(address=>UserInfo)) public userInfo;
    uint256 public totalAllocPoint= 0;
    uint256 public startBlock;

    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 qentPerBlock);

    constructor(
        QEntry _qent,
        address _burnAddr,
        address _feeAddr,
        uint256 _QentPerBlock,
        uint256 _startBlock
    ){
        qentry = _qent;
        burnaddr= _burnAddr;
        feeAddress = _feeAddr;
        QentryPerBlock = _QentPerBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns(uint256){
        return poolInfo.length;
    }

    mapping(IERC20=>bool) public poolExistence;
    modifier  nonDuplicated(IERC20 _lpToken){
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    // Add new pool, only owner
    function addPool(uint256 _allocPoint, IERC20 _lpToken, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner nonDuplicated(_lpToken) {
        require(_depositFeeBP <= 1000, "add: Never more than 10% fees!");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;
        poolInfo.push(PoolInfo({
        lpToken : _lpToken,
        allocPoint : _allocPoint,
        lastRewardBlock : lastRewardBlock,
        accQentryPerShare : 0,
        depositFeeBP : _depositFeeBP
        }));
    }

    // Update pool, only owner
    function setPoolProperty(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 1000, "set: Never more than 10% fees.");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending qentry on frontend.
    function pendingQentry(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accQentryPerShare = pool.accQentryPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 QentryReward = multiplier.mul(QentryPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accQentryPerShare = accQentryPerShare.add(QentryReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accQentryPerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 QentryReward = multiplier.mul(QentryPerBlock).mul(pool.allocPoint).div(totalAllocPoint);

        if (nftaddr!=address(0x0)){
            // Reserved for NFT address. 5% will be minted for the NFT system
            qentry.mint(nftaddr, QentryReward.div(20));
            qentry.mint(burnaddr, QentryReward.div(20));
        }else{
            qentry.mint(burnaddr, QentryReward.div(10));
        }
        qentry.mint(address(this), QentryReward);
        pool.accQentryPerShare = pool.accQentryPerShare.add(QentryReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for qent allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accQentryPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                safeQentryTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            if (pool.depositFeeBP > 0) {
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
            } else {
                user.amount = user.amount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accQentryPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Harvest pending Qentry
    function harvest(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        uint256 pending = 0;
        if (user.amount > 0) {
            pending = user.amount.mul(pool.accQentryPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                safeQentryTransfer(msg.sender, pending);
            }
        }

        user.rewardDebt = user.amount.mul(pool.accQentryPerShare).div(1e12);
        emit Harvest(msg.sender, _pid , pending);
    }

    // Harvest all pending Qentry
    function harvestAll() public nonReentrant {

        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
            PoolInfo storage pool = poolInfo[pid];
            UserInfo storage user = userInfo[pid][msg.sender];
            uint256 pending = 0;
            if (user.amount > 0) {
                pending = user.amount.mul(pool.accQentryPerShare).div(1e12).sub(user.rewardDebt);
                if (pending > 0) {
                    safeQentryTransfer(msg.sender, pending);
                }
            }
            user.rewardDebt = user.amount.mul(pool.accQentryPerShare).div(1e12);
            emit Harvest(msg.sender, pid , pending);
        }
    }


    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accQentryPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            safeQentryTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accQentryPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe Qentry transfer function, just in case if rounding error causes pool to not have enough SH13LD.
    function safeQentryTransfer(address _to, uint256 _amount) internal {
        uint256 QentryBal = qentry.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > QentryBal) {
            transferSuccess = qentry.transfer(_to, QentryBal);
        } else {
            transferSuccess = qentry.transfer(_to, _amount);
        }
        require(transferSuccess, "safeQentryTransfer: transfer failed");
    }

    function setFeeAddress(address _feeAddress) public onlyOwner {
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }


    // for front end
    function getQentryPriceCents() public view returns (uint256 spc){
        uint QentryBalance = qentry.balanceOf(usdcQentryLP);
        if (QentryBalance > 0) {
            uint256 priceCents = usdc.balanceOf(usdcQentryLP).mul(1e14).div(QentryBalance);
            return priceCents;
        }
        return 0;
    }


    //Only update before start of farm
    function updateStartBlock(uint256 _startBlock) public onlyOwner {
        startBlock = _startBlock;
    }

    function setNFTAddress(address _address) public onlyOwner {
        nftaddr = _address;
    }

}
